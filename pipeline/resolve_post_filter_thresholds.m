function thresholds = resolve_post_filter_thresholds(cfg, sensor_type, point_id)
% resolve_post_filter_thresholds  Merge default + per-point post-filter rules.

    thresholds = struct('min', {}, 'max', {}, 't_range_start', {}, 't_range_end', {});
    if nargin < 3 || isempty(point_id)
        point_id = '';
    end
    if ~isstruct(cfg) || ~ischar(sensor_type) && ~isstring(sensor_type)
        return;
    end
    sensor_type = char(string(sensor_type));

    if isfield(cfg, 'defaults') && isfield(cfg.defaults, sensor_type)
        def = cfg.defaults.(sensor_type);
        thresholds = merge_thresholds(thresholds, get_post_thresholds(def));
    end

    if isempty(point_id)
        return;
    end
    safe_id = strrep(char(string(point_id)), '-', '_');
    if isfield(cfg, 'per_point') && isfield(cfg.per_point, sensor_type) ...
            && isfield(cfg.per_point.(sensor_type), safe_id)
        pt = cfg.per_point.(sensor_type).(safe_id);
        thresholds = merge_thresholds(thresholds, get_post_thresholds(pt));
    end
end

function thresholds = get_post_thresholds(block)
    thresholds = struct('min', {}, 'max', {}, 't_range_start', {}, 't_range_end', {});
    if ~isstruct(block) || ~isfield(block, 'post_filter_thresholds')
        return;
    end
    raw = block.post_filter_thresholds;
    if isempty(raw) || ~isstruct(raw)
        return;
    end
    thresholds = raw(:);
end

function out = merge_thresholds(base, extra)
    out = base;
    if isempty(extra)
        return;
    end
    if isempty(out)
        out = extra(:);
    else
        out = [out(:); extra(:)];
    end
end
