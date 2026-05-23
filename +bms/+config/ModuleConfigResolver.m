classdef ModuleConfigResolver
    %MODULECONFIGRESOLVER Unified read access for module config sections.

    methods (Static)
        function spec = spec(module)
            spec = bms.config.ModuleConfigRegistry.normalize(module);
        end

        function style = resolvePlotStyle(cfg, module, defaultStyle)
            if nargin < 3
                defaultStyle = struct();
            end
            raw = bms.config.ModuleConfigResolver.rawPlotStyle(cfg, module);
            style = bms.config.ConfigReader.mergeStruct(defaultStyle, raw);
        end

        function style = rawPlotStyle(cfg, module)
            spec = bms.config.ModuleConfigResolver.spec(module);
            style = struct();
            if ~isstruct(cfg) || ~isfield(cfg, 'plot_styles') || ~isstruct(cfg.plot_styles) || ...
                    isempty(spec.style_key) || ~isfield(cfg.plot_styles, spec.style_key) || ...
                    ~isstruct(cfg.plot_styles.(spec.style_key))
                return;
            end
            block = cfg.plot_styles.(spec.style_key);
            if isempty(spec.section)
                style = block;
            elseif isfield(block, spec.section) && isstruct(block.(spec.section))
                style = block.(spec.section);
            end
        end

        function cfg = setPlotStyle(cfg, module, style)
            spec = bms.config.ModuleConfigResolver.spec(module);
            if ~isfield(cfg, 'plot_styles') || ~isstruct(cfg.plot_styles)
                cfg.plot_styles = struct();
            end
            if isempty(spec.section)
                cfg.plot_styles.(spec.style_key) = style;
                return;
            end
            if ~isfield(cfg.plot_styles, spec.style_key) || ~isstruct(cfg.plot_styles.(spec.style_key))
                cfg.plot_styles.(spec.style_key) = struct();
            end
            cfg.plot_styles.(spec.style_key).(spec.section) = style;
        end

        function params = resolveParams(cfg, module)
            spec = bms.config.ModuleConfigResolver.spec(module);
            params = struct();
            if ~isempty(spec.params_key) && isstruct(cfg) && isfield(cfg, spec.params_key) && isstruct(cfg.(spec.params_key))
                params = cfg.(spec.params_key);
            end
        end

        function points = resolvePoints(cfg, module, fallback)
            if nargin < 3
                fallback = {};
            end
            spec = bms.config.ModuleConfigResolver.spec(module);
            points = bms.data.PointResolver.normalize(fallback);
            if isstruct(cfg) && isfield(cfg, 'points') && isstruct(cfg.points) && ...
                    ~isempty(spec.point_key) && isfield(cfg.points, spec.point_key)
                points = bms.data.PointResolver.normalize(cfg.points.(spec.point_key));
            end
            if isempty(points)
                groups = bms.config.ModuleConfigResolver.resolveGroups(cfg, spec);
                names = fieldnames(groups);
                for i = 1:numel(names)
                    points = [points; groups.(names{i})(:)]; %#ok<AGROW>
                end
                points = bms.data.PointResolver.uniqueText(points);
            end
        end

        function groups = resolveGroups(cfg, module)
            spec = bms.config.ModuleConfigResolver.spec(module);
            groups = struct();
            if ~isstruct(cfg) || ~isfield(cfg, 'groups') || ~isstruct(cfg.groups)
                return;
            end
            keys = bms.config.ModuleConfigResolver.groupAliases(spec);
            for i = 1:numel(keys)
                key = keys{i};
                if isfield(cfg.groups, key)
                    groups = bms.data.PointResolver.normalizeGroups(cfg.groups.(key));
                    return;
                end
            end
        end

        function value = resolveSubfolder(cfg, module, defaultValue)
            if nargin < 3
                defaultValue = '';
            end
            spec = bms.config.ModuleConfigResolver.spec(module);
            value = defaultValue;
            if ~isstruct(cfg) || ~isfield(cfg, 'subfolders') || ~isstruct(cfg.subfolders)
                return;
            end
            aliases = bms.config.ModuleConfigRegistry.aliasesForKey(spec.value);
            for i = 1:numel(aliases)
                key = aliases{i};
                if isfield(cfg.subfolders, key)
                    value = cfg.subfolders.(key);
                    return;
                end
            end
        end

        function aliases = groupAliases(spec)
            spec = bms.config.ModuleConfigRegistry.normalize(spec);
            aliases = {spec.group_key, spec.point_key, spec.style_key, spec.value};
            if strcmp(spec.value, 'strain')
                aliases = [{'strain_timeseries'}, aliases];
            elseif strcmp(spec.value, 'dynamic_strain')
                aliases = [{'dynamic_strain', 'strain_timeseries', 'strain'}, aliases];
            elseif strcmp(spec.value, 'dynamic_strain_lowpass')
                aliases = [{'dynamic_strain_lowpass', 'dynamic_strain', 'strain_timeseries', 'strain'}, aliases];
            end
            aliases = unique(aliases(~cellfun(@isempty, aliases)), 'stable');
        end
    end
end
