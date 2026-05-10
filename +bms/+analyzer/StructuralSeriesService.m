classdef StructuralSeriesService
    %STRUCTURALSERIESSERVICE Shared helpers for structural time-series analyzers.

    methods (Static)
        function data = loadPoint(rootDir, subfolder, pointId, startDate, endDate, cfg, sensorType)
            [times, vals] = load_timeseries_range(rootDir, subfolder, pointId, startDate, endDate, cfg, sensorType);
            data = struct('pid', pointId, 'times', times, 'vals', vals);
        end

        function [dataList, statsRows] = collectPoints(rootDir, subfolder, pointIds, startDate, endDate, cfg, sensorType, decimals, warningPrefix)
            if nargin < 8 || isempty(decimals), decimals = 3; end
            if nargin < 9 || isempty(warningPrefix), warningPrefix = 'Point'; end

            pointIds = bms.data.PointResolver.normalize(pointIds);
            dataList = struct('pid', {}, 'times', {}, 'vals', {});
            statsRows = cell(0, 4);
            for i = 1:numel(pointIds)
                pid = pointIds{i};
                fprintf('Extracting %s ...\n', pid);
                data = bms.analyzer.StructuralSeriesService.loadPoint( ...
                    rootDir, subfolder, pid, startDate, endDate, cfg, sensorType);
                if isempty(data.vals)
                    warning('%s %s has no data, skip', warningPrefix, pid);
                    continue;
                end

                dataList(end+1, 1) = data; %#ok<AGROW>
                statsRows(end+1, :) = bms.analyzer.StructuralSeriesService.basicStatsRow( ...
                    pid, data.vals, decimals); %#ok<AGROW>
            end
        end

        function values = finiteValues(values)
            values = values(isfinite(values));
        end

        function row = basicStatsRow(pointId, values, decimals)
            if nargin < 3 || isempty(decimals), decimals = 3; end
            values = bms.analyzer.StructuralSeriesService.finiteValues(values);
            if isempty(values)
                row = {pointId, NaN, NaN, NaN};
                return;
            end

            row = { ...
                pointId, ...
                round(min(values), decimals), ...
                round(max(values), decimals), ...
                round(mean(values), decimals)};
        end

        function T = basicStatsTable(rows)
            T = cell2table(rows, 'VariableNames', {'PointID', 'Min', 'Max', 'Mean'});
        end

        function valsFiltered = movingMedian10Min(times, vals)
            valsFiltered = vals;
            if isempty(vals) || isempty(times)
                return;
            end

            winLen = bms.analyzer.StructuralSeriesService.tenMinuteWindowLength(times);
            valsFiltered = movmedian(vals, winLen, 'omitnan');
        end

        function winLen = tenMinuteWindowLength(times)
            winLen = 201;
            if numel(times) < 2
                return;
            end

            dt = seconds(diff(times));
            dt = dt(isfinite(dt) & dt > 0);
            if isempty(dt)
                return;
            end

            fs = 1 / median(dt, 'omitnan');
            if ~isfinite(fs) || fs <= 0
                return;
            end

            winLen = max(3, round(10 * 60 * fs));
            if mod(winLen, 2) == 0
                winLen = winLen + 1;
            end
        end

        function row = filteredStatsRow(pointId, rawValues, filteredValues, decimals)
            if nargin < 4 || isempty(decimals), decimals = 3; end
            rawStats = bms.analyzer.StructuralSeriesService.statsTriple(rawValues, decimals);
            filteredStats = bms.analyzer.StructuralSeriesService.statsTriple(filteredValues, decimals);
            row = {pointId, rawStats(1), rawStats(2), rawStats(3), ...
                filteredStats(1), filteredStats(2), filteredStats(3)};
        end

        function T = filteredStatsTable(rows)
            T = cell2table(rows, 'VariableNames', ...
                {'PointID', 'OrigMin_mm', 'OrigMax_mm', 'OrigMean_mm', ...
                'FiltMin_mm', 'FiltMax_mm', 'FiltMean_mm'});
        end

        function [times, values] = validSeries(times, values)
            if isempty(times) || isempty(values)
                times = [];
                values = [];
                return;
            end

            mask = isfinite(values);
            if isdatetime(times)
                mask = mask & ~isnat(times);
            elseif isnumeric(times)
                mask = mask & isfinite(times);
            end
            times = times(mask);
            values = values(mask);
        end

        function row = componentStatsRow(pointId, component, componentLabel, times, values, decimals)
            if nargin < 6 || isempty(decimals), decimals = 3; end
            stats = bms.analyzer.StructuralSeriesService.statsTriple(values, decimals);
            peakToPeak = NaN;
            values = bms.analyzer.StructuralSeriesService.finiteValues(values);
            if ~isempty(values)
                peakToPeak = round(max(values) - min(values), decimals);
            end

            row = { ...
                pointId, component, componentLabel, ...
                datestr(min(times), 'yyyy-mm-dd HH:MM:SS'), ...
                datestr(max(times), 'yyyy-mm-dd HH:MM:SS'), ...
                numel(values), ...
                stats(1), stats(2), stats(3), peakToPeak};
        end

        function T = componentStatsTable(rows)
            T = cell2table(rows, 'VariableNames', ...
                {'PointID', 'Component', 'ComponentLabel', 'StartTime', 'EndTime', ...
                'ValidCount', 'Min_mm', 'Max_mm', 'Mean_mm', 'PeakToPeak_mm'});
        end

        function stats = statsTriple(values, decimals)
            if nargin < 2 || isempty(decimals), decimals = 3; end
            values = bms.analyzer.StructuralSeriesService.finiteValues(values);
            if isempty(values)
                stats = [NaN NaN NaN];
                return;
            end
            stats = round([min(values), max(values), mean(values)], decimals);
        end
    end
end
