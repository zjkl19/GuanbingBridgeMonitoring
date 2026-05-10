classdef StructuralPlotConfigService
    %STRUCTURALPLOTCONFIGSERVICE Shared config helpers for structural plots.

    methods (Static)
        function groups = getGroups(cfg, key, fallback)
            if nargin < 3
                fallback = [];
            end
            groups = fallback;
            if isstruct(cfg) && isfield(cfg, 'groups') && isstruct(cfg.groups) && isfield(cfg.groups, key)
                groups = cfg.groups.(key);
            end
        end

        function groups = normalizeGroupMap(groupsCfg)
            groups = bms.data.PointResolver.normalizeGroups(groupsCfg);
        end

        function tf = hasGroups(groupsCfg)
            tf = bms.data.PointResolver.hasGroups(groupsCfg);
        end

        function tf = hasGroupConfig(groupsCfg)
            tf = isstruct(groupsCfg) && ~isempty(fieldnames(groupsCfg));
        end

        function pts = flattenGroups(groupsCfg)
            pts = bms.data.PointResolver.flattenGroups(groupsCfg);
        end

        function pts = flattenGroupPoints(groupsCfg)
            pts = bms.analyzer.StructuralPlotConfigService.flattenGroups(groupsCfg);
        end

        function pts = getPoints(cfg, key, fallback)
            if nargin < 3
                fallback = {};
            end
            pts = bms.data.PointResolver.fromConfig(cfg, key, fallback);
        end

        function pts = getPointsOrFlattenFallback(cfg, key, fallbackGroups)
            if isstruct(cfg) && isfield(cfg, 'points') && isstruct(cfg.points) && isfield(cfg.points, key)
                pts = bms.data.PointResolver.normalize(cfg.points.(key));
            else
                pts = bms.analyzer.StructuralPlotConfigService.flattenGroups(fallbackGroups);
            end
        end

        function pts = normalizePoints(points)
            pts = bms.data.PointResolver.normalize(points);
        end

        function style = getStyle(cfg, key)
            style = bms.config.ConfigReader.getPlotStyle(cfg, key);
        end

        function val = getStyleField(style, field, defaultValue)
            val = bms.config.ConfigReader.getField(style, field, defaultValue);
        end

        function y = resolveNamedYLim(style, name, defaultValue)
            ylims = bms.config.ConfigReader.getField(style, 'ylims', []);
            y = bms.plot.PlotService.resolveNamedYLim(ylims, name, defaultValue);
        end

        function y = defaultYLim(style)
            y = [];
            if ~isstruct(style)
                return;
            end
            ylimAuto = false;
            if isfield(style, 'ylim_auto') && ~isempty(style.ylim_auto)
                ylimAuto = logical(style.ylim_auto);
            end
            if ~ylimAuto && isfield(style, 'ylim')
                y = style.ylim;
            end
        end

        function ok = isValidYLim(value)
            ok = bms.plot.PlotService.isValidYLim(value);
        end

        function colors = normalizeColors(raw, defaultColors)
            if nargin < 2
                defaultColors = {};
            end
            colors = bms.plot.PlotService.normalizeColors(raw, defaultColors);
        end

        function colors = groupColors(style, nSeries, fieldName, defaultColors)
            if nargin < 3 || isempty(fieldName)
                fieldName = 'colors_6';
            end
            if nargin < 4 || isempty(defaultColors)
                defaultColors = [
                    0.0000 0.4470 0.7410
                    0.8500 0.3250 0.0980
                    0.9290 0.6940 0.1250
                    0.4940 0.1840 0.5560
                    0.4660 0.6740 0.1880
                    0.3010 0.7450 0.9330
                ];
            end

            raw = bms.analyzer.StructuralPlotConfigService.getStyleField(style, fieldName, defaultColors);
            colors = bms.plot.PlotService.normalizeColors(raw, defaultColors);
            if size(colors, 1) < nSeries
                colors = bms.analyzer.StructuralPlotConfigService.distinctColors(nSeries);
            else
                colors = colors(1:nSeries, :);
            end
        end

        function colors = distinctColors(nSeries)
            if exist('turbo', 'builtin') == 5 || exist('turbo', 'file') == 2
                colors = turbo(nSeries);
                return;
            end

            idx = (0:nSeries-1)';
            hues = mod(idx * 0.61803398875, 1.0);
            sat = 0.65 + 0.20 * mod(idx * 0.31, 1.0);
            val = 0.78 + 0.18 * mod(idx * 0.47, 1.0);
            colors = hsv2rgb([hues, sat, val]);
        end

        function warnLines = resolveWarnLines(style, cfg, key, pid)
            warnLines = {};
            globalWarn = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'warn_lines', {});
            if ~isempty(globalWarn)
                warnLines = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(globalWarn);
            end
            if isempty(pid) || ~isstruct(cfg) || ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point) || ...
                    ~isfield(cfg.per_point, key) || ~isstruct(cfg.per_point.(key))
                return;
            end

            safeId = strrep(char(string(pid)), '-', '_');
            pointCfg = cfg.per_point.(key);
            if ~isfield(pointCfg, safeId)
                return;
            end
            pointCfg = pointCfg.(safeId);
            if isfield(pointCfg, 'warn_lines')
                if isempty(pointCfg.warn_lines)
                    warnLines = {};
                else
                    warnLines = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(pointCfg.warn_lines);
                end
            elseif isfield(pointCfg, 'alarm_bounds') && ~isempty(pointCfg.alarm_bounds)
                warnLines = bms.analyzer.StructuralPlotConfigService.boundsToWarnLines(pointCfg.alarm_bounds, style);
            end
        end

        function warnLines = boundsToWarnLines(bounds, style)
            warnLines = {};
            if isempty(bounds) || ~isstruct(bounds)
                return;
            end

            colors = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'alarm_colors', []);
            level2Color = [0.929 0.694 0.125];
            level3Color = [0.85 0.1 0.1];
            if isnumeric(colors) && size(colors, 2) == 3
                if size(colors, 1) >= 1
                    level2Color = colors(1, :);
                end
                if size(colors, 1) >= 2
                    level3Color = colors(2, :);
                end
            elseif iscell(colors)
                if numel(colors) >= 1 && isnumeric(colors{1}) && numel(colors{1}) == 3
                    level2Color = reshape(colors{1}, 1, 3);
                end
                if numel(colors) >= 2 && isnumeric(colors{2}) && numel(colors{2}) == 3
                    level3Color = reshape(colors{2}, 1, 3);
                end
            end

            level2 = char([20108 32423]);
            level3 = char([19977 32423]);
            warnLines = [warnLines; bms.analyzer.StructuralPlotConfigService.appendAlarmPair(bounds, 'level2', level2, level2Color)]; %#ok<AGROW>
            warnLines = [warnLines; bms.analyzer.StructuralPlotConfigService.appendAlarmPair(bounds, 'level3', level3, level3Color)]; %#ok<AGROW>
        end

        function lines = appendAlarmPair(bounds, fieldName, prefix, color)
            lines = {};
            if ~isfield(bounds, fieldName)
                return;
            end
            vals = bounds.(fieldName);
            if ~isnumeric(vals) || numel(vals) ~= 2
                return;
            end
            vals = sort(vals(:));
            lowerLabel = [char(string(prefix)) char([19979 38480])];
            upperLabel = [char(string(prefix)) char([19978 38480])];
            labels = {lowerLabel, upperLabel};
            for i = 1:2
                if ~isfinite(vals(i))
                    continue;
                end
                lines{end+1, 1} = struct('y', vals(i), 'label', labels{i}, 'color', color); %#ok<AGROW>
            end
        end

        function lines = normalizeWarnLines(value)
            lines = {};
            if isempty(value)
                return;
            end
            if isstruct(value)
                lines = num2cell(value);
                return;
            end
            if isnumeric(value)
                vv = value(:);
                lines = cell(numel(vv), 1);
                for i = 1:numel(vv)
                    lines{i} = struct('y', vv(i));
                end
                return;
            end
            if iscell(value)
                for i = 1:numel(value)
                    item = value{i};
                    if isstruct(item)
                        lines{end+1, 1} = item; %#ok<AGROW>
                    elseif isnumeric(item) && isscalar(item)
                        lines{end+1, 1} = struct('y', item); %#ok<AGROW>
                    end
                end
            end
        end

        function label = warnLabel(warnLine)
            label = '';
            if isstruct(warnLine) && isfield(warnLine, 'label') && ...
                    (ischar(warnLine.label) || isstring(warnLine.label))
                label = char(string(warnLine.label));
            end
        end

        function tf = hasPlotData(dataList)
            tf = false;
            for i = 1:numel(dataList)
                if isfield(dataList(i), 'vals') && ~isempty(dataList(i).vals)
                    tf = true;
                    return;
                end
            end
        end

        function sheet = sheetName(name, prefix)
            if nargin < 2
                prefix = '';
            end
            sheet = regexprep(char(string(name)), '[:\\/?*\[\]]', '_');
            if strlength(string(sheet)) > 31
                sheet = extractBefore(string(sheet), 32);
                sheet = char(sheet);
            end
            if ~isempty(prefix) && ~startsWith(sheet, prefix, 'IgnoreCase', true)
                sheet = [char(prefix) sheet];
            end
            if strlength(string(sheet)) > 31
                sheet = char(extractBefore(string(sheet), 32));
            end
        end

        function out = sanitizeFilename(name)
            out = regexprep(char(string(name)), '[\\/:*?"<>|]', '_');
        end

        function text = toChar(value)
            if isstring(value)
                text = char(value);
            elseif ischar(value)
                text = value;
            else
                text = char(string(value));
            end
        end

        function tf = isJiulongjiang(cfg)
            tf = isstruct(cfg) && isfield(cfg, 'vendor') && strcmpi(cfg.vendor, 'jiulongjiang');
        end
    end
end
