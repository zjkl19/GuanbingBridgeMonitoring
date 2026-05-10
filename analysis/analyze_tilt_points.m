function analyze_tilt_points(root_dir, start_date, end_date, excel_file, subfolder, cfg)
% analyze_tilt_points  Tilt analysis entry point.

    if nargin < 1, root_dir = []; end
    if nargin < 2, start_date = []; end
    if nargin < 3, end_date = []; end
    if nargin < 4, excel_file = []; end
    if nargin < 5, subfolder = []; end
    if nargin < 6, cfg = []; end

    bms.analyzer.StructuralFilteredSeriesPipeline.run( ...
        'tilt', root_dir, start_date, end_date, excel_file, subfolder, cfg);
end
