function analyze_accel_spectrum_points(root_dir,start_date,end_date,point_ids,...
                                       excel_file,subfolder,target_freqs, ...
                                       tolerance,use_parallel,cfg)
% analyze_accel_spectrum_points
%   兼容旧入口；实际流程由 bms.analyzer.SpectrumAnalysisPipeline 执行。

    if nargin < 1, root_dir = []; end
    if nargin < 2, start_date = []; end
    if nargin < 3, end_date = []; end
    if nargin < 4, point_ids = {}; end
    if nargin < 5, excel_file = []; end
    if nargin < 6, subfolder = []; end
    if nargin < 7, target_freqs = []; end
    if nargin < 8, tolerance = []; end
    if nargin < 9, use_parallel = false; end
    if nargin < 10, cfg = []; end

    bms.analyzer.SpectrumAnalysisPipeline.run('accel_spectrum', root_dir, start_date, end_date, ...
        point_ids, excel_file, subfolder, target_freqs, tolerance, use_parallel, cfg);
end
