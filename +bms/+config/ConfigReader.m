classdef ConfigReader
    %CONFIGREADER Safe read-only accessors for nested config structs.

    methods (Static)
        function value = get(cfg, dottedPath, defaultValue)
            if nargin < 3
                defaultValue = [];
            end
            [ok, value] = bms.config.ConfigPatch.getPath(cfg, dottedPath);
            if ~ok || isempty(value)
                value = defaultValue;
            end
        end

        function value = getAllowEmpty(cfg, dottedPath, defaultValue)
            if nargin < 3
                defaultValue = [];
            end
            [ok, value] = bms.config.ConfigPatch.getPath(cfg, dottedPath);
            if ~ok
                value = defaultValue;
            end
        end

        function tf = has(cfg, dottedPath)
            tf = bms.config.ConfigPatch.getPath(cfg, dottedPath);
        end

        function value = getStruct(cfg, dottedPath, defaultValue)
            if nargin < 3
                defaultValue = struct();
            end
            value = bms.config.ConfigReader.get(cfg, dottedPath, defaultValue);
            if ~isstruct(value)
                value = defaultValue;
            end
        end

        function value = getSubfolder(cfg, key, defaultValue)
            if nargin < 3
                defaultValue = '';
            end
            value = bms.config.ConfigReader.get(cfg, ['subfolders.' char(string(key))], defaultValue);
        end

        function value = getPlotStyle(cfg, key, defaultValue)
            if nargin < 3
                defaultValue = struct();
            end
            value = defaultValue;
            ps = bms.config.ConfigReader.getStruct(cfg, ['plot_styles.' char(string(key))], struct());
            if isempty(fieldnames(ps))
                return;
            end
            ps = ps(1);
            value = bms.config.ConfigReader.mergeStruct(value, ps);
            value = bms.config.ConfigReader.applyPlotStyleAliases(value, ps, defaultValue);
        end

        function value = getField(s, fieldName, defaultValue)
            if nargin < 3
                defaultValue = [];
            end
            value = defaultValue;
            if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
                value = s.(fieldName);
            end
        end

        function value = getBool(cfg, dottedPath, defaultValue)
            if nargin < 3
                defaultValue = false;
            end
            raw = bms.config.ConfigReader.get(cfg, dottedPath, defaultValue);
            value = bms.config.ConfigReader.boolValue(raw, defaultValue);
        end

        function value = getNumeric(cfg, dottedPath, defaultValue)
            if nargin < 3
                defaultValue = [];
            end
            raw = bms.config.ConfigReader.get(cfg, dottedPath, defaultValue);
            if isnumeric(raw)
                value = raw;
            elseif isstring(raw) || ischar(raw)
                value = str2double(raw);
                if isnan(value)
                    value = defaultValue;
                end
            else
                value = defaultValue;
            end
        end

        function value = getColors(cfg, dottedPath, defaultValue)
            if nargin < 3
                defaultValue = [];
            end
            raw = bms.config.ConfigReader.get(cfg, dottedPath, defaultValue);
            value = bms.plot.PlotService.normalizeColors(raw, defaultValue);
        end

        function merged = mergeStruct(defaults, overrides)
            merged = defaults;
            if ~isstruct(merged)
                merged = struct();
            end
            if ~isstruct(overrides)
                return;
            end
            names = fieldnames(overrides);
            for i = 1:numel(names)
                merged.(names{i}) = overrides.(names{i});
            end
        end

        function style = applyPlotStyleAliases(style, overrides, defaults)
            if ~isstruct(overrides)
                return;
            end
            if isfield(overrides, 'colors')
                if isfield(defaults, 'colors')
                    style.colors = bms.plot.PlotService.normalizeColors(overrides.colors, defaults.colors);
                elseif isfield(style, 'colors')
                    style.colors = bms.plot.PlotService.normalizeColors(overrides.colors, style.colors);
                end

                cmat = bms.plot.PlotService.normalizeColors(overrides.colors, []);
                if isnumeric(cmat) && size(cmat, 1) >= 1
                    if isfield(style, 'color_main')
                        style.color_main = cmat(1, :);
                    end
                    if isfield(style, 'color_rms') && size(cmat, 1) >= 2
                        style.color_rms = cmat(2, :);
                    end
                end
            end

            if isfield(overrides, 'rms') && isstruct(overrides.rms)
                rms = overrides.rms(1);
                if isfield(rms, 'ylabel'), style.rms_ylabel = rms.ylabel; end
                if isfield(rms, 'title_prefix'), style.rms_title_prefix = rms.title_prefix; end
                if isfield(rms, 'ylim'), style.rms_ylim = rms.ylim; end
                if isfield(rms, 'ylims'), style.rms_ylims = rms.ylims; end
                if isfield(rms, 'color'), style.color_rms = rms.color; end
            end
        end

        function tf = boolValue(value, defaultValue)
            if nargin < 2
                defaultValue = false;
            end
            if islogical(value) && isscalar(value)
                tf = value;
            elseif isnumeric(value) && isscalar(value) && isfinite(value)
                tf = value ~= 0;
            elseif isstring(value) || ischar(value)
                txt = lower(strtrim(char(string(value))));
                if any(strcmp(txt, {'true','yes','on','1'}))
                    tf = true;
                elseif any(strcmp(txt, {'false','no','off','0'}))
                    tf = false;
                else
                    tf = logical(defaultValue);
                end
            else
                tf = logical(defaultValue);
            end
        end
    end
end
