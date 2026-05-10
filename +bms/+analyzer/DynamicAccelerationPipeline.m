classdef DynamicAccelerationPipeline
    %DYNAMICACCELERATIONPIPELINE Shared pipeline for acceleration-like modules.

    methods (Static)
        function run(kind, rootDir, startDate, endDate, excelFile, subfolder, autoDetectFs, cfg)
            spec = bms.analyzer.DynamicAccelerationPipeline.spec(kind);
            if nargin < 2 || isempty(rootDir), rootDir = pwd; end
            if nargin < 3 || isempty(startDate), startDate = input('开始日期 (yyyy-MM-dd): ', 's'); end
            if nargin < 4 || isempty(endDate), endDate = input('结束日期 (yyyy-MM-dd): ', 's'); end
            if nargin < 5 || isempty(excelFile), excelFile = spec.defaultStatsFile; end
            if nargin < 7 || isempty(autoDetectFs), autoDetectFs = false; end
            if nargin < 8 || isempty(cfg), cfg = load_config(); end

            rootDir = char(rootDir);
            excelFile = resolve_data_output_path(rootDir, excelFile, 'stats');
            if nargin < 6 || isempty(subfolder)
                subfolder = bms.config.ConfigReader.getSubfolder(cfg, spec.subfolderKey, spec.defaultSubfolder);
            end

            timeStart = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
            fprintf('开始时间: %s\n', char(timeStart));

            points = bms.analyzer.DynamicAccelerationPipeline.resolvePoints(cfg, spec);
            style = bms.analyzer.DynamicAccelerationPipeline.plotStyle(cfg, spec);
            stats = cell(numel(points), 6);

            if spec.keepSeries
                stats = bms.analyzer.DynamicAccelerationPipeline.runSequential( ...
                    rootDir, subfolder, startDate, endDate, cfg, autoDetectFs, points, style, stats, spec);
            else
                stats = bms.analyzer.DynamicAccelerationPipeline.runWithOptionalParallel( ...
                    rootDir, subfolder, startDate, endDate, cfg, autoDetectFs, points, style, stats, spec);
            end

            tableOut = bms.analyzer.DynamicSeriesService.dynamicStatsTable(stats);
            bms.io.StatsWriter.writeModuleTableChecked(tableOut, excelFile, spec.moduleKey);
            fprintf('统计结果已保存至 %s\n', excelFile);

            timeEnd = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
            fprintf('结束时间: %s\n', char(timeEnd));
            fprintf('总用时 %.2f 秒\n', seconds(timeEnd - timeStart));
        end

        function stats = runSequential(rootDir, subfolder, startDate, endDate, cfg, autoDetectFs, points, style, stats, spec)
            parallelPlan = get_parallel_plan(cfg, numel(points), spec.parallelLabel);
            if parallelPlan.enabled
                fprintf('%s分析检测到并行配置，但为避免整段波形累积导致内存不足，改为逐测点顺序处理。\n', spec.displayName);
            end

            for i = 1:numel(points)
                rec = bms.analyzer.DynamicAccelerationPipeline.collectRecord( ...
                    rootDir, subfolder, points{i}, startDate, endDate, cfg, autoDetectFs, spec, true);
                fprintf('处理测点 %s ...\n', rec.pid);
                if ~rec.has_data
                    warning('测点 %s 无数据，跳过', rec.pid);
                    continue;
                end
                bms.analyzer.DynamicAccelerationPipeline.printSampleRate(rec.fs, autoDetectFs, false);
                stats(i, :) = {rec.pid, rec.mn, rec.mx, rec.av, rec.rms_max, rec.rms_time};
                bms.analyzer.DynamicAccelerationPipeline.plotAccelCurve( ...
                    rootDir, rec.pid, rec.times, rec.vals, rec.mn, rec.mx, style, cfg, spec);
                bms.analyzer.DynamicAccelerationPipeline.plotRmsCurve( ...
                    rootDir, rec.pid, rec.times, rec.vals, rec.fs, style, cfg, spec);
            end
        end

        function stats = runWithOptionalParallel(rootDir, subfolder, startDate, endDate, cfg, autoDetectFs, points, style, stats, spec)
            records = repmat(bms.analyzer.DynamicSeriesService.initRecord(), numel(points), 1);
            parallelPlan = get_parallel_plan(cfg, numel(points), spec.parallelLabel);
            if parallelPlan.enabled
                dayCount = days(datetime(endDate, 'InputFormat', 'yyyy-MM-dd') - datetime(startDate, 'InputFormat', 'yyyy-MM-dd')) + 1;
                if dayCount > 7
                    fprintf('%s分析时间跨度为 %d 天，禁用并行数据收集以避免内存峰值。\n', spec.displayName, round(dayCount));
                    parallelPlan.enabled = false;
                end
            end

            if parallelPlan.enabled
                fprintf('%s分析使用并行数据收集 (%d workers)\n', spec.displayName, parallelPlan.worker_count);
                parfor i = 1:numel(points)
                    records(i) = bms.analyzer.DynamicAccelerationPipeline.collectRecord( ...
                        rootDir, subfolder, points{i}, startDate, endDate, cfg, autoDetectFs, spec, false);
                end
            else
                for i = 1:numel(points)
                    records(i) = bms.analyzer.DynamicAccelerationPipeline.collectRecord( ...
                        rootDir, subfolder, points{i}, startDate, endDate, cfg, autoDetectFs, spec, false);
                end
            end

            for i = 1:numel(points)
                rec = records(i);
                fprintf('处理测点 %s ...\n', rec.pid);
                if ~rec.has_data
                    warning('测点 %s 无数据，跳过', rec.pid);
                    continue;
                end
                [times, values] = load_timeseries_range(rootDir, subfolder, rec.pid, startDate, endDate, cfg, spec.sensorType);
                if isempty(values)
                    warning('测点 %s 在绘图阶段无数据，跳过', rec.pid);
                    continue;
                end
                bms.analyzer.DynamicAccelerationPipeline.printSampleRate(rec.fs, autoDetectFs, parallelPlan.enabled);
                if parallelPlan.enabled
                    record_parallel_offset_correction(cfg, spec.sensorType, rec.pid, times, values);
                end
                stats(i, :) = {rec.pid, rec.mn, rec.mx, rec.av, rec.rms_max, rec.rms_time};
                bms.analyzer.DynamicAccelerationPipeline.plotAccelCurve(rootDir, rec.pid, times, values, rec.mn, rec.mx, style, cfg, spec);
                bms.analyzer.DynamicAccelerationPipeline.plotRmsCurve(rootDir, rec.pid, times, values, rec.fs, style, cfg, spec);
            end
        end

        function rec = collectRecord(rootDir, subfolder, pointId, startDate, endDate, cfg, autoDetectFs, spec, keepSeries)
            rec = bms.analyzer.DynamicSeriesService.collectRecord( ...
                rootDir, subfolder, pointId, startDate, endDate, cfg, spec.sensorType, autoDetectFs, keepSeries);
        end

        function printSampleRate(fs, autoDetectFs, parallelEnabled)
            if parallelEnabled
                fprintf('并行收集完成，采样率 %.2f Hz\n', fs);
            elseif bms.config.ConfigReader.boolValue(autoDetectFs, false)
                fprintf('自动检测采样率 %.2f Hz\n', fs);
            else
                fprintf('使用默认采样率 %d Hz\n', round(fs));
            end
        end

        function points = resolvePoints(cfg, spec)
            points = {};
            for i = 1:numel(spec.pointKeys)
                points = bms.data.PointResolver.fromConfig(cfg, spec.pointKeys{i}, {});
                if ~isempty(points)
                    return;
                end
            end
            points = spec.defaultPoints;
        end

        function style = plotStyle(cfg, spec)
            style = bms.config.ConfigReader.getPlotStyle(cfg, spec.styleKey, spec.defaultStyle);
        end

        function plotAccelCurve(rootDir, pointId, times, values, minVal, maxVal, style, cfg, spec)
            fig = figure('Position', [100 100 1000 469]);
            [timesPlot, valuesPlot] = prepare_plot_series(times, values);
            plot(timesPlot, valuesPlot, 'LineWidth', 1, 'Color', style.color_main);
            xlabel('时间');
            ylabel(style.ylabel);
            bms.analyzer.DynamicAccelerationPipeline.applyMainYLim(style, pointId);
            hold on;
            h1 = yline(maxVal, '--r');
            h1.Label = sprintf('最大值 %.3f', maxVal);
            h1.LabelHorizontalAlignment = 'left';
            h2 = yline(minVal, '--r');
            h2.Label = sprintf('最小值 %.3f', minVal);
            h2.LabelHorizontalAlignment = 'left';

            bms.analyzer.DynamicAccelerationPipeline.applyTimeAxis(times);
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
            bms.analyzer.DynamicAccelerationPipeline.applyRmsYLim(style, pointId);
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
            bms.analyzer.DynamicAccelerationPipeline.applyTimeAxisLimits(xmin, xmax);

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

        function spec = spec(kind)
            defaultPoints = { ...
                'GB-VIB-G04-001-01', 'GB-VIB-G05-001-01', 'GB-VIB-G05-002-01', 'GB-VIB-G05-003-01', ...
                'GB-VIB-G06-001-01', 'GB-VIB-G06-002-01', 'GB-VIB-G06-003-01', 'GB-VIB-G07-001-01'};
            kind = lower(char(string(kind)));
            switch kind
                case {'acceleration', 'accel'}
                    spec.moduleKey = 'acceleration';
                    spec.sensorType = 'acceleration';
                    spec.parallelLabel = 'acceleration';
                    spec.displayName = '加速度';
                    spec.pointKeys = {'acceleration'};
                    spec.styleKey = 'acceleration';
                    spec.subfolderKey = 'acceleration';
                    spec.defaultSubfolder = '波形_重采样';
                    spec.defaultStatsFile = 'accel_stats.xlsx';
                    spec.outputDir = '时程曲线_加速度';
                    spec.rmsOutputDir = '时程曲线_加速度_RMS10min';
                    spec.rmsFilePrefix = 'AccelRMS10';
                    spec.keepSeries = true;
                    spec.defaultPoints = defaultPoints;
                    spec.defaultStyle = struct('ylabel', '主梁竖向振动加速度 (m/s^2)', ...
                        'title_prefix', '加速度时程', ...
                        'ylim_auto', false, ...
                        'ylim', [], ...
                        'ylims', [], ...
                        'color_main', [0 0.447 0.741], ...
                        'color_rms', [0.8500 0.3250 0.0980], ...
                        'rms_ylabel', '10 min RMS (m/s^2)', ...
                        'rms_title_prefix', '10 min RMS 时程', ...
                        'rms_ylim', [], ...
                        'rms_ylims', []);
                case {'cable_accel', 'cable_acceleration'}
                    spec.moduleKey = 'cable_accel';
                    spec.sensorType = 'cable_accel';
                    spec.parallelLabel = 'cable_accel';
                    spec.displayName = '索力加速度';
                    spec.pointKeys = {'cable_accel', 'cable_force'};
                    spec.styleKey = 'cable_accel';
                    spec.subfolderKey = 'cable_accel';
                    spec.defaultSubfolder = '索力加速度_重采样';
                    spec.defaultStatsFile = 'cable_accel_stats.xlsx';
                    spec.outputDir = '时程曲线_索力加速度';
                    spec.rmsOutputDir = '时程曲线_索力加速度_RMS10min';
                    spec.rmsFilePrefix = 'CableAccelRMS10';
                    spec.keepSeries = false;
                    spec.defaultPoints = defaultPoints;
                    spec.defaultStyle = struct('ylabel', '索力加速度 (m/s^2)', ...
                        'title_prefix', '索力加速度时程', ...
                        'ylim_auto', false, ...
                        'ylim', [], ...
                        'ylims', [], ...
                        'color_main', [0 0.447 0.741], ...
                        'color_rms', [0.8500 0.3250 0.0980], ...
                        'rms_ylabel', '10 min RMS (m/s^2)', ...
                        'rms_title_prefix', '10 min RMS 时程', ...
                        'rms_ylim', [], ...
                        'rms_ylims', []);
                otherwise
                    error('DynamicAccelerationPipeline:UnsupportedKind', 'Unsupported acceleration pipeline kind: %s', kind);
            end
        end
    end
end
