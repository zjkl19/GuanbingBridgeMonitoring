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

        function plotAccelGroup(rootDir, groupName, records, startDate, endDate, style, cfg, spec)
            if isempty(records)
                return;
            end

            [timesList, valuesList, labels] = bms.analyzer.DynamicAccelerationPlotService.recordsToCells(records, 'vals');
            if isempty(timesList)
                return;
            end

            groupLabel = bms.analyzer.DynamicAccelerationPlotService.groupLabel(style, groupName);
            opts = bms.analyzer.DynamicAccelerationPlotService.groupPlotOptions( ...
                style, spec, groupName, startDate, endDate, false, numel(timesList));
            opts.outputDir = bms.analyzer.DynamicAccelerationPlotService.groupOutputDir(style, spec);
            opts.ylabel = style.ylabel;
            opts.titleText = sprintf('%s %s', style.title_prefix, groupLabel);
            opts.ylimRange = bms.analyzer.DynamicAccelerationPlotService.resolveMainYLim(style, groupName);
            opts.warnLines = bms.analyzer.DynamicAccelerationPlotService.resolveGroupWarnLines( ...
                style, 'group_warn_lines', groupName);

            bms.analyzer.StructuralTimeSeriesPlotService.plotCells( ...
                rootDir, timesList, valuesList, labels, startDate, endDate, opts, cfg);
        end

        function plotRmsGroup(rootDir, groupName, records, startDate, endDate, style, cfg, spec)
            if isempty(records)
                return;
            end

            timesList = {};
            valuesList = {};
            labels = {};
            for i = 1:numel(records)
                rec = records(i);
                if isempty(rec.vals) || numel(rec.times) ~= numel(rec.vals)
                    continue;
                end
                rmsSeries = bms.analyzer.DynamicSeriesService.rmsSeries(rec.times, rec.vals, rec.fs, 10, 0.7);
                if isempty(rmsSeries)
                    continue;
                end
                timesList{end+1, 1} = rec.times; %#ok<AGROW>
                valuesList{end+1, 1} = rmsSeries; %#ok<AGROW>
                labels{end+1, 1} = rec.pid; %#ok<AGROW>
            end
            if isempty(timesList)
                return;
            end

            groupLabel = bms.analyzer.DynamicAccelerationPlotService.groupLabel(style, groupName);
            opts = bms.analyzer.DynamicAccelerationPlotService.groupPlotOptions( ...
                style, spec, groupName, startDate, endDate, true, numel(timesList));
            opts.outputDir = bms.analyzer.DynamicAccelerationPlotService.rmsGroupOutputDir(style, spec);
            opts.ylabel = style.rms_ylabel;
            opts.titleText = sprintf('%s %s', style.rms_title_prefix, groupLabel);
            opts.ylimRange = bms.analyzer.DynamicAccelerationPlotService.resolveRmsYLim(style, groupName);
            opts.warnLines = bms.analyzer.DynamicAccelerationPlotService.resolveGroupWarnLines( ...
                style, 'rms_warn_lines', groupName);

            bms.analyzer.StructuralTimeSeriesPlotService.plotCells( ...
                rootDir, timesList, valuesList, labels, startDate, endDate, opts, cfg);
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

        function [timesList, valuesList, labels] = recordsToCells(records, valueField)
            timesList = {};
            valuesList = {};
            labels = {};
            for i = 1:numel(records)
                if ~isfield(records(i), valueField) || isempty(records(i).(valueField))
                    continue;
                end
                timesList{end+1, 1} = records(i).times; %#ok<AGROW>
                valuesList{end+1, 1} = records(i).(valueField); %#ok<AGROW>
                labels{end+1, 1} = records(i).pid; %#ok<AGROW>
            end
        end

        function opts = groupPlotOptions(style, spec, groupName, startDate, endDate, isRms, nSeries)
            [dt0, dt1] = bms.analyzer.DynamicAccelerationPlotService.fileDateRange(startDate, endDate);
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            if isRms
                prefix = spec.rmsFilePrefix;
                suffix = 'Group';
            else
                prefix = spec.filePrefix;
                suffix = 'Group';
            end

            opts = struct();
            opts.style = style;
            opts.baseName = sprintf('%s_%s_%s_%s_%s_%s', prefix, groupName, suffix, ...
                datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd'), timestamp);
            opts.legendLocation = bms.analyzer.DynamicAccelerationPlotService.styleField( ...
                style, 'group_legend_location', 'northeast');
            opts.legendBox = bms.analyzer.DynamicAccelerationPlotService.styleField( ...
                style, 'group_legend_box', 'off');
            opts.legendInterpreter = 'none';
            opts.titleInterpreter = 'none';
            opts.defaultColors = bms.analyzer.StructuralPlotConfigService.distinctColors(max(1, nSeries));
            opts.colorField = 'group_colors';
            opts.warnLines = {};
        end

        function warnLines = resolveGroupWarnLines(style, fieldName, groupName)
            warnLines = {};
            if ~isstruct(style) || ~isfield(style, fieldName) || isempty(style.(fieldName))
                return;
            end

            raw = style.(fieldName);
            if isstruct(raw) && ~isfield(raw, 'y')
                candidates = {char(string(groupName)), bms.data.PointResolver.safeId(groupName), ...
                    bms.data.PointResolver.legacySafeId(groupName), bms.data.PointResolver.dashSafeId(groupName)};
                for i = 1:numel(candidates)
                    if isfield(raw, candidates{i})
                        raw = raw.(candidates{i});
                        warnLines = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(raw);
                        return;
                    end
                end
                return;
            end

            warnLines = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(raw);
        end

        function outDir = groupOutputDir(style, spec)
            outDir = bms.analyzer.DynamicAccelerationPlotService.styleField(style, 'group_output_dir', '');
            if isempty(outDir)
                outDir = spec.groupOutputDir;
            end
        end

        function outDir = rmsGroupOutputDir(style, spec)
            outDir = bms.analyzer.DynamicAccelerationPlotService.styleField(style, 'rms_group_output_dir', '');
            if isempty(outDir) && isstruct(style) && isfield(style, 'rms') && isstruct(style.rms) ...
                    && isfield(style.rms, 'group_output_dir') && ~isempty(style.rms.group_output_dir)
                outDir = style.rms.group_output_dir;
            end
            if isempty(outDir)
                outDir = spec.rmsGroupOutputDir;
            end
        end

        function yl = resolveMainYLim(style, groupName)
            if bms.config.ConfigReader.boolValue(style.ylim_auto, false)
                yl = [];
                return;
            end
            yl = bms.plot.PlotService.resolveNamedYLim(style.ylims, groupName, style.ylim);
            if ~bms.plot.PlotService.isValidYLim(yl)
                yl = [];
            end
        end

        function yl = resolveRmsYLim(style, groupName)
            yl = bms.plot.PlotService.resolveNamedYLim(style.rms_ylims, groupName, style.rms_ylim);
            if ~bms.plot.PlotService.isValidYLim(yl)
                yl = [];
            end
        end

        function label = groupLabel(style, groupName)
            label = char(string(groupName));
            if ~isstruct(style) || ~isfield(style, 'group_labels') || ~isstruct(style.group_labels)
                return;
            end
            labels = style.group_labels;
            if isfield(labels, groupName)
                label = char(string(labels.(groupName)));
            end
        end

        function value = styleField(style, fieldName, defaultValue)
            value = defaultValue;
            if isstruct(style) && isfield(style, fieldName) && ~isempty(style.(fieldName))
                value = style.(fieldName);
            end
        end

        function [dt0, dt1] = fileDateRange(startDate, endDate)
            dt0 = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
            dt1 = datetime(endDate, 'InputFormat', 'yyyy-MM-dd');
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
