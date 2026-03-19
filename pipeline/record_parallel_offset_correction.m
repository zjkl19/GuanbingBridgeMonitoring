function record_parallel_offset_correction(cfg, sensor_type, point_id, times, vals)
% record_parallel_offset_correction  Restore offset logs after worker-side loading.

    if nargin < 5 || isempty(times) || isempty(vals)
        return;
    end

    offset = resolve_offset_correction(cfg, sensor_type, point_id);
    if isempty(offset) || ~isnumeric(offset) || ~isscalar(offset) || ~isfinite(offset) || offset == 0
        return;
    end

    try
        offset_correction_registry('record', struct( ...
            'sensor_type', sensor_type, ...
            'point_id', point_id, ...
            'offset_correction', offset, ...
            'start_time', min(times), ...
            'end_time', max(times), ...
            'sample_count', numel(vals), ...
            'files', {{}}));
    catch
    end
end
