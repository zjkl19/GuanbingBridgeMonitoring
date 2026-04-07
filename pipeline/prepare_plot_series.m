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
    x_valid = x(valid);
    y_valid = y(valid);

    if isempty(x_valid)
        x_plot = x_valid;
        y_plot = y_valid;
        return;
    end

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

function val = get_opt(opts, field_name, default_val)
    if isstruct(opts) && isfield(opts, field_name)
        val = opts.(field_name);
    else
        val = default_val;
    end
end
