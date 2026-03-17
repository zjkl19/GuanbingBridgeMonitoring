function out_path = resolve_data_output_path(root_dir, relative_path, subdir)
% resolve_data_output_path Resolve a result file path under the data root.
%   Relative paths are placed under root_dir/subdir. Absolute paths are kept.

    if nargin < 3
        subdir = '';
    end

    if nargin < 2 || isempty(relative_path)
        out_path = relative_path;
        return;
    end

    path_str = char(string(relative_path));
    if is_absolute_path(path_str)
        out_path = path_str;
        ensure_parent_dir(out_path);
        return;
    end

    base_dir = root_dir;
    if nargin >= 3 && ~isempty(subdir)
        base_dir = fullfile(base_dir, subdir);
    end
    if ~exist(base_dir, 'dir')
        mkdir(base_dir);
    end

    out_path = fullfile(base_dir, path_str);
    ensure_parent_dir(out_path);
end

function tf = is_absolute_path(path_str)
    tf = false;
    if isempty(path_str)
        return;
    end
    if ispc
        tf = ~isempty(regexp(path_str, '^[A-Za-z]:[\\/]|^\\\\', 'once'));
    else
        tf = startsWith(path_str, '/');
    end
end

function ensure_parent_dir(path_str)
    parent = fileparts(path_str);
    if ~isempty(parent) && ~exist(parent, 'dir')
        mkdir(parent);
    end
end
