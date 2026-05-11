classdef DynamicStrainPlotService
    %DYNAMICSTRAINPLOTSERVICE Plot and stats writers for dynamic strain boxplots.

    methods (Static)
        function makeBoxplotAndStats(dataMat, labels, groupName, outDir, ds, spec, tag, timestamp, dt0, dt1, cfg)
            fig = figure('Position', [100 100 1100 520]);
            plotMat = bms.analyzer.DynamicStrainBoxplotService.sampleBoxplotMatrix(dataMat, 50000);
            if ds.ShowOutliers
                boxplot(plotMat, 'Labels', labels, 'LabelOrientation', 'horizontal', 'Whisker', ds.Whisker);
            else
                boxplot(plotMat, 'Labels', labels, 'LabelOrientation', 'horizontal', 'Whisker', ds.Whisker, 'Symbol', '');
            end
            xlabel('测点');
            ylabel('应变 (με)');
            title(sprintf(spec.boxTitle, groupName, tag), 'Interpreter', 'none');
            xtickangle(45);
            grid on;
            grid minor;
            if ds.YLimManual
                ylim(ds.YLimRange);
            end

            base = sprintf('boxplot_%s_%s', groupName, tag);
            bms.plot.PlotService.saveModuleBundle(fig, outDir, [base '_' timestamp], cfg);

            statsTable = bms.analyzer.DynamicStrainBoxplotService.statsTable(dataMat, labels);
            txtPath = fullfile(outDir, sprintf('boxplot_stats_%s_%s.txt', groupName, tag));
            xlsxPath = fullfile(outDir, sprintf('boxplot_stats_%s.xlsx', tag));
            bms.analyzer.DynamicStrainPlotService.writeStatsTxt(txtPath, statsTable, dt0, dt1, spec);
            bms.io.StatsWriter.writeModuleTableChecked(statsTable, xlsxPath, spec.moduleKey, 'Sheet', groupName);
        end

        function plotTimeseriesGroup(tsList, labels, groupName, outDir, dt0, dt1, ds, spec, ylimGroup, tag, timestamp, cfg)
            fig = figure('Position', [100 100 1100 520]);
            hold on;
            colors = {[0 0 0], [0 0 1], [0 0.7 0], [1 0.4 0.8], [1 0.6 0], [1 0 0]};

            n = numel(tsList);
            labels = labels(:);
            hLines = gobjects(n, 1);
            hasLine = false(n, 1);
            for i = 1:n
                times = tsList(i).times;
                values = tsList(i).vals;
                if isempty(times) || isempty(values)
                    continue;
                end
                color = colors{min(i, numel(colors))};
                [timesPlot, valuesPlot] = prepare_plot_series(times, values);
                if isempty(timesPlot) || isempty(valuesPlot) || ~any(isfinite(valuesPlot))
                    continue;
                end
                lineHandle = plot(timesPlot, valuesPlot, 'LineWidth', 1.0, 'Color', color);
                if ~isempty(lineHandle)
                    hLines(i) = lineHandle(1);
                    hasLine(i) = true;
                end
            end

            xlabel('时间');
            ylabel('应变 (με)');
            title(sprintf(spec.timeseriesTitle, groupName, tag), 'Interpreter', 'none');
            grid on;
            grid minor;

            allTimes = vertcat(tsList.times);
            if ~isempty(allTimes)
                xmin = min(allTimes);
                xmax = max(allTimes);
            else
                xmin = dt0;
                xmax = dt1;
            end
            if xmin == xmax
                xmin = xmin - minutes(1);
                xmax = xmax + minutes(1);
            end
            ax = gca;
            ax.XLim = [xmin xmax];
            ax.XTick = linspace(xmin, xmax, 5);
            if days(xmax - xmin) >= 1
                xtickformat('yyyy-MM-dd');
            else
                xtickformat('MM-dd HH:mm');
            end

            if ~isempty(ylimGroup)
                ylim(ylimGroup);
            elseif ds.YLimManual
                ylim(ds.YLimRange);
            end

            if any(hasLine)
                legend(hLines(hasLine), labels(hasLine), 'Location', 'northeast', 'Box', 'off', 'Interpreter', 'none');
            end

            base = sprintf('%s_%s_%s', spec.timeseriesBase, groupName, tag);
            bms.plot.PlotService.saveModuleBundle(fig, outDir, [base '_' timestamp], cfg);
        end

        function writeStatsTxt(path, statsTable, dt0, dt1, spec)
            fid = fopen(path, 'wt');
            if fid < 0
                error('DynamicStrainBoxplotPipeline:CannotWriteStats', 'Cannot write stats file: %s', path);
            end
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, spec.statsHeader, char(string(dt0, 'yyyy-MM-dd')), char(string(dt1, 'yyyy-MM-dd')));
            fprintf(fid, "字段: PointID, Min, Q1, Median, Q3, Max, Mean, Std, Count\n\n");
            for i = 1:height(statsTable)
                fprintf(fid, '%s\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%d\n', ...
                    statsTable.PointID{i}, statsTable.Min(i), statsTable.Q1(i), statsTable.Median(i), ...
                    statsTable.Q3(i), statsTable.Max(i), statsTable.Mean(i), statsTable.Std(i), statsTable.Count(i));
            end
        end
    end
end
