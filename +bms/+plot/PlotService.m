classdef PlotService
    %PLOTSERVICE Thin facade for plot output naming/saving conventions.

    methods (Static)
        function name = outputBase(baseName, appendTimestamp, timestamp)
            if nargin < 2, appendTimestamp = false; end
            if nargin < 3 || isempty(timestamp), timestamp = datestr(now, 'yyyymmdd_HHMMSS'); end
            name = char(baseName);
            if appendTimestamp
                name = [name '_' char(timestamp)];
            end
        end

        function saveBundle(fig, outDir, baseName, opts)
            if nargin < 4, opts = struct(); end
            save_plot_bundle(fig, outDir, baseName, opts);
        end

        function saveBundleWithTimestamp(fig, outDir, baseName, opts)
            if nargin < 4, opts = struct(); end
            bms.plot.PlotService.saveBundle(fig, outDir, ...
                bms.plot.PlotService.outputBase(baseName, true), opts);
        end

        function [xPlot, yPlot] = prepareSeries(x, y, opts)
            if nargin < 3, opts = struct(); end
            [xPlot, yPlot] = prepare_plot_series(x, y, opts);
        end

        function setTimeAxis(times)
            if isempty(times)
                return;
            end
            times = times(:);
            if isdatetime(times)
                valid = ~isnat(times);
            else
                valid = isfinite(times);
            end
            if ~any(valid)
                return;
            end
            t = times(valid);
            xmin = min(t);
            xmax = max(t);
            if bms.plot.PlotService.isSameLimit(xmin, xmax)
                if isdatetime(t)
                    xmin = xmin - minutes(1);
                    xmax = xmax + minutes(1);
                else
                    xmin = xmin - 1;
                    xmax = xmax + 1;
                end
            end

            ax = gca;
            ax.XLim = [xmin xmax];
            ticks = bms.plot.PlotService.makeTicks(xmin, xmax, 5);
            if numel(ticks) >= 2
                ax.XTick = ticks;
            else
                ax.XTickMode = 'auto';
            end
            if isdatetime(t)
                if days(xmax - xmin) >= 1
                    xtickformat('yyyy-MM-dd');
                else
                    xtickformat('MM-dd HH:mm');
                end
            end
        end

        function ticks = makeTicks(xmin, xmax, n)
            if nargin < 3, n = 5; end
            if isdatetime(xmin)
                ticks = datetime(linspace(posixtime(xmin), posixtime(xmax), n), 'ConvertFrom', 'posixtime');
                ticks = unique(ticks, 'stable');
                if numel(ticks) >= 2 && ~all(diff(ticks) > duration(0,0,0))
                    ticks = ticks([]);
                end
            else
                ticks = unique(linspace(double(xmin), double(xmax), n), 'stable');
                if numel(ticks) >= 2 && ~all(diff(ticks) > 0)
                    ticks = [];
                end
            end
        end

        function tf = isSameLimit(a, b)
            if isdatetime(a)
                tf = a == b;
            else
                tf = double(a) == double(b);
            end
        end

        function yl = resolveNamedYLim(ylims, name, defaultYLim)
            if nargin < 3
                defaultYLim = [];
            end
            yl = defaultYLim;
            if isempty(ylims) || isempty(name)
                return;
            end
            name = char(string(name));
            safeName = bms.data.PointResolver.safeId(name);
            dashSafeName = strrep(name, '-', '_');

            if isa(ylims, 'containers.Map')
                if isKey(ylims, name)
                    yl = ylims(name);
                    return;
                end
                if isKey(ylims, safeName)
                    yl = ylims(safeName);
                    return;
                end
                if isKey(ylims, dashSafeName)
                    yl = ylims(dashSafeName);
                    return;
                end
            elseif isstruct(ylims)
                if isfield(ylims, name)
                    yl = ylims.(name);
                    return;
                end
                if isfield(ylims, safeName)
                    yl = ylims.(safeName);
                    return;
                end
                if isfield(ylims, dashSafeName)
                    yl = ylims.(dashSafeName);
                    return;
                end
                if isfield(ylims, 'name') && isfield(ylims, 'ylim')
                    for i = 1:numel(ylims)
                        itemName = char(string(ylims(i).name));
                        if strcmp(itemName, name) || strcmp(itemName, safeName) || strcmp(itemName, dashSafeName)
                            yl = ylims(i).ylim;
                            return;
                        end
                    end
                end
            elseif iscell(ylims)
                for i = 1:numel(ylims)
                    item = ylims{i};
                    if isstruct(item) && isfield(item, 'name') && isfield(item, 'ylim')
                        itemName = char(string(item.name));
                        if strcmp(itemName, name) || strcmp(itemName, safeName) || strcmp(itemName, dashSafeName)
                            yl = item.ylim;
                            return;
                        end
                    end
                end
            end
        end

        function tf = isValidYLim(v)
            tf = isnumeric(v) && numel(v) == 2 && isvector(v) && ...
                isfinite(v(1)) && (isfinite(v(2)) || isinf(v(2))) && v(2) > v(1);
        end

        function applyYLim(style, pointId, defaultAuto)
            if nargin < 3
                defaultAuto = true;
            end
            if bms.config.ConfigReader.boolValue(bms.config.ConfigReader.getField(style, 'ylim_auto', defaultAuto), defaultAuto)
                ylim auto;
                return;
            end
            defaultYLim = bms.config.ConfigReader.getField(style, 'ylim', []);
            ylims = bms.config.ConfigReader.getField(style, 'ylims', []);
            yl = bms.plot.PlotService.resolveNamedYLim(ylims, pointId, defaultYLim);
            if bms.plot.PlotService.isValidYLim(yl)
                ylim(yl);
            elseif bms.plot.PlotService.isValidYLim(defaultYLim)
                ylim(defaultYLim);
            else
                ylim auto;
            end
        end

        function colors = normalizeColors(raw, defaultColors)
            if nargin < 2
                defaultColors = [];
            end
            colors = raw;
            wantCell = iscell(defaultColors);
            if isempty(colors)
                colors = defaultColors;
            end
            if iscell(colors)
                numeric = bms.plot.PlotService.cellColorsToMatrix(colors);
                if isempty(numeric)
                    numeric = bms.plot.PlotService.cellColorsToMatrix(defaultColors);
                end
                colors = numeric;
            end
            if ~isnumeric(colors) || isempty(colors) || size(colors, 2) ~= 3
                if iscell(defaultColors)
                    colors = bms.plot.PlotService.cellColorsToMatrix(defaultColors);
                elseif isnumeric(defaultColors) && size(defaultColors, 2) == 3
                    colors = defaultColors;
                else
                    colors = lines(6);
                end
            end
            if wantCell
                colors = bms.plot.PlotService.matrixColorsToCell(colors);
            end
        end

        function c = getColor(colors, idx, defaultColors)
            if nargin < 3
                defaultColors = lines(max(idx, 1));
            end
            colors = bms.plot.PlotService.normalizeColors(colors, defaultColors);
            if iscell(colors)
                if idx <= numel(colors)
                    c = colors{idx};
                else
                    c = colors{end};
                end
            else
                if idx <= size(colors, 1)
                    c = colors(idx, :);
                else
                    c = colors(end, :);
                end
            end
        end

        function mat = cellColorsToMatrix(colors)
            mat = [];
            if ~iscell(colors)
                if isnumeric(colors) && size(colors, 2) == 3
                    mat = colors;
                end
                return;
            end
            rows = {};
            for i = 1:numel(colors)
                c = colors{i};
                if isnumeric(c) && numel(c) == 3
                    rows{end+1,1} = reshape(double(c), 1, 3); %#ok<AGROW>
                end
            end
            if ~isempty(rows)
                mat = cell2mat(rows);
            end
        end

        function cells = matrixColorsToCell(colors)
            cells = {};
            if ~isnumeric(colors) || size(colors, 2) ~= 3
                return;
            end
            for i = 1:size(colors, 1)
                cells{end+1} = colors(i, :); %#ok<AGROW>
            end
        end
    end
end
