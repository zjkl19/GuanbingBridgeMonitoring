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

    out_path = bms.data.DataLayoutResolver.resolveOutputPath(root_dir, relative_path, subdir);
end
