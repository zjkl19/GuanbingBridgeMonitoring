function save_plot_bundle(fig, out_dir, file_stub, opts)
% save_plot_bundle Export full-resolution images and a lightweight .fig copy.
%   Images are exported from the original full-data figure. The .fig file is
%   saved after line data are reduced with peak-preserving bucket sampling so
%   that long time-series remain editable without blocking batch processing.

    if nargin < 4 || isempty(opts)
        opts = struct();
    end

    runtime = get_runtime_settings();

    save_jpg = get_opt(opts, 'save_jpg', true);
    save_emf = get_opt(opts, 'save_emf', true);
    save_fig = get_opt(opts, 'save_fig', runtime.save_fig);
    lightweight_fig = get_opt(opts, 'lightweight_fig', runtime.lightweight_fig);
    fig_max_points = get_opt(opts, 'fig_max_points', runtime.fig_max_points);

    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end

    if save_jpg
        saveas(fig, fullfile(out_dir, [file_stub '.jpg']));
    end
    if save_emf
        saveas(fig, fullfile(out_dir, [file_stub '.emf']));
    end

    if save_fig
        fig_path = fullfile(out_dir, [file_stub '.fig']);
        try
            if lightweight_fig
                simplify_figure_lines(fig, fig_max_points);
            end
            make_figure_visible_for_save(fig);
            drawnow;
            savefig(fig, fig_path, 'compact');
        catch ME
            warning('save_plot_bundle:SaveFigFailed', ...
                'Failed to save .fig file "%s": %s', fig_path, ME.message);
        end
    end

    if isvalid(fig)
        close(fig);
    end
end

function simplify_figure_lines(fig, fig_max_points)
    if isempty(fig_max_points) || ~isscalar(fig_max_points) || fig_max_points < 1000
        fig_max_points = 50000;
    end

    ax_list = findall(fig, 'Type', 'axes');
    for i = 1:numel(ax_list)
        ax = ax_list(i);
        line_list = findall(ax, 'Type', 'line');
        for j = 1:numel(line_list)
            h = line_list(j);
            x = get(h, 'XData');
            y = get(h, 'YData');
            if ~isvector(x) || ~isvector(y)
                continue;
            end
            n = min(numel(x), numel(y));
            if n <= fig_max_points
                continue;
            end
            idx = pick_line_indices(y(1:n), fig_max_points);
            x_new = x(idx);
            y_new = y(idx);
            set(h, 'XData', x_new, 'YData', y_new);

            if isprop(h, 'ZData')
                z = get(h, 'ZData');
                if isvector(z) && numel(z) >= n
                    set(h, 'ZData', z(idx));
                end
            end
        end
    end
end

function idx = pick_line_indices(y, max_points)
    n = numel(y);
    if n <= max_points
        idx = 1:n;
        return;
    end

    bucket_count = max(1, floor(max_points / 4));
    edges = round(linspace(1, n + 1, bucket_count + 1));
    edges = unique(edges, 'stable');
    if edges(end) ~= n + 1
        edges(end + 1) = n + 1; %#ok<AGROW>
    end

    keep = false(1, n);
    for k = 1:(numel(edges) - 1)
        s = edges(k);
        e = edges(k + 1) - 1;
        if s > e
            continue;
        end
        bucket_idx = s:e;
        keep(s) = true;
        keep(e) = true;

        finite_idx = bucket_idx(isfinite(y(bucket_idx)));
        if isempty(finite_idx)
            continue;
        end
        [~, imin] = min(y(finite_idx));
        [~, imax] = max(y(finite_idx));
        keep(finite_idx(imin)) = true;
        keep(finite_idx(imax)) = true;
    end

    idx = find(keep);
    if numel(idx) > max_points
        sel = round(linspace(1, numel(idx), max_points));
        idx = unique(idx(sel), 'stable');
        if idx(1) ~= 1
            idx = [1 idx]; %#ok<AGROW>
        end
        if idx(end) ~= n
            idx = [idx n]; %#ok<AGROW>
        end
    end
end

function make_figure_visible_for_save(fig)
    if strcmpi(get(fig, 'Visible'), 'off')
        old_units = get(fig, 'Units');
        set(fig, 'Units', 'pixels');
        pos = get(fig, 'Position');
        pos(1) = -20000;
        if numel(pos) >= 2
            pos(2) = max(50, pos(2));
        end
        set(fig, 'Position', pos, 'Visible', 'on');
        set(fig, 'Units', old_units);
    end
end

function val = get_opt(opts, field_name, default_val)
    if isstruct(opts) && isfield(opts, field_name)
        val = opts.(field_name);
    else
        val = default_val;
    end
end

function runtime = get_runtime_settings()
    runtime = struct('save_fig', true, 'lightweight_fig', true, 'fig_max_points', 50000);
    try
        candidate = plot_runtime_settings('get');
        if isstruct(candidate)
            if isfield(candidate, 'save_fig'), runtime.save_fig = logical(candidate.save_fig); end
            if isfield(candidate, 'lightweight_fig'), runtime.lightweight_fig = logical(candidate.lightweight_fig); end
            if isfield(candidate, 'fig_max_points') && ~isempty(candidate.fig_max_points)
                runtime.fig_max_points = candidate.fig_max_points;
            end
        end
    catch
    end
end
