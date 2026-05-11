classdef DynamicAccelerationPlotService
    %DYNAMICACCELERATIONPLOTSERVICE Plot helpers for acceleration modules.

    methods (Static)
        function plotAccelCurve(rootDir, pointId, times, values, minVal, maxVal, style, cfg, spec)
            fig = figure('Position', [100 100 1000 469]);
            [timesPlot, valuesPlot] = prepare_plot_series(times, values);
            plot(timesPlot, valuesPlot, 'LineWidth', 1, 'Color', style.color_main);
            xlabel('时间');
            ylabel(style.ylabel);
            bms.analyzer.DynamicAccelerationPlotService.applyMainYLim(style, pointId);
            hold on;
            h1 = yline(maxVal, '--r');
            h1.Label = sprintf('最大值 %.3f', maxVal);
            h1.LabelHorizontalAlignment = 'left';
            h2 = yline(minVal, '--r');
            h2.Label = sprintf('最小值 %.3f', minVal);
            h2.LabelHorizontalAlignment = 'left';

            bms.analyzer.DynamicAccelerationPlotService.applyTimeAxis(times);
            grid on;
            grid minor;
            title([style.title_prefix ' ' pointId]);

            outDir = fullfile(rootDir, spec.outputDir);
            bms.core.PathResolver.ensureDir(outDir);
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            fname = [pointId '_' datestr(times(1), 'yyyymmdd') '_' datestr(times(end), 'yyyymmdd')];
            bms.plot.PlotService.saveModuleBundle(fig, outDir, [fname '_' timestamp], cfg);
        end

        function plotRmsCurve(rootDir, pointId, times, values, fs, style, cfg, spec)
            if isempty(values) || numel(times) ~= numel(values)
                return;
            end
            validTimeMask = ~isnat(times);
            if ~any(validTimeMask)
                return;
            end

            [rmsSeries, rmsMax, tMax] = bms.analyzer.DynamicSeriesService.rmsSeries(times, values, fs, 10, 0.7);
            fig = figure('Position', [100 100 1000 469]);
            [timesPlot, rmsPlot] = prepare_plot_series(times, rmsSeries);
            if isempty(timesPlot)
                timesPlot = times(validTimeMask);
                rmsPlot = NaN(size(timesPlot));
            end
            plot(timesPlot, rmsPlot, 'LineWidth', 1.2, 'Color', style.color_rms);
            xlabel('时间');
            ylabel(style.rms_ylabel);
            bms.analyzer.DynamicAccelerationPlotService.applyRmsYLim(style, pointId);
            title(sprintf('%s %s', style.rms_title_prefix, pointId));
            grid on;
            grid minor;
            hold on;

            if ~isnan(rmsMax)
                h1 = yline(rmsMax, '--r');
                h1.Label = sprintf('最大值 %.3f', rmsMax);
                h1.LabelHorizontalAlignment = 'left';
                if ~isnat(tMax)
                    plot(tMax, rmsMax, 'ro', 'MarkerFaceColor', 'r');
                end
            end

            validTimes = times(validTimeMask);
            xmin = min(validTimes);
            xmax = max(validTimes);
            if xmin >= xmax
                xmin = xmin - minutes(1);
                xmax = xmax + minutes(1);
            end
            bms.analyzer.DynamicAccelerationPlotService.applyTimeAxisLimits(xmin, xmax);

            outDir = fullfile(rootDir, spec.rmsOutputDir);
            bms.core.PathResolver.ensureDir(outDir);
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            fname = sprintf('%s_%s_%s_%s', spec.rmsFilePrefix, pointId, datestr(xmin, 'yyyymmdd'), datestr(xmax, 'yyyymmdd'));
            bms.plot.PlotService.saveModuleBundle(fig, outDir, [fname '_' timestamp], cfg);
        end

        function applyMainYLim(style, pointId)
            if bms.config.ConfigReader.boolValue(style.ylim_auto, false)
                ylim auto;
                return;
            end
            yl = bms.plot.PlotService.resolveNamedYLim(style.ylims, pointId, style.ylim);
            if bms.plot.PlotService.isValidYLim(yl)
                ylim(yl);
            elseif ~isempty(style.ylim)
                ylim(style.ylim);
            else
                ylim auto;
            end
        end

        function applyRmsYLim(style, pointId)
            yl = bms.plot.PlotService.resolveNamedYLim(style.rms_ylims, pointId, style.rms_ylim);
            if bms.plot.PlotService.isValidYLim(yl)
                ylim(yl);
            elseif ~isempty(style.rms_ylim)
                ylim(style.rms_ylim);
            else
                ylim auto;
            end
        end

        function applyTimeAxis(times)
            dn0 = datenum(times(1));
            dn1 = datenum(times(end));
            ticks = datetime(linspace(dn0, dn1, 5), 'ConvertFrom', 'datenum');
            ax = gca;
            ax.XLim = ticks([1 end]);
            ax.XTick = ticks;
            xtickformat('yyyy-MM-dd');
        end

        function applyTimeAxisLimits(xmin, xmax)
            ax = gca;
            ax.XLim = [xmin xmax];
            ticks = datetime(linspace(datenum(xmin), datenum(xmax), 5), 'ConvertFrom', 'datenum');
            ticks = unique(ticks, 'stable');
            if numel(ticks) >= 2 && all(diff(ticks) > duration(0, 0, 0))
                ax.XTick = ticks;
            else
                ax.XTickMode = 'auto';
            end
            if days(xmax - xmin) >= 1
                xtickformat('yyyy-MM-dd');
            else
                xtickformat('MM-dd HH:mm');
            end
        end
    end
end
