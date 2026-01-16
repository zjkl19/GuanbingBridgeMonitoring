function validate_config(cfg)
% validate_config  Basic schema checks for configuration struct.
% Throws error if validation fails.
%
% Checks:
%   - header_marker exists (string)
%   - defaults.* thresholds numeric with min<=max
%   - per_point.* thresholds same rule; optional t_range_start/end format
%   - outlier fields non-negative if present

    assert(isstruct(cfg), 'cfg must be a struct');
    assert(isfield(cfg,'defaults'), 'cfg.defaults missing');
    assert(isfield(cfg.defaults,'header_marker'), 'cfg.defaults.header_marker missing');
    if ~ischar(cfg.defaults.header_marker)
        error('header_marker must be a char array');
    end

    sensor_fields = fieldnames(cfg.defaults);
    for i = 1:numel(sensor_fields)
        key = sensor_fields{i};
        if strcmp(key,'header_marker'), continue; end
        def = cfg.defaults.(key);
        check_rule_block(def, sprintf('defaults.%s', key));
    end

    if isfield(cfg,'per_point') && isstruct(cfg.per_point)
        sens = fieldnames(cfg.per_point);
        for i = 1:numel(sens)
            pts = cfg.per_point.(sens{i});
            if ~isstruct(pts), error('per_point.%s must be struct', sens{i}); end
            pnames = fieldnames(pts);
            for j = 1:numel(pnames)
                check_rule_block(pts.(pnames{j}), sprintf('per_point.%s.%s', sens{i}, pnames{j}));
            end
        end
    end

    fprintf('config validation passed.\n');
end

function check_rule_block(block, path)
    if ~isstruct(block), error('%s must be struct', path); end
    if isfield(block,'thresholds')
        ths = block.thresholds;
        if ~isempty(ths)
            for k = 1:numel(ths)
                th = ths(k);
                if ~(isfield(th,'min') && isfield(th,'max'))
                    error('%s.thresholds(%d) must have min/max', path, k);
                end
                if ~(isnumeric(th.min) && isnumeric(th.max))
                    error('%s.thresholds(%d) min/max must be numeric', path, k);
                end
                if th.min > th.max
                    error('%s.thresholds(%d) min>max', path, k);
                end
                if isfield(th,'t_range_start') && ~isempty(th.t_range_start)
                    try datetime(th.t_range_start,'InputFormat','yyyy-MM-dd HH:mm:ss'); catch
                        error('%s.thresholds(%d) t_range_start format invalid', path, k);
                    end
                end
                if isfield(th,'t_range_end') && ~isempty(th.t_range_end)
                    try datetime(th.t_range_end,'InputFormat','yyyy-MM-dd HH:mm:ss'); catch
                        error('%s.thresholds(%d) t_range_end format invalid', path, k);
                    end
                end
            end
        end
    end
    if isfield(block,'outlier') && ~isempty(block.outlier)
        o = block.outlier;
        if isfield(o,'window_sec') && ~isempty(o.window_sec) && o.window_sec < 0
            error('%s.outlier.window_sec must be >=0', path);
        end
        if isfield(o,'threshold_factor') && ~isempty(o.threshold_factor) && o.threshold_factor < 0
            error('%s.outlier.threshold_factor must be >=0', path);
        end
    end
    if isfield(block,'zero_to_nan') && ~islogical(block.zero_to_nan)
        block.zero_to_nan = logical(block.zero_to_nan); %#ok<NASGU> % tolerate numeric logicals
    end
end
