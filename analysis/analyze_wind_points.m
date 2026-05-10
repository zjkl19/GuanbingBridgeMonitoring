function analyze_wind_points(root_dir, start_date, end_date, subfolder, cfg)
% analyze_wind_points  Wind speed/direction analysis entry point.

    if nargin < 1, root_dir = []; end
    if nargin < 2, start_date = []; end
    if nargin < 3, end_date = []; end
    if nargin < 4, subfolder = []; end
    if nargin < 5, cfg = []; end

    bms.analyzer.WindAnalysisPipeline.run(root_dir, start_date, end_date, subfolder, cfg);
end
