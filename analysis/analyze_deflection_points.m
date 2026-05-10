function analyze_deflection_points(root_dir, start_date, end_date, excel_file, subfolder, cfg)
% analyze_deflection_points
%   兼容旧入口；实际流程由 bms.analyzer.StructuralFilteredSeriesPipeline 执行。

    if nargin < 1, root_dir = []; end
    if nargin < 2, start_date = []; end
    if nargin < 3, end_date = []; end
    if nargin < 4, excel_file = []; end
    if nargin < 5, subfolder = []; end
    if nargin < 6, cfg = []; end

    bms.analyzer.StructuralFilteredSeriesPipeline.run( ...
        'deflection', root_dir, start_date, end_date, excel_file, subfolder, cfg);
end
