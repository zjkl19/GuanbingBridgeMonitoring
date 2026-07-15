classdef PlotOptionResolver
    %PLOTOPTIONRESOLVER Resolve inherited plot settings in one place.
    % Precedence for gap rendering is:
    %   per-point plot > module plot style > legacy dynamic raw module > global.

    methods (Static)
        function gap = effectiveGap(cfg, moduleKey, pointId)
            if nargin < 2, moduleKey = ''; end
            if nargin < 3, pointId = ''; end
            if ~isstruct(cfg) || isempty(cfg), cfg = struct(); else, cfg = cfg(1); end
            moduleKey = strtrim(char(string(moduleKey)));
            pointId = strtrim(char(string(pointId)));

            gap = struct( ...
                'gap_mode', bms.plot.PlotOptionResolver.validMode( ...
                    bms.config.ConfigReader.get(cfg, 'plot_common.gap_mode', 'connect'), 'connect'), ...
                'gap_break_factor', bms.plot.PlotOptionResolver.validFactor( ...
                    bms.config.ConfigReader.get(cfg, 'plot_common.gap_break_factor', 5), 5), ...
                'mode_source', 'global', ...
                'factor_source', 'global');

            if ~isempty(moduleKey) && isfield(cfg, 'plot_common') && ...
                    isstruct(cfg.plot_common) && ...
                    isfield(cfg.plot_common, 'dynamic_raw_modules') && ...
                    isstruct(cfg.plot_common.dynamic_raw_modules)
                gap = bms.plot.PlotOptionResolver.applyLayer( ...
                    gap, cfg.plot_common.dynamic_raw_modules, ...
                    bms.plot.PlotOptionResolver.layerKeys(moduleKey, 'legacy'), ...
                    'legacy_module');
            end

            if ~isempty(moduleKey) && isfield(cfg, 'plot_styles') && ...
                    isstruct(cfg.plot_styles)
                gap = bms.plot.PlotOptionResolver.applyLayer( ...
                    gap, cfg.plot_styles, ...
                    bms.plot.PlotOptionResolver.layerKeys(moduleKey, 'style'), ...
                    'module');
            end

            if ~isempty(moduleKey) && ~isempty(pointId) && ...
                    isfield(cfg, 'per_point') && isstruct(cfg.per_point)
                pointKeys = bms.plot.PlotOptionResolver.layerKeys(moduleKey, 'point');
                % Compatibility roots are applied first; an explicit root
                % matching the running analysis module wins field by field.
                for i = numel(pointKeys):-1:1
                    key = pointKeys{i};
                    if ~isfield(cfg.per_point, key) || ~isstruct(cfg.per_point.(key))
                        continue;
                    end
                    [found, pointCfg] = bms.data.PointResolver.getPointConfig( ...
                        cfg.per_point.(key), pointId, cfg);
                    if found && isstruct(pointCfg) && isfield(pointCfg, 'plot')
                        gap = bms.plot.PlotOptionResolver.applyOverride( ...
                            gap, pointCfg.plot, 'point');
                    end
                end
            end
        end

        function cfgOut = materializeGap(cfg, moduleKey, pointId)
            if nargin < 2, moduleKey = ''; end
            if nargin < 3, pointId = ''; end
            if ~isstruct(cfg) || isempty(cfg), cfgOut = struct(); else, cfgOut = cfg(1); end
            gap = bms.plot.PlotOptionResolver.effectiveGap(cfgOut, moduleKey, pointId);
            if ~isfield(cfgOut, 'plot_common') || ~isstruct(cfgOut.plot_common)
                cfgOut.plot_common = struct();
            end
            cfgOut.plot_common.gap_mode = gap.gap_mode;
            cfgOut.plot_common.gap_break_factor = gap.gap_break_factor;
        end
    end

    methods (Static, Access = private)
        function gap = applyLayer(gap, container, keys, source)
            if ~isstruct(container) || isempty(container)
                return;
            end
            container = container(1);
            for i = numel(keys):-1:1
                key = keys{i};
                if isfield(container, key)
                    gap = bms.plot.PlotOptionResolver.applyOverride( ...
                        gap, container.(key), source);
                end
            end
        end

        function keys = layerKeys(moduleKey, layer)
            moduleKey = strtrim(char(string(moduleKey)));
            keys = {moduleKey};
            if isempty(moduleKey)
                keys = {};
                return;
            end
            try
                spec = bms.config.ModuleConfigRegistry.fromKey(moduleKey);
                switch lower(char(string(layer)))
                    case 'style'
                        candidates = {spec.style_key, spec.value};
                    case 'point'
                        candidates = {spec.per_point_key, spec.point_key, ...
                            spec.style_key, spec.value};
                    otherwise
                        candidates = {spec.value, spec.style_key};
                end
                keys = [keys, candidates]; %#ok<AGROW>
            catch
                % The explicit key remains usable even for a future module
                % that has not yet been registered.
            end
            keys = bms.plot.PlotOptionResolver.uniqueText(keys);
        end

        function values = uniqueText(values)
            out = {};
            for i = 1:numel(values)
                value = strtrim(char(string(values{i})));
                if ~isempty(value) && ~any(strcmp(out, value))
                    out{end+1} = value; %#ok<AGROW>
                end
            end
            values = out;
        end

        function gap = applyOverride(gap, raw, source)
            if ~isstruct(raw) || isempty(raw)
                return;
            end
            raw = raw(1);
            if isfield(raw, 'gap_mode') && ~isempty(raw.gap_mode)
                candidate = bms.plot.PlotOptionResolver.validMode(raw.gap_mode, '');
                if ~isempty(candidate)
                    gap.gap_mode = candidate;
                    gap.mode_source = source;
                end
            end
            if isfield(raw, 'gap_break_factor') && ~isempty(raw.gap_break_factor)
                candidate = bms.plot.PlotOptionResolver.validFactor(raw.gap_break_factor, NaN);
                if isfinite(candidate)
                    gap.gap_break_factor = candidate;
                    gap.factor_source = source;
                end
            end
        end

        function mode = validMode(value, fallback)
            mode = lower(strtrim(char(string(value))));
            if ~any(strcmp(mode, {'connect', 'break'}))
                mode = fallback;
            end
        end

        function factor = validFactor(value, fallback)
            factor = fallback;
            if isnumeric(value) && isscalar(value) && isfinite(value) && value >= 1.1
                factor = double(value);
                return;
            end
            parsed = str2double(char(string(value)));
            if isscalar(parsed) && isfinite(parsed) && parsed >= 1.1
                factor = double(parsed);
            end
        end
    end
end
