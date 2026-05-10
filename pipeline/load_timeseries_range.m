function [times, vals, meta] = load_timeseries_range(root_dir, subfolder, point_id, start_date, end_date, cfg, sensor_type)
%LOAD_TIMESERIES_RANGE Compatibility wrapper for vendor-aware time-series loading.
%   The implementation lives in bms.data.TimeSeriesRangeLoader so data-source
%   orchestration can be tested without depending on the legacy pipeline path.

    if nargin < 7
        sensor_type = 'generic';
    end
    if nargin < 6
        cfg = [];
    end
    [times, vals, meta] = bms.data.TimeSeriesRangeLoader.load( ...
        root_dir, subfolder, point_id, start_date, end_date, cfg, sensor_type);
end
