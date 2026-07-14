classdef DynamicAccelerationSeriesService
    %DYNAMICACCELERATIONSERIESSERVICE Data collection for acceleration modules.

    methods (Static)
        function stats = runSequential(rootDir, subfolder, startDate, endDate, cfg, autoDetectFs, points, style, stats, spec)
            cfg = bms.analyzer.DynamicAccelerationSeriesService.modulePlotConfig(cfg, spec);
            releaseFullSeries = bms.analyzer.DynamicSeriesService.isFullRawSampling(cfg);
            parallelPlan = get_parallel_plan(cfg, numel(points), spec.parallelLabel);
            if parallelPlan.enabled
                fprintf('%s分析检测到并行配置，但为避免整段波形累积导致内存不足，改为逐测点顺序处理。\n', spec.displayName);
            end

            records = repmat(bms.analyzer.DynamicSeriesService.initRecord(), numel(points), 1);
            for i = 1:numel(points)
                bms.app.StopController.throwIfRequested('Stop requested before next dynamic point');
                fprintf('Collecting %s point %s (%d/%d) ...\n', ...
                    char(string(spec.moduleKey)), char(string(points{i})), i, numel(points));
                rec = bms.analyzer.DynamicAccelerationSeriesService.collectRecord( ...
                    rootDir, subfolder, points{i}, startDate, endDate, cfg, autoDetectFs, spec, true);
                fprintf('处理测点 %s ...\n', rec.pid);
                if ~rec.has_data
                    warning('测点 %s 无数据，跳过', rec.pid);
                    records(i) = bms.analyzer.DynamicAccelerationSeriesService.stripSeries(rec);
                    continue;
                end
                bms.analyzer.DynamicAccelerationSeriesService.printSampleRate(rec.fs, autoDetectFs, false);
                stats(i, :) = {rec.pid, rec.mn, rec.mx, rec.av, rec.rms_max, rec.rms_time};
                bms.analyzer.DynamicAccelerationPlotService.plotAccelCurve( ...
                    rootDir, rec.pid, rec.times, rec.vals, rec.mn, rec.mx, style, cfg, spec, rec.source_provenance);
                bms.analyzer.DynamicAccelerationPlotService.plotRmsCurve( ...
                    rootDir, rec.pid, rec.times, rec.vals, rec.fs, style, cfg, spec, rec.rms_times, rec.rms_vals);
                bms.analyzer.DynamicAccelerationPlotService.plotEnvelopeCurve( ...
                    rootDir, rec.pid, rec.times, rec.vals, style, cfg, spec);
                if releaseFullSeries
                    records(i) = bms.analyzer.DynamicAccelerationSeriesService.stripSeries(rec);
                    clear rec;
                else
                    records(i) = rec;
                end
            end

            bms.analyzer.DynamicAccelerationSeriesService.plotConfiguredGroups( ...
                rootDir, subfolder, startDate, endDate, cfg, autoDetectFs, style, spec, records);
        end

        function stats = runWithOptionalParallel(rootDir, subfolder, startDate, endDate, cfg, autoDetectFs, points, style, stats, spec)
            cfg = bms.analyzer.DynamicAccelerationSeriesService.modulePlotConfig(cfg, spec);
            if bms.analyzer.DynamicSeriesService.isFullRawSampling(cfg)
                fprintf('%s full sampling forces sequential point processing.\n', ...
                    char(string(spec.moduleKey)));
                stats = bms.analyzer.DynamicAccelerationSeriesService.runSequential( ...
                    rootDir, subfolder, startDate, endDate, cfg, autoDetectFs, points, style, stats, spec);
                return;
            end
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
                    bms.app.StopController.throwIfRequested('Stop requested before next dynamic point');
                    fprintf('Collecting %s point %s (%d/%d) ...\n', ...
                        char(string(spec.moduleKey)), char(string(points{i})), i, numel(points));
                    records(i) = bms.analyzer.DynamicAccelerationSeriesService.collectRecord( ...
                        rootDir, subfolder, points{i}, startDate, endDate, cfg, autoDetectFs, spec, true);
                end
            end

            for i = 1:numel(points)
                bms.app.StopController.throwIfRequested('Stop requested before next dynamic plot point');
                rec = records(i);
                fprintf('处理测点 %s ...\n', rec.pid);
                if ~rec.has_data
                    warning('测点 %s 无数据，跳过', rec.pid);
                    continue;
                end
                times = rec.times;
                values = rec.vals;
                if isempty(values)
                    plotRecord = bms.analyzer.DynamicAccelerationSeriesService.collectRecord( ...
                        rootDir, subfolder, rec.pid, startDate, endDate, cfg, autoDetectFs, spec, true);
                    times = plotRecord.times;
                    values = plotRecord.vals;
                    rec.source_provenance = plotRecord.source_provenance;
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
                bms.analyzer.DynamicAccelerationPlotService.plotAccelCurve( ...
                    rootDir, rec.pid, times, values, rec.mn, rec.mx, style, cfg, spec, rec.source_provenance);
                bms.analyzer.DynamicAccelerationPlotService.plotRmsCurve( ...
                    rootDir, rec.pid, times, values, rec.fs, style, cfg, spec, rec.rms_times, rec.rms_vals);
                bms.analyzer.DynamicAccelerationPlotService.plotEnvelopeCurve(rootDir, rec.pid, times, values, style, cfg, spec);
            end

            bms.analyzer.DynamicAccelerationSeriesService.plotConfiguredGroups( ...
                rootDir, subfolder, startDate, endDate, cfg, autoDetectFs, style, spec, records);
        end

        function rec = collectRecord(rootDir, subfolder, pointId, startDate, endDate, cfg, autoDetectFs, spec, keepSeries)
            cfg = bms.analyzer.DynamicAccelerationSeriesService.modulePlotConfig(cfg, spec);
            rec = bms.analyzer.DynamicSeriesService.collectRecord( ...
                rootDir, subfolder, pointId, startDate, endDate, cfg, spec.sensorType, autoDetectFs, keepSeries);
        end

        function cfgOut = modulePlotConfig(cfg, spec)
            cfgOut = cfg;
            if ~isstruct(spec) || ~isfield(spec, 'moduleKey')
                return;
            end
            moduleKey = lower(strtrim(char(string(spec.moduleKey))));
            if ~any(strcmp(moduleKey, {'acceleration', 'cable_accel'}))
                return;
            end
            cfgOut = bms.analyzer.DynamicSeriesService.configForRawPlotModule(cfg, moduleKey);
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
            cfg = bms.analyzer.DynamicAccelerationSeriesService.modulePlotConfig(cfg, spec);
            groupMode = bms.analyzer.DynamicAccelerationSeriesService.groupSamplingMode(cfg);
            if strcmp(groupMode, 'off')
                fprintf('%s group plots disabled by dynamic_group_sampling_mode.\n', ...
                    char(string(spec.moduleKey)));
                return;
            end
            groupCfg = bms.analyzer.DynamicAccelerationSeriesService.configForSamplingMode(cfg, groupMode);
            groupsCfg = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, spec.groupKey, []);
            hasExplicitGroups = isstruct(cfg) && isfield(cfg, 'groups') ...
                && isstruct(cfg.groups) && isfield(cfg.groups, spec.groupKey);
            if ~bms.analyzer.StructuralPlotConfigService.hasGroups(groupsCfg) ...
                    && strcmp(spec.moduleKey, 'cable_accel') && ~hasExplicitGroups
                groupsCfg = bms.analyzer.DynamicAccelerationSeriesService.cableForceGroups(cfg);
            end
            if ~bms.analyzer.StructuralPlotConfigService.hasGroups(groupsCfg)
                return;
            end

            groups = bms.analyzer.StructuralPlotConfigService.normalizeGroupMap(groupsCfg);
            names = fieldnames(groups);
            for i = 1:numel(names)
                bms.app.StopController.throwIfRequested('Stop requested before next dynamic group');
                groupName = names{i};
                pointIds = groups.(groupName);
                records = bms.analyzer.DynamicAccelerationSeriesService.cachedGroupRecords(cachedRecords, pointIds);
                if isempty(records)
                    records = bms.analyzer.DynamicAccelerationSeriesService.collectGroupRecords( ...
                        rootDir, subfolder, pointIds, startDate, endDate, groupCfg, autoDetectFs, spec);
                end
                if isempty(records)
                    warning('%s组 %s 无有效数据，跳过组图', spec.displayName, groupName);
                    continue;
                end
                bms.analyzer.DynamicAccelerationPlotService.plotAccelGroup( ...
                    rootDir, groupName, records, startDate, endDate, style, groupCfg, spec);
                bms.analyzer.DynamicAccelerationPlotService.plotRmsGroup( ...
                    rootDir, groupName, records, startDate, endDate, style, groupCfg, spec);
                clear records;
            end
        end

        function mode = groupSamplingMode(cfg)
            defaultMode = bms.analyzer.DynamicSeriesService.rawSamplingMode(cfg, 'capped');
            mode = bms.config.ConfigReader.get(cfg, ...
                'plot_common.dynamic_group_sampling_mode', defaultMode);
            mode = lower(strtrim(char(string(mode))));
            if ~any(strcmp(mode, {'capped', 'full', 'off'}))
                mode = defaultMode;
            end
        end

        function cfgOut = configForSamplingMode(cfg, mode)
            cfgOut = cfg;
            if ~isstruct(cfgOut)
                cfgOut = struct();
            end
            if ~isfield(cfgOut, 'plot_common') || ~isstruct(cfgOut.plot_common)
                cfgOut.plot_common = struct();
            end
            cfgOut.plot_common.dynamic_raw_sampling_mode = char(string(mode));
        end

        function rec = stripSeries(rec)
            if ~isstruct(rec)
                return;
            end
            rec.times = [];
            rec.vals = [];
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
                bms.app.StopController.throwIfRequested('Stop requested before next dynamic group point');
                pid = pointIds{i};
                % cfg already carries the explicit group sampling policy.  Do
                % not route through collectRecord here: that wrapper reapplies
                % the point-level acceleration/cable override (normally full)
                % and would silently defeat a capped group-memory policy.
                rec = bms.analyzer.DynamicSeriesService.collectRecord( ...
                    rootDir, subfolder, pid, startDate, endDate, cfg, ...
                    spec.sensorType, autoDetectFs, true);
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
