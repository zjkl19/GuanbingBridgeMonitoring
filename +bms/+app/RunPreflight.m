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
            result.wim_month_files = struct('month', {}, 'fmt', {}, 'bcp', {}, 'exists', {});

            result = bms.app.RunPreflight.checkDateRange(result, startDate, endDate);
            result = bms.app.RunPreflight.checkRoot(result, root);
            result = bms.app.RunPreflight.checkConfig(result, cfg);
            result = bms.app.RunPreflight.attachProfileAndLayout(result, root, cfg);
            result = bms.app.RunPreflight.attachModuleInfo(result, root, opts);
            result = bms.app.RunPreflight.checkEnabledModuleConfig(result, root, startDate, endDate, opts, cfg);
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
            if ~isfield(cfg.file_patterns, key)
                tf = false;
                return;
            end
            value = cfg.file_patterns.(key);
            tf = ~isempty(value);
        end

        function result = checkWimInputs(result, root, startDate, endDate, opts, cfg)
            if ~bms.app.RunPreflight.optionEnabled(opts, 'doWIM')
                return;
            end
            prefix = 'HS_Data_';
            if isstruct(cfg) && isfield(cfg, 'wim') && isstruct(cfg.wim) ...
                    && isfield(cfg.wim, 'file_prefix') && ~isempty(cfg.wim.file_prefix)
                prefix = char(string(cfg.wim.file_prefix));
            end
            try
                files = bms.data.DataLayoutResolver.wimMonthFiles(root, startDate, endDate, prefix);
                result.wim_month_files = files;
                for i = 1:numel(files)
                    if ~files(i).exists
                        result.warnings{end+1} = sprintf('WIM input missing for %s: fmt=%s; bcp=%s', ...
                            files(i).month, files(i).fmt, files(i).bcp); %#ok<AGROW>
                    end
                end
            catch ME
                result.warnings{end+1} = ['WIM preflight failed: ' ME.message];
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
