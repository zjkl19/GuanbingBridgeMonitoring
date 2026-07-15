classdef EarthquakeAnalysisPipeline
    %EARTHQUAKEANALYSISPIPELINE Earthquake motion time-series workflow.

    methods (Static)
        function run(rootDir, startDate, endDate, subfolder, cfg)
            if nargin < 1 || isempty(rootDir), rootDir = pwd; end
            if nargin < 2 || isempty(startDate), startDate = input('开始日期 (yyyy-MM-dd): ', 's'); end
            if nargin < 3 || isempty(endDate), endDate = input('结束日期 (yyyy-MM-dd): ', 's'); end
            if nargin < 5 || isempty(cfg), cfg = load_config(); end
            if nargin < 4 || isempty(subfolder)
                subfolder = bms.analyzer.EarthquakeAnalysisPipeline.resolveSubfolder(cfg);
            end

            rootDir = char(string(rootDir));
            startDate = char(string(startDate));
            endDate = char(string(endDate));
            subfolder = char(string(subfolder));

            timeStart = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
            fprintf('开始时间: %s\n', char(timeStart));

            points = bms.analyzer.EarthquakeAnalysisPipeline.resolvePoints(cfg);
            style = bms.analyzer.EarthquakeAnalysisPipeline.style(cfg);
            outRoot = fullfile(rootDir, style.output.root_dir);
            bms.core.PathResolver.ensureDir(outRoot);

            parallelPlan = bms.analyzer.EarthquakeAnalysisPipeline.parallelPlan(cfg, numel(points));
            fullSampling = bms.analyzer.DynamicSeriesService.isFullRawSampling(cfg);
            if fullSampling
                [records, parallelPlan] = bms.analyzer.EarthquakeAnalysisPipeline.collectPlotFullSequential( ...
                    rootDir, subfolder, startDate, endDate, cfg, points, style, outRoot, parallelPlan);
            else
                records = bms.analyzer.EarthquakeAnalysisPipeline.collectRecords( ...
                    rootDir, subfolder, startDate, endDate, cfg, points, parallelPlan);
            end

            statsPath = bms.analyzer.EarthquakeAnalysisPipeline.writeStats(rootDir, records);
            fprintf('地震动统计已写入: %s\n', statsPath);

            if ~fullSampling
                bms.analyzer.EarthquakeAnalysisPipeline.plotRecords( ...
                    records, style, outRoot, startDate, endDate, cfg, parallelPlan);
            end

            timeEnd = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
            fprintf('结束时间: %s\n', char(timeEnd));
            fprintf('总用时: %.2f sec\n', seconds(timeEnd - timeStart));
        end

        function subfolder = resolveSubfolder(cfg)
            subfolder = bms.config.ConfigReader.getSubfolder(cfg, 'eq_raw', '波形');
        end

        function points = resolvePoints(cfg)
            points = bms.data.PointResolver.fromConfig(cfg, 'eq', {'EQ-X', 'EQ-Y', 'EQ-Z'});
        end

        function style = style(cfg)
            style = struct();
            style.output = struct( ...
                'root_dir', '地震动结果', ...
                'series_dir', '地震动时程', ...
                'prefix', 'EQ');
            style.ylabel = '地震动加速度 (m/s^2)';
            style.title_prefix = '地震动时程';
            style.ylim_auto = false;
            style.ylim = [];
            style.ylims = [];
            style.main_color = [0 0.447 0.741];

            ps = bms.config.ConfigReader.getStruct(cfg, 'plot_styles.eq', struct());
            if isempty(fieldnames(ps))
                return;
            end
            ps = ps(1);

            if isfield(ps, 'output') && isstruct(ps.output)
                style.output = bms.config.ConfigReader.mergeStruct(style.output, ps.output);
            end
            if isfield(ps, 'ylabel'), style.ylabel = ps.ylabel; end
            if isfield(ps, 'title_prefix'), style.title_prefix = ps.title_prefix; end
            if isfield(ps, 'ylim_auto'), style.ylim_auto = ps.ylim_auto; end
            if isfield(ps, 'ylim'), style.ylim = ps.ylim; end
            if isfield(ps, 'ylims'), style.ylims = ps.ylims; end
            if isfield(ps, 'color'), style.main_color = ps.color; end
        end

        function params = params(cfg, pointId)
            params = struct('alarm_levels', [1, 2], 'raw_min_filter', [], 'value_scale', 1);
            ep = bms.config.ConfigReader.getStruct(cfg, 'eq_params', struct());
            if isfield(ep, 'alarm_levels') && ~isempty(ep.alarm_levels)
                params.alarm_levels = double(ep.alarm_levels(:))';
            end
            if isfield(ep, 'raw_min_filter') && ~isempty(ep.raw_min_filter)
                params.raw_min_filter = double(ep.raw_min_filter);
            end
            if isfield(ep, 'value_scale') && ~isempty(ep.value_scale)
                params.value_scale = double(ep.value_scale);
            end

            if nargin < 2 || isempty(pointId)
                return;
            end
            ok = false;
            perPoint = [];
            if isstruct(cfg) && isfield(cfg, 'per_point') && isfield(cfg.per_point, 'eq') ...
                    && isstruct(cfg.per_point.eq)
                [ok, perPoint] = bms.data.PointResolver.getPointConfig(cfg.per_point.eq, pointId, cfg);
            end
            if ok && isstruct(perPoint) && isfield(perPoint, 'alarm_levels') && ~isempty(perPoint.alarm_levels)
                params.alarm_levels = double(perPoint.alarm_levels(:))';
            end
            if ok && isstruct(perPoint) && isfield(perPoint, 'raw_min_filter') && ~isempty(perPoint.raw_min_filter)
                params.raw_min_filter = double(perPoint.raw_min_filter);
            end
            if ok && isstruct(perPoint) && isfield(perPoint, 'value_scale') && ~isempty(perPoint.value_scale)
                params.value_scale = double(perPoint.value_scale);
            end
        end

        function plan = parallelPlan(cfg, pointCount)
            plan = get_parallel_plan(cfg, pointCount, 'eq');
        end

        function records = collectRecords(rootDir, subfolder, startDate, endDate, cfg, points, parallelPlan)
            records = repmat(bms.analyzer.EarthquakeSeriesService.initRecord(), numel(points), 1);
            if parallelPlan.enabled
                fprintf('地震动分析使用并行数据收集 (%d workers)\n', parallelPlan.worker_count);
                parfor i = 1:numel(points)
                    records(i) = bms.analyzer.EarthquakeAnalysisPipeline.collectRecord( ...
                        rootDir, subfolder, points{i}, startDate, endDate, cfg);
                end
            else
                for i = 1:numel(points)
                    bms.app.StopController.throwIfRequested('Stop requested before next earthquake point');
                    fprintf('Collecting earthquake point %s (%d/%d) ...\n', ...
                        char(string(points{i})), i, numel(points));
                    records(i) = bms.analyzer.EarthquakeAnalysisPipeline.collectRecord( ...
                        rootDir, subfolder, points{i}, startDate, endDate, cfg);
                    fprintf('Collected earthquake point %s (%d/%d).\n', ...
                        char(string(points{i})), i, numel(points));
                end
            end
        end

        function [records, parallelPlan] = collectPlotFullSequential(rootDir, subfolder, startDate, endDate, cfg, points, style, outRoot, parallelPlan)
            if parallelPlan.enabled
                fprintf('Earthquake full sampling forces sequential component processing.\n');
            end
            parallelPlan.enabled = false;
            records = repmat(bms.analyzer.EarthquakeSeriesService.initRecord(), numel(points), 1);
            for i = 1:numel(points)
                bms.app.StopController.throwIfRequested('Stop requested before next earthquake full point');
                pointId = points{i};
                fprintf('Collecting full earthquake point %s (%d/%d) ...\n', ...
                    char(string(pointId)), i, numel(points));
                rec = bms.analyzer.EarthquakeAnalysisPipeline.collectRecord( ...
                    rootDir, subfolder, pointId, startDate, endDate, cfg);
                if rec.has_data
                    bms.analyzer.EarthquakeAnalysisPipeline.plotTimeseries( ...
                        rec.times, rec.vals, rec.pid, rec.comp, rec.params, style, outRoot, ...
                        startDate, endDate, cfg, rec.peak, rec.peak_signed, rec.peak_time, ...
                        rec.source_provenance);
                else
                    warning('Earthquake point %s has no data; skipped.', char(string(pointId)));
                end
                rec.times = [];
                rec.vals = [];
                records(i) = rec;
                clear rec;
            end
        end

        function rec = collectRecord(rootDir, subfolder, pointId, startDate, endDate, cfg)
            rec = bms.analyzer.EarthquakeSeriesService.collectRecord( ...
                rootDir, subfolder, pointId, startDate, endDate, cfg, ...
                bms.analyzer.EarthquakeAnalysisPipeline.params(cfg, pointId));
        end

        function plotRecords(records, style, outRoot, startDate, endDate, cfg, parallelPlan)
            for i = 1:numel(records)
                bms.app.StopController.throwIfRequested('Stop requested before next earthquake plot');
                rec = records(i);
                fprintf('处理测点 %s ...\n', rec.pid);
                if ~rec.has_data
                    warning('测点 %s 无数据，跳过', rec.pid);
                    continue;
                end
                if parallelPlan.enabled
                    record_parallel_offset_correction(cfg, rec.sensor_type, rec.pid, rec.times, rec.vals);
                end
                bms.analyzer.EarthquakeAnalysisPipeline.plotTimeseries( ...
                    rec.times, rec.vals, rec.pid, rec.comp, rec.params, style, outRoot, startDate, endDate, cfg, ...
                    rec.peak, rec.peak_signed, rec.peak_time, rec.source_provenance);
            end
        end

        function path = writeStats(rootDir, records)
            T = bms.analyzer.EarthquakeAnalysisPipeline.statsTable(records);
            path = bms.data.DataLayoutResolver.statsFile(rootDir, 'eq_stats.xlsx');
            bms.io.StatsWriter.writeModuleTableChecked(T, path, 'earthquake');
        end

        function T = statsTable(records)
            pointIds = {};
            components = {};
            peaks = [];
            peakSigneds = [];
            peakTimes = {};
            for i = 1:numel(records)
                rec = records(i);
                if ~isstruct(rec) || ~isfield(rec, 'has_data') || ~rec.has_data
                    continue;
                end
                peak = NaN;
                peakSigned = NaN;
                peakTime = NaT;
                if isfield(rec, 'peak') && isfinite(rec.peak)
                    peak = rec.peak;
                    if isfield(rec, 'peak_signed') && isfinite(rec.peak_signed)
                        peakSigned = rec.peak_signed;
                    end
                    if isfield(rec, 'peak_time')
                        peakTime = rec.peak_time;
                    end
                else
                    vals = rec.vals(:);
                    if isempty(vals)
                        continue;
                    end
                    [peak, peakSigned, peakTime, idx] = bms.analyzer.EarthquakeSeriesService.absPeak(rec.times, vals);
                    if isempty(idx) || ~isfinite(peak) || idx < 1 || idx > numel(rec.times)
                        continue;
                    end
                end
                if ~isfinite(peakSigned)
                    peakSigned = peak;
                end
                pointIds{end+1, 1} = bms.analyzer.EarthquakeAnalysisPipeline.basePointId(rec.pid); %#ok<AGROW>
                components{end+1, 1} = char(string(rec.comp)); %#ok<AGROW>
                peaks(end+1, 1) = peak; %#ok<AGROW>
                peakSigneds(end+1, 1) = peakSigned; %#ok<AGROW>
                peakTimes{end+1, 1} = bms.analyzer.EarthquakeAnalysisPipeline.formatTime(peakTime); %#ok<AGROW>
            end
            T = table(string(pointIds(:)), string(components(:)), peaks(:), peakSigneds(:), string(peakTimes(:)), ...
                'VariableNames', {'PointID', 'Component', 'Peak', 'PeakSigned', 'PeakTime'});
            T = bms.io.StatsSchema.normalizeTable(T, 'earthquake');
        end

        function pointId = basePointId(pointId)
            pointId = regexprep(char(string(pointId)), '[-_][XYZxyz]$', '');
        end

        function text = formatTime(value)
            if isdatetime(value)
                text = char(string(value, 'yyyy-MM-dd HH:mm:ss'));
            elseif isnumeric(value)
                text = datestr(value, 'yyyy-mm-dd HH:MM:ss');
            else
                text = char(string(value));
            end
        end

        function plotTimeseries(times, vals, pointId, component, params, style, outRoot, startDate, endDate, cfg, peakAbs, peakSigned, peakTime, sourceProvenance)
            if nargin < 10
                cfg = struct();
            end
            if nargin < 11
                peakAbs = NaN;
            end
            if nargin < 12
                peakSigned = NaN;
            end
            if nargin < 13
                peakTime = NaT;
            end
            if nargin < 14
                sourceProvenance = struct();
            end

            fig = figure('Position', [100 100 1100 500]);
            plotOpts = bms.analyzer.DynamicSeriesService.rawPlotOptions( ...
                cfg, 50000, 'eq', pointId);
            plotOpts.series_id = pointId;
            if isstruct(sourceProvenance) && ~isempty(fieldnames(sourceProvenance))
                plotOpts.source_provenance = sourceProvenance;
            end
            lineWidth = bms.analyzer.DynamicSeriesService.rawPlotLineWidth(cfg, 1.1);
            bms.analyzer.DynamicSeriesService.plotRawSeries( ...
                gca, times, vals, style.main_color, plotOpts, lineWidth);
            xlabel('时间');
            ylabel(style.ylabel);
            title(sprintf('%s %s [%s-%s]', style.title_prefix, pointId, startDate, endDate));
            grid on;
            grid minor;
            hold on;

            bms.analyzer.EarthquakeAnalysisPipeline.applyYLim(style, pointId);
            bms.plot.PlotService.setTimeAxis(times);
            bms.analyzer.EarthquakeAnalysisPipeline.drawAlarmLines(params);
            bms.analyzer.EarthquakeAnalysisPipeline.drawMaxMarker(times, vals, peakAbs, peakSigned, peakTime);

            outDir = fullfile(outRoot, style.output.series_dir);
            bms.core.PathResolver.ensureDir(outDir);
            baseName = sprintf('%s_%s_%s_%s', style.output.prefix, component, startDate, endDate);
            bms.plot.PlotService.saveModuleBundleWithTimestamp(fig, outDir, baseName, cfg);
        end

        function applyYLim(style, pointId)
            if bms.config.ConfigReader.boolValue(style.ylim_auto, false)
                ylim auto;
                return;
            end

            yl = bms.plot.PlotService.resolveNamedYLim(style.ylims, pointId, style.ylim);
            if bms.plot.PlotService.isValidYLim(yl)
                ylim(yl);
            elseif ~isempty(style.ylim)
                ylim(style.ylim);
            end
        end

        function drawAlarmLines(params)
            levels = bms.analyzer.EarthquakeAnalysisPipeline.alarmLevels(params);
            labels = {'E1地震作用加速度峰值', 'E2地震作用加速度峰值'};
            colors = [1 0.85 0; 0.85 0.1 0.1];
            for i = 1:min(numel(levels), numel(labels))
                lv = levels(i);
                if ~isfinite(lv)
                    continue;
                end
                h = yline(lv, '--', sprintf('%s %.2f', labels{i}, lv), 'Color', colors(i, :));
                h.LabelHorizontalAlignment = 'left';
                h.LabelVerticalAlignment = 'bottom';
                hn = yline(-lv, '--', sprintf('-%s %.2f', labels{i}, -lv), 'Color', colors(i, :));
                hn.LabelHorizontalAlignment = 'left';
                hn.LabelVerticalAlignment = 'top';
            end
        end

        function levels = alarmLevels(params)
            levels = [];
            if isstruct(params) && isfield(params, 'alarm_levels') && ~isempty(params.alarm_levels)
                levels = double(params.alarm_levels(:))';
            end
            levels = sort(levels(~isnan(levels)));
        end

        function drawMaxMarker(times, vals, peakAbs, peakSigned, peakTime)
            if nargin < 3 || ~isfinite(peakAbs) || nargin < 4 || ~isfinite(peakSigned) ...
                    || nargin < 5 || ~isdatetime(peakTime) || isnat(peakTime)
                [peakAbs, peakSigned, peakTime] = bms.analyzer.EarthquakeSeriesService.absPeak(times, vals);
            end
            if ~isfinite(peakAbs) || ~isfinite(peakSigned) || ~isdatetime(peakTime) || isnat(peakTime)
                return;
            end
            plot(peakTime, peakSigned, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 6);
            text(peakTime, peakSigned, sprintf('峰值 |a|=%.3f\n%s', peakAbs, datestr(peakTime, 'yyyy-mm-dd HH:MM:ss')), ...
                'VerticalAlignment', 'bottom', ...
                'HorizontalAlignment', 'left', ...
                'Color', [0.6 0 0]);
        end
    end
end
