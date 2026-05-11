classdef StrainPlotService
    %STRAINPLOTSERVICE Plot helpers for static strain analysis.

    methods (Static)
        function plotPointCurve(rootDir, times, vals, startDate, endDate, pointId, style, warnLines, cfg)
            if nargin < 9
                cfg = struct();
            end
            fig = figure('Position', [100 100 1000 469]);
            hold on;
            [timesPlot, valsPlot] = prepare_plot_series(times, vals);
            plot(timesPlot, valsPlot, 'LineWidth', 1.0, 'Color', [0 0.447 0.741]);

            [dt0, dt1] = bms.analyzer.StructuralTimeSeriesPlotService.dateRange(startDate, endDate);
            bms.analyzer.StructuralTimeSeriesPlotService.applyDateAxis(dt0, dt1);

            xlabel('时间');
            ylabel(bms.analyzer.StrainConfigService.styleField(style, 'ylabel', '主梁应变 (με)'));
            title(sprintf('%s %s', ...
                bms.analyzer.StrainConfigService.styleField(style, 'title_prefix', '应变时程曲线'), ...
                char(string(pointId))), 'Interpreter', 'none');

            if bms.analyzer.StrainConfigService.truthy( ...
                    bms.analyzer.StrainConfigService.styleField(style, 'show_warn_lines_point', true))
                bms.analyzer.StructuralTimeSeriesPlotService.drawWarnLines(warnLines);
            end

            if bms.analyzer.StrainConfigService.truthy( ...
                    bms.analyzer.StrainConfigService.styleField(style, 'ylim_auto', false))
                ylim auto;
            else
                ylimRange = bms.analyzer.StrainConfigService.pointYLim(style, pointId, ...
                    bms.analyzer.StrainConfigService.styleField(style, 'ylim', []));
                bms.analyzer.StructuralTimeSeriesPlotService.applyYLim(ylimRange);
            end

            grid on;
            grid minor;

            outDir = fullfile(rootDir, char(string( ...
                bms.analyzer.StrainConfigService.styleField(style, 'output_dir', '时程曲线_应变'))));
            bms.core.PathResolver.ensureDir(outDir);
            baseName = bms.analyzer.StrainConfigService.sanitizeFilename( ...
                sprintf('Strain_%s_%s_%s_%s', char(string(pointId)), ...
                datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd'), datestr(now, 'yyyymmdd_HHMMSS')));
            bms.plot.PlotService.saveModuleBundle(fig, outDir, baseName, cfg);
        end

        function plotGroupTimeseries(rootDir, dataList, startDate, endDate, groupName, style, cfg)
            if nargin < 7
                cfg = struct();
            end
            if isempty(dataList)
                return;
            end

            nSeries = numel(dataList);
            if nSeries > 12
                fprintf('[WARN] Strain group %s has %d curves; consider splitting it for readability.\n', ...
                    char(string(groupName)), nSeries);
            end

            [dt0, dt1] = bms.analyzer.StructuralTimeSeriesPlotService.dateRange(startDate, endDate);
            opts = struct();
            opts.style = style;
            opts.outputDir = bms.analyzer.StrainConfigService.styleField(style, 'group_output_dir', '时程曲线_应变_组图');
            opts.baseName = sprintf('Strain_%s_%s_%s_%s', char(string(groupName)), ...
                datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd'), datestr(now, 'yyyymmdd_HHMMSS'));
            opts.titleText = sprintf('%s %s', ...
                bms.analyzer.StrainConfigService.styleField(style, 'title_prefix', '应变时程曲线'), ...
                char(string(groupName)));
            opts.ylabel = bms.analyzer.StrainConfigService.styleField(style, 'ylabel', '主梁应变 (με)');
            opts.ylimRange = bms.analyzer.StrainConfigService.groupYLim(style, groupName, []);
            opts.defaultColors = bms.analyzer.StrainConfigService.groupColors(style, nSeries);
            opts.legendInterpreter = 'none';
            opts.titleInterpreter = 'none';
            bms.analyzer.StructuralTimeSeriesPlotService.plotDataList( ...
                rootDir, dataList, startDate, endDate, opts, cfg);
        end

        function plotGroupBoxplot(rootDir, dataList, startDate, endDate, groupName, style, cfg)
            if nargin < 7
                cfg = struct();
            end
            if isempty(dataList)
                return;
            end

            labels = {dataList.pid};
            maxPoints = bms.analyzer.StrainConfigService.styleField(style, 'boxplot_max_points_per_series', 50000);
            dataMat = bms.analyzer.StrainPlotService.buildBoxplotMatrix(dataList, maxPoints);

            fig = figure('Position', [100 100 1200 520]);
            if bms.analyzer.StrainConfigService.truthy( ...
                    bms.analyzer.StrainConfigService.styleField(style, 'show_boxplot_outliers', false))
                boxplot(dataMat, 'Labels', labels, 'LabelOrientation', 'inline');
            else
                boxplot(dataMat, 'Labels', labels, 'LabelOrientation', 'inline', 'Symbol', '');
            end
            hold on;
            xtickangle(45);

            if bms.analyzer.StrainConfigService.truthy( ...
                    bms.analyzer.StrainConfigService.styleField(style, 'show_warn_lines_boxplot', true))
                bms.analyzer.StrainPlotService.drawBoxplotWarnLines(dataList, style, cfg);
            end

            ylabel(bms.analyzer.StrainConfigService.styleField(style, 'ylabel', '主梁应变 (με)'));
            title(sprintf('%s %s', ...
                bms.analyzer.StrainConfigService.styleField(style, 'boxplot_title_prefix', '应变箱线图'), ...
                char(string(groupName))), 'Interpreter', 'none');

            bms.analyzer.StructuralTimeSeriesPlotService.applyYLim( ...
                bms.analyzer.StrainConfigService.groupYLim(style, groupName, []));
            grid on;
            grid minor;

            dt0 = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
            dt1 = datetime(endDate, 'InputFormat', 'yyyy-MM-dd');
            outDir = fullfile(rootDir, char(string( ...
                bms.analyzer.StrainConfigService.styleField(style, 'boxplot_output_dir', '箱线图_应变'))));
            bms.core.PathResolver.ensureDir(outDir);
            baseName = bms.analyzer.StrainConfigService.sanitizeFilename( ...
                sprintf('StrainBox_%s_%s_%s_%s', char(string(groupName)), ...
                datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd'), datestr(now, 'yyyymmdd_HHMMSS')));
            bms.plot.PlotService.saveModuleBundle(fig, outDir, baseName, cfg);
        end

        function dataMat = buildBoxplotMatrix(dataList, maxPointsPerSeries)
            if nargin < 2 || isempty(maxPointsPerSeries) || ~isscalar(maxPointsPerSeries) || ...
                    ~isfinite(maxPointsPerSeries) || maxPointsPerSeries < 1000
                maxPointsPerSeries = 50000;
            end
            maxPointsPerSeries = round(maxPointsPerSeries);

            maxLen = 0;
            for i = 1:numel(dataList)
                maxLen = max(maxLen, min(numel(dataList(i).vals), maxPointsPerSeries));
            end
            dataMat = NaN(maxLen, numel(dataList));
            for i = 1:numel(dataList)
                v = dataList(i).vals(:);
                if numel(v) > maxPointsPerSeries
                    idx = unique(round(linspace(1, numel(v), maxPointsPerSeries)), 'stable');
                    v = v(idx);
                end
                dataMat(1:numel(v), i) = v;
            end
        end

        function drawBoxplotWarnLines(dataList, style, cfg)
            for i = 1:numel(dataList)
                warnLines = bms.analyzer.StrainConfigService.resolveWarnLines(style, cfg, dataList(i).pid);
                warnLines = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(warnLines);
                for k = 1:numel(warnLines)
                    wl = warnLines{k};
                    if ~isstruct(wl) || ~isfield(wl, 'y') || ~isnumeric(wl.y) || ...
                            ~isscalar(wl.y) || ~isfinite(wl.y)
                        continue;
                    end
                    color = [0.5 0.5 0.5];
                    if isfield(wl, 'color') && isnumeric(wl.color) && numel(wl.color) == 3
                        color = reshape(wl.color, 1, 3);
                    end
                    line([i - 0.28, i + 0.28], [wl.y, wl.y], ...
                        'LineStyle', '--', 'LineWidth', 1.0, 'Color', color);
                end
            end
        end
    end
end
