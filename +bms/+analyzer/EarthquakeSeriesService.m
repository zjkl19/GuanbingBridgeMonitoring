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
                'times', [], 'vals', [], 'params', struct(), 'has_data', false);
        end

        function rec = collectRecord(rootDir, subfolder, pointId, startDate, endDate, cfg, params)
            if nargin < 7 || isempty(params)
                params = struct();
            end

            rec = bms.analyzer.EarthquakeSeriesService.initRecord();
            rec.pid = pointId;
            [rec.sensor_type, rec.comp] = bms.analyzer.EarthquakeSeriesService.componentFromPoint(pointId);
            rec.params = params;
            [times, vals] = load_timeseries_range(rootDir, subfolder, pointId, startDate, endDate, cfg, rec.sensor_type);
            if isempty(vals)
                return;
            end
            rec.times = times;
            rec.vals = vals;
            rec.has_data = true;
        end
    end
end
