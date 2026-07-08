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
    if isfield(cfg, 'per_point') && isfield(cfg.per_point, sensor_type) ...
            && isstruct(cfg.per_point.(sensor_type))
        [ok, pt] = bms.data.PointResolver.getPointConfig(cfg.per_point.(sensor_type), point_id, cfg);
        if ~ok
            return;
        end
        thresholds = merge_thresholds(thresholds, get_post_thresholds(pt));
    end
end

function thresholds = get_post_thresholds(block)
    thresholds = struct('min', {}, 'max', {}, 't_range_start', {}, 't_range_end', {});
    if ~isstruct(block) || ~isfield(block, 'post_filter_thresholds')
        return;
    end
    raw = block.post_filter_thresholds;
    if isempty(raw)
        return;
    end
    if iscell(raw)
        for i = 1:numel(raw)
            item = raw{i};
            if isstruct(item)
                thresholds = merge_thresholds(thresholds, normalize_thresholds(item)); %#ok<AGROW>
            end
        end
        return;
    end
    if ~isstruct(raw)
        return;
    end
    thresholds = normalize_thresholds(raw);
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

function out = normalize_thresholds(raw)
    out = struct('min', {}, 'max', {}, 't_range_start', {}, 't_range_end', {});
    if isempty(raw) || ~isstruct(raw)
        return;
    end
    raw = raw(:);
    out(numel(raw), 1) = struct('min', [], 'max', [], 't_range_start', '', 't_range_end', '');
    for i = 1:numel(raw)
        if isfield(raw(i), 'min')
            out(i).min = raw(i).min;
        end
        if isfield(raw(i), 'max')
            out(i).max = raw(i).max;
        end
        if isfield(raw(i), 't_range_start')
            out(i).t_range_start = raw(i).t_range_start;
        end
        if isfield(raw(i), 't_range_end')
            out(i).t_range_end = raw(i).t_range_end;
        end
    end
end
