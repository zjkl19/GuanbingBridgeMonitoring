classdef DynamicSeriesService
    %DYNAMICSERIESSERVICE Shared helpers for acceleration-like analyzers.

    methods (Static)
        function rec = initRecord()
            rec = struct('pid', '', 'times', [], 'vals', [], 'fs', NaN, ...
                'mn', NaN, 'mx', NaN, 'av', NaN, 'rms_max', NaN, ...
                'rms_time', NaT, 'rms_times', [], 'rms_vals', [], 'has_data', false);
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

            for i = 1:numel(dateList)
                bms.app.StopController.throwIfRequested('Stop requested before next dynamic data day');
                day = dateList{i};
                if i == 1 || i == numel(dateList) || mod(i, 10) == 0
                    fprintf('Dynamic %s %s loading %s (%d/%d)\n', ...
                        char(string(sensorType)), char(string(pointId)), day, i, numel(dateList));
                end
                [times, vals] = load_timeseries_range(rootDir, subfolder, pointId, day, day, cfg, sensorType);
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

                if keepSeries
                    [td, vd] = bms.analyzer.DynamicSeriesService.limitSeriesPoints(times, vals, perDayMax);
                    if ~isempty(vd)
                        keptTimes{end+1, 1} = td; %#ok<AGROW>
                        keptVals{end+1, 1} = vd; %#ok<AGROW>
                    end
                end
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

            if keepSeries && ~isempty(keptVals)
                rec.times = vertcat(keptTimes{:});
                rec.vals = vertcat(keptVals{:});
                [rec.times, order] = sort(rec.times);
                rec.vals = rec.vals(order);
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
            baseMax = bms.analyzer.DynamicSeriesService.plotMaxPoints(cfg, defaultValue);
            maxPoints = baseMax;
            rawMax = bms.config.ConfigReader.getNumeric(cfg, ...
                'plot_common.dynamic_raw_fig_max_points', baseMax);
            if isscalar(rawMax) && isfinite(rawMax) && rawMax > 0
                maxPoints = max(baseMax, round(rawMax));
            end
            maxPoints = max(1000, round(maxPoints));
        end

        function perDayMax = rawPlotPerDayMax(cfg, dayCount, defaultValue)
            if nargin < 3 || isempty(defaultValue), defaultValue = 50000; end
            dayCount = max(1, double(dayCount));
            totalMax = bms.analyzer.DynamicSeriesService.rawPlotMaxPoints(cfg, defaultValue);
            perDayMax = max(100, ceil(totalMax / dayCount));

            minPerDay = bms.config.ConfigReader.getNumeric(cfg, ...
                'plot_common.dynamic_raw_min_points_per_day', []);
            if isscalar(minPerDay) && isfinite(minPerDay) && minPerDay > 0
                perDayMax = max(perDayMax, round(minPerDay));
            end
            perDayMax = max(100, round(perDayMax));
        end

        function opts = rawPlotOptions(cfg, defaultValue)
            if nargin < 2 || isempty(defaultValue), defaultValue = 50000; end
            opts = bms.plot.PlotService.runtimeOptionsFromConfig(cfg);
            opts.fig_max_points = bms.analyzer.DynamicSeriesService.rawPlotMaxPoints(cfg, defaultValue);
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
                    times, vals, windowMinutes, minCoverage, 'rms', fs);
        end

        function [binTimes, meanSeries, meanMax, tMax] = movingMeanByTimeBins(times, vals, windowMinutes, minCoverage, fs)
            if nargin < 3 || isempty(windowMinutes), windowMinutes = 10; end
            if nargin < 4 || isempty(minCoverage), minCoverage = 0.7; end
            if nargin < 5, fs = []; end

            [binTimes, meanSeries, meanMax, tMax] = ...
                bms.analyzer.DynamicSeriesService.aggregateByTimeBins( ...
                    times, vals, windowMinutes, minCoverage, 'mean', fs);
        end

        function [binTimes, aggSeries, aggMax, tMax] = aggregateByTimeBins(times, vals, windowMinutes, minCoverage, mode, fs)
            if nargin < 3 || isempty(windowMinutes), windowMinutes = 10; end
            if nargin < 4 || isempty(minCoverage), minCoverage = 0.7; end
            if nargin < 5 || isempty(mode), mode = 'mean'; end
            if nargin < 6, fs = []; end

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
            aggSeries(count < minNeed) = NaN;

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
    end
end
