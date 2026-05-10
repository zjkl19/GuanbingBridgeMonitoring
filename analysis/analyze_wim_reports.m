function analyze_wim_reports(root_dir, start_date, end_date, cfg)
% analyze_wim_reports  Compatibility wrapper for WIM report generation.

    if nargin < 1, root_dir = []; end
    if nargin < 2, start_date = []; end
    if nargin < 3, end_date = []; end
    if nargin < 4, cfg = []; end

    bms.analyzer.WimReportPipeline.run(root_dir, start_date, end_date, cfg);
end
