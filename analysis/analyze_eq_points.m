function analyze_eq_points(root_dir, start_date, end_date, subfolder, cfg)
% analyze_eq_points  Earthquake motion time-series with alarm lines.

    if nargin < 1, root_dir = []; end
    if nargin < 2, start_date = []; end
    if nargin < 3, end_date = []; end
    if nargin < 4, subfolder = []; end
    if nargin < 5, cfg = []; end

    bms.analyzer.EarthquakeAnalysisPipeline.run( ...
        root_dir, start_date, end_date, subfolder, cfg);
end
