classdef StructuralPlotConfigService
    %STRUCTURALPLOTCONFIGSERVICE Shared config helpers for structural plots.

    methods (Static)
        function groups = getGroups(cfg, key, fallback)
            if nargin < 3
                fallback = [];
            end
            groups = bms.config.ModuleConfigResolver.resolveGroups(cfg, key);
            if isempty(fieldnames(groups))
                groups = fallback;
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
            pts = bms.config.ModuleConfigResolver.resolvePoints(cfg, key, fallback);
        end

        function pts = getPointsOrFlattenFallback(cfg, key, fallbackGroups)
            pts = bms.config.ModuleConfigResolver.resolvePoints(cfg, key, {});
            if isempty(pts)
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
            nSeries = max(0, round(nSeries));
            if nSeries == 0
                colors = zeros(0, 3);
                return;
            end

            base = [
                0.1216 0.4667 0.7059
                1.0000 0.4980 0.0549
                0.1725 0.6275 0.1725
                0.8392 0.1529 0.1569
                0.5804 0.4039 0.7412
                0.5490 0.3373 0.2941
                0.8902 0.4667 0.7608
                0.4980 0.4980 0.4980
                0.7373 0.7412 0.1333
                0.0902 0.7451 0.8118
                0.6824 0.7804 0.9098
                1.0000 0.7333 0.4706
                0.5961 0.8745 0.5412
                1.0000 0.5961 0.5882
                0.7725 0.6902 0.8353
                0.7686 0.6118 0.5804
                0.9686 0.7137 0.8235
                0.7804 0.7804 0.7804
                0.8588 0.8588 0.5529
                0.6196 0.8549 0.8980
            ];
            if nSeries <= size(base, 1)
                colors = base(1:nSeries, :);
                return;
            end

            extraCount = nSeries - size(base, 1);
            idx = (0:extraCount-1)';
            hues = mod(idx * 0.61803398875, 1.0);
            extra = hsv2rgb([hues, repmat(0.72, extraCount, 1), repmat(0.85, extraCount, 1)]);
            colors = [base; extra];
        end

        function warnLines = resolveWarnLines(style, cfg, key, pid)
            warnLines = {};
            globalWarn = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'warn_lines', {});
            if ~isempty(globalWarn)
                warnLines = bms.analyzer.StructuralPlotConfigService.applyWarnLineDefaults(globalWarn, style);
            end
            if isempty(pid) || ~isstruct(cfg) || ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point) || ...
                    ~isfield(cfg.per_point, key) || ~isstruct(cfg.per_point.(key))
                return;
            end

            pointCfg = cfg.per_point.(key);
            [ok, pointCfg] = bms.data.PointResolver.getPointConfig(pointCfg, pid, cfg);
            if ~ok
                return;
            end
            if isfield(pointCfg, 'warn_lines')
                if isempty(pointCfg.warn_lines)
                    warnLines = {};
                else
                    warnLines = bms.analyzer.StructuralPlotConfigService.applyWarnLineDefaults(pointCfg.warn_lines, style);
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
            level2Color = [0.72 0.50 0.00];
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
            unit = bms.analyzer.StructuralPlotConfigService.warnUnit(style);
            warnLines = [warnLines; bms.analyzer.StructuralPlotConfigService.appendAlarmPair(bounds, 'level2', level2, level2Color, unit)]; %#ok<AGROW>
            warnLines = [warnLines; bms.analyzer.StructuralPlotConfigService.appendAlarmPair(bounds, 'level3', level3, level3Color, unit)]; %#ok<AGROW>
        end

        function lines = appendAlarmPair(bounds, fieldName, prefix, color, unit)
            lines = {};
            if ~isfield(bounds, fieldName)
                return;
            end
            if nargin < 5
                unit = '';
            end
            vals = bounds.(fieldName);
            if ~isnumeric(vals) || numel(vals) ~= 2
                return;
            end
            vals = sort(vals(:));
            for i = 1:2
                if ~isfinite(vals(i))
                    continue;
                end
                lines{end+1, 1} = struct( ... %#ok<AGROW>
                    'y', vals(i), ...
                    'label', bms.analyzer.StructuralPlotConfigService.composeWarnValueLabel(prefix, vals(i), unit), ...
                    'color', color, ...
                    'level', char(string(prefix)), ...
                    'unit', char(string(unit)));
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

        function lines = applyWarnLineDefaults(lines, style)
            lines = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(lines);
            unit = bms.analyzer.StructuralPlotConfigService.warnUnit(style);
            for i = 1:numel(lines)
                wl = lines{i};
                if ~isstruct(wl)
                    continue;
                end
                if ~isfield(wl, 'unit') || isempty(wl.unit)
                    wl.unit = unit;
                end
                lines{i} = wl;
            end
        end

        function label = warnLabel(warnLine)
            label = '';
            if isstruct(warnLine) && isfield(warnLine, 'label') && ...
                    (ischar(warnLine.label) || isstring(warnLine.label))
                label = char(string(warnLine.label));
            end
            if isempty(label) && isstruct(warnLine) && isfield(warnLine, 'level') && ...
                    isfield(warnLine, 'y') && isnumeric(warnLine.y) && isscalar(warnLine.y)
                unit = '';
                if isfield(warnLine, 'unit')
                    unit = warnLine.unit;
                end
                label = bms.analyzer.StructuralPlotConfigService.composeWarnValueLabel(warnLine.level, warnLine.y, unit);
            end
            label = bms.analyzer.StructuralPlotConfigService.normalizeWarnLabel(label, warnLine);
        end

        function label = normalizeWarnLabel(label, warnLine)
            label = char(string(label));
            if isempty(label)
                return;
            end

            warnValueText = bms.analyzer.StructuralPlotConfigService.warnValueText();
            levels = {char([19968 32423]), char([20108 32423]), char([19977 32423])};
            oldTerms = {char([38408 20540]), char([25253 35686 20540]), ...
                char([19978 38480]), char([19979 38480])};
            for i = 1:numel(levels)
                for j = 1:numel(oldTerms)
                    label = strrep(label, [levels{i} oldTerms{j}], [levels{i} warnValueText]);
                end
            end
            colorTerms = {char([40644 32447]), char([32418 32447])};
            colorLevels = {levels{2}, levels{3}};
            for i = 1:numel(colorTerms)
                for j = 1:numel(oldTerms)
                    label = strrep(label, [colorTerms{i} oldTerms{j}], [colorLevels{i} warnValueText]);
                end
            end
            label = regexprep(label, [warnValueText '([+\-]?\d)'], [warnValueText ' $1']);

            if isstruct(warnLine) && isfield(warnLine, 'y') && isnumeric(warnLine.y) && ...
                    isscalar(warnLine.y) && isfinite(warnLine.y) && ...
                    contains(label, warnValueText) && ...
                    ~bms.analyzer.StructuralPlotConfigService.warnLabelHasValue(label)
                unit = '';
                if isfield(warnLine, 'unit')
                    unit = warnLine.unit;
                end
                label = sprintf('%s %s%s', label, ...
                    bms.analyzer.StructuralPlotConfigService.formatWarnValue(warnLine.y), ...
                    char(string(unit)));
            end
        end

        function tf = warnLabelHasValue(label)
            warnValueText = bms.analyzer.StructuralPlotConfigService.warnValueText();
            idx = strfind(label, warnValueText);
            tf = false;
            if isempty(idx)
                return;
            end
            suffix = label(idx(end) + length(warnValueText):end);
            tf = ~isempty(regexp(suffix, '[+\-]?\d', 'once'));
        end

        function label = composeWarnValueLabel(level, value, unit)
            if nargin < 3
                unit = '';
            end
            label = sprintf('%s%s %s%s', ...
                char(string(level)), ...
                bms.analyzer.StructuralPlotConfigService.warnValueText(), ...
                bms.analyzer.StructuralPlotConfigService.formatWarnValue(value), ...
                char(string(unit)));
        end

        function text = warnValueText()
            text = char([39044 35686 20540]);
        end

        function text = formatWarnValue(value)
            if abs(value) < 1e-12
                value = 0;
            end
            text = regexprep(sprintf('%.6g', value), '^-0$', '0');
        end

        function unit = warnUnit(style)
            unit = '';
            if nargin < 1 || ~isstruct(style)
                return;
            end

            directFields = {'warn_unit', 'unit'};
            for i = 1:numel(directFields)
                field = directFields{i};
                if isfield(style, field) && ~isempty(style.(field))
                    unit = bms.analyzer.StructuralPlotConfigService.normalizeUnit(style.(field));
                    return;
                end
            end

            labelFields = {'ylabel', 'rms_ylabel', 'force_ylabel'};
            for i = 1:numel(labelFields)
                field = labelFields{i};
                if ~isfield(style, field) || isempty(style.(field))
                    continue;
                end
                tokens = regexp(char(string(style.(field))), '\(([^)]*)\)', 'tokens', 'once');
                if ~isempty(tokens)
                    unit = bms.analyzer.StructuralPlotConfigService.normalizeUnit(tokens{1});
                    return;
                end
            end
        end

        function unit = normalizeUnit(value)
            unit = char(string(value));
            unit = strrep(unit, '^2', char(178));
        end

        function color = warnDisplayColor(color)
            if ~(isnumeric(color) && numel(color) == 3)
                color = [];
                return;
            end
            color = reshape(color, 1, 3);
            if color(1) >= 0.85 && color(2) >= 0.60 && color(3) <= 0.25
                color = [0.72 0.50 0.00];
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
