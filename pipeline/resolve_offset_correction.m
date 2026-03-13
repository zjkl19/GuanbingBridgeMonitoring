function offset = resolve_offset_correction(cfg, sensor_type, point_id)
% resolve_offset_correction  Resolve effective per-point offset correction.

    offset = [];
    if nargin < 3 || isempty(point_id) || ~isstruct(cfg)
        return;
    end
    sensor_type = char(string(sensor_type));
    point_id = char(string(point_id));

    if isfield(cfg, 'defaults') && isfield(cfg.defaults, sensor_type)
        offset = get_offset_value(cfg.defaults.(sensor_type));
    end

    safe_id = strrep(point_id, '-', '_');
    if isfield(cfg, 'per_point') && isfield(cfg.per_point, sensor_type) ...
            && isfield(cfg.per_point.(sensor_type), safe_id)
        pt = cfg.per_point.(sensor_type).(safe_id);
        ptOffset = get_offset_value(pt);
        if ~isempty(ptOffset)
            offset = ptOffset;
        end
    end
end

function offset = get_offset_value(block)
    offset = [];
    if ~isstruct(block) || ~isfield(block, 'offset_correction') || isempty(block.offset_correction)
        return;
    end
    raw = block.offset_correction;
    if ischar(raw) || isstring(raw)
        raw = str2double(raw);
    end
    if isnumeric(raw) && isscalar(raw) && isfinite(raw)
        offset = double(raw);
    end
end
