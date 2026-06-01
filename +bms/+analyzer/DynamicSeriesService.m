classdef DynamicSeriesService
    %DYNAMICSERIESSERVICE Shared helpers for acceleration-like analyzers.

    methods (Static)
        function rec = initRecord()
            rec = struct('pid', '', 'times', [], 'vals', [], 'fs', NaN, ...
                'mn', NaN, 'mx', NaN, 'av', NaN, 'rms_max', NaN, ...
                'rms_time', NaT, 'has_data', false);
        end

        function rec = collectRecord(rootDir, subfolder, pointId, startDate, endDate, cfg, sensorType, autoDetectFs, keepSeries)
            if nargin < 8 || isempty(autoDetectFs), autoDetectFs = false; end
            if nargin < 9 || isempty(keepSeries), keepSeries = false; end

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
            rec.has_data = true;

            if keepSeries
                rec.times = times;
                rec.vals = vals;
            end
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
            winLen = bms.analyzer.DynamicSeriesService.rmsWindowLength(fs, windowMinutes);
            if numel(vals) < winLen
                return;
            end

            validCnt = movsum(isfinite(vals), winLen, 'Endpoints', 'shrink');
            rmsVals = sqrt(movmean(vals.^2, winLen, 'omitnan', 'Endpoints', 'shrink'));
            minNeed = max(1, round(0.7 * winLen));
            rmsVals(validCnt < minNeed) = NaN;
            [rawMax, idx] = max(rmsVals, [], 'omitnan');
            if isempty(idx) || ~isfinite(rawMax)
                return;
            end

            rmsMax = round(rawMax, decimals);
            if numel(times) >= idx
                tMax = times(idx);
            end
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
