function analyze_acceleration_points(root_dir, start_date, end_date, excel_file, subfolder, auto_detect_fs, cfg)
% analyze_acceleration_points Compatibility wrapper for acceleration analysis.

    if nargin < 1, root_dir = []; end
    if nargin < 2, start_date = []; end
    if nargin < 3, end_date = []; end
    if nargin < 4, excel_file = []; end
    if nargin < 5, subfolder = []; end
    if nargin < 6, auto_detect_fs = []; end
    if nargin < 7, cfg = []; end

    bms.analyzer.DynamicAccelerationPipeline.run( ...
        'acceleration', root_dir, start_date, end_date, excel_file, subfolder, auto_detect_fs, cfg);
end
