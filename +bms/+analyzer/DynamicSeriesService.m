classdef DynamicSeriesService
    %DYNAMICSERIESSERVICE Shared helpers for acceleration-like analyzers.

    methods (Static)
        function rec = initRecord()
            rec = struct('pid', '', 'times', [], 'vals', [], 'fs', NaN, ...
                'mn', NaN, 'mx', NaN, 'av', NaN, 'rms_max', NaN, ...
                'rms_time', NaT, 'rms_times', [], 'rms_vals', [], 'has_data', false, ...
                'envelope', bms.analyzer.DynamicSeriesService.emptyEnvelope(30), ...
                'source_provenance', bms.analyzer.DynamicSeriesService.initSourceProvenance(0));
        end

        function rec = collectRecord(rootDir, subfolder, pointId, startDate, endDate, cfg, sensorType, autoDetectFs, keepSeries)
            if nargin < 8 || isempty(autoDetectFs), autoDetectFs = false; end
            if nargin < 9 || isempty(keepSeries), keepSeries = false; end

            if bms.analyzer.DynamicSeriesService.shouldReduceByDay(sensorType)
                rec = bms.analyzer.DynamicSeriesService.collectRecordByDay( ...
                    rootDir, subfolder, pointId, startDate, endDate, cfg, sensorType, autoDetectFs, keepSeries);
                return;
            end

            rec = bms.analyzer.DynamicSeriesService.initRecord();
            rec.pid = pointId;
            [times, vals] = load_timeseries_range(rootDir, subfolder, pointId, startDate, endDate, cfg, sensorType);
            if isempty(vals)
                return;
            end

            rec.fs = bms.analyzer.DynamicSeriesService.sampleRate(times, autoDetectFs, 100);
            stats = bms.analyzer.StructuralSeriesService.statsTriple(vals, 3);
            rec.mn = stats(1);
            rec.mx = stats(2);
            rec.av = stats(3);
            [rec.rms_max, rec.rms_time] = bms.analyzer.DynamicSeriesService.rmsPeakForStats(times, vals, rec.fs, 10, 3);
            [rec.rms_times, rec.rms_vals] = bms.analyzer.DynamicSeriesService.rmsByTimeBins(times, vals, 10, 0.7, rec.fs);
            rec.has_data = true;

            if keepSeries
                rec.times = times;
                rec.vals = vals;
            end
        end

        function tf = shouldReduceByDay(sensorType)
            sensorType = lower(char(string(sensorType)));
            tf = any(strcmp(sensorType, {'acceleration', 'cable_accel'}));
        end

        function rec = collectRecordByDay(rootDir, subfolder, pointId, startDate, endDate, cfg, sensorType, autoDetectFs, keepSeries)
            rec = bms.analyzer.DynamicSeriesService.initRecord();
            rec.pid = pointId;

            dateList = bms.data.TimeSeriesRangeLoader.buildDateList(startDate, endDate);
            perDayMax = bms.analyzer.DynamicSeriesService.rawPlotPerDayMax(cfg, numel(dateList), 50000);

            totalCount = 0;
            totalSum = 0;
            mn = Inf;
            mx = -Inf;
            bestRms = NaN;
            bestTime = NaT;
            fsValues = [];
            keptTimes = {};
            keptVals = {};
            keptRmsTimes = {};
            keptRmsVals = {};
            keptEnvelope = {};
            envelopeEnabled = bms.analyzer.DynamicSeriesService.dynamicEnvelopeEnabled(cfg, sensorType);
            envelopeBinMinutes = bms.analyzer.DynamicSeriesService.dynamicEnvelopeBinMinutes(cfg, sensorType, 30);
            sourceProvenance = bms.analyzer.DynamicSeriesService.initSourceProvenance(numel(dateList));

            for i = 1:numel(dateList)
                bms.app.StopController.throwIfRequested('Stop requested before next dynamic data day');
                day = dateList{i};
                if i == 1 || i == numel(dateList) || mod(i, 10) == 0
                    fprintf('Dynamic %s %s loading %s (%d/%d)\n', ...
                        char(string(sensorType)), char(string(pointId)), day, i, numel(dateList));
                end
                [times, vals, dayMeta] = bms.data.TimeSeriesRangeLoader.loadCalendarDay( ...
                    rootDir, subfolder, pointId, day, cfg, sensorType);
                sourceProvenance = bms.analyzer.DynamicSeriesService.accumulateSourceProvenance( ...
                    sourceProvenance, day, dayMeta, times, vals);
                if isempty(vals)
                    continue;
                end

                fsDay = bms.analyzer.DynamicSeriesService.sampleRate(times, autoDetectFs, 100);
                if isfinite(fsDay) && fsDay > 0
                    fsValues(end+1, 1) = fsDay; %#ok<AGROW>
                end

                finite = isfinite(vals);
                if any(finite)
                    dayVals = vals(finite);
                    totalCount = totalCount + numel(dayVals);
                    totalSum = totalSum + sum(dayVals);
                    mn = min(mn, min(dayVals));
                    mx = max(mx, max(dayVals));
                end

                [rmsTimesDay, rmsSeriesDay, rmsDay, tDay] = bms.analyzer.DynamicSeriesService.rmsByTimeBins(times, vals, 10, 0.7, fsDay);
                if isfinite(rmsDay) && (~isfinite(bestRms) || rmsDay > bestRms)
                    bestRms = rmsDay;
                    bestTime = tDay;
                end
                if ~isempty(rmsSeriesDay)
                    keptRmsTimes{end+1, 1} = rmsTimesDay; %#ok<AGROW>
                    keptRmsVals{end+1, 1} = rmsSeriesDay; %#ok<AGROW>
                end

                if envelopeEnabled
                    envelopeDay = bms.analyzer.DynamicSeriesService.envelopeByTimeBins( ...
                        times, vals, envelopeBinMinutes);
                    if ~isempty(envelopeDay.times)
                        keptEnvelope{end+1, 1} = envelopeDay; %#ok<AGROW>
                    end
                end

                if keepSeries
                    [td, vd] = bms.analyzer.DynamicSeriesService.limitSeriesPoints(times, vals, perDayMax);
                    if ~isempty(vd)
                        keptTimes{end+1, 1} = td; %#ok<AGROW>
                        keptVals{end+1, 1} = vd; %#ok<AGROW>
                    end
                end
            end

            rec.source_provenance = bms.analyzer.DynamicSeriesService.finalizeSourceProvenance(sourceProvenance);
            if rec.source_provenance.incomplete_day_count > 0
                warning('DynamicSeriesService:IncompleteSourceCoverage', ...
                    '%s %s has incomplete rolling-export source coverage on %d/%d calendar days: %s', ...
                    char(string(sensorType)), char(string(pointId)), ...
                    rec.source_provenance.incomplete_day_count, ...
                    rec.source_provenance.calendar_day_count_requested, ...
                    strjoin(rec.source_provenance.incomplete_days, ', '));
            end

            if totalCount <= 0
                return;
            end

            rec.fs = median(fsValues, 'omitnan');
            if isempty(fsValues) || ~isfinite(rec.fs)
                rec.fs = 100;
            end
            rec.mn = round(mn, 3);
            rec.mx = round(mx, 3);
            rec.av = round(totalSum / totalCount, 3);
            if isfinite(bestRms)
                rec.rms_max = round(bestRms, 3);
                rec.rms_time = bestTime;
            end
            rec.has_data = true;

            if ~isempty(keptRmsVals)
                rec.rms_times = vertcat(keptRmsTimes{:});
                rec.rms_vals = vertcat(keptRmsVals{:});
                [rec.rms_times, order] = sort(rec.rms_times);
                rec.rms_vals = rec.rms_vals(order);
            end
            if ~isempty(keptEnvelope)
                rec.envelope = bms.analyzer.DynamicSeriesService.mergeEnvelopes( ...
                    keptEnvelope, envelopeBinMinutes);
            end

            if keepSeries && ~isempty(keptVals)
                rec.times = vertcat(keptTimes{:});
                rec.vals = vertcat(keptVals{:});
                if ~bms.analyzer.DynamicSeriesService.isFullRawSampling(cfg)
                    [rec.times, order] = sort(rec.times);
                    rec.vals = rec.vals(order);
                end
            end
            fprintf('Dynamic %s %s collected %d plot samples; rms=%.6g\n', ...
                char(string(sensorType)), char(string(pointId)), numel(rec.vals), rec.rms_max);
        end

        function fs = sampleRate(times, autoDetectFs, defaultFs)
            if nargin < 2 || isempty(autoDetectFs), autoDetectFs = false; end
            if nargin < 3 || isempty(defaultFs), defaultFs = 100; end
            fs = defaultFs;
            if ~bms.config.ConfigReader.boolValue(autoDetectFs, false) || numel(times) < 2
                return;
            end

            dts = seconds(diff(times));
            dts = dts(isfinite(dts) & dts > 0);
            if isempty(dts)
                return;
            end

            detected = 1 / median(dts, 'omitnan');
            if isfinite(detected) && detected > 0
                fs = detected;
            end
        end

        function fs = binnedCoverageSampleRate(times, windowMinutes, defaultFs)
            %BINNEDCOVERAGESAMPLERATE Estimate the effective rate of bursty exports.
            % Some vendor MAT exports contain short high-rate bursts separated by
            % regular gaps.  A median inter-sample interval then describes the
            % burst clock rather than the sample coverage available to a 10-minute
            % statistic.  Estimate the typical populated-bin count instead so the
            % coverage threshold remains meaningful for the derived statistic.
            if nargin < 2 || isempty(windowMinutes), windowMinutes = 10; end
            if nargin < 3 || isempty(defaultFs), defaultFs = 1; end
            fs = double(defaultFs);
            if ~isdatetime(times) || numel(times) < 2
                return;
            end

            times = times(:);
            times = times(~isnat(times));
            windowMinutes = double(windowMinutes);
            if numel(times) < 2 || ~isscalar(windowMinutes) ...
                    || ~isfinite(windowMinutes) || windowMinutes <= 0
                return;
            end

            t0 = dateshift(min(times), 'start', 'day');
            t1 = dateshift(max(times), 'start', 'day') + days(1);
            edges = (t0:minutes(windowMinutes):t1)';
            if numel(edges) < 2
                return;
            end
            idx = discretize(times, edges);
            idx = idx(~isnan(idx));
            if isempty(idx)
                return;
            end
            counts = accumarray(idx, 1, [numel(edges) - 1, 1], @sum, 0);
            counts = sort(counts(counts > 0));
            if isempty(counts)
                return;
            end

            % The upper quartile avoids a partially populated leading/trailing
            % bin lowering the expected coverage while remaining robust to an
            % isolated duplicate burst.
            typicalCount = counts(max(1, ceil(0.75 * numel(counts))));
            detected = double(typicalCount) / (windowMinutes * 60);
            if isfinite(detected) && detected > 0
                fs = detected;
            end
        end

        function maxPoints = plotMaxPoints(cfg, defaultValue)
            if nargin < 2 || isempty(defaultValue), defaultValue = 50000; end
            maxPoints = defaultValue;
            if isstruct(cfg) && isfield(cfg, 'plot_common') && isstruct(cfg.plot_common) ...
                    && isfield(cfg.plot_common, 'fig_max_points') && ~isempty(cfg.plot_common.fig_max_points)
                maxPoints = double(cfg.plot_common.fig_max_points);
            end
            if ~isfinite(maxPoints) || maxPoints <= 0
                maxPoints = defaultValue;
            end
            maxPoints = max(1000, round(maxPoints));
        end

        function maxPoints = rawPlotMaxPoints(cfg, defaultValue)
            if nargin < 2 || isempty(defaultValue), defaultValue = 50000; end
            fullSampling = bms.analyzer.DynamicSeriesService.isFullRawSampling(cfg);
            if fullSampling && strcmp( ...
                    bms.analyzer.DynamicSeriesService.rawFullRenderPolicy(cfg), 'all_vertices')
                maxPoints = Inf;
                return;
            end
            baseMax = bms.analyzer.DynamicSeriesService.plotMaxPoints(cfg, defaultValue);
            maxPoints = baseMax;
            rawDefault = baseMax;
            if fullSampling
                % Full analysis still consumes every source sample. Rendering
                % is bounded independently because a screen cannot display
                % hundreds of millions of distinct vertices and MATLAB
                % graphics otherwise duplicates those arrays in memory.
                rawDefault = max(1200000, baseMax);
            end
            rawMax = bms.config.ConfigReader.getNumeric(cfg, ...
                'plot_common.dynamic_raw_fig_max_points', rawDefault);
            if isscalar(rawMax) && isfinite(rawMax) && rawMax > 0
                maxPoints = max(baseMax, round(rawMax));
            end
            maxPoints = max(1000, round(maxPoints));
        end

        function perDayMax = rawPlotPerDayMax(cfg, dayCount, defaultValue)
            if nargin < 3 || isempty(defaultValue), defaultValue = 50000; end
            fullSampling = bms.analyzer.DynamicSeriesService.isFullRawSampling(cfg);
            if fullSampling && strcmp( ...
                    bms.analyzer.DynamicSeriesService.rawFullRenderPolicy(cfg), 'all_vertices')
                perDayMax = Inf;
                return;
            end
            dayCount = max(1, double(dayCount));
            totalMax = bms.analyzer.DynamicSeriesService.rawPlotMaxPoints(cfg, defaultValue);
            perDayMax = max(100, ceil(totalMax / dayCount));

            minPerDay = bms.config.ConfigReader.getNumeric(cfg, ...
                'plot_common.dynamic_raw_min_points_per_day', []);
            if fullSampling && (isempty(minPerDay) || ~isscalar(minPerDay) || ...
                    ~isfinite(minPerDay) || minPerDay <= 0)
                minPerDay = 12000;
            end
            if isscalar(minPerDay) && isfinite(minPerDay) && minPerDay > 0
                perDayMax = max(perDayMax, round(minPerDay));
            end
            perDayMax = max(100, round(perDayMax));
        end

        function opts = rawPlotOptions(cfg, defaultValue, moduleKey, pointId)
            if nargin < 2 || isempty(defaultValue), defaultValue = 50000; end
            if nargin < 3, moduleKey = ''; end
            if nargin < 4, pointId = ''; end
            opts = bms.plot.PlotService.runtimeOptionsFromConfig(cfg, moduleKey, pointId);
            opts.fig_max_points = bms.analyzer.DynamicSeriesService.rawPlotMaxPoints(cfg, defaultValue);
            opts.raw_render_mode = bms.analyzer.DynamicSeriesService.rawPlotRenderMode(cfg, 'line');
            opts.raw_band_bins = bms.analyzer.DynamicSeriesService.rawPlotBandBins(cfg, 24000);
            opts.raw_band_line_width = bms.analyzer.DynamicSeriesService.rawPlotBandLineWidth(cfg, 0.55);
            opts.raw_trace_points = bms.analyzer.DynamicSeriesService.rawPlotTracePoints(cfg, 120000);
            opts.raw_sampling_mode = bms.analyzer.DynamicSeriesService.rawSamplingMode(cfg, 'capped');
            opts.raw_full_render_policy = bms.analyzer.DynamicSeriesService.rawFullRenderPolicy(cfg);
            opts.reduction_algorithm = 'peak_preserving_bucket_minmax_v1';
            opts.reduction_scope = 'render_only';
            opts.extrema_preserved = true;
            opts.first_last_preserved = true;
            if strcmp(opts.raw_sampling_mode, 'full')
                opts.raw_render_mode = 'line';
            end
        end

        function cfgOut = configForRawPlotModule(cfg, moduleKey)
            %CONFIGFORRAWPLOTMODULE Apply one module's raw-plot override.
            % Module overrides materialize into the existing plot_common
            % keys so downstream services retain one parsing contract.
            % Callers decide which modules are eligible; wind and earthquake
            % services intentionally do not call this method.
            cfgOut = cfg;
            if ~isstruct(cfgOut) || isempty(cfgOut)
                cfgOut = struct();
                return;
            end
            cfgOut = cfgOut(1);
            moduleKey = lower(strtrim(char(string(moduleKey))));
            if isempty(moduleKey) || ~isfield(cfgOut, 'plot_common') || ...
                    ~isstruct(cfgOut.plot_common) || ...
                    ~isfield(cfgOut.plot_common, 'dynamic_raw_modules') || ...
                    ~isstruct(cfgOut.plot_common.dynamic_raw_modules) || ...
                    ~isfield(cfgOut.plot_common.dynamic_raw_modules, moduleKey)
                return;
            end
            override = cfgOut.plot_common.dynamic_raw_modules.(moduleKey);
            if ~isstruct(override) || isempty(override)
                return;
            end
            override = override(1);
            mappings = { ...
                'sampling_mode', 'dynamic_raw_sampling_mode'; ...
                'line_width', 'dynamic_raw_line_width'; ...
                'render_mode', 'dynamic_raw_render_mode'; ...
                'full_render_policy', 'dynamic_raw_full_render_policy'; ...
                'render_max_points', 'dynamic_raw_fig_max_points'; ...
                'min_points_per_day', 'dynamic_raw_min_points_per_day'; ...
                'gap_mode', 'gap_mode'};
            for i = 1:size(mappings, 1)
                sourceField = mappings{i, 1};
                targetField = mappings{i, 2};
                if isfield(override, sourceField) && ~isempty(override.(sourceField))
                    cfgOut.plot_common.(targetField) = override.(sourceField);
                end
            end
        end

        function mode = rawSamplingMode(cfg, defaultValue)
            if nargin < 2 || isempty(defaultValue), defaultValue = 'capped'; end
            mode = bms.config.ConfigReader.get(cfg, ...
                'plot_common.dynamic_raw_sampling_mode', defaultValue);
            mode = lower(strtrim(char(string(mode))));
            if ~any(strcmp(mode, {'capped', 'full'}))
                mode = lower(strtrim(char(string(defaultValue))));
            end
            if ~any(strcmp(mode, {'capped', 'full'}))
                mode = 'capped';
            end
        end

        function tf = isFullRawSampling(cfg)
            tf = strcmp(bms.analyzer.DynamicSeriesService.rawSamplingMode(cfg, 'capped'), 'full');
        end

        function policy = rawFullRenderPolicy(cfg, defaultValue)
            % Preserve the legacy contract unless a high-frequency module
            % explicitly opts into bounded full-source rendering.  Wind and
            % earthquake intentionally do not consume dynamic_raw_modules;
            % silently changing their historic global "full" setting would
            % alter both memory use and the saved-figure vertex contract.
            if nargin < 2 || isempty(defaultValue), defaultValue = 'all_vertices'; end
            policy = bms.config.ConfigReader.get(cfg, ...
                'plot_common.dynamic_raw_full_render_policy', defaultValue);
            policy = lower(strtrim(char(string(policy))));
            aliases = struct('bounded', 'peak_preserving', ...
                'peak_preserving_bucket', 'peak_preserving', ...
                'legacy', 'all_vertices');
            if isfield(aliases, matlab.lang.makeValidName(policy))
                policy = aliases.(matlab.lang.makeValidName(policy));
            end
            if ~any(strcmp(policy, {'peak_preserving', 'all_vertices'}))
                policy = 'peak_preserving';
            end
        end

        function lineWidth = rawPlotLineWidth(cfg, defaultValue)
            if nargin < 2 || isempty(defaultValue), defaultValue = 1.0; end
            lineWidth = bms.config.ConfigReader.getNumeric(cfg, ...
                'plot_common.dynamic_raw_line_width', defaultValue);
            if ~isscalar(lineWidth) || ~isfinite(lineWidth) || lineWidth <= 0
                lineWidth = defaultValue;
            end
            lineWidth = min(3.0, max(0.5, double(lineWidth)));
        end

        function mode = rawPlotRenderMode(cfg, defaultValue)
            if nargin < 2 || isempty(defaultValue), defaultValue = 'line'; end
            if bms.analyzer.DynamicSeriesService.isFullRawSampling(cfg)
                mode = 'line';
                return;
            end
            mode = bms.config.ConfigReader.get(cfg, ...
                'plot_common.dynamic_raw_render_mode', defaultValue);
            mode = lower(strtrim(char(string(mode))));
            if isempty(mode)
                mode = defaultValue;
            end
        end

        function nBins = rawPlotBandBins(cfg, defaultValue)
            if nargin < 2 || isempty(defaultValue), defaultValue = 24000; end
            nBins = bms.config.ConfigReader.getNumeric(cfg, ...
                'plot_common.dynamic_raw_band_bins', defaultValue);
            if ~isscalar(nBins) || ~isfinite(nBins) || nBins <= 0
                nBins = defaultValue;
            end
            nBins = min(100000, max(1000, round(double(nBins))));
        end

        function lineWidth = rawPlotBandLineWidth(cfg, defaultValue)
            if nargin < 2 || isempty(defaultValue), defaultValue = 0.55; end
            lineWidth = bms.config.ConfigReader.getNumeric(cfg, ...
                'plot_common.dynamic_raw_band_line_width', defaultValue);
            if ~isscalar(lineWidth) || ~isfinite(lineWidth) || lineWidth <= 0
                lineWidth = defaultValue;
            end
            lineWidth = min(2.0, max(0.1, double(lineWidth)));
        end

        function maxPoints = rawPlotTracePoints(cfg, defaultValue)
            if nargin < 2 || isempty(defaultValue), defaultValue = 120000; end
            maxPoints = bms.config.ConfigReader.getNumeric(cfg, ...
                'plot_common.dynamic_raw_trace_points', defaultValue);
            if ~isscalar(maxPoints) || ~isfinite(maxPoints) || maxPoints < 0
                maxPoints = defaultValue;
            end
            maxPoints = min(1000000, max(0, round(double(maxPoints))));
        end

        function h = plotRawSeries(ax, times, vals, color, opts, lineWidth)
            if nargin < 1 || isempty(ax), ax = gca; end
            if nargin < 4, color = []; end
            if nargin < 5 || isempty(opts), opts = struct(); end
            if nargin < 6 || isempty(lineWidth), lineWidth = 1.0; end
            if isnumeric(color) && ~isempty(color)
                color = double(color(:).');
                if numel(color) ~= 3
                    color = [];
                end
            end

            mode = 'line';
            if isstruct(opts) && isfield(opts, 'raw_render_mode') && ~isempty(opts.raw_render_mode)
                mode = lower(strtrim(char(string(opts.raw_render_mode))));
            end

            if strcmp(mode, 'dense_band') || strcmp(mode, 'band')
                [xBand, yLow, yHigh] = bms.analyzer.DynamicSeriesService.denseBandEnvelope( ...
                    times, vals, bms.analyzer.DynamicSeriesService.opt(opts, 'raw_band_bins', 24000));
                if ~isempty(yLow)
                    wasHold = ishold(ax);
                    hold(ax, 'on');
                    cleaner = onCleanup(@() bms.analyzer.DynamicSeriesService.restoreHold(ax, wasHold)); %#ok<NASGU>
                    bandWidth = bms.analyzer.DynamicSeriesService.opt(opts, 'raw_band_line_width', 0.55);
                    bandColor = color;
                    if isempty(bandColor)
                        bandColor = [0 0.4470 0.7410];
                    end
                    fill(ax, [xBand; flipud(xBand)], [yLow; flipud(yHigh)], bandColor, ...
                        'FaceAlpha', 0.72, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                    plot(ax, xBand, yLow, 'LineWidth', max(0.1, bandWidth * 0.35), ...
                        'Color', bandColor, 'HandleVisibility', 'off');
                    plot(ax, xBand, yHigh, 'LineWidth', max(0.1, bandWidth * 0.35), ...
                        'Color', bandColor, 'HandleVisibility', 'off');

                    if isdatetime(xBand)
                        h = plot(ax, NaT, NaN, 'LineWidth', max(0.5, lineWidth), 'Color', bandColor);
                    else
                        h = plot(ax, NaN, NaN, 'LineWidth', max(0.5, lineWidth), 'Color', bandColor);
                    end

                    tracePoints = bms.analyzer.DynamicSeriesService.opt(opts, 'raw_trace_points', 120000);
                    if tracePoints > 0
                        traceOpts = opts;
                        traceOpts.fig_max_points = tracePoints;
                        [xTrace, yTrace] = prepare_plot_series(times, vals, traceOpts);
                        if ~isempty(yTrace)
                            traceWidth = max(0.15, min(lineWidth, lineWidth * 0.45));
                            if isempty(color)
                                plot(ax, xTrace, yTrace, 'LineWidth', traceWidth, 'HandleVisibility', 'off');
                            else
                                plot(ax, xTrace, yTrace, 'LineWidth', traceWidth, ...
                                    'Color', color, 'HandleVisibility', 'off');
                            end
                        end
                    end
                    return;
                end
            end

            [xPlot, yPlot] = prepare_plot_series(times, vals, opts);
            if isempty(color)
                h = plot(ax, xPlot, yPlot, 'LineWidth', lineWidth);
            else
                h = plot(ax, xPlot, yPlot, 'LineWidth', lineWidth, 'Color', color);
            end
            bms.analyzer.DynamicSeriesService.attachPlotProvenance( ...
                h, times, vals, yPlot, mode, opts);
        end

        function attachPlotProvenance(h, times, vals, yPlot, renderMode, opts)
            if isempty(h) || ~isgraphics(h)
                return;
            end
            inputCount = min(numel(times), numel(vals));
            if inputCount <= 0
                finiteCount = 0;
            else
                values = vals(1:inputCount);
                if isdatetime(times)
                    validTime = ~isnat(times(1:inputCount));
                else
                    validTime = isfinite(times(1:inputCount));
                end
                finiteCount = nnz(validTime(:) & isfinite(values(:)));
            end
            renderInputCount = inputCount;
            renderFiniteCount = finiteCount;
            source = struct();
            if isstruct(opts) && isfield(opts, 'source_provenance') ...
                    && isstruct(opts.source_provenance)
                source = opts.source_provenance;
                sourceInput = bms.analyzer.DynamicSeriesService.provenanceCount( ...
                    source, 'source_sample_count', inputCount);
                sourceFinite = bms.analyzer.DynamicSeriesService.provenanceCount( ...
                    source, 'finite_source_sample_count', finiteCount);
                if sourceInput >= sourceFinite && sourceFinite >= renderFiniteCount
                    inputCount = sourceInput;
                    finiteCount = sourceFinite;
                end
            end
            plottedFiniteCount = nnz(isfinite(yPlot));
            samplingMode = bms.analyzer.DynamicSeriesService.opt( ...
                opts, 'raw_sampling_mode', 'capped');
            reductionApplied = plottedFiniteCount < finiteCount;
            provenance = struct( ...
                'schema_version', 2, ...
                'sampling_mode', char(string(samplingMode)), ...
                'render_mode', char(string(renderMode)), ...
                'input_count', double(inputCount), ...
                'finite_count', double(finiteCount), ...
                'plotted_finite_count', double(plottedFiniteCount), ...
                'render_input_count', double(renderInputCount), ...
                'render_finite_input_count', double(renderFiniteCount), ...
                'render_vertex_count', double(plottedFiniteCount), ...
                'reduction_applied', reductionApplied, ...
                'reduction_scope', char(string(bms.analyzer.DynamicSeriesService.opt( ...
                    opts, 'reduction_scope', 'render_only'))), ...
                'reduction_algorithm', char(string(bms.analyzer.DynamicSeriesService.opt( ...
                    opts, 'reduction_algorithm', 'peak_preserving_bucket_minmax_v1'))), ...
                'extrema_preserved', logical(bms.analyzer.DynamicSeriesService.opt( ...
                    opts, 'extrema_preserved', true)), ...
                'first_last_preserved', logical(bms.analyzer.DynamicSeriesService.opt( ...
                    opts, 'first_last_preserved', true)));
            if ~isempty(fieldnames(source))
                provenance.source = source;
            end
            if isstruct(opts) && isfield(opts, 'series_id') && ~isempty(opts.series_id)
                provenance.point_id = char(string(opts.series_id));
            end
            if isstruct(opts) && isfield(opts, 'plot_scope') && ~isempty(opts.plot_scope)
                provenance.plot_scope = char(string(opts.plot_scope));
            end
            userData = get(h, 'UserData');
            if ~isstruct(userData)
                userData = struct();
            end
            userData.plot_provenance = provenance;
            set(h, 'UserData', userData);
        end

        function [xBand, yBand] = denseBandSeries(times, vals, maxBins)
            xBand = [];
            yBand = [];
            [xEnv, lo, hi] = bms.analyzer.DynamicSeriesService.denseBandEnvelope(times, vals, maxBins);
            if isempty(lo)
                return;
            end

            xBand = repelem(xEnv, 2);
            yBand = reshape([lo.'; hi.'], [], 1);
        end

        function [xEnv, lo, hi] = denseBandEnvelope(times, vals, maxBins)
            xEnv = [];
            lo = [];
            hi = [];
            if isempty(vals) || numel(times) ~= numel(vals)
                return;
            end
            if nargin < 3 || isempty(maxBins) || ~isfinite(maxBins) || maxBins <= 0
                maxBins = 24000;
            end

            times = times(:);
            vals = vals(:);
            if isdatetime(times)
                validTime = ~isnat(times);
            else
                validTime = isfinite(times);
            end
            finite = validTime & isfinite(vals);
            if ~any(finite)
                return;
            end

            keepIdx = find(finite);
            n = numel(keepIdx);
            maxBins = max(1, min(round(maxBins), n));
            edges = unique(round(linspace(1, n + 1, maxBins + 1)), 'stable');
            if numel(edges) < 2
                return;
            end
            if edges(1) ~= 1
                edges = [1 edges(:).']; %#ok<AGROW>
            end
            if edges(end) ~= n + 1
                edges(end + 1) = n + 1; %#ok<AGROW>
            end

            centers = keepIdx(max(1, min(n, round((edges(1:end-1) + edges(2:end) - 1) / 2))));
            lo = NaN(numel(centers), 1);
            hi = NaN(numel(centers), 1);
            for k = 1:numel(centers)
                s = max(1, min(n, edges(k)));
                e = max(1, min(n, edges(k + 1) - 1));
                if s > e
                    continue;
                end
                v = vals(keepIdx(s:e));
                lo(k) = min(v, [], 'omitnan');
                hi(k) = max(v, [], 'omitnan');
            end

            ok = isfinite(lo) & isfinite(hi);
            centers = centers(ok);
            lo = lo(ok);
            hi = hi(ok);
            if isempty(lo)
                return;
            end

            xEnv = times(centers(:));
            lo = lo(:);
            hi = hi(:);
        end

        function [timesOut, valsOut] = limitSeriesPoints(times, vals, maxPoints)
            timesOut = [];
            valsOut = [];
            if isempty(vals) || numel(times) ~= numel(vals)
                return;
            end
            times = times(:);
            vals = vals(:);
            n = numel(vals);
            if nargin < 3 || isempty(maxPoints) || ~isfinite(maxPoints) || maxPoints <= 0 || n <= maxPoints
                timesOut = times;
                valsOut = vals;
                return;
            end
            idx = bms.analyzer.DynamicSeriesService.pickPlotIndices(vals, maxPoints);
            timesOut = times(idx);
            valsOut = vals(idx);
        end

        function idx = pickPlotIndices(vals, maxPoints)
            vals = vals(:);
            n = numel(vals);
            if n <= maxPoints
                idx = 1:n;
                return;
            end

            bucketCount = max(1, floor(maxPoints / 4));
            edges = unique(round(linspace(1, n + 1, bucketCount + 1)), 'stable');
            if edges(1) ~= 1
                edges = [1 edges(:).']; %#ok<AGROW>
            end
            if edges(end) ~= n + 1
                edges(end + 1) = n + 1; %#ok<AGROW>
            end

            keep = false(n, 1);
            keep(1) = true;
            keep(n) = true;
            for k = 1:(numel(edges) - 1)
                s = max(1, min(n, edges(k)));
                e = max(1, min(n, edges(k + 1) - 1));
                if s > e
                    continue;
                end
                bucketIdx = (s:e).';
                keep(s) = true;
                keep(e) = true;

                finiteIdx = bucketIdx(isfinite(vals(bucketIdx)));
                if isempty(finiteIdx)
                    continue;
                end
                finiteVals = vals(finiteIdx);
                [~, minRel] = min(finiteVals);
                [~, maxRel] = max(finiteVals);
                [~, absRel] = max(abs(finiteVals));
                keep(finiteIdx([minRel maxRel absRel])) = true;
            end

            idx = find(keep);
            if numel(idx) > maxPoints
                idx = bms.analyzer.DynamicSeriesService.trimPlotIndices( ...
                    idx, bms.analyzer.DynamicSeriesService.keySampleIndices(vals), n, maxPoints);
            end
            idx = sort(idx(:)).';
        end

        function idx = trimPlotIndices(idx, protected, n, maxPoints)
            idx = unique(idx(:), 'stable');
            protected = unique([1; n; protected(:)], 'stable');
            if numel(protected) >= maxPoints
                sel = round(linspace(1, numel(protected), maxPoints));
                idx = protected(sel);
                return;
            end

            rest = setdiff(idx, protected, 'stable');
            room = maxPoints - numel(protected);
            if isempty(rest) || room <= 0
                idx = protected;
                return;
            end
            sel = unique(round(linspace(1, numel(rest), min(room, numel(rest)))), 'stable');
            idx = [protected; rest(sel)];
        end

        function idx = keySampleIndices(vals)
            idx = [];
            if isempty(vals)
                return;
            end
            vals = vals(:);
            finite = isfinite(vals);
            if ~any(finite)
                return;
            end
            finiteIdx = find(finite);
            finiteVals = vals(finite);
            [~, minRel] = min(finiteVals);
            [~, maxRel] = max(finiteVals);
            [~, absRel] = max(abs(finiteVals));
            idx = unique([finiteIdx(minRel), finiteIdx(maxRel), finiteIdx(absRel)], 'stable');
        end

        function winLen = rmsWindowLength(fs, windowMinutes)
            if nargin < 2 || isempty(windowMinutes), windowMinutes = 10; end
            if isempty(fs) || ~isfinite(fs) || fs <= 0
                fs = 100;
            end
            winLen = max(1, round(windowMinutes * 60 * fs));
        end

        function [rmsMax, tMax] = rmsPeakForStats(times, vals, fs, windowMinutes, decimals)
            if nargin < 4 || isempty(windowMinutes), windowMinutes = 10; end
            if nargin < 5 || isempty(decimals), decimals = 3; end

            rmsMax = NaN;
            tMax = NaT;
            if isempty(vals) || numel(times) ~= numel(vals)
                return;
            end

            [~, ~, rawMax, rawT] = bms.analyzer.DynamicSeriesService.rmsByTimeBins( ...
                times, vals, windowMinutes, 0.7, fs);
            if ~isfinite(rawMax)
                return;
            end

            rmsMax = round(rawMax, decimals);
            tMax = rawT;
        end

        function [rmsSeries, rmsMax, tMax] = rmsSeries(times, vals, fs, windowMinutes, minCoverage)
            if nargin < 4 || isempty(windowMinutes), windowMinutes = 10; end
            if nargin < 5 || isempty(minCoverage), minCoverage = 0.7; end

            rmsSeries = [];
            rmsMax = NaN;
            tMax = NaT;
            if isempty(vals) || numel(times) ~= numel(vals)
                return;
            end

            winLen = bms.analyzer.DynamicSeriesService.rmsWindowLength(fs, windowMinutes);
            validCnt = movsum(isfinite(vals), winLen, 'Endpoints', 'shrink');
            rmsSeries = sqrt(movmean(vals.^2, winLen, 'omitnan', 'Endpoints', 'shrink'));
            minNeed = max(1, round(minCoverage * winLen));
            rmsSeries(validCnt < minNeed) = NaN;

            [rmsMax, idxMax] = max(rmsSeries, [], 'omitnan');
            if isempty(idxMax) || ~isfinite(rmsMax)
                rmsMax = NaN;
                return;
            end
            tMax = times(idxMax);
        end

        function [meanSeries, meanMax, tMax] = movingMeanSeries(times, vals, fs, windowMinutes, minCoverage)
            if nargin < 4 || isempty(windowMinutes), windowMinutes = 10; end
            if nargin < 5 || isempty(minCoverage), minCoverage = 0.7; end

            meanSeries = [];
            meanMax = NaN;
            tMax = NaT;
            if isempty(vals) || numel(times) ~= numel(vals)
                return;
            end

            winLen = bms.analyzer.DynamicSeriesService.rmsWindowLength(fs, windowMinutes);
            validCnt = movsum(isfinite(vals), winLen, 'Endpoints', 'shrink');
            meanSeries = movmean(vals, winLen, 'omitnan', 'Endpoints', 'shrink');
            minNeed = max(1, round(minCoverage * winLen));
            meanSeries(validCnt < minNeed) = NaN;

            [meanMax, idxMax] = max(meanSeries, [], 'omitnan');
            if isempty(idxMax) || ~isfinite(meanMax)
                meanMax = NaN;
                return;
            end
            tMax = times(idxMax);
        end

        function [binTimes, rmsSeries, rmsMax, tMax] = rmsByTimeBins(times, vals, windowMinutes, minCoverage, fs)
            if nargin < 3 || isempty(windowMinutes), windowMinutes = 10; end
            if nargin < 4 || isempty(minCoverage), minCoverage = 0.7; end
            if nargin < 5, fs = []; end

            [binTimes, rmsSeries, rmsMax, tMax] = ...
                bms.analyzer.DynamicSeriesService.aggregateByTimeBins( ...
                    times, vals, windowMinutes, minCoverage, 'rms', fs, false);
        end

        function [binTimes, meanSeries, meanMax, tMax] = movingMeanByTimeBins(times, vals, windowMinutes, minCoverage, fs, requireTemporalCoverage)
            if nargin < 3 || isempty(windowMinutes), windowMinutes = 10; end
            if nargin < 4 || isempty(minCoverage), minCoverage = 0.7; end
            if nargin < 5, fs = []; end
            if nargin < 6 || isempty(requireTemporalCoverage), requireTemporalCoverage = false; end

            [binTimes, meanSeries, meanMax, tMax] = ...
                bms.analyzer.DynamicSeriesService.aggregateByTimeBins( ...
                    times, vals, windowMinutes, minCoverage, 'mean', fs, requireTemporalCoverage);
        end

        function [binTimes, aggSeries, aggMax, tMax] = aggregateByTimeBins(times, vals, windowMinutes, minCoverage, mode, fs, requireTemporalCoverage)
            if nargin < 3 || isempty(windowMinutes), windowMinutes = 10; end
            if nargin < 4 || isempty(minCoverage), minCoverage = 0.7; end
            if nargin < 5 || isempty(mode), mode = 'mean'; end
            if nargin < 6, fs = []; end
            if nargin < 7 || isempty(requireTemporalCoverage), requireTemporalCoverage = false; end

            binTimes = datetime.empty(0, 1);
            aggSeries = [];
            aggMax = NaN;
            tMax = NaT;
            if isempty(vals) || numel(times) ~= numel(vals) || ~isdatetime(times)
                return;
            end

            times = times(:);
            vals = vals(:);
            validTime = ~isnat(times);
            if ~any(validTime)
                return;
            end

            windowMinutes = double(windowMinutes);
            if ~isfinite(windowMinutes) || windowMinutes <= 0
                windowMinutes = 10;
            end
            minCoverage = double(minCoverage);
            if ~isfinite(minCoverage) || minCoverage <= 0 || minCoverage > 1
                minCoverage = 0.7;
            end

            validTimes = times(validTime);
            t0 = dateshift(min(validTimes), 'start', 'day');
            t1 = dateshift(max(validTimes), 'start', 'day') + days(1);
            if t0 >= t1
                t1 = t0 + days(1);
            end

            edges = (t0:minutes(windowMinutes):t1)';
            if numel(edges) < 2
                return;
            end
            binTimes = edges(1:end-1) + minutes(windowMinutes / 2);
            nBins = numel(binTimes);
            aggSeries = NaN(nBins, 1);

            idxAll = discretize(times(validTime), edges);
            valsAll = vals(validTime);
            finite = ~isnan(idxAll) & isfinite(valsAll);
            if ~any(finite)
                return;
            end

            idx = idxAll(finite);
            binVals = valsAll(finite);
            count = accumarray(idx, 1, [nBins 1], @sum, 0);
            sumVals = accumarray(idx, binVals, [nBins 1], @sum, 0);
            sumSq = accumarray(idx, binVals .^ 2, [nBins 1], @sum, 0);

            mode = lower(char(string(mode)));
            switch mode
                case 'rms'
                    positiveCount = count > 0;
                    aggSeries(positiveCount) = sqrt(sumSq(positiveCount) ./ count(positiveCount));
                case 'mean'
                    positiveCount = count > 0;
                    aggSeries(positiveCount) = sumVals(positiveCount) ./ count(positiveCount);
                otherwise
                    error('DynamicSeriesService:UnsupportedAggregateMode', ...
                        'Unsupported aggregate mode: %s', mode);
            end

            if isempty(fs) || ~isfinite(fs) || fs <= 0
                fs = bms.analyzer.DynamicSeriesService.sampleRate(validTimes, true, 1);
            end
            expectedPerBin = max(1, round(windowMinutes * 60 * fs));
            minNeed = max(1, round(minCoverage * expectedPerBin));
            insufficientCoverage = count < minNeed;
            if logical(requireTemporalCoverage)
                % Wind vendor exports may contain a high-rate burst representing
                % only seconds of a 10-minute interval.  Count coverage alone
                % would accept that burst, so wind mean calculations additionally
                % require observations across the configured fraction of minute-
                % scale time slices.  RMS callers deliberately retain their
                % established count-based statistical contract.
                windowSeconds = windowMinutes * 60;
                sliceCount = max(1, ceil(windowMinutes));
                finiteTimes = times(validTime);
                finiteTimes = finiteTimes(finite);
                relativeSeconds = seconds(finiteTimes - edges(idx));
                sliceIndex = floor(relativeSeconds / windowSeconds * sliceCount) + 1;
                sliceIndex = max(1, min(sliceCount, sliceIndex));
                occupiedPairs = unique([idx(:), sliceIndex(:)], 'rows');
                occupiedSlices = accumarray(occupiedPairs(:, 1), 1, [nBins 1], @sum, 0);
                minOccupiedSlices = max(1, ceil(minCoverage * sliceCount));
                insufficientCoverage = insufficientCoverage | occupiedSlices < minOccupiedSlices;
            end
            aggSeries(insufficientCoverage) = NaN;

            [aggMax, idxMax] = max(aggSeries, [], 'omitnan');
            if isempty(idxMax) || ~isfinite(aggMax)
                aggMax = NaN;
                return;
            end
            tMax = binTimes(idxMax);
        end

        function T = dynamicStatsTable(rows)
            T = cell2table(rows, 'VariableNames', ...
                {'PointID', 'Min', 'Max', 'Mean', 'RMS10minMax', 'RMSStartTime'});
        end

        function T = windStatsTable(rows)
            T = cell2table(rows, 'VariableNames', ...
                {'PointID', 'MinSpeed', 'MaxSpeed', 'MeanSpeed', 'Mean10minMax', 'Mean10minTime'});
        end

        function value = opt(opts, fieldName, defaultValue)
            value = defaultValue;
            if isstruct(opts) && isfield(opts, fieldName) && ~isempty(opts.(fieldName))
                value = opts.(fieldName);
            end
        end

        function value = provenanceCount(source, fieldName, defaultValue)
            value = double(defaultValue);
            if ~isstruct(source) || ~isfield(source, fieldName)
                return;
            end
            candidate = source.(fieldName);
            if isnumeric(candidate) && isscalar(candidate) && ...
                    isfinite(candidate) && candidate >= 0
                value = double(candidate);
            end
        end

        function tf = dynamicEnvelopeEnabled(cfg, sensorType)
            sensorType = lower(strtrim(char(string(sensorType))));
            tf = strcmp(sensorType, 'cable_accel');
            if ~tf
                return;
            end
            try
                style = bms.config.ConfigReader.getPlotStyle(cfg, 'cable_accel', struct());
                if isstruct(style) && isfield(style, 'envelope_enabled') ...
                        && ~isempty(style.envelope_enabled)
                    tf = bms.config.ConfigReader.boolValue(style.envelope_enabled, tf);
                end
            catch
                % Keep the pipeline default when an older configuration does
                % not expose the optional envelope style.
            end
        end

        function value = dynamicEnvelopeBinMinutes(cfg, sensorType, defaultValue)
            if nargin < 3 || isempty(defaultValue), defaultValue = 30; end
            value = double(defaultValue);
            sensorType = lower(strtrim(char(string(sensorType))));
            if ~strcmp(sensorType, 'cable_accel')
                return;
            end
            try
                style = bms.config.ConfigReader.getPlotStyle(cfg, 'cable_accel', struct());
                if isstruct(style) && isfield(style, 'envelope_bin_minutes') ...
                        && isnumeric(style.envelope_bin_minutes) ...
                        && isscalar(style.envelope_bin_minutes) ...
                        && isfinite(style.envelope_bin_minutes) ...
                        && style.envelope_bin_minutes > 0
                    value = double(style.envelope_bin_minutes);
                end
            catch
                % Preserve the default for legacy style layouts.
            end
        end

        function envelope = emptyEnvelope(binMinutes)
            if nargin < 1 || isempty(binMinutes), binMinutes = 30; end
            envelope = struct( ...
                'bin_minutes', double(binMinutes), ...
                'times', datetime.empty(0, 1), ...
                'p01', zeros(0, 1), ...
                'p05', zeros(0, 1), ...
                'p50', zeros(0, 1), ...
                'p95', zeros(0, 1), ...
                'p99', zeros(0, 1), ...
                'min', zeros(0, 1), ...
                'max', zeros(0, 1), ...
                'rms', zeros(0, 1));
        end

        function envelope = envelopeByTimeBins(times, vals, binMinutes)
            if nargin < 3 || isempty(binMinutes), binMinutes = 30; end
            envelope = bms.analyzer.DynamicSeriesService.emptyEnvelope(binMinutes);
            if isempty(vals) || numel(times) ~= numel(vals) || ~isdatetime(times)
                return;
            end
            times = times(:);
            vals = vals(:);
            valid = ~isnat(times) & isfinite(vals);
            if ~any(valid)
                return;
            end
            validTimes = times(valid);
            validVals = vals(valid);
            xmin = dateshift(min(validTimes), 'start', 'day');
            xmax = dateshift(max(validTimes), 'start', 'day') + days(1);
            edges = (xmin:minutes(binMinutes):xmax)';
            if numel(edges) < 2
                return;
            end
            idx = discretize(validTimes, edges);
            good = ~isnan(idx);
            if ~any(good)
                return;
            end
            idx = idx(good);
            validVals = validVals(good);
            nBins = numel(edges) - 1;
            envelope.times = edges(1:end-1) + minutes(binMinutes / 2);
            envelope.p01 = accumarray(idx, validVals, [nBins 1], @(x) prctile(x, 1), NaN);
            envelope.p05 = accumarray(idx, validVals, [nBins 1], @(x) prctile(x, 5), NaN);
            envelope.p50 = accumarray(idx, validVals, [nBins 1], @(x) median(x, 'omitnan'), NaN);
            envelope.p95 = accumarray(idx, validVals, [nBins 1], @(x) prctile(x, 95), NaN);
            envelope.p99 = accumarray(idx, validVals, [nBins 1], @(x) prctile(x, 99), NaN);
            envelope.min = accumarray(idx, validVals, [nBins 1], @(x) min(x, [], 'omitnan'), NaN);
            envelope.max = accumarray(idx, validVals, [nBins 1], @(x) max(x, [], 'omitnan'), NaN);
            envelope.rms = accumarray(idx, validVals, [nBins 1], ...
                @(x) sqrt(mean(x.^2, 'omitnan')), NaN);
        end

        function merged = mergeEnvelopes(envelopes, binMinutes)
            if nargin < 2 || isempty(binMinutes), binMinutes = 30; end
            merged = bms.analyzer.DynamicSeriesService.emptyEnvelope(binMinutes);
            if isempty(envelopes)
                return;
            end
            fields = {'times', 'p01', 'p05', 'p50', 'p95', 'p99', 'min', 'max', 'rms'};
            for i = 1:numel(fields)
                name = fields{i};
                chunks = cellfun(@(item) item.(name), envelopes, 'UniformOutput', false);
                merged.(name) = vertcat(chunks{:});
            end
            if isempty(merged.times)
                return;
            end
            [merged.times, order] = sort(merged.times);
            for i = 2:numel(fields)
                name = fields{i};
                merged.(name) = merged.(name)(order);
            end

            % Each daily envelope already contains NaN bins for gaps inside
            % that day.  Reindex the merged result onto one continuous bin
            % grid as well, so a completely missing day cannot be rendered as
            % a straight connection between the surrounding dates.
            validTime = ~isnat(merged.times);
            if ~any(validTime)
                return;
            end
            merged.times = merged.times(validTime);
            for i = 2:numel(fields)
                name = fields{i};
                merged.(name) = merged.(name)(validTime);
            end
            fullTimes = (merged.times(1):minutes(binMinutes):merged.times(end))';
            if numel(fullTimes) <= numel(merged.times)
                return;
            end
            [present, locations] = ismember(merged.times, fullTimes);
            if ~all(present)
                error('bms:analyzer:EnvelopeGridMismatch', ...
                    'Envelope bins do not align to the configured %.6g minute grid.', ...
                    double(binMinutes));
            end
            for i = 2:numel(fields)
                name = fields{i};
                expanded = NaN(numel(fullTimes), 1);
                expanded(locations) = merged.(name);
                merged.(name) = expanded;
            end
            merged.times = fullTimes;
        end

        function provenance = initSourceProvenance(dayCount)
            if nargin < 1 || isempty(dayCount)
                dayCount = 0;
            end
            provenance = struct( ...
                'schema_version', 1, ...
                'calendar_day_count_requested', double(dayCount), ...
                'calendar_day_count_with_data', 0, ...
                'complete_day_count', 0, ...
                'incomplete_day_count', 0, ...
                'incomplete_days', {{}}, ...
                'missing_required_sources', {{}}, ...
                'ambiguous_sources', {{}}, ...
                'source_files', {{}}, ...
                'source_file_count', 0, ...
                'source_sample_count', 0, ...
                'finite_source_sample_count', 0, ...
                'duplicate_timestamp_count', 0, ...
                'conflicting_timestamp_count', 0, ...
                'completeness_scope', '', ...
                'internal_gap_coverage_assessed', false, ...
                'coverage_start', '', ...
                'coverage_end', '');
        end

        function provenance = accumulateSourceProvenance(provenance, day, meta, ~, vals)
            if ~isempty(vals)
                provenance.calendar_day_count_with_data = provenance.calendar_day_count_with_data + 1;
            end
            provenance.source_sample_count = provenance.source_sample_count + numel(vals);
            provenance.finite_source_sample_count = provenance.finite_source_sample_count + nnz(isfinite(vals));
            provenance.duplicate_timestamp_count = provenance.duplicate_timestamp_count + ...
                bms.analyzer.DynamicSeriesService.metaNumeric(meta, 'duplicate_timestamp_count', 0);
            provenance.conflicting_timestamp_count = provenance.conflicting_timestamp_count + ...
                bms.analyzer.DynamicSeriesService.metaNumeric(meta, 'conflicting_timestamp_count', 0);

            complete = isstruct(meta) && isfield(meta, 'calendar_day_source_complete') ...
                && bms.config.ConfigReader.boolValue(meta.calendar_day_source_complete, false);
            if complete
                provenance.complete_day_count = provenance.complete_day_count + 1;
            else
                provenance.incomplete_day_count = provenance.incomplete_day_count + 1;
                provenance.incomplete_days = bms.analyzer.DynamicSeriesService.appendUniqueText( ...
                    provenance.incomplete_days, day);
            end

            provenance.missing_required_sources = bms.analyzer.DynamicSeriesService.appendTextList( ...
                provenance.missing_required_sources, meta, 'calendar_day_missing_required_sources');
            provenance.ambiguous_sources = bms.analyzer.DynamicSeriesService.appendTextList( ...
                provenance.ambiguous_sources, meta, 'calendar_day_ambiguous_sources');
            provenance.source_files = bms.analyzer.DynamicSeriesService.appendTextList( ...
                provenance.source_files, meta, 'files');
            dayScope = bms.analyzer.DynamicSeriesService.metaText( ...
                meta, 'calendar_day_completeness_scope');
            if isempty(provenance.completeness_scope)
                provenance.completeness_scope = dayScope;
            elseif ~isempty(dayScope) && ~strcmp(provenance.completeness_scope, dayScope)
                provenance.completeness_scope = 'mixed';
            end
            provenance.coverage_start = bms.analyzer.DynamicSeriesService.earlierText( ...
                provenance.coverage_start, bms.analyzer.DynamicSeriesService.metaText(meta, 'calendar_day_coverage_start'));
            provenance.coverage_end = bms.analyzer.DynamicSeriesService.laterText( ...
                provenance.coverage_end, bms.analyzer.DynamicSeriesService.metaText(meta, 'calendar_day_coverage_end'));
        end

        function provenance = finalizeSourceProvenance(provenance)
            provenance.incomplete_days = unique(provenance.incomplete_days, 'stable');
            provenance.missing_required_sources = unique(provenance.missing_required_sources, 'stable');
            provenance.ambiguous_sources = unique(provenance.ambiguous_sources, 'stable');
            provenance.source_files = unique(provenance.source_files, 'stable');
            provenance.source_file_count = numel(provenance.source_files);
            if isempty(provenance.completeness_scope)
                provenance.completeness_scope = 'unknown';
            end
            provenance.incomplete_day_count = numel(provenance.incomplete_days);
            provenance.complete_day_count = max(0, ...
                provenance.calendar_day_count_requested - provenance.incomplete_day_count);
        end

        function value = metaNumeric(meta, fieldName, defaultValue)
            value = defaultValue;
            if isstruct(meta) && isfield(meta, fieldName) && ~isempty(meta.(fieldName)) ...
                    && isnumeric(meta.(fieldName)) && isscalar(meta.(fieldName))
                value = double(meta.(fieldName));
            end
        end

        function value = metaText(meta, fieldName)
            value = '';
            if isstruct(meta) && isfield(meta, fieldName) && ~isempty(meta.(fieldName))
                value = char(string(meta.(fieldName)));
            end
        end

        function items = appendTextList(items, meta, fieldName)
            if ~isstruct(meta) || ~isfield(meta, fieldName) || isempty(meta.(fieldName))
                return;
            end
            values = cellstr(string(meta.(fieldName)));
            for i = 1:numel(values)
                items = bms.analyzer.DynamicSeriesService.appendUniqueText(items, values{i});
            end
        end

        function items = appendUniqueText(items, value)
            textValue = char(string(value));
            if isempty(textValue) || any(strcmp(items, textValue))
                return;
            end
            items{end+1, 1} = textValue;
        end

        function value = earlierText(current, candidate)
            value = current;
            if isempty(candidate)
                return;
            end
            ordered = sort({current, candidate});
            if isempty(current) || strcmp(ordered{1}, candidate)
                value = candidate;
            end
        end

        function value = laterText(current, candidate)
            value = current;
            if isempty(candidate)
                return;
            end
            ordered = sort({current, candidate});
            if isempty(current) || strcmp(ordered{2}, candidate)
                value = candidate;
            end
        end

        function restoreHold(ax, wasHold)
            if isvalid(ax) && ~wasHold
                hold(ax, 'off');
            end
        end
    end
end
