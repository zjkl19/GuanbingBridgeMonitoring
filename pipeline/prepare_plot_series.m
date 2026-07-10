function [x_plot, y_plot] = prepare_plot_series(x, y, opts)
% prepare_plot_series Normalize gap rendering for time-series plots.
%   gap_mode = 'break'   : break line on long internal gaps
%   gap_mode = 'connect' : connect internal gaps with a straight line
% Leading/trailing missing data are always left blank.

    if nargin < 3 || isempty(opts)
        opts = struct();
    end

    runtime = plot_runtime_settings('get');
    gap_mode = get_opt(opts, 'gap_mode', runtime.gap_mode);
    gap_break_factor = get_opt(opts, 'gap_break_factor', runtime.gap_break_factor);
    max_points = get_opt(opts, 'fig_max_points', Inf);

    gap_mode = lower(char(string(gap_mode)));
    if ~ismember(gap_mode, {'break','connect'})
        gap_mode = 'break';
    end
    if ~isscalar(gap_break_factor) || ~isfinite(gap_break_factor) || gap_break_factor <= 1
        gap_break_factor = 5;
    end

    x = x(:);
    y = y(:);
    n = min(numel(x), numel(y));
    x = x(1:n);
    y = y(1:n);

    valid = is_valid_x(x) & isfinite(y);
    no_limit = isempty(max_points) || ~isscalar(max_points) || ...
        ~isfinite(double(max_points)) || double(max_points) <= 0;
    if all(valid) && strcmp(gap_mode, 'connect') && no_limit
        x_plot = x;
        y_plot = y;
        return;
    end
    x_valid = x(valid);
    y_valid = y(valid);

    if isempty(x_valid)
        x_plot = x_valid;
        y_plot = y_valid;
        return;
    end
    [x_valid, y_valid] = limit_plot_points(x_valid, y_valid, max_points);

    if strcmp(gap_mode, 'connect') || numel(x_valid) <= 1
        x_plot = x_valid;
        y_plot = y_valid;
        return;
    end

    dt = diff_x(x_valid);
    dt = dt(isfinite(dt) & dt > 0);
    if isempty(dt)
        x_plot = x_valid;
        y_plot = y_valid;
        return;
    end
    gap_threshold = gap_break_factor * median(dt);
    gap_break = diff_x(x_valid) > gap_threshold;
    gap_break = gap_break(:);
    if ~any(gap_break)
        x_plot = x_valid;
        y_plot = y_valid;
        return;
    end

    n_valid = numel(x_valid);
    n_gap = nnz(gap_break);
    x_plot = gap_x_value(x_valid, n_valid + n_gap);
    y_plot = NaN(n_valid + n_gap, 1);

    shift = [0; cumsum(gap_break)];
    keep_pos = (1:n_valid)' + shift;
    x_plot(keep_pos) = x_valid;
    y_plot(keep_pos) = y_valid;
end

function tf = is_valid_x(x)
    if isdatetime(x)
        tf = ~isnat(x);
    else
        tf = isfinite(x);
    end
end

function d = diff_x(x)
    if isdatetime(x)
        d = seconds(diff(x));
    else
        d = diff(double(x));
    end
end

function gx = gap_x_value(x, n)
    if nargin < 2 || isempty(n)
        n = 1;
    end
    if isdatetime(x)
        gx = NaT(n, 1);
    else
        gx = NaN(n, 1);
    end
end

function [x_out, y_out] = limit_plot_points(x, y, max_points)
    x_out = x;
    y_out = y;
    if isempty(x) || isempty(y) || isempty(max_points)
        return;
    end
    max_points = double(max_points);
    if ~isscalar(max_points) || ~isfinite(max_points) || max_points <= 0
        return;
    end
    max_points = max(2, round(max_points));
    n = numel(x);
    if n <= max_points
        return;
    end
    idx = pick_plot_indices(y, max_points);
    x_out = x(idx);
    y_out = y(idx);
end

function idx = pick_plot_indices(y, max_points)
    y = y(:);
    n = numel(y);
    if n <= max_points
        idx = 1:n;
        return;
    end

    bucket_count = max(1, floor(max_points / 4));
    edges = unique(round(linspace(1, n + 1, bucket_count + 1)), 'stable');
    if edges(1) ~= 1
        edges = [1 edges(:).']; %#ok<AGROW>
    end
    if edges(end) ~= n + 1
        edges(end + 1) = n + 1; %#ok<AGROW>
    end

    keep = false(n, 1);
    keep(1) = true;
    keep(n) = true;
    for k = 1:(numel(edges) - 1)
        s = max(1, min(n, edges(k)));
        e = max(1, min(n, edges(k + 1) - 1));
        if s > e
            continue;
        end

        bucket_idx = (s:e).';
        keep(s) = true;
        keep(e) = true;

        finite_idx = bucket_idx(isfinite(y(bucket_idx)));
        if isempty(finite_idx)
            continue;
        end
        finite_vals = y(finite_idx);
        [~, min_rel] = min(finite_vals);
        [~, max_rel] = max(finite_vals);
        [~, abs_rel] = max(abs(finite_vals));
        keep(finite_idx([min_rel max_rel abs_rel])) = true;
    end

    idx = find(keep);
    if numel(idx) > max_points
        idx = trim_indices(idx, key_sample_indices(y), n, max_points);
    end
    idx = sort(idx(:)).';
end

function idx = trim_indices(idx, protected, n, max_points)
    idx = unique(idx(:), 'stable');
    protected = unique([1; n; protected(:)], 'stable');
    if numel(protected) >= max_points
        sel = round(linspace(1, numel(protected), max_points));
        idx = protected(sel);
        return;
    end

    rest = setdiff(idx, protected, 'stable');
    room = max_points - numel(protected);
    if isempty(rest) || room <= 0
        idx = protected;
        return;
    end
    sel = unique(round(linspace(1, numel(rest), min(room, numel(rest)))), 'stable');
    idx = [protected; rest(sel)];
end

function idx = key_sample_indices(y)
    idx = [];
    if isempty(y)
        return;
    end
    finite = isfinite(y);
    if ~any(finite)
        return;
    end
    finiteIdx = find(finite);
    finiteVals = y(finite);
    [~, minRel] = min(finiteVals);
    [~, maxRel] = max(finiteVals);
    [~, absRel] = max(abs(finiteVals));
    idx = unique([finiteIdx(minRel), finiteIdx(maxRel), finiteIdx(absRel)], 'stable');
end

function val = get_opt(opts, field_name, default_val)
    if isstruct(opts) && isfield(opts, field_name)
        val = opts.(field_name);
    else
        val = default_val;
    end
end
