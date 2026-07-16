function paths = save_plot_bundle(fig, out_dir, file_stub, opts)
% save_plot_bundle Export full-resolution images and a lightweight .fig copy.
%   Images are exported from the original full-data figure. The .fig file is
%   saved after line data are reduced with peak-preserving bucket sampling so
%   that long time-series remain editable without blocking batch processing.

    if nargin < 4 || isempty(opts)
        opts = struct();
    end
    paths = {};
    figure_cleanup = onCleanup(@() close_figure_if_valid(fig)); %#ok<NASGU>

    runtime = get_runtime_settings();

    save_jpg = get_opt(opts, 'save_jpg', true);
    save_emf = get_opt(opts, 'save_emf', true);
    save_fig = get_opt(opts, 'save_fig', runtime.save_fig);
    lightweight_fig = get_opt(opts, 'lightweight_fig', runtime.lightweight_fig);
    fig_max_points = get_opt(opts, 'fig_max_points', runtime.fig_max_points);
    append_timestamp = get_opt(opts, 'append_timestamp', runtime.append_timestamp);
    file_stub = apply_timestamp_policy(file_stub, append_timestamp);

    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end

    if save_jpg
        p = fullfile(out_dir, [file_stub '.jpg']);
        atomic_saveas(fig, p);
        paths{end+1} = p; %#ok<AGROW>
    end
    if save_emf
        p = fullfile(out_dir, [file_stub '.emf']);
        atomic_saveas(fig, p);
        paths{end+1} = p; %#ok<AGROW>
    end

    provenance_path = save_plot_provenance(fig, out_dir, file_stub);
    if ~isempty(provenance_path)
        paths{end+1} = provenance_path; %#ok<AGROW>
    end

    if save_fig
        fig_path = fullfile(out_dir, [file_stub '.fig']);
        try
            if lightweight_fig
                simplify_figure_lines(fig, fig_max_points);
            end
            drawnow;
            atomic_savefig(fig, fig_path);
            if isfile(fig_path)
                paths{end+1} = fig_path; %#ok<AGROW>
            end
        catch ME
            warning('save_plot_bundle:SaveFigFailed', ...
                'Failed to save .fig file "%s": %s', fig_path, ME.message);
        end
    end

end

function atomic_saveas(fig, target_path)
    [target_dir, ~, ext] = fileparts(target_path);
    tmp_path = [tempname(target_dir) ext];
    tmp_cleanup = onCleanup(@() delete_if_exists(tmp_path)); %#ok<NASGU>
    saveas(fig, tmp_path);
    replace_file(tmp_path, target_path);
end

function atomic_savefig(fig, target_path)
    [target_dir, ~, ~] = fileparts(target_path);
    tmp_path = [tempname(target_dir) '.fig'];
    tmp_cleanup = onCleanup(@() delete_if_exists(tmp_path)); %#ok<NASGU>
    bms.plot.PlotVisibilityPolicy.saveFigVisibleOn(fig, tmp_path);
    replace_file(tmp_path, target_path);
end

function replace_file(source_path, target_path)
    [ok, msg] = movefile(source_path, target_path, 'f');
    if ~ok
        error('save_plot_bundle:AtomicReplaceFailed', ...
            'Failed to replace "%s": %s', target_path, msg);
    end
end

function path = save_plot_provenance(fig, out_dir, file_stub)
    path = '';
    lines = findall(fig, 'Type', 'line');
    entries = {};
    for i = 1:numel(lines)
        user_data = get(lines(i), 'UserData');
        if ~isstruct(user_data) || ~isfield(user_data, 'plot_provenance') ...
                || ~isstruct(user_data.plot_provenance)
            continue;
        end
        entry = user_data.plot_provenance;
        entry.series_index = numel(entries) + 1;
        entries{end+1, 1} = entry; %#ok<AGROW>
    end
    if isempty(entries)
        return;
    end

    schema_version = 1;
    for i = 1:numel(entries)
        if isfield(entries{i}, 'schema_version') && ...
                isnumeric(entries{i}.schema_version) && ...
                isscalar(entries{i}.schema_version) && ...
                isfinite(entries{i}.schema_version)
            schema_version = max(schema_version, double(entries{i}.schema_version));
        end
    end
    payload = struct( ...
        'schema_version', schema_version, ...
        'file_stub', file_stub, ...
        'created_at', char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss')), ...
        'series', vertcat(entries{:}));
    path = fullfile(out_dir, [file_stub '.plot.json']);
    tmp_path = [tempname(out_dir) '.json'];
    tmp_cleanup = onCleanup(@() delete_if_exists(tmp_path)); %#ok<NASGU>
    fid = fopen(tmp_path, 'w', 'n', 'UTF-8');
    if fid < 0
        error('save_plot_bundle:ProvenanceOpenFailed', ...
            'Failed to open provenance temp file for "%s".', path);
    end
    fid_cleanup = onCleanup(@() close_file_if_open(fid)); %#ok<NASGU>
    fwrite(fid, jsonencode(payload, 'PrettyPrint', true), 'char');
    fclose(fid);
    fid = -1;
    replace_file(tmp_path, path);
end

function close_file_if_open(fid)
    if isnumeric(fid) && isscalar(fid) && fid >= 0
        try
            fclose(fid);
        catch
        end
    end
end

function delete_if_exists(path)
    if isfile(path)
        delete(path);
    end
end

function close_figure_if_valid(fig)
    if isgraphics(fig, 'figure')
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
        protected = key_line_indices(y);
        sel = round(linspace(1, numel(idx), max_points));
        idx = unique(idx(sel), 'stable');
        idx = unique([idx(:); protected(:)], 'stable')';
        if idx(1) ~= 1
            idx = [1 idx]; %#ok<AGROW>
        end
        if idx(end) ~= n
            idx = [idx n]; %#ok<AGROW>
        end
        idx = sort(idx);
    end
end

function idx = key_line_indices(y)
    idx = [];
    if isempty(y)
        return;
    end
    y = y(:);
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

function runtime = get_runtime_settings()
    runtime = struct('save_fig', true, 'lightweight_fig', true, 'fig_max_points', 50000, 'append_timestamp', false);
    try
        candidate = plot_runtime_settings('get');
        if isstruct(candidate)
            if isfield(candidate, 'save_fig'), runtime.save_fig = logical(candidate.save_fig); end
            if isfield(candidate, 'lightweight_fig'), runtime.lightweight_fig = logical(candidate.lightweight_fig); end
            if isfield(candidate, 'fig_max_points') && ~isempty(candidate.fig_max_points)
                runtime.fig_max_points = candidate.fig_max_points;
            end
            if isfield(candidate, 'append_timestamp') && ~isempty(candidate.append_timestamp)
                runtime.append_timestamp = logical(candidate.append_timestamp);
            end
        end
    catch
    end
end

function stub = apply_timestamp_policy(stub, append_timestamp)
    if isstring(stub)
        stub = char(stub);
    end
    if append_timestamp || ~ischar(stub)
        return;
    end

    % Keep the data period in the file name, but drop the run timestamp so
    % repeated analysis of the same period overwrites the previous images.
    patterns = { ...
        '_\d{8}_\d{6}$', ...
        '_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$'};
    for i = 1:numel(patterns)
        stub = regexprep(stub, patterns{i}, '');
    end
end

