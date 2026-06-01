classdef RunPreflight
    %RUNPREFLIGHT Fast checks before launching a long analysis run.

    methods (Static)
        function result = check(root, startDate, endDate, opts, cfg)
            fromRequest = false;
            if nargin >= 1 && isa(root, 'bms.app.RunRequest')
                request = root;
                root = request.DataRoot;
                startDate = request.StartDate;
                endDate = request.EndDate;
                opts = request.Options;
                cfg = request.Config;
                fromRequest = true;
            end
            if ~fromRequest
                if nargin < 4 || isempty(opts), opts = struct(); end
                if nargin < 5 || isempty(cfg), cfg = struct(); end
            end

            result = struct();
            result.status = 'ok';
            result.errors = {};
            result.warnings = {};
            result.checked_at = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss');
            result.root = char(root);
            result.start_date = char(startDate);
            result.end_date = char(endDate);
            result.profile = struct();
            result.data_layout = struct();
            result.config_validation = struct();
            result.enabled_modules = {};
            result.enabled_module_specs = {};
            result.module_preflight = {};
            result.module_config_warnings = {};
            result.point_coverage = {};
            result.stats_inventory = struct();
            result.stats_inventory_path = '';
            result.stats_inventory_summary_path = '';
            result.data_index = struct();
            result.data_index_path = '';
            result.data_index_summary_path = '';
            result.run_health_report = struct();
            result.run_health_report_path = '';
            result.run_health_report_summary_path = '';
            result.reporting_contract = struct();
            result.reporting_contract_path = '';
            result.result_artifact_preflight = {};
            result.wim_month_files = struct('month', {}, 'fmt', {}, 'bcp', {}, 'exists', {});
            result.wim_preflight = struct();

            result = bms.app.RunPreflight.checkDateRange(result, startDate, endDate);
            result = bms.app.RunPreflight.checkRoot(result, root);
            result = bms.app.RunPreflight.checkConfig(result, cfg);
            result = bms.app.RunPreflight.attachProfileAndLayout(result, root, cfg);
            result = bms.app.RunPreflight.attachModuleInfo(result, root, opts);
            result = bms.app.RunPreflight.checkEnabledModuleConfig(result, root, startDate, endDate, opts, cfg);
            result = bms.app.RunPreflight.checkStatsInventory(result, root, opts, cfg);
            result = bms.app.RunPreflight.checkDataIndex(result, root, startDate, endDate, opts, cfg);
            result = bms.app.RunPreflight.checkReportingContract(result, root, opts, cfg);
            result = bms.app.RunPreflight.checkPointCoverage(result, root, startDate, endDate, opts, cfg);
            result = bms.app.RunPreflight.checkResultArtifacts(result, root, startDate, endDate, opts, cfg);
            result = bms.app.RunPreflight.checkWimInputs(result, root, startDate, endDate, opts, cfg);
            result = bms.app.RunPreflight.finalizeStatus(result);
            result = bms.app.RunPreflight.checkRunHealthReport(result, root, opts, cfg);
            result = bms.app.RunPreflight.finalizeStatus(result);
        end

        function result = checkDateRange(result, startDate, endDate)
            try
                bms.data.TimeRangeResolver.parseRange(startDate, endDate);
            catch ME
                result.errors{end+1} = ['date range invalid: ' ME.message];
            end
        end

        function result = checkRoot(result, root)
            if isempty(char(root)) || ~isfolder(root)
                result.errors{end+1} = ['data root does not exist: ' char(root)];
            end
        end

        function result = checkConfig(result, cfg)
            try
                validation = bms.config.ConfigLinter.lint(cfg);
                result.config_validation = validation;
                if isfield(validation, 'errors') && ~isempty(validation.errors)
                    result.errors = [result.errors, validation.errors];
                end
                if isfield(validation, 'warnings') && ~isempty(validation.warnings)
                    result.warnings = [result.warnings, validation.warnings];
                end
            catch ME
                result.errors{end+1} = ['config validation failed: ' ME.message];
            end
        end

        function result = attachProfileAndLayout(result, root, cfg)
            try
                profile = bms.profile.BridgeProfileRegistry.infer(cfg, root);
                if isa(profile, 'bms.profile.BridgeProfile')
                    result.profile = profile.toStruct();
                end
            catch ME
                result.warnings{end+1} = ['profile inference failed: ' ME.message];
            end
            try
                result.data_layout = bms.data.DataLayoutResolver.describe(root, cfg);
            catch ME
                result.warnings{end+1} = ['data layout inference failed: ' ME.message];
            end
        end

        function result = attachModuleInfo(result, root, opts)
            try
                statsDir = bms.data.DataLayoutResolver.statsDir(root);
                result.enabled_modules = bms.module.ModuleRegistry.enabledKeys(opts);
                specs = bms.module.ModuleRegistry.enabledFromOptions(opts);
                result.enabled_module_specs = bms.module.ModuleRegistry.toStructArray(specs, statsDir);
                result.module_preflight = bms.module.ModuleRegistry.preflight(statsDir, opts);
            catch ME
                result.warnings{end+1} = ['module preflight failed: ' ME.message];
            end
        end

        function result = checkEnabledModuleConfig(result, root, startDate, endDate, opts, cfg)
            try
                specs = bms.module.ModuleRegistry.enabledFromOptions(opts);
                dataSource = bms.data.DataSourceFactory.create(root, cfg);
                for i = 1:numel(specs)
                    spec = specs(i);
                    if strcmp(spec.Key, 'wim') || strcmp(spec.Category, 'preprocess') || isempty(spec.SubfolderKey)
                        continue;
                    end
                    [hasSubfolder, subfolder] = bms.app.RunPreflight.resolveSubfolder(cfg, spec.SubfolderKey);
                    if ~hasSubfolder
                        result = bms.app.RunPreflight.addModuleConfigWarning(result, ...
                            sprintf('%s missing subfolders.%s', spec.Key, spec.SubfolderKey));
                    elseif ~isempty(subfolder)
                        folders = dataSource.candidateDirs(subfolder, startDate, endDate);
                        if isempty(folders) && ~strcmp(spec.SubfolderKey, 'strain')
                            result = bms.app.RunPreflight.addModuleConfigWarning(result, ...
                                sprintf('%s no input directory found for subfolder "%s"', spec.Key, subfolder));
                        end
                    end

                    points = bms.app.RunPreflight.configuredPoints(cfg, spec.Key);
                    if ~isempty(points)
                        if isempty(points)
                            result = bms.app.RunPreflight.addModuleConfigWarning(result, ...
                                sprintf('%s points list is empty', spec.Key));
                        end
                        if ~bms.app.RunPreflight.hasFilePattern(cfg, spec.Key)
                            result = bms.app.RunPreflight.addModuleConfigWarning(result, ...
                                sprintf('%s has points but no file_patterns.%s', spec.Key, spec.Key));
                        end
                    end
                end
            catch ME
                result.warnings{end+1} = ['module config preflight failed: ' ME.message];
            end
        end

        function result = addModuleConfigWarning(result, message)
            result.module_config_warnings{end+1} = message;
            result.warnings{end+1} = ['module config: ' message];
        end

        function result = checkStatsInventory(result, root, opts, cfg)
            if ~bms.app.RunPreflight.statsInventoryEnabled(opts, cfg)
                return;
            end
            try
                inventory = bms.io.StatsInventory.build(root, opts, cfg);
                result.stats_inventory = bms.io.StatsInventory.summarize(inventory);
                runId = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
                result.stats_inventory_path = bms.io.StatsInventory.write(root, inventory, runId);
                result.stats_inventory_summary_path = bms.io.StatsInventory.writeSummary(root, inventory, runId);
            catch ME
                result.warnings{end+1} = ['stats inventory build failed: ' ME.message];
            end
        end

        function tf = statsInventoryEnabled(opts, cfg)
            tf = false;
            if bms.app.RunHealthReport.enabled(opts, cfg)
                tf = true;
                return;
            end
            if isstruct(opts) && isfield(opts, 'buildStatsInventory') && ~isempty(opts.buildStatsInventory)
                tf = logical(opts.buildStatsInventory);
                return;
            end
            if isstruct(cfg) && isfield(cfg, 'stats_inventory') && isstruct(cfg.stats_inventory) ...
                    && isfield(cfg.stats_inventory, 'enabled') && ~isempty(cfg.stats_inventory.enabled)
                tf = logical(cfg.stats_inventory.enabled);
            end
        end

        function result = checkPointCoverage(result, root, startDate, endDate, opts, cfg)
            try
                layout = '';
                if isfield(result, 'data_layout') && isstruct(result.data_layout) && isfield(result.data_layout, 'layout')
                    layout = char(string(result.data_layout.layout));
                end
                if ~strcmp(layout, 'jlj_daily_export') || ~isfolder(root)
                    return;
                end

                actualRecords = bms.data.ZipDailyExportAdapter.collectCsvPointIds(root, startDate, endDate, cfg);
                actualIds = cell(1, numel(actualRecords));
                actualDays = containers.Map('KeyType', 'char', 'ValueType', 'any');
                for i = 1:numel(actualRecords)
                    rec = actualRecords{i};
                    actualIds{i} = rec.point_id;
                    actualDays(rec.point_id) = rec.days;
                end
                actualMap = containers.Map('KeyType', 'char', 'ValueType', 'char');
                for i = 1:numel(actualIds)
                    actualMap(actualIds{i}) = actualIds{i};
                end

                specs = bms.module.ModuleRegistry.enabledFromOptions(opts);
                rows = {};
                for i = 1:numel(specs)
                    spec = specs(i);
                    if ~strcmp(spec.Category, 'analysis') || strcmp(spec.Key, 'wim')
                        continue;
                    end
                    expected = bms.app.RunPreflight.configuredPoints(cfg, spec.Key);
                    if isempty(expected)
                        continue;
                    end
                    found = {};
                    missing = {};
                    matchedIds = {};
                    for j = 1:numel(expected)
                        [tf, matched] = bms.app.RunPreflight.pointExists(actualMap, expected{j}, cfg, spec.Key);
                        if tf
                            found{end+1} = expected{j}; %#ok<AGROW>
                            matchedIds{end+1} = matched; %#ok<AGROW>
                        else
                            missing{end+1} = expected{j}; %#ok<AGROW>
                        end
                    end
                    coverage = 0;
                    if ~isempty(expected)
                        coverage = numel(found) / numel(expected);
                    end
                    row = struct();
                    row.key = spec.Key;
                    row.label = spec.Label;
                    row.designed_count = numel(expected);
                    row.found_count = numel(found);
                    row.missing_count = numel(missing);
                    row.coverage = coverage;
                    row.found_points = found;
                    row.missing_points = missing;
                    row.matched_csv_points = matchedIds;
                    rows{end+1} = row; %#ok<AGROW>

                    if ~isempty(missing)
                        preview = strjoin(missing(1:min(5, numel(missing))), ', ');
                        if numel(missing) > 5
                            preview = [preview, sprintf(' ... +%d', numel(missing) - 5)];
                        end
                        result.warnings{end+1} = sprintf('point coverage: %s found %d/%d, missing %d (%s)', ...
                            spec.Key, numel(found), numel(expected), numel(missing), preview); %#ok<AGROW>
                    end
                end
                result.point_coverage = rows;
            catch ME
                result.warnings{end+1} = ['point coverage preflight failed: ' ME.message];
            end
        end

        function result = checkDataIndex(result, root, startDate, endDate, opts, cfg)
            if ~bms.app.RunPreflight.dataIndexEnabled(opts, cfg)
                return;
            end
            try
                index = bms.data.DataIndex.build(root, startDate, endDate, cfg, opts);
                result.data_index = bms.data.DataIndex.summarize(index);
                if isfield(result, 'preflight_json') && ~isempty(result.preflight_json)
                    [~, runId] = fileparts(char(string(result.preflight_json)));
                    runId = regexprep(runId, '^preflight_', '');
                else
                    runId = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
                end
                result.data_index_path = bms.data.DataIndex.write(root, index, runId);
                result.data_index_summary_path = bms.data.DataIndex.writeSummary(root, index, runId);
            catch ME
                result.warnings{end+1} = ['data index build failed: ' ME.message];
            end
        end

        function tf = dataIndexEnabled(opts, cfg)
            tf = false;
            if bms.app.RunHealthReport.enabled(opts, cfg)
                tf = true;
                return;
            end
            if isstruct(opts) && isfield(opts, 'buildDataIndex') && ~isempty(opts.buildDataIndex)
                tf = logical(opts.buildDataIndex);
                return;
            end
            if isstruct(cfg) && isfield(cfg, 'data_index') && isstruct(cfg.data_index) ...
                    && isfield(cfg.data_index, 'enabled') && ~isempty(cfg.data_index.enabled)
                tf = logical(cfg.data_index.enabled);
            end
        end

        function points = configuredPoints(cfg, key)
            points = {};
            if ~isstruct(cfg), return; end
            points = bms.config.ModuleConfigResolver.resolvePoints(cfg, key, {});
        end

        function aliases = pointAliases(key)
            aliases = bms.config.ModuleConfigRegistry.aliasesForKey(key);
        end

        function points = flattenPointValues(value)
            points = {};
            if isempty(value)
                return;
            elseif ischar(value)
                points = {strtrim(value)};
            elseif isstring(value)
                points = cellstr(value(:));
                points = reshape(points, 1, []);
            elseif iscell(value)
                for i = 1:numel(value)
                    points = [points, bms.app.RunPreflight.flattenPointValues(value{i})]; %#ok<AGROW>
                end
            elseif isstruct(value)
                names = fieldnames(value);
                for i = 1:numel(names)
                    points = [points, bms.app.RunPreflight.flattenPointValues(value.(names{i}))]; %#ok<AGROW>
                end
            elseif isnumeric(value) || islogical(value)
                return;
            else
                try
                    points = cellstr(string(value(:)));
                catch
                    points = {};
                end
            end
            keep = ~cellfun(@isempty, points);
            points = points(keep);
            points = reshape(points, 1, []);
        end

        function values = uniqueText(values)
            if isempty(values), return; end
            values = cellstr(string(values));
            values = reshape(values, 1, []);
            values = values(~cellfun(@isempty, values));
            [~, ia] = unique(values, 'stable');
            values = values(sort(ia));
            values = reshape(values, 1, []);
        end

        function [tf, matched] = pointExists(actualMap, pointId, cfg, moduleKey)
            tf = false;
            matched = '';
            candidates = bms.app.RunPreflight.csvPointCandidates(pointId);
            if nargin >= 4
                sensorType = bms.app.RunPreflight.sensorTypeForPoint(moduleKey, pointId);
                fileId = bms.data.TimeSeriesLoader.resolveFileId(cfg, sensorType, pointId);
                candidates = bms.app.RunPreflight.uniqueText([candidates, ...
                    bms.app.RunPreflight.csvPointCandidates(fileId)]);
            end
            for i = 1:numel(candidates)
                if isKey(actualMap, candidates{i})
                    tf = true;
                    matched = actualMap(candidates{i});
                    return;
                end
            end
        end

        function candidates = csvPointCandidates(pointId)
            p = char(string(pointId));
            candidates = {p};
            candidates{end+1} = regexprep(p, '[-_][XYZ]$', '');
            candidates{end+1} = regexprep(p, '[-_][XYZ][-_]?', '-');
            candidates{end+1} = regexprep(p, '[-_][XYZ][-_]([^\\/]*)$', '-$1');
            candidates = bms.app.RunPreflight.uniqueText(candidates);
        end

        function sensorType = sensorTypeForPoint(moduleKey, pointId)
            sensorType = char(string(moduleKey));
            switch sensorType
                case 'earthquake'
                    [sensorType, ~] = bms.analyzer.EarthquakeSeriesService.componentFromPoint(pointId);
                case 'wind'
                    sensorType = 'wind_speed';
            end
        end

        function [tf, value] = resolveSubfolder(cfg, key)
            tf = false;
            value = '';
            if ~isstruct(cfg) || ~isfield(cfg, 'subfolders') || ~isstruct(cfg.subfolders)
                return;
            end
            aliases = bms.config.ModuleConfigRegistry.aliasesForKey(key);
            for i = 1:numel(aliases)
                if isfield(cfg.subfolders, aliases{i})
                    tf = true;
                    value = char(string(cfg.subfolders.(aliases{i})));
                    return;
                end
            end
        end

        function tf = hasFilePattern(cfg, key)
            tf = true;
            if ~isstruct(cfg) || ~isfield(cfg, 'file_patterns') || ~isstruct(cfg.file_patterns)
                return;
            end
            aliases = bms.config.SchemaValidator.aliasesForKey(key);
            for i = 1:numel(aliases)
                if isfield(cfg.file_patterns, aliases{i})
                    value = cfg.file_patterns.(aliases{i});
                    tf = ~isempty(value);
                    return;
                end
            end
            tf = false;
        end

        function result = checkWimInputs(result, root, startDate, endDate, opts, cfg)
            if ~bms.app.RunPreflight.optionEnabled(opts, 'doWIM')
                return;
            end
            try
                wimResult = bms.app.WimPreflight.check(root, startDate, endDate, cfg);
                result.wim_preflight = wimResult;
                if isfield(wimResult, 'month_files')
                    result.wim_month_files = wimResult.month_files;
                end
                if isfield(wimResult, 'warnings') && ~isempty(wimResult.warnings)
                    result.warnings = [result.warnings, wimResult.warnings];
                end
                if isfield(wimResult, 'errors') && ~isempty(wimResult.errors)
                    result.errors = [result.errors, wimResult.errors];
                end
            catch ME
                result.warnings{end+1} = ['WIM preflight failed: ' ME.message];
            end
        end

        function result = checkRunHealthReport(result, root, opts, cfg)
            if ~bms.app.RunHealthReport.enabled(opts, cfg)
                return;
            end
            try
                report = bms.app.RunHealthReport.build(result);
                result.run_health_report = report;
                runId = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
                result.run_health_report_path = bms.app.RunHealthReport.write(root, report, runId);
                result.run_health_report_summary_path = bms.app.RunHealthReport.writeSummary(root, report, runId);
            catch ME
                result.warnings{end+1} = ['run health report build failed: ' ME.message];
            end
        end

        function result = checkReportingContract(result, root, opts, cfg)
            try
                contract = bms.reporting.AnalysisReportingContract.build(cfg, opts);
                result.reporting_contract = contract;
                if bms.app.RunHealthReport.enabled(opts, cfg)
                    runId = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
                    result.reporting_contract_path = bms.reporting.AnalysisReportingContract.write(root, contract, runId);
                end
            catch ME
                result.warnings{end+1} = ['reporting contract build failed: ' ME.message];
            end
        end

        function result = checkResultArtifacts(result, root, startDate, endDate, opts, cfg)
            try
                specs = bms.module.ModuleRegistry.enabledFromOptions(opts);
                statsDir = bms.data.DataLayoutResolver.statsDir(root);
                dataSource = bms.data.DataSourceFactory.create(root, cfg);
                records = {};
                for i = 1:numel(specs)
                    spec = specs(i);
                    statsPath = spec.statsPath(statsDir);
                    if isempty(statsPath) || ~isfile(statsPath) || isempty(spec.SubfolderKey)
                        continue;
                    end
                    [hasSubfolder, subfolder] = bms.app.RunPreflight.resolveSubfolder(cfg, spec.SubfolderKey);
                    newestInput = NaN;
                    if hasSubfolder && ~isempty(subfolder)
                        inputDirs = dataSource.candidateDirs(subfolder, startDate, endDate);
                        newestInput = bms.app.RunPreflight.newestFirstLevelTimestamp(inputDirs);
                    end
                    statsInfo = dir(statsPath);
                    rec = struct('key', spec.Key, 'label', spec.Label, 'stats_path', statsPath, ...
                        'stats_modified', '', 'newest_input_modified', '', 'status', 'ok', ...
                        'issue_type', '', 'message', '');
                    if ~isempty(statsInfo)
                        rec.stats_modified = datestr(statsInfo.datenum, 'yyyy-mm-dd HH:MM:ss');
                    end
                    if ~isnan(newestInput)
                        rec.newest_input_modified = datestr(newestInput, 'yyyy-mm-dd HH:MM:ss');
                        if ~isempty(statsInfo) && statsInfo.datenum + (1 / (24 * 60)) < newestInput
                            rec.status = 'possible_stale';
                            rec.issue_type = 'stats_older_than_input';
                            rec.message = sprintf('%s stats may be older than source data: %s', spec.Key, statsPath);
                            result.warnings{end+1} = ['result artifact: ' rec.message]; %#ok<AGROW>
                        end
                    end
                    records{end+1} = rec; %#ok<AGROW>
                end
                records = [records, bms.app.RunPreflight.checkPreviousManifestArtifacts(root)]; %#ok<AGROW>
                for k = 1:numel(records)
                    rec = records{k};
                    if isstruct(rec) && isfield(rec, 'status') && strcmp(char(string(rec.status)), 'possible_stale') ...
                            && isfield(rec, 'message') && ~isempty(rec.message)
                        warningText = ['result artifact: ' char(string(rec.message))];
                        if ~any(strcmp(result.warnings, warningText))
                            result.warnings{end+1} = warningText; %#ok<AGROW>
                        end
                    end
                end
                result.result_artifact_preflight = records;
            catch ME
                result.warnings{end+1} = ['result artifact preflight failed: ' ME.message];
            end
        end

        function records = checkPreviousManifestArtifacts(root)
            records = {};
            try
                manifestPath = bms.app.ManifestReader.latest(root);
                if isempty(manifestPath) || ~isfile(manifestPath)
                    return;
                end
                manifest = bms.app.ManifestReader.load(manifestPath);
                moduleRecords = bms.app.ManifestReader.fieldValue(manifest, 'module_results', {});
                if isempty(moduleRecords)
                    moduleRecords = bms.app.ManifestReader.fieldValue(manifest, 'module_logs', {});
                end
                moduleRecords = bms.app.ManifestReader.recordsToCell(moduleRecords);
                for i = 1:numel(moduleRecords)
                    rec = moduleRecords{i};
                    if ~isstruct(rec), continue; end
                    statsPath = bms.app.RunPreflight.recordFieldText(rec, 'stats_path');
                    statsTime = bms.app.RunPreflight.fileDatenum(statsPath);
                    if isnan(statsTime), continue; end
                    startedTime = bms.app.RunPreflight.textDatenum( ...
                        bms.app.RunPreflight.recordFieldText(rec, 'started_at'));
                    endedTime = bms.app.RunPreflight.textDatenum( ...
                        bms.app.RunPreflight.recordFieldText(rec, 'ended_at'));
                    artifacts = bms.app.RunPreflight.recordFieldValue(rec, 'artifacts', {});
                    artifacts = bms.app.ManifestReader.recordsToCell(artifacts);
                    for j = 1:numel(artifacts)
                        artifact = artifacts{j};
                        if ~isstruct(artifact), continue; end
                        kind = lower(bms.app.RunPreflight.recordFieldText(artifact, 'kind'));
                        if ~strcmp(kind, 'figure'), continue; end
                        figPath = bms.app.RunPreflight.recordFieldText(artifact, 'path');
                        figTime = bms.app.RunPreflight.fileDatenum(figPath);
                        if isnan(figTime), continue; end
                        if bms.app.RunPreflight.isWithinRunWindow(figTime, startedTime, endedTime)
                            continue;
                        end
                        if figTime + (1 / (24 * 60)) < statsTime
                            out = struct();
                            out.key = bms.app.RunPreflight.recordFieldText(rec, 'key');
                            out.label = bms.app.RunPreflight.recordFieldText(rec, 'label');
                            out.status = 'possible_stale';
                            out.issue_type = 'figure_older_than_stats';
                            out.stats_path = statsPath;
                            out.artifact_path = figPath;
                            out.stats_modified = datestr(statsTime, 'yyyy-mm-dd HH:MM:ss');
                            out.artifact_modified = datestr(figTime, 'yyyy-mm-dd HH:MM:ss');
                            out.message = sprintf('%s figure may be older than stats: %s', out.key, figPath);
                            records{end+1} = out; %#ok<AGROW>
                        end
                    end
                end
            catch
                records = {};
            end
        end

        function t = fileDatenum(pathValue)
            t = NaN;
            if isempty(pathValue), return; end
            p = char(string(pathValue));
            if ~isfile(p), return; end
            info = dir(p);
            if ~isempty(info), t = info(1).datenum; end
        end

        function t = textDatenum(value)
            t = NaN;
            if isempty(value), return; end
            txt = char(string(value));
            if isempty(txt), return; end
            try
                t = datenum(txt, 'yyyy-mm-dd HH:MM:ss');
            catch
                try
                    t = datenum(datetime(txt));
                catch
                    t = NaN;
                end
            end
        end

        function tf = isWithinRunWindow(fileTime, startedTime, endedTime)
            tf = false;
            if isnan(fileTime) || isnan(startedTime)
                return;
            end
            tolerance = 1 / (24 * 60);
            if fileTime + tolerance < startedTime
                return;
            end
            if ~isnan(endedTime) && fileTime > endedTime + tolerance
                return;
            end
            tf = true;
        end

        function txt = recordFieldText(s, name)
            txt = '';
            if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
                txt = char(string(s.(name)));
            end
        end

        function value = recordFieldValue(s, name, fallback)
            value = fallback;
            if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
                value = s.(name);
            end
        end

        function newest = newestFirstLevelTimestamp(paths)
            newest = NaN;
            if isempty(paths), return; end
            if ischar(paths) || isstring(paths), paths = cellstr(string(paths)); end
            for i = 1:numel(paths)
                p = char(paths{i});
                if isfolder(p)
                    info = dir(p);
                    if ~isempty(info)
                        newest = max([newest, info(1).datenum]);
                    end
                    children = dir(fullfile(p, '*'));
                    children = children(~[children.isdir]);
                    if ~isempty(children)
                        newest = max([newest, max([children.datenum])]);
                    end
                elseif isfile(p)
                    info = dir(p);
                    newest = max([newest, info.datenum]);
                end
            end
        end

        function tf = optionEnabled(opts, name)
            tf = isstruct(opts) && isfield(opts, name) && ~isempty(opts.(name)) && logical(opts.(name));
        end

        function result = finalizeStatus(result)
            if ~isempty(result.errors)
                result.status = 'failed';
            elseif ~isempty(result.warnings)
                result.status = 'warning';
            else
                result.status = 'ok';
            end
        end

        function lines = toLogLines(result)
            lines = {};
            if ~isstruct(result)
                return;
            end
            profileName = '';
            profileId = '';
            if isfield(result, 'profile') && isstruct(result.profile)
                if isfield(result.profile, 'bridge_name'), profileName = char(string(result.profile.bridge_name)); end
                if isfield(result.profile, 'bridge_id'), profileId = char(string(result.profile.bridge_id)); end
            end
            layout = '';
            if isfield(result, 'data_layout') && isstruct(result.data_layout) && isfield(result.data_layout, 'layout')
                layout = char(string(result.data_layout.layout));
            end
            modules = {};
            if isfield(result, 'enabled_modules') && iscell(result.enabled_modules)
                modules = result.enabled_modules;
            end
            lines{end+1} = sprintf('preflight=%s, profile=%s (%s), layout=%s, modules=%d', ...
                char(string(result.status)), profileId, profileName, layout, numel(modules));
            if isfield(result, 'preflight_json') && ~isempty(result.preflight_json)
                lines{end+1} = ['preflight json=' char(string(result.preflight_json))];
            end
            if isfield(result, 'point_coverage') && ~isempty(result.point_coverage)
                coverageRows = bms.app.ManifestReader.recordsToCell(result.point_coverage);
                totalDesigned = 0;
                totalFound = 0;
                for i = 1:numel(coverageRows)
                    rec = coverageRows{i};
                    if ~isstruct(rec), continue; end
                    if isfield(rec, 'designed_count'), totalDesigned = totalDesigned + double(rec.designed_count); end
                    if isfield(rec, 'found_count'), totalFound = totalFound + double(rec.found_count); end
                end
                pct = 0;
                if totalDesigned > 0
                    pct = totalFound / totalDesigned * 100;
                end
                lines{end+1} = sprintf('point coverage=%d/%d (%.1f%%)', totalFound, totalDesigned, pct);
                shown = 0;
                for i = 1:numel(coverageRows)
                    rec = coverageRows{i};
                    if ~isstruct(rec) || ~isfield(rec, 'missing_count') || double(rec.missing_count) <= 0
                        continue;
                    end
                    shown = shown + 1;
                    lines{end+1} = sprintf('  missing: %s %d/%d missing', ...
                        char(string(rec.key)), double(rec.missing_count), double(rec.designed_count)); %#ok<AGROW>
                    if shown >= 5
                        break;
                    end
                end
            end
            if isfield(result, 'data_index') && isstruct(result.data_index) && isfield(result.data_index, 'summary')
                s = result.data_index.summary;
                lines{end+1} = sprintf('data index: modules=%d, points=%d, found=%d, missing=%d, files=%d', ...
                    bms.app.RunPreflight.numField(s, 'module_count'), ...
                    bms.app.RunPreflight.numField(s, 'point_count'), ...
                    bms.app.RunPreflight.numField(s, 'found_point_count'), ...
                    bms.app.RunPreflight.numField(s, 'missing_point_count'), ...
                    bms.app.RunPreflight.numField(s, 'file_count'));
                if isfield(result, 'data_index_path') && ~isempty(result.data_index_path)
                    lines{end+1} = ['data index json=' char(string(result.data_index_path))]; %#ok<AGROW>
                end
                if isfield(result, 'data_index_summary_path') && ~isempty(result.data_index_summary_path)
                    lines{end+1} = ['data index summary=' char(string(result.data_index_summary_path))]; %#ok<AGROW>
                end
            end
            if isfield(result, 'stats_inventory') && isstruct(result.stats_inventory) && isfield(result.stats_inventory, 'summary')
                s = result.stats_inventory.summary;
                lines{end+1} = sprintf('stats inventory: expected=%d, existing=%d, missing=%d, empty=%d, read_failed=%d', ...
                    bms.app.RunPreflight.numField(s, 'stats_expected_count'), ...
                    bms.app.RunPreflight.numField(s, 'stats_existing_count'), ...
                    bms.app.RunPreflight.numField(s, 'stats_missing_count'), ...
                    bms.app.RunPreflight.numField(s, 'stats_empty_count'), ...
                    bms.app.RunPreflight.numField(s, 'stats_read_failed_count'));
                if isfield(result, 'stats_inventory_path') && ~isempty(result.stats_inventory_path)
                    lines{end+1} = ['stats inventory json=' char(string(result.stats_inventory_path))]; %#ok<AGROW>
                end
                if isfield(result, 'stats_inventory_summary_path') && ~isempty(result.stats_inventory_summary_path)
                    lines{end+1} = ['stats inventory summary=' char(string(result.stats_inventory_summary_path))]; %#ok<AGROW>
                end
            end
            if isfield(result, 'run_health_report') && isstruct(result.run_health_report) && isfield(result.run_health_report, 'issue_counts')
                c = result.run_health_report.issue_counts;
                lines{end+1} = sprintf('run health: issues=%d, errors=%d, warnings=%d', ...
                    bms.app.RunPreflight.numField(c, 'total'), ...
                    bms.app.RunPreflight.numField(c, 'error'), ...
                    bms.app.RunPreflight.numField(c, 'warning'));
                if isfield(result, 'run_health_report_path') && ~isempty(result.run_health_report_path)
                    lines{end+1} = ['run health json=' char(string(result.run_health_report_path))]; %#ok<AGROW>
                end
                if isfield(result, 'run_health_report_summary_path') && ~isempty(result.run_health_report_summary_path)
                    lines{end+1} = ['run health summary=' char(string(result.run_health_report_summary_path))]; %#ok<AGROW>
                end
            end
            if isfield(result, 'reporting_contract') && isstruct(result.reporting_contract) && ...
                    isfield(result.reporting_contract, 'summary')
                s = result.reporting_contract.summary;
                lines{end+1} = sprintf('reporting contract: modules=%d, points=%d, groups=%d', ...
                    bms.app.RunPreflight.numField(s, 'module_count'), ...
                    bms.app.RunPreflight.numField(s, 'point_count'), ...
                    bms.app.RunPreflight.numField(s, 'group_count'));
                if isfield(result, 'reporting_contract_path') && ~isempty(result.reporting_contract_path)
                    lines{end+1} = ['reporting contract json=' char(string(result.reporting_contract_path))]; %#ok<AGROW>
                end
            end
            if isfield(result, 'warnings') && ~isempty(result.warnings)
                lines{end+1} = sprintf('preflight warnings=%d', numel(result.warnings));
                for i = 1:min(numel(result.warnings), 5)
                    lines{end+1} = ['  warn: ' char(string(result.warnings{i}))]; %#ok<AGROW>
                end
            end
            if isfield(result, 'errors') && ~isempty(result.errors)
                lines{end+1} = sprintf('preflight errors=%d', numel(result.errors));
                for i = 1:numel(result.errors)
                    lines{end+1} = ['  error: ' char(string(result.errors{i}))]; %#ok<AGROW>
                end
            end
        end

        function jsonPath = writeJson(requestOrRoot, preflight)
            jsonPath = '';
            try
                if isa(requestOrRoot, 'bms.app.RunRequest')
                    root = requestOrRoot.DataRoot;
                    logDir = requestOrRoot.LogDir;
                else
                    root = char(string(requestOrRoot));
                    logDir = bms.data.DataLayoutResolver.logDir(root);
                end
                if isempty(logDir)
                    logDir = bms.data.DataLayoutResolver.logDir(root);
                end
                if ~exist(logDir, 'dir')
                    mkdir(logDir);
                end
                ts = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
                jsonPath = fullfile(logDir, ['preflight_' ts '.json']);
                payload = preflight;
                payload.preflight_json = jsonPath;
                fid = fopen(jsonPath, 'w');
                if fid < 0
                    jsonPath = '';
                    return;
                end
                cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
                fprintf(fid, '%s', jsonencode(payload, 'PrettyPrint', true));
            catch
                jsonPath = '';
            end
        end

        function v = numField(s, field)
            v = 0;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field)) && isnumeric(s.(field))
                v = double(s.(field));
            end
        end
    end
end
