function analyze_humidity_points(root_dir, point_ids, start_date, end_date, excel_file, subfolder, cfg)
% analyze_humidity_points  Humidity analysis entry point.

    if nargin < 1, root_dir = []; end
    if nargin < 2, point_ids = []; end
    if nargin < 3, start_date = []; end
    if nargin < 4, end_date = []; end
    if nargin < 5, excel_file = []; end
    if nargin < 6, subfolder = []; end
    if nargin < 7, cfg = []; end

    bms.analyzer.ScalarSeriesPipeline.run( ...
        'humidity', root_dir, point_ids, start_date, end_date, excel_file, subfolder, cfg);
end
