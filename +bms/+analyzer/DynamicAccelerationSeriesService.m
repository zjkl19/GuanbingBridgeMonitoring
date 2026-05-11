classdef DynamicAccelerationSeriesService
    %DYNAMICACCELERATIONSERIESSERVICE Data collection for acceleration modules.

    methods (Static)
        function stats = runSequential(rootDir, subfolder, startDate, endDate, cfg, autoDetectFs, points, style, stats, spec)
            parallelPlan = get_parallel_plan(cfg, numel(points), spec.parallelLabel);
            if parallelPlan.enabled
                fprintf('%s分析检测到并行配置，但为避免整段波形累积导致内存不足，改为逐测点顺序处理。\n', spec.displayName);
            end

            for i = 1:numel(points)
                rec = bms.analyzer.DynamicAccelerationSeriesService.collectRecord( ...
                    rootDir, subfolder, points{i}, startDate, endDate, cfg, autoDetectFs, spec, true);
                fprintf('处理测点 %s ...\n', rec.pid);
                if ~rec.has_data
                    warning('测点 %s 无数据，跳过', rec.pid);
                    continue;
                end
                bms.analyzer.DynamicAccelerationSeriesService.printSampleRate(rec.fs, autoDetectFs, false);
                stats(i, :) = {rec.pid, rec.mn, rec.mx, rec.av, rec.rms_max, rec.rms_time};
                bms.analyzer.DynamicAccelerationPlotService.plotAccelCurve( ...
                    rootDir, rec.pid, rec.times, rec.vals, rec.mn, rec.mx, style, cfg, spec);
                bms.analyzer.DynamicAccelerationPlotService.plotRmsCurve( ...
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
                    records(i) = bms.analyzer.DynamicAccelerationSeriesService.collectRecord( ...
                        rootDir, subfolder, points{i}, startDate, endDate, cfg, autoDetectFs, spec, false);
                end
            else
                for i = 1:numel(points)
                    records(i) = bms.analyzer.DynamicAccelerationSeriesService.collectRecord( ...
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
                bms.analyzer.DynamicAccelerationSeriesService.printSampleRate(rec.fs, autoDetectFs, parallelPlan.enabled);
                if parallelPlan.enabled
                    record_parallel_offset_correction(cfg, spec.sensorType, rec.pid, times, values);
                end
                stats(i, :) = {rec.pid, rec.mn, rec.mx, rec.av, rec.rms_max, rec.rms_time};
                bms.analyzer.DynamicAccelerationPlotService.plotAccelCurve(rootDir, rec.pid, times, values, rec.mn, rec.mx, style, cfg, spec);
                bms.analyzer.DynamicAccelerationPlotService.plotRmsCurve(rootDir, rec.pid, times, values, rec.fs, style, cfg, spec);
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
    end
end
