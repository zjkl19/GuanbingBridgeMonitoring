function warns = validate_config(cfg, throwOnError)
% validate_config  Basic schema checks for configuration struct.
%   warns = validate_config(cfg) returns warning strings (no error unless
%   the structure itself is missing critical fields).
%   validate_config(cfg,true) will throw on critical structure issues; data
%   issues (e.g., thresholds missing min/max) are reported as warnings.
%
% Checks:
%   - header_marker exists (string)
%   - defaults.* thresholds numeric with min<=max (warn if missing)
%   - per_point.* thresholds same rule; optional t_range_start/end format
%   - outlier fields non-negative if present

    if nargin < 2, throwOnError = true; end
    warns = {};

    if ~isstruct(cfg)
        error('cfg must be a struct');
    end
    if ~isfield(cfg,'defaults')
        error('cfg.defaults missing');
    end
    if ~isfield(cfg.defaults,'header_marker')
        error('cfg.defaults.header_marker missing');
    end
    if ~ischar(cfg.defaults.header_marker) && ~isstring(cfg.defaults.header_marker)
        error('header_marker must be a char array or string');
    end

    sensor_fields = fieldnames(cfg.defaults);
    for i = 1:numel(sensor_fields)
        key = sensor_fields{i};
        if strcmp(key,'header_marker'), continue; end
        def = cfg.defaults.(key);
        warns = [warns, check_rule_block(def, sprintf('defaults.%s', key))]; %#ok<AGROW>
    end

    if isfield(cfg,'per_point') && isstruct(cfg.per_point)
        sens = fieldnames(cfg.per_point);
        for i = 1:numel(sens)
            pts = cfg.per_point.(sens{i});
            if ~isstruct(pts), error('per_point.%s must be struct', sens{i}); end
            pnames = fieldnames(pts);
            for j = 1:numel(pnames)
                warns = [warns, check_rule_block(pts.(pnames{j}), sprintf('per_point.%s.%s', sens{i}, pnames{j}))]; %#ok<AGROW>
            end
        end
    end

    if nargout == 0
        if isempty(warns)
            fprintf('config validation passed.\n');
        else
            fprintf('config validation warnings:\n');
            for i = 1:numel(warns), fprintf(' - %s\n', warns{i}); end
        end
    end
    if throwOnError && ~isempty(warns)
        error(warns{1});
    end
end

function warns = check_rule_block(block, path)
    warns = {};
    if ~isstruct(block), warns{end+1} = sprintf('%s must be struct', path); return; end
    if isfield(block,'thresholds')
        ths = block.thresholds;
        if ~isempty(ths)
            for k = 1:numel(ths)
                th = ths(k);
                hasMin = isfield(th,'min') && ~isempty(th.min) && isnumeric(th.min);
                hasMax = isfield(th,'max') && ~isempty(th.max) && isnumeric(th.max);
                if ~(hasMin && hasMax)
                    warns{end+1} = sprintf('%s.thresholds(%d) must have numeric min/max', path, k); %#ok<AGROW>
                    continue;
                end
                if th.min > th.max
                    warns{end+1} = sprintf('%s.thresholds(%d) min>max', path, k); %#ok<AGROW>
                end
                if isfield(th,'t_range_start') && ~isempty(th.t_range_start)
                    try datetime(th.t_range_start,'InputFormat','yyyy-MM-dd HH:mm:ss'); catch
                        warns{end+1} = sprintf('%s.thresholds(%d) t_range_start format invalid', path, k); %#ok<AGROW>
                    end
                end
                if isfield(th,'t_range_end') && ~isempty(th.t_range_end)
                    try datetime(th.t_range_end,'InputFormat','yyyy-MM-dd HH:mm:ss'); catch
                        warns{end+1} = sprintf('%s.thresholds(%d) t_range_end format invalid', path, k); %#ok<AGROW>
                    end
                end
            end
        end
    end
    if isfield(block,'outlier') && ~isempty(block.outlier)
        o = block.outlier;
        if isfield(o,'window_sec') && ~isempty(o.window_sec) && o.window_sec < 0
            warns{end+1} = sprintf('%s.outlier.window_sec must be >=0', path); %#ok<AGROW>
        end
        if isfield(o,'threshold_factor') && ~isempty(o.threshold_factor) && o.threshold_factor < 0
            warns{end+1} = sprintf('%s.outlier.threshold_factor must be >=0', path); %#ok<AGROW>
        end
    end
    if isfield(block,'zero_to_nan') && ~islogical(block.zero_to_nan)
        block.zero_to_nan = logical(block.zero_to_nan); %#ok<NASGU> % tolerate numeric logicals
    end
end
