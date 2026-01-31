function wim_smoke_test()
% wim_smoke_test  Smoke test for WIM using sample bcp/fmt.
    addpath(pwd, fullfile(pwd,'analysis'), fullfile(pwd,'config'));
    cfg = load_config('config/hongtang_config.json');

    sample_dir = fullfile(pwd, 'data', '_samples', 'wim', 'zhichen', '202512');
    cfg.wim.vendor = 'zhichen';
    cfg.wim.bridge = 'hongtang';
    cfg.wim.input.zhichen.dir = sample_dir;
    cfg.wim.input.zhichen.bcp = 'HS_Data_202512_sample_300.bcp';
    cfg.wim.input.zhichen.fmt = 'HS_Data_202512_sample_300.fmt';

    analyze_wim_reports(pwd, '2025-12-01', '2025-12-31', cfg);
end
