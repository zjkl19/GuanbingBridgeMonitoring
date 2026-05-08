classdef RunPreflight
    %RUNPREFLIGHT Fast checks before launching a long analysis run.

    methods (Static)
        function result = check(root, startDate, endDate, opts, cfg)
            if nargin >= 1 && isa(root, 'bms.app.RunRequest')
                request = root;
                root = request.DataRoot;
                startDate = request.StartDate;
                endDate = request.EndDate;
                opts = request.Options;
                cfg = request.Config;
            end
            if nargin < 4 || isempty(opts), opts = struct(); end
            if nargin < 5 || isempty(cfg), cfg = struct(); end

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
            result.result_artifact_preflight = {};
            result.wim_month_files = struct('month', {}, 'fmt', {}, 'bcp', {}, 'exists', {});
            result.wim_preflight = struct();

            result = bms.app.RunPreflight.checkDateRange(result, startDate, endDate);
            result = bms.app.RunPreflight.checkRoot(result, root);
            result = bms.app.RunPreflight.checkConfig(result, cfg);
            result = bms.app.RunPreflight.attachProfileAndLayout(result, root, cfg);
            result = bms.app.RunPreflight.attachModuleInfo(result, root, opts);
            result = bms.app.RunPreflight.checkEnabledModuleConfig(result, root, startDate, endDate, opts, cfg);
            result = bms.app.RunPreflight.checkResultArtifacts(result, root, startDate, endDate, opts, cfg);
            result = bms.app.RunPreflight.checkWimInputs(result, root, startDate, endDate, opts, cfg);
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
                validation = bms.config.SchemaValidator.validateDetailed(cfg);
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

                    if isfield(cfg, 'points') && isstruct(cfg.points) && isfield(cfg.points, spec.Key)
                        points = cfg.points.(spec.Key);
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

        function [tf, value] = resolveSubfolder(cfg, key)
            tf = false;
            value = '';
            if ~isstruct(cfg) || ~isfield(cfg, 'subfolders') || ~isstruct(cfg.subfolders)
                return;
            end
            key = char(key);
            candidates = {key};
            switch key
                case 'wind_raw'
                    candidates = {'wind_raw', 'wind'};
                case 'eq_raw'
                    candidates = {'eq_raw', 'eq', 'earthquake'};
                case 'acceleration_raw'
                    candidates = {'acceleration_raw', 'acceleration'};
                case 'cable_accel_raw'
                    candidates = {'cable_accel_raw', 'cable_accel'};
            end
            for i = 1:numel(candidates)
                if isfield(cfg.subfolders, candidates{i})
                    tf = true;
                    value = char(string(cfg.subfolders.(candidates{i})));
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
    end
end
