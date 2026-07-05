classdef DynamicAccelerationSeriesService
    %DYNAMICACCELERATIONSERIESSERVICE Data collection for acceleration modules.

    methods (Static)
        function stats = runSequential(rootDir, subfolder, startDate, endDate, cfg, autoDetectFs, points, style, stats, spec)
            parallelPlan = get_parallel_plan(cfg, numel(points), spec.parallelLabel);
            if parallelPlan.enabled
                fprintf('%s分析检测到并行配置，但为避免整段波形累积导致内存不足，改为逐测点顺序处理。\n', spec.displayName);
            end

            records = repmat(bms.analyzer.DynamicSeriesService.initRecord(), numel(points), 1);
            for i = 1:numel(points)
                fprintf('Collecting %s point %s (%d/%d) ...\n', ...
                    char(string(spec.moduleKey)), char(string(points{i})), i, numel(points));
                rec = bms.analyzer.DynamicAccelerationSeriesService.collectRecord( ...
                    rootDir, subfolder, points{i}, startDate, endDate, cfg, autoDetectFs, spec, true);
                records(i) = rec;
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
                    rootDir, rec.pid, rec.times, rec.vals, rec.fs, style, cfg, spec, rec.rms_times, rec.rms_vals);
                bms.analyzer.DynamicAccelerationPlotService.plotEnvelopeCurve( ...
                    rootDir, rec.pid, rec.times, rec.vals, style, cfg, spec);
            end

            bms.analyzer.DynamicAccelerationSeriesService.plotConfiguredGroups( ...
                rootDir, subfolder, startDate, endDate, cfg, autoDetectFs, style, spec, records);
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
                    fprintf('Collecting %s point %s (%d/%d) ...\n', ...
                        char(string(spec.moduleKey)), char(string(points{i})), i, numel(points));
                    records(i) = bms.analyzer.DynamicAccelerationSeriesService.collectRecord( ...
                        rootDir, subfolder, points{i}, startDate, endDate, cfg, autoDetectFs, spec, true);
                end
            end

            for i = 1:numel(points)
                rec = records(i);
                fprintf('处理测点 %s ...\n', rec.pid);
                if ~rec.has_data
                    warning('测点 %s 无数据，跳过', rec.pid);
                    continue;
                end
                times = rec.times;
                values = rec.vals;
                if isempty(values)
                    [times, values] = load_timeseries_range(rootDir, subfolder, rec.pid, startDate, endDate, cfg, spec.sensorType);
                end
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
                bms.analyzer.DynamicAccelerationPlotService.plotRmsCurve( ...
                    rootDir, rec.pid, times, values, rec.fs, style, cfg, spec, rec.rms_times, rec.rms_vals);
                bms.analyzer.DynamicAccelerationPlotService.plotEnvelopeCurve(rootDir, rec.pid, times, values, style, cfg, spec);
            end

            bms.analyzer.DynamicAccelerationSeriesService.plotConfiguredGroups( ...
                rootDir, subfolder, startDate, endDate, cfg, autoDetectFs, style, spec, records);
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
            groupsCfg = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, spec.groupKey, []);
            points = bms.analyzer.StructuralPlotConfigService.flattenGroups(groupsCfg);
            if ~isempty(points)
                points = unique(points(:), 'stable');
                return;
            end
            points = spec.defaultPoints;
        end

        function style = plotStyle(cfg, spec)
            style = bms.config.ConfigReader.getPlotStyle(cfg, spec.styleKey, spec.defaultStyle);
        end

        function plotConfiguredGroups(rootDir, subfolder, startDate, endDate, cfg, autoDetectFs, style, spec, cachedRecords)
            if nargin < 9
                cachedRecords = [];
            end
            groupsCfg = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, spec.groupKey, []);
            if ~bms.analyzer.StructuralPlotConfigService.hasGroups(groupsCfg) && strcmp(spec.moduleKey, 'cable_accel')
                groupsCfg = bms.analyzer.DynamicAccelerationSeriesService.cableForceGroups(cfg);
            end
            if ~bms.analyzer.StructuralPlotConfigService.hasGroups(groupsCfg)
                return;
            end

            groups = bms.analyzer.StructuralPlotConfigService.normalizeGroupMap(groupsCfg);
            names = fieldnames(groups);
            for i = 1:numel(names)
                groupName = names{i};
                pointIds = groups.(groupName);
                records = bms.analyzer.DynamicAccelerationSeriesService.cachedGroupRecords(cachedRecords, pointIds);
                if isempty(records)
                    records = bms.analyzer.DynamicAccelerationSeriesService.collectGroupRecords( ...
                        rootDir, subfolder, pointIds, startDate, endDate, cfg, autoDetectFs, spec);
                end
                if isempty(records)
                    warning('%s组 %s 无有效数据，跳过组图', spec.displayName, groupName);
                    continue;
                end
                bms.analyzer.DynamicAccelerationPlotService.plotAccelGroup( ...
                    rootDir, groupName, records, startDate, endDate, style, cfg, spec);
                bms.analyzer.DynamicAccelerationPlotService.plotRmsGroup( ...
                    rootDir, groupName, records, startDate, endDate, style, cfg, spec);
            end
        end

        function records = cachedGroupRecords(cachedRecords, pointIds)
            records = repmat(bms.analyzer.DynamicSeriesService.initRecord(), 0, 1);
            if isempty(cachedRecords)
                return;
            end
            pointIds = bms.data.PointResolver.normalize(pointIds);
            for i = 1:numel(pointIds)
                pid = char(string(pointIds{i}));
                match = [];
                for j = 1:numel(cachedRecords)
                    rec = cachedRecords(j);
                    if isfield(rec, 'pid') && strcmp(char(string(rec.pid)), pid)
                        match = rec;
                        break;
                    end
                end
                if isempty(match) || ~isfield(match, 'has_data') || ~match.has_data ...
                        || ~isfield(match, 'vals') || isempty(match.vals)
                    records = repmat(bms.analyzer.DynamicSeriesService.initRecord(), 0, 1);
                    return;
                end
                records(end+1, 1) = match; %#ok<AGROW>
            end
        end

        function records = collectGroupRecords(rootDir, subfolder, pointIds, startDate, endDate, cfg, autoDetectFs, spec)
            records = repmat(bms.analyzer.DynamicSeriesService.initRecord(), 0, 1);
            pointIds = bms.data.PointResolver.normalize(pointIds);
            for i = 1:numel(pointIds)
                pid = pointIds{i};
                rec = bms.analyzer.DynamicAccelerationSeriesService.collectRecord( ...
                    rootDir, subfolder, pid, startDate, endDate, cfg, autoDetectFs, spec, true);
                if ~rec.has_data
                    warning('%s组图测点 %s 无数据，跳过', spec.displayName, pid);
                    continue;
                end
                records(end+1, 1) = rec; %#ok<AGROW>
            end
        end

        function groups = cableForceGroups(cfg)
            groups = struct();
            if isstruct(cfg) && isfield(cfg, 'groups') && isstruct(cfg.groups) && ...
                    isfield(cfg.groups, 'cable_force')
                groups = bms.data.PointResolver.normalizeGroups(cfg.groups.cable_force);
            end
        end
    end
end
