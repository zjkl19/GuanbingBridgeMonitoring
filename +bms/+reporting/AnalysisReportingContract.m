classdef AnalysisReportingContract
    %ANALYSISREPORTINGCONTRACT Declares MATLAB outputs consumed by reports.

    methods (Static)
        function contract = build(cfg, opts)
            if nargin < 1 || isempty(cfg)
                cfg = struct();
            end
            if nargin < 2 || isempty(opts)
                opts = struct();
            end

            specs = bms.module.ModuleRegistry.enabledFromOptions(opts);
            if isempty(specs)
                specs = bms.module.ModuleRegistry.forCategory('analysis');
            end

            contract = struct();
            contract.schema_version = 1;
            contract.contract_type = 'analysis_reporting_contract';
            contract.created_at = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss');
            contract.profile = bms.reporting.AnalysisReportingContract.profileStruct(cfg);
            contract.modules = {};
            contract.summary = struct('module_count', 0, 'point_count', 0, 'group_count', 0);

            for i = 1:numel(specs)
                spec = specs(i);
                if strcmp(spec.Category, 'preprocess') || strcmp(spec.Key, 'wim')
                    continue;
                end
                rec = bms.reporting.AnalysisReportingContract.moduleRecord(cfg, spec);
                contract.modules{end+1} = rec; %#ok<AGROW>
                contract.summary.module_count = contract.summary.module_count + 1;
                contract.summary.point_count = contract.summary.point_count + rec.point_count;
                contract.summary.group_count = contract.summary.group_count + rec.group_count;
            end
        end

        function rec = moduleRecord(cfg, moduleSpec)
            cfgSpec = bms.config.ModuleConfigRegistry.normalize(moduleSpec.Key);
            points = bms.config.ModuleConfigResolver.resolvePoints(cfg, cfgSpec, {});
            groups = bms.config.ModuleConfigResolver.resolveGroups(cfg, cfgSpec);
            style = bms.config.ModuleConfigResolver.rawPlotStyle(cfg, cfgSpec);
            subfolder = bms.config.ModuleConfigResolver.resolveSubfolder(cfg, moduleSpec.SubfolderKey, '');

            rec = struct();
            rec.key = moduleSpec.Key;
            rec.label = moduleSpec.Label;
            rec.category = moduleSpec.Category;
            rec.stats_file = moduleSpec.StatsFile;
            rec.subfolder_key = moduleSpec.SubfolderKey;
            rec.subfolder = subfolder;
            rec.config = struct( ...
                'value', cfgSpec.value, ...
                'style_key', cfgSpec.style_key, ...
                'section', cfgSpec.section, ...
                'point_key', cfgSpec.point_key, ...
                'per_point_key', cfgSpec.per_point_key, ...
                'group_key', cfgSpec.group_key, ...
                'params_key', cfgSpec.params_key);
            rec.points = points(:)';
            rec.point_count = numel(points);
            rec.groups = bms.reporting.AnalysisReportingContract.groupRecords(groups);
            rec.group_count = numel(rec.groups);
            rec.output_dir_records = bms.reporting.AnalysisReportingContract.collectOutputDirRecords(style);
            rec.output_dirs = bms.reporting.AnalysisReportingContract.outputDirsFromRecords(rec.output_dir_records);
            rec.warn_fields = cfgSpec.warn_fields(:)';
            rec.is_spectrum = logical(cfgSpec.is_spectrum);
        end

        function path = write(root, contract, runId)
            if nargin < 3 || isempty(runId)
                runId = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
            end
            logDir = bms.data.DataLayoutResolver.logDir(root);
            bms.data.DataLayoutResolver.ensureDir(logDir);
            path = fullfile(logDir, ['analysis_reporting_contract_' char(string(runId)) '.json']);
            bms.core.Logger.writeJson(path, contract);
        end
    end

    methods (Static, Access = private)
        function profile = profileStruct(cfg)
            profile = struct('bridge_id', '', 'bridge_name', '', 'vendor', '');
            try
                p = bms.profile.BridgeProfileRegistry.infer(cfg, '');
                if isa(p, 'bms.profile.BridgeProfile')
                    profile.bridge_id = p.BridgeId;
                    profile.bridge_name = p.BridgeName;
                end
            catch
            end
            if isstruct(cfg) && isfield(cfg, 'vendor') && ~isempty(cfg.vendor)
                profile.vendor = char(string(cfg.vendor));
            end
        end

        function records = groupRecords(groups)
            records = {};
            if ~isstruct(groups)
                return;
            end
            names = fieldnames(groups);
            for i = 1:numel(names)
                pts = bms.data.PointResolver.normalize(groups.(names{i}));
                records{end+1} = struct('name', names{i}, 'points', {pts(:)'}, ...
                    'point_count', numel(pts)); %#ok<AGROW>
            end
        end

        function dirs = collectOutputDirs(style)
            records = bms.reporting.AnalysisReportingContract.collectOutputDirRecords(style);
            dirs = bms.reporting.AnalysisReportingContract.outputDirsFromRecords(records);
        end

        function dirs = outputDirsFromRecords(records)
            dirs = {};
            if isempty(records) || ~isstruct(records)
                return;
            end
            for i = 1:numel(records)
                if isfield(records(i), 'dir') && ~isempty(records(i).dir)
                    dirs{end+1} = records(i).dir; %#ok<AGROW>
                end
            end
            dirs = unique(dirs(~cellfun(@isempty, dirs)), 'stable');
        end

        function records = collectOutputDirRecords(style)
            records = struct('field', {}, 'dir', {}, 'role', {});
            if ~isstruct(style)
                return;
            end
            records = bms.reporting.AnalysisReportingContract.collectOutputDirRecordsRecursive(style, '');
            if isempty(records)
                return;
            end
            keys = cellfun(@(a, b) [a '=' b], {records.field}, {records.dir}, 'UniformOutput', false);
            [~, idx] = unique(keys, 'stable');
            records = records(idx);
        end

        function records = collectOutputDirRecordsRecursive(s, prefix)
            records = struct('field', {}, 'dir', {}, 'role', {});
            if ~isstruct(s)
                return;
            end
            names = fieldnames(s);
            for i = 1:numel(names)
                name = names{i};
                value = s.(name);
                pathName = name;
                if ~isempty(prefix)
                    pathName = [prefix '.' name];
                end
                if (strcmp(name, 'output_dir') || endsWith(name, '_output_dir')) && ...
                        (ischar(value) || isstring(value)) && ~isempty(value)
                    records(end+1) = struct( ...
                        'field', pathName, ...
                        'dir', char(string(value)), ...
                        'role', bms.reporting.AnalysisReportingContract.outputDirRole(pathName)); %#ok<AGROW>
                elseif isstruct(value)
                    records = [records, bms.reporting.AnalysisReportingContract.collectOutputDirRecordsRecursive(value, pathName)]; %#ok<AGROW>
                end
            end
        end

        function role = outputDirRole(fieldPath)
            text = lower(char(string(fieldPath)));
            if contains(text, 'group')
                role = 'group_plot';
            elseif contains(text, 'stats') || contains(text, 'table')
                role = 'stats';
            elseif contains(text, 'box')
                role = 'boxplot';
            elseif contains(text, 'spec') || contains(text, 'spectrum') || contains(text, 'freq')
                role = 'spectrum';
            elseif contains(text, 'rms')
                role = 'rms_plot';
            else
                role = 'single_plot';
            end
        end
    end
end
