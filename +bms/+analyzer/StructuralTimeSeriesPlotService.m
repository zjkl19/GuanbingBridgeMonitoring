classdef StructuralTimeSeriesPlotService
    %STRUCTURALTIMESERIESPLOTSERVICE Shared line-plot helpers for structural series.

    methods (Static)
        function dataList = fromCells(timesList, valuesList, labels)
            if nargin < 3
                labels = {};
            end
            n = max([numel(timesList), numel(valuesList), numel(labels)]);
            dataList = repmat(struct('pid', '', 'times', [], 'vals', []), n, 1);
            for i = 1:n
                if i <= numel(labels)
                    dataList(i).pid = char(string(labels{i}));
                else
                    dataList(i).pid = sprintf('S%d', i);
                end
                if i <= numel(timesList)
                    dataList(i).times = timesList{i};
                end
                if i <= numel(valuesList)
                    dataList(i).vals = valuesList{i};
                end
            end
        end

        function plotDataList(rootDir, dataList, startDate, endDate, opts, cfg)
            if nargin < 5 || isempty(opts)
                opts = struct();
            end
            if nargin < 6
                cfg = struct();
            end
            if isempty(dataList) || ~bms.analyzer.StructuralPlotConfigService.hasPlotData(dataList)
                return;
            end

            [dt0, dt1] = bms.analyzer.StructuralTimeSeriesPlotService.dateRange(startDate, endDate);
            fig = figure('Position', [100 100 1000 469]);
            hold on;

            n = numel(dataList);
            colors = bms.analyzer.StructuralTimeSeriesPlotService.resolveColors(opts, n);
            plotOpts = bms.plot.PlotService.mergeOptions( ...
                bms.plot.PlotService.runtimeOptionsFromConfig(cfg), opts);
            h = gobjects(n, 1);
            for i = 1:n
                if isempty(dataList(i).vals)
                    continue;
                end
                [timesPlot, valuesPlot] = prepare_plot_series(dataList(i).times, dataList(i).vals, plotOpts);
                if isempty(timesPlot) || isempty(valuesPlot)
                    continue;
                end
                color = bms.analyzer.StructuralTimeSeriesPlotService.colorAt(colors, i);
                if isempty(color)
                    h(i) = plot(timesPlot, valuesPlot, 'LineWidth', 1.0);
                else
                    h(i) = plot(timesPlot, valuesPlot, 'LineWidth', 1.0, 'Color', color);
                end
            end

            valid = isgraphics(h);
            if any(valid)
                labels = {dataList(valid).pid};
                lg = legend(h(valid), labels, ...
                    'Location', bms.analyzer.StructuralTimeSeriesPlotService.opt(opts, 'legendLocation', 'northeast'), ...
                    'Box', bms.analyzer.StructuralTimeSeriesPlotService.opt(opts, 'legendBox', 'off'));
                legendInterpreter = bms.analyzer.StructuralTimeSeriesPlotService.opt(opts, 'legendInterpreter', '');
                if ~isempty(legendInterpreter)
                    lg.Interpreter = legendInterpreter;
                end
                lg.AutoUpdate = 'off';
            end

            bms.analyzer.StructuralTimeSeriesPlotService.applyDateAxis(dt0, dt1);
            xlabel(bms.analyzer.StructuralTimeSeriesPlotService.opt(opts, 'xlabel', '时间'));
            ylabel(bms.analyzer.StructuralTimeSeriesPlotService.opt(opts, 'ylabel', ''));
            titleText = bms.analyzer.StructuralTimeSeriesPlotService.opt(opts, 'titleText', '');
            titleInterpreter = bms.analyzer.StructuralTimeSeriesPlotService.opt(opts, 'titleInterpreter', '');
            if isempty(titleInterpreter)
                title(titleText);
            else
                title(titleText, 'Interpreter', titleInterpreter);
            end
            bms.analyzer.StructuralTimeSeriesPlotService.drawWarnLines( ...
                bms.analyzer.StructuralTimeSeriesPlotService.opt(opts, 'warnLines', {}), ...
                bms.analyzer.StructuralTimeSeriesPlotService.opt(opts, 'style', struct()));
            bms.analyzer.StructuralTimeSeriesPlotService.applyYLim( ...
                bms.analyzer.StructuralTimeSeriesPlotService.opt(opts, 'ylimRange', []));

            grid on;
            grid minor;
            hold off;

            outDir = bms.analyzer.StructuralTimeSeriesPlotService.resolveOutputDir(rootDir, ...
                bms.analyzer.StructuralTimeSeriesPlotService.opt(opts, 'outputDir', 'plots'));
            bms.core.PathResolver.ensureDir(outDir);
            baseName = bms.analyzer.StructuralPlotConfigService.sanitizeFilename( ...
                bms.analyzer.StructuralTimeSeriesPlotService.opt(opts, 'baseName', 'Series'));
            bms.plot.PlotService.saveModuleBundle(fig, outDir, baseName, cfg);
        end

        function plotCells(rootDir, timesList, valuesList, labels, startDate, endDate, opts, cfg)
            dataList = bms.analyzer.StructuralTimeSeriesPlotService.fromCells(timesList, valuesList, labels);
            bms.analyzer.StructuralTimeSeriesPlotService.plotDataList(rootDir, dataList, startDate, endDate, opts, cfg);
        end

        function [dt0, dt1] = dateRange(startDate, endDate)
            dt0 = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
            dt1 = datetime(endDate, 'InputFormat', 'yyyy-MM-dd');
            if dt1 <= dt0
                dt1 = dt0 + days(1);
            end
        end

        function applyDateAxis(dt0, dt1)
            ticks = dt0 + (dt1 - dt0) * (0:4) / 4;
            ax = gca;
            try
                ax.XLim = [dt0 dt1];
                ax.XTick = ticks;
                xtickformat('yyyy-MM-dd');
            catch
                ax.XLim = datenum([dt0 dt1]);
                ax.XTick = datenum(ticks);
                datetick(ax, 'x', 'yyyy-mm-dd', 'keeplimits', 'keepticks');
            end
        end

        function colors = resolveColors(opts, nSeries)
            colors = [];
            style = bms.analyzer.StructuralTimeSeriesPlotService.opt(opts, 'style', struct());
            colorField = bms.analyzer.StructuralTimeSeriesPlotService.opt(opts, 'colorField', '');
            defaultColors = bms.analyzer.StructuralTimeSeriesPlotService.opt(opts, 'defaultColors', []);
            if isempty(defaultColors)
                defaultColors = lines(max(nSeries, 1));
            end
            if isempty(colorField)
                colors = defaultColors;
                return;
            end
            raw = bms.analyzer.StructuralPlotConfigService.getStyleField(style, colorField, defaultColors);
            colors = bms.plot.PlotService.normalizeColors(raw, defaultColors);
        end

        function color = colorAt(colors, idx)
            color = [];
            if iscell(colors)
                if idx <= numel(colors) && isnumeric(colors{idx}) && numel(colors{idx}) == 3
                    color = reshape(colors{idx}, 1, 3);
                end
            elseif isnumeric(colors) && size(colors, 2) == 3 && idx <= size(colors, 1)
                color = colors(idx, :);
            end
        end

        function drawWarnLines(warnLines, style)
            if nargin < 2
                style = struct();
            end
            warnLines = bms.analyzer.StructuralPlotConfigService.applyWarnLineDefaults(warnLines, style);
            for k = 1:numel(warnLines)
                wl = warnLines{k};
                if ~isstruct(wl) || ~isfield(wl, 'y') || ~isnumeric(wl.y) || ~isscalar(wl.y) || ~isfinite(wl.y)
                    continue;
                end
                yl = yline(wl.y, '--', bms.analyzer.StructuralPlotConfigService.warnLabel(wl), ...
                    'LabelHorizontalAlignment', 'left');
                if isfield(wl, 'color') && isnumeric(wl.color) && numel(wl.color) == 3
                    yl.Color = bms.analyzer.StructuralPlotConfigService.warnDisplayColor(wl.color);
                end
                yl.LineWidth = 1.0;
                if wl.y >= 0
                    yl.LabelVerticalAlignment = 'bottom';
                else
                    yl.LabelVerticalAlignment = 'top';
                end
            end
        end

        function applyYLim(ylimRange)
            if bms.analyzer.StructuralPlotConfigService.isValidYLim(ylimRange)
                ylim(bms.plot.PlotService.normalizeYLim(ylimRange));
            else
                ylim auto;
            end
        end

        function ylimRange = resolveStyleYLim(style, pointId)
            if bms.config.ConfigReader.boolValue( ...
                    bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'ylim_auto', false), false)
                ylimRange = [];
                return;
            end
            defaultYLim = bms.analyzer.StructuralPlotConfigService.getStyleField(style, 'ylim', []);
            ylimRange = bms.analyzer.StructuralPlotConfigService.resolveNamedYLim(style, pointId, defaultYLim);
            if ~bms.analyzer.StructuralPlotConfigService.isValidYLim(ylimRange)
                ylimRange = [];
            end
        end

        function warnLines = resolveWarnLines(style, cfg, key, pointId)
            warnLines = bms.analyzer.StructuralPlotConfigService.resolveWarnLines(style, cfg, key, pointId);
        end

        function outDir = resolveOutputDir(rootDir, outDir)
            outDir = char(string(outDir));
            if isempty(outDir)
                outDir = char(rootDir);
                return;
            end
            if ~isempty(regexp(outDir, '^[A-Za-z]:[\\/]', 'once')) || startsWith(outDir, '\\') || startsWith(outDir, '/')
                return;
            end
            outDir = fullfile(char(rootDir), outDir);
        end

        function value = opt(opts, field, defaultValue)
            value = defaultValue;
            if isstruct(opts) && isfield(opts, field) && ~isempty(opts.(field))
                value = opts.(field);
            end
        end
    end
end
