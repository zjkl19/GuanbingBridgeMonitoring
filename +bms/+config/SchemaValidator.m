classdef SchemaValidator
    %SCHEMAVALIDATOR Lightweight config schema checks for preflight use.

    methods (Static)
        function warns = validate(cfg)
            result = bms.config.SchemaValidator.validateDetailed(cfg);
            warns = result.warnings;
        end

        function result = validateDetailed(cfg)
            result = struct('status', 'ok', 'errors', {{}}, 'warnings', {{}}, 'checked_at', datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss'));
            if ~isstruct(cfg)
                result.status = 'failed';
                result.errors{end+1} = 'cfg must be a struct';
                return;
            end

            result.warnings = [result.warnings, bms.config.SchemaValidator.checkTopLevel(cfg)];
            result.warnings = [result.warnings, bms.config.SchemaValidator.checkModuleKeys(cfg)];
            result.warnings = [result.warnings, bms.config.SchemaValidator.checkPerPoint(cfg)];
            result.warnings = [result.warnings, bms.config.SchemaValidator.checkFilePatterns(cfg)];
            result.warnings = [result.warnings, bms.config.SchemaValidator.checkPlotStyles(cfg)];
            result.warnings = [result.warnings, bms.config.SchemaValidator.checkAnalyzerModules(cfg)];
            result.warnings = [result.warnings, bms.config.SchemaValidator.checkWim(cfg)];
            if ~isempty(result.errors)
                result.status = 'failed';
            elseif ~isempty(result.warnings)
                result.status = 'warning';
            end
        end

        function warns = checkTopLevel(cfg)
            warns = {};
            required = {'defaults','subfolders','file_patterns','points','plot_styles'};
            for i = 1:numel(required)
                if ~isfield(cfg, required{i})
                    warns{end+1} = ['missing top-level field: ' required{i}]; %#ok<AGROW>
                end
            end
            optional = {'per_point','post_filter_thresholds','plot_common','reporting','wim','vendor'};
            for i = 1:numel(optional)
                if isfield(cfg, optional{i}) && ~isstruct(cfg.(optional{i}))
                    warns{end+1} = ['top-level field should be struct: ' optional{i}]; %#ok<AGROW>
                end
            end
        end

        function warns = checkModuleKeys(cfg)
            warns = {};
            known = bms.module.ModuleRegistry.knownConfigKeys();
            sections = {'points','plot_styles','subfolders','post_filter_thresholds'};
            for s = 1:numel(sections)
                section = sections{s};
                if ~isfield(cfg, section) || ~isstruct(cfg.(section))
                    continue;
                end
                names = fieldnames(cfg.(section));
                for i = 1:numel(names)
                    key = names{i};
                    if startsWith(key, '_') || ismember(key, {'global','common'})
                        continue;
                    end
                    if ~ismember(key, known)
                        warns{end+1} = [section '.' key ' is not registered in ModuleRegistry']; %#ok<AGROW>
                    end
                end
            end

            if isfield(cfg, 'points') && isstruct(cfg.points)
                names = fieldnames(cfg.points);
                for i = 1:numel(names)
                    key = names{i};
                    if isfield(cfg, 'subfolders') && isstruct(cfg.subfolders) && ~isfield(cfg.subfolders, key) ...
                            && ~ismember(key, {'temp_humidity','accel_spectrum','cable_accel_spectrum','cable_force','wind','eq','acceleration_raw','cable_accel_raw'})
                        warns{end+1} = ['points.' key ' has no matching subfolders.' key]; %#ok<AGROW>
                    end
                end
            end
        end

        function warns = checkPerPoint(cfg)
            warns = {};
            if ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point)
                return;
            end
            modules = fieldnames(cfg.per_point);
            for i = 1:numel(modules)
                pts = cfg.per_point.(modules{i});
                if ~isstruct(pts), continue; end
                pnames = fieldnames(pts);
                for j = 1:numel(pnames)
                    rule = pts.(pnames{j});
                    if isfield(rule, 'thresholds') && ~isempty(rule.thresholds)
                        ths = rule.thresholds;
                        for k = 1:numel(ths)
                            if ~isfield(ths(k), 'min') || ~isfield(ths(k), 'max')
                                warns{end+1} = ['threshold missing min/max: per_point.' modules{i} '.' pnames{j}]; %#ok<AGROW>
                            elseif isnumeric(ths(k).min) && isnumeric(ths(k).max) && ths(k).min > ths(k).max
                                warns{end+1} = ['threshold min > max: per_point.' modules{i} '.' pnames{j}]; %#ok<AGROW>
                            end
                        end
                    end
                end
            end
        end

        function warns = checkFilePatterns(cfg)
            warns = {};
            if ~isfield(cfg, 'file_patterns') || ~isstruct(cfg.file_patterns)
                return;
            end
            names = fieldnames(cfg.file_patterns);
            for i = 1:numel(names)
                item = cfg.file_patterns.(names{i});
                if ~isstruct(item)
                    warns{end+1} = ['file_patterns.' names{i} ' should be struct']; %#ok<AGROW>
                    continue;
                end
                if ~isfield(item, 'default') && ~isfield(item, 'per_point')
                    warns{end+1} = ['file_patterns.' names{i} ' has neither default nor per_point']; %#ok<AGROW>
                end
            end
        end

        function warns = checkWim(cfg)
            warns = {};
            if ~isfield(cfg, 'wim') || ~isstruct(cfg.wim)
                return;
            end
            if isfield(cfg.wim, 'pipeline') && ~(ischar(cfg.wim.pipeline) || isstring(cfg.wim.pipeline))
                warns{end+1} = 'wim.pipeline should be string';
            end
            if isfield(cfg.wim, 'db') && ~isstruct(cfg.wim.db)
                warns{end+1} = 'wim.db should be struct';
            end
        end

        function warns = checkPlotStyles(cfg)
            warns = {};
            if ~isfield(cfg, 'plot_styles') || ~isstruct(cfg.plot_styles)
                return;
            end
            names = fieldnames(cfg.plot_styles);
            for i = 1:numel(names)
                style = cfg.plot_styles.(names{i});
                if ~isstruct(style), continue; end
                if isfield(style, 'ylim') && ~isempty(style.ylim) && ~bms.plot.PlotService.isValidYLim(style.ylim)
                    warns{end+1} = ['plot_styles.' names{i} '.ylim is not a valid 1x2 range']; %#ok<AGROW>
                end
                if isfield(style, 'ylim_auto') && ~(islogical(style.ylim_auto) || isnumeric(style.ylim_auto))
                    warns{end+1} = ['plot_styles.' names{i} '.ylim_auto should be boolean']; %#ok<AGROW>
                end
            end
        end

        function warns = checkAnalyzerModules(cfg)
            warns = {};
            keys = {'temperature','humidity','rainfall','deflection','crack'};
            for i = 1:numel(keys)
                key = keys{i};
                if isfield(cfg, 'points') && isstruct(cfg.points) && isfield(cfg.points, key) && isempty(cfg.points.(key))
                    warns{end+1} = ['points.' key ' is configured but empty']; %#ok<AGROW>
                end
                if isfield(cfg, 'subfolders') && isstruct(cfg.subfolders) && isfield(cfg.subfolders, key)
                    value = cfg.subfolders.(key);
                    if ~(ischar(value) || isstring(value))
                        warns{end+1} = ['subfolders.' key ' should be text']; %#ok<AGROW>
                    end
                end
            end
        end
    end
end
