classdef EarthquakeSeriesService
    %EARTHQUAKESERIESSERVICE Shared helpers for earthquake motion analyzers.

    methods (Static)
        function [sensorType, component] = componentFromPoint(pointId)
            pointId = char(string(pointId));
            component = 'X';
            sensorType = 'eq_x';
            if contains(pointId, '-Y')
                component = 'Y';
                sensorType = 'eq_y';
            elseif contains(pointId, '-Z')
                component = 'Z';
                sensorType = 'eq_z';
            elseif contains(pointId, '-X')
                component = 'X';
                sensorType = 'eq_x';
            end
        end

        function rec = initRecord()
            rec = struct('pid', '', 'sensor_type', '', 'comp', '', ...
                'times', [], 'vals', [], 'params', struct(), 'peak', NaN, ...
                'peak_signed', NaN, 'peak_time', NaT, 'has_data', false);
        end

        function rec = collectRecord(rootDir, subfolder, pointId, startDate, endDate, cfg, params)
            if nargin < 7 || isempty(params)
                params = struct();
            end

            rec = bms.analyzer.EarthquakeSeriesService.initRecord();
            rec.pid = pointId;
            [rec.sensor_type, rec.comp] = bms.analyzer.EarthquakeSeriesService.componentFromPoint(pointId);
            rec.params = params;

            dateList = bms.data.TimeSeriesRangeLoader.buildDateList(startDate, endDate);
            perDayMax = bms.analyzer.DynamicSeriesService.rawPlotPerDayMax(cfg, numel(dateList), 50000);
            keptTimes = {};
            keptVals = {};
            bestPeak = NaN;
            bestSigned = NaN;
            bestTime = NaT;

            for i = 1:numel(dateList)
                bms.app.StopController.throwIfRequested('Stop requested before next earthquake data day');
                day = dateList{i};
                if i == 1 || i == numel(dateList) || mod(i, 10) == 0
                    fprintf('Earthquake %s loading %s (%d/%d)\n', ...
                        char(string(pointId)), day, i, numel(dateList));
                end
                [times, vals] = load_timeseries_range(rootDir, subfolder, pointId, day, day, cfg, rec.sensor_type);
                if isempty(vals)
                    continue;
                end
                vals = bms.analyzer.EarthquakeSeriesService.applyValueRules(vals, params);
                [dayPeak, daySigned, dayTime, idx] = bms.analyzer.EarthquakeSeriesService.absPeak(times, vals);
                if ~isempty(idx) && isfinite(dayPeak) && idx >= 1 && idx <= numel(times) ...
                        && (~isfinite(bestPeak) || dayPeak > bestPeak)
                    bestPeak = dayPeak;
                    bestSigned = daySigned;
                    bestTime = dayTime;
                end
                [td, vd] = bms.analyzer.DynamicSeriesService.limitSeriesPoints(times, vals, perDayMax);
                if ~isempty(vd)
                    keptTimes{end+1, 1} = td; %#ok<AGROW>
                    keptVals{end+1, 1} = vd; %#ok<AGROW>
                end
            end

            if isempty(keptVals)
                return;
            end
            rec.times = vertcat(keptTimes{:});
            rec.vals = vertcat(keptVals{:});
            [rec.times, order] = sort(rec.times);
            rec.vals = rec.vals(order);
            rec.peak = bestPeak;
            rec.peak_signed = bestSigned;
            rec.peak_time = bestTime;
            rec.has_data = true;
            fprintf('Earthquake %s collected %d plot samples; peak=%.6g\n', ...
                char(string(pointId)), numel(rec.vals), bestPeak);
        end

        function [peakAbs, peakSigned, peakTime, idx] = absPeak(times, vals)
            peakAbs = NaN;
            peakSigned = NaN;
            peakTime = NaT;
            idx = [];
            if isempty(vals) || numel(times) ~= numel(vals)
                return;
            end
            vals = vals(:);
            finite = isfinite(vals);
            if ~any(finite)
                return;
            end
            finiteIdx = find(finite);
            [peakAbs, relIdx] = max(abs(vals(finite)), [], 'omitnan');
            if isempty(relIdx) || ~isfinite(peakAbs)
                return;
            end
            idx = finiteIdx(relIdx);
            peakSigned = vals(idx);
            peakTime = times(idx);
        end

        function vals = applyValueRules(vals, params)
            if isempty(vals) || ~isstruct(params)
                return;
            end

            if isfield(params, 'raw_min_filter') && ~isempty(params.raw_min_filter)
                minValue = double(params.raw_min_filter);
                minValue = minValue(1);
                if isfinite(minValue)
                    vals(vals < minValue) = NaN;
                end
            end

            if isfield(params, 'value_scale') && ~isempty(params.value_scale)
                scale = double(params.value_scale);
                scale = scale(1);
                if isfinite(scale) && scale ~= 1
                    vals = vals .* scale;
                end
            end
        end
    end
end
