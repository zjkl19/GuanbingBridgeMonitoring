classdef DynamicAccelerationPlotService
    %DYNAMICACCELERATIONPLOTSERVICE Plot helpers for acceleration modules.

    methods (Static)
        function plotAccelCurve(rootDir, pointId, times, values, minVal, maxVal, style, cfg, spec)
            fig = figure('Position', [100 100 1000 469]);
            plotOpts = bms.analyzer.DynamicSeriesService.rawPlotOptions(cfg, 50000);
            [timesPlot, valuesPlot] = prepare_plot_series(times, values, plotOpts);
            lineWidth = bms.analyzer.DynamicSeriesService.rawPlotLineWidth(cfg, 1.0);
            plot(timesPlot, valuesPlot, 'LineWidth', lineWidth, 'Color', style.color_main);
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

        function plotRmsCurve(rootDir, pointId, times, values, fs, style, cfg, spec, rmsTimes, rmsSeries)
            if isempty(values) || numel(times) ~= numel(values)
                return;
            end
            validTimeMask = ~isnat(times);
            if ~any(validTimeMask)
                return;
            end

            if nargin < 9 || isempty(rmsTimes) || isempty(rmsSeries)
                [rmsTimes, rmsSeries, rmsMax, tMax] = bms.analyzer.DynamicSeriesService.rmsByTimeBins(times, values, 10, 0.7, fs);
            else
                rmsTimes = rmsTimes(:);
                rmsSeries = rmsSeries(:);
                [rmsMax, idxMax] = max(rmsSeries, [], 'omitnan');
                if isempty(idxMax) || ~isfinite(rmsMax)
                    rmsMax = NaN;
                    tMax = NaT;
                else
                    tMax = rmsTimes(idxMax);
                end
            end
            fig = figure('Position', [100 100 1000 469]);
            plotOpts = bms.plot.PlotService.runtimeOptionsFromConfig(cfg);
            [timesPlot, rmsPlot] = prepare_plot_series(rmsTimes, rmsSeries, plotOpts);
            if isempty(timesPlot)
                timesPlot = rmsTimes;
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
            bms.analyzer.StructuralTimeSeriesPlotService.drawWarnLines( ...
                bms.analyzer.DynamicAccelerationPlotService.resolveGroupWarnLines( ...
                    style, 'rms_warn_lines', pointId, cfg, spec, []), style);

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

        function plotEnvelopeCurve(rootDir, pointId, times, values, style, cfg, spec)
            enabled = bms.analyzer.DynamicAccelerationPlotService.specField(spec, 'envelopeEnabled', false);
            enabled = bms.config.ConfigReader.boolValue( ...
                bms.analyzer.DynamicAccelerationPlotService.styleField(style, 'envelope_enabled', enabled), enabled);
            if ~enabled || isempty(values) || numel(times) ~= numel(values) || ~isdatetime(times)
                return;
            end

            valid = isfinite(values) & ~isnat(times);
            if ~any(valid)
                return;
            end

            binMinutes = bms.analyzer.DynamicAccelerationPlotService.styleField( ...
                style, 'envelope_bin_minutes', ...
                bms.analyzer.DynamicAccelerationPlotService.specField(spec, 'envelopeBinMinutes', 30));
            if isempty(binMinutes) || ~isscalar(binMinutes) || ~isfinite(binMinutes) || binMinutes <= 0
                binMinutes = 30;
            end

            validTimes = times(valid);
            xmin = dateshift(min(validTimes), 'start', 'day');
            xmax = dateshift(max(validTimes), 'start', 'day') + days(1);
            if xmin >= xmax
                xmax = xmin + days(1);
            end
            binEdges = xmin:minutes(binMinutes):xmax;
            if numel(binEdges) < 2
                return;
            end

            idx = discretize(times(valid), binEdges);
            good = ~isnan(idx);
            if ~any(good)
                return;
            end
            idx = idx(good);
            vals = values(valid);
            vals = vals(good);
            binCenters = binEdges(1:end-1)' + minutes(binMinutes / 2);
            nBins = numel(binCenters);

            p01 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 1), NaN);
            p05 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 5), NaN);
            p50 = accumarray(idx, vals, [nBins 1], @(x) median(x, 'omitnan'), NaN);
            p95 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 95), NaN);
            p99 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 99), NaN);
            ymin = accumarray(idx, vals, [nBins 1], @(x) min(x, [], 'omitnan'), NaN);
            ymax = accumarray(idx, vals, [nBins 1], @(x) max(x, [], 'omitnan'), NaN);
            rmsv = accumarray(idx, vals, [nBins 1], @(x) sqrt(mean(x.^2, 'omitnan')), NaN);

            outDir = bms.analyzer.DynamicAccelerationPlotService.specField(spec, 'envelopeOutputDir', '');
            if isempty(outDir)
                return;
            end

            fig = figure('Visible', 'off', 'Position', [100 100 1200 620]);
            tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

            ax1 = nexttile;
            hold(ax1, 'on');
            bms.analyzer.DynamicAccelerationPlotService.fillEnvelopeBand(ax1, binCenters, p01, p99, [0.78 0.86 0.96], '1%~99%');
            bms.analyzer.DynamicAccelerationPlotService.fillEnvelopeBand(ax1, binCenters, p05, p95, [0.45 0.68 0.90], '5%~95%');
            plot(ax1, binCenters, p50, 'Color', [0 0.25 0.55], 'LineWidth', 1.2, 'DisplayName', 'median');
            plot(ax1, binCenters, ymin, ':', 'Color', [0.65 0.65 0.65], 'LineWidth', 0.6, 'DisplayName', 'min/max');
            plot(ax1, binCenters, ymax, ':', 'Color', [0.65 0.65 0.65], 'LineWidth', 0.6, 'HandleVisibility', 'off');
            hold(ax1, 'off');
            grid(ax1, 'on');
            grid(ax1, 'minor');
            xlim(ax1, [xmin xmax - seconds(1)]);
            ylabel(ax1, style.ylabel);
            titlePrefix = bms.analyzer.DynamicAccelerationPlotService.styleField(style, ...
                'envelope_title_prefix', [num2str(round(binMinutes)) ' min ' char([21253 32476]) '/RMS']);
            title(ax1, sprintf('%s %s', titlePrefix, pointId), 'Interpreter', 'none');
            legend(ax1, 'Location', 'northeast', 'Box', 'off');

            ax2 = nexttile;
            plot(ax2, binCenters, rmsv, 'LineWidth', 1.2, 'Color', style.color_rms);
            grid(ax2, 'on');
            grid(ax2, 'minor');
            xlim(ax2, [xmin xmax - seconds(1)]);
            ylabel(ax2, bms.analyzer.DynamicAccelerationPlotService.envelopeRmsYLabel(style, binMinutes));
            xlabel(ax2, char([26102 38388]));
            title(ax2, sprintf('%d min RMS %s', round(binMinutes), pointId), 'Interpreter', 'none');
            xtickformat(ax1, 'yyyy-MM-dd');
            xtickformat(ax2, 'yyyy-MM-dd');

            outDir = fullfile(rootDir, outDir);
            bms.core.PathResolver.ensureDir(outDir);
            prefix = bms.analyzer.DynamicAccelerationPlotService.specField(spec, 'envelopeFilePrefix', 'Envelope');
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            fname = sprintf('%s_%s_%s_%s_%s', prefix, pointId, datestr(xmin, 'yyyymmdd'), datestr(xmax - days(1), 'yyyymmdd'), timestamp);
            bms.plot.PlotService.saveModuleBundle(fig, outDir, fname, cfg);
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
            warnField = bms.analyzer.DynamicAccelerationPlotService.specField(spec, 'groupWarnField', 'group_warn_lines');
            opts.warnLines = bms.analyzer.DynamicAccelerationPlotService.resolveGroupWarnLines( ...
                style, warnField, groupName, cfg, spec, records);
            opts.fig_max_points = bms.analyzer.DynamicSeriesService.rawPlotMaxPoints(cfg, 50000);
            opts.lineWidth = bms.analyzer.DynamicSeriesService.rawPlotLineWidth(cfg, 1.0);

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
                if isfield(rec, 'rms_times') && isfield(rec, 'rms_vals') ...
                        && ~isempty(rec.rms_times) && ~isempty(rec.rms_vals)
                    rmsTimes = rec.rms_times;
                    rmsSeries = rec.rms_vals;
                else
                    [rmsTimes, rmsSeries] = bms.analyzer.DynamicSeriesService.rmsByTimeBins(rec.times, rec.vals, 10, 0.7, rec.fs);
                end
                if isempty(rmsSeries)
                    continue;
                end
                timesList{end+1, 1} = rmsTimes; %#ok<AGROW>
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
                style, 'rms_warn_lines', groupName, cfg, spec, records);

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

        function warnLines = resolveGroupWarnLines(style, fieldName, groupName, cfg, spec, records)
            warnLines = {};
            if nargin < 4
                cfg = struct();
            end
            if nargin < 5
                spec = struct();
            end
            if nargin < 6
                records = [];
            end

            if isempty(fieldName)
                warnLines = bms.analyzer.DynamicAccelerationPlotService.commonGroupWarnLines(cfg, spec, style, records);
                return;
            end

            if ~isstruct(style) || ~isfield(style, fieldName) || isempty(style.(fieldName))
                if ~strcmp(fieldName, 'group_warn_lines')
                    return;
                end
                warnLines = bms.analyzer.DynamicAccelerationPlotService.commonGroupWarnLines(cfg, spec, style, records);
                return;
            end

            raw = style.(fieldName);
            if isstruct(raw) && ~isfield(raw, 'y')
                candidates = {char(string(groupName)), bms.data.PointResolver.safeId(groupName), ...
                    bms.data.PointResolver.legacySafeId(groupName), bms.data.PointResolver.dashSafeId(groupName)};
                for i = 1:numel(candidates)
                    if isfield(raw, candidates{i})
                        raw = raw.(candidates{i});
                        warnLines = bms.analyzer.StructuralPlotConfigService.applyWarnLineDefaults(raw, style);
                        return;
                    end
                end
                if ~strcmp(fieldName, 'group_warn_lines')
                    return;
                end
                warnLines = bms.analyzer.DynamicAccelerationPlotService.commonGroupWarnLines(cfg, spec, style, records);
                return;
            end

            warnLines = bms.analyzer.StructuralPlotConfigService.applyWarnLineDefaults(raw, style);
        end

        function warnLines = commonGroupWarnLines(cfg, spec, style, records)
            warnLines = {};
            if isempty(records) || ~isstruct(cfg) || ~isstruct(spec) || ~isfield(spec, 'moduleKey')
                return;
            end

            common = {};
            for i = 1:numel(records)
                if ~isfield(records(i), 'pid') || isempty(records(i).pid)
                    continue;
                end
                pid = records(i).pid;
                current = bms.analyzer.StructuralTimeSeriesPlotService.resolveWarnLines( ...
                    style, cfg, spec.moduleKey, pid);
                current = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(current);
                if isempty(current)
                    current = bms.analyzer.DynamicAccelerationPlotService.thresholdWarnLines(cfg, spec.moduleKey, pid, style);
                end
                if isempty(current)
                    warnLines = {};
                    return;
                end
                if isempty(common)
                    common = current;
                elseif ~bms.analyzer.DynamicAccelerationPlotService.warnLinesHaveSameY(common, current)
                    warnLines = {};
                    return;
                end
            end
            warnLines = common;
        end

        function warnLines = thresholdWarnLines(cfg, moduleKey, pointId, style)
            warnLines = {};
            if ~isstruct(cfg) || ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point) || ...
                    ~isfield(cfg.per_point, moduleKey) || ~isstruct(cfg.per_point.(moduleKey))
                return;
            end

            [ok, pointCfg] = bms.data.PointResolver.getPointConfig(cfg.per_point.(moduleKey), pointId, cfg);
            if ~ok || ~isfield(pointCfg, 'thresholds') || isempty(pointCfg.thresholds) || ~isstruct(pointCfg.thresholds)
                return;
            end

            ths = pointCfg.thresholds(:);
            unit = bms.analyzer.StructuralPlotConfigService.warnUnit(style);
            lowerLabel = char([19979 38480]);
            upperLabel = char([19978 38480]);
            lineColor = [0.85 0.1 0.1];
            values = [];
            labels = {};
            for i = 1:numel(ths)
                th = ths(i);
                if isfield(th, 'min') && isnumeric(th.min) && isscalar(th.min) && isfinite(th.min)
                    values(end+1, 1) = th.min; %#ok<AGROW>
                    labels{end+1, 1} = bms.analyzer.StructuralPlotConfigService.composeWarnValueLabel(lowerLabel, th.min, unit); %#ok<AGROW>
                end
                if isfield(th, 'max') && isnumeric(th.max) && isscalar(th.max) && isfinite(th.max)
                    values(end+1, 1) = th.max; %#ok<AGROW>
                    labels{end+1, 1} = bms.analyzer.StructuralPlotConfigService.composeWarnValueLabel(upperLabel, th.max, unit); %#ok<AGROW>
                end
            end
            if isempty(values)
                return;
            end

            [values, ia] = unique(values, 'stable');
            labels = labels(ia);
            warnLines = cell(numel(values), 1);
            for i = 1:numel(values)
                warnLines{i} = struct('y', values(i), 'label', labels{i}, ...
                    'color', lineColor, 'unit', unit);
            end
        end

        function tf = warnLinesHaveSameY(a, b)
            av = bms.analyzer.DynamicAccelerationPlotService.warnLineYValues(a);
            bv = bms.analyzer.DynamicAccelerationPlotService.warnLineYValues(b);
            av = sort(av(isfinite(av)));
            bv = sort(bv(isfinite(bv)));
            tf = numel(av) == numel(bv) && all(abs(av(:) - bv(:)) < 1e-9);
        end

        function values = warnLineYValues(warnLines)
            warnLines = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(warnLines);
            values = NaN(numel(warnLines), 1);
            for i = 1:numel(warnLines)
                wl = warnLines{i};
                if isstruct(wl) && isfield(wl, 'y') && isnumeric(wl.y) && isscalar(wl.y)
                    values(i) = wl.y;
                end
            end
        end

        function label = envelopeRmsYLabel(style, binMinutes)
            if nargin < 2 || isempty(binMinutes) || ~isfinite(binMinutes)
                binMinutes = 30;
            end
            unit = bms.analyzer.StructuralPlotConfigService.warnUnit(style);
            if isempty(unit)
                label = sprintf('%d min RMS', round(binMinutes));
            else
                label = sprintf('%d min RMS (%s)', round(binMinutes), unit);
            end
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
            label = bms.analyzer.StructuralPlotConfigService.groupLabel(style, groupName);
        end

        function value = styleField(style, fieldName, defaultValue)
            value = defaultValue;
            if isstruct(style) && isfield(style, fieldName) && ~isempty(style.(fieldName))
                value = style.(fieldName);
            end
        end

        function value = specField(spec, fieldName, defaultValue)
            value = defaultValue;
            if isstruct(spec) && isfield(spec, fieldName)
                value = spec.(fieldName);
            end
        end

        function fillEnvelopeBand(ax, t, lo, hi, color, label)
            t = t(:);
            lo = lo(:);
            hi = hi(:);
            ok = isfinite(lo) & isfinite(hi) & ~isnat(t);
            if ~any(ok)
                return;
            end

            edges = diff([false; ok; false]);
            starts = find(edges == 1);
            stops = find(edges == -1) - 1;
            wasHold = ishold(ax);
            hold(ax, 'on');
            holdCleaner = onCleanup(@() bms.analyzer.DynamicAccelerationPlotService.restoreHold(ax, wasHold)); %#ok<NASGU>
            showLegend = true;
            for i = 1:numel(starts)
                runIdx = starts(i):stops(i);
                if numel(runIdx) < 2
                    continue;
                end
                args = {'FaceAlpha', 0.6, 'EdgeColor', 'none'};
                if showLegend
                    args = [args, {'DisplayName', label}]; %#ok<AGROW>
                    showLegend = false;
                else
                    args = [args, {'HandleVisibility', 'off'}]; %#ok<AGROW>
                end
                fill(ax, [t(runIdx); flipud(t(runIdx))], [lo(runIdx); flipud(hi(runIdx))], color, args{:});
            end
        end

        function restoreHold(ax, wasHold)
            if isvalid(ax) && ~wasHold
                hold(ax, 'off');
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
