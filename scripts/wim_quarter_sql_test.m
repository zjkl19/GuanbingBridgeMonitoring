function wim_quarter_sql_test(input_dir, start_date, end_date)
% wim_quarter_sql_test  Run quarterly WIM processing through SQL Server pipeline.

    if nargin < 1 || isempty(input_dir)
        input_dir = 'E:\洪塘数据\WIM_Quarter_Test';
    end
    if nargin < 2 || isempty(start_date)
        start_date = '2026-01-01';
    end
    if nargin < 3 || isempty(end_date)
        end_date = '2026-03-31';
    end

    addpath(pwd, fullfile(pwd, 'analysis'), fullfile(pwd, 'config'), fullfile(pwd, 'scripts'));
    cfg = load_config('config/hongtang_config.json');
    cfg.wim.vendor = 'zhichen';
    cfg.wim.bridge = 'hongtang';
    cfg.wim.pipeline = 'database';
    cfg.wim.output_root = fullfile(pwd, 'outputs', 'wim_quarter_sql');
    cfg.wim.input.zhichen.dir = input_dir;
    cfg.wim.input.zhichen.bcp = 'HS_Data_{yyyymm}.bcp';
    cfg.wim.input.zhichen.fmt = 'HS_Data_{yyyymm}.fmt';

    if isfield(cfg, 'wim_plot') && isstruct(cfg.wim_plot)
        cfg.wim_plot.enabled = true;
        cfg.wim_plot.output_dir = 'plots';
        cfg.wim_plot.format = 'png';
    end
    if isfield(cfg.wim, 'plot') && isstruct(cfg.wim.plot)
        cfg.wim.plot.enabled = true;
    end

    analyze_wim_reports(pwd, start_date, end_date, cfg);
    fprintf('[WIM] Quarter SQL run complete. Output root: %s\n', cfg.wim.output_root);
end
