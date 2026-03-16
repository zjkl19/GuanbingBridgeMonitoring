function wim_quarter_smoke_test(input_dir, start_date, end_date, use_sample, sample_rows, pipeline)
% wim_quarter_smoke_test  Smoke test monthly WIM processing across multiple months.
%   By default extracts small per-month samples from the real monthly bcp/fmt files,
%   then runs analyze_wim_reports across the requested date range.

    if nargin < 1 || isempty(input_dir)
        input_dir = 'E:\洪塘数据\WIM_Quarter_Test';
    end
    if nargin < 2 || isempty(start_date)
        start_date = '2026-01-01';
    end
    if nargin < 3 || isempty(end_date)
        end_date = '2026-02-28';
    end
    if nargin < 4 || isempty(use_sample)
        use_sample = true;
    end
    if nargin < 5 || isempty(sample_rows)
        sample_rows = 5000;
    end
    if nargin < 6 || isempty(pipeline)
        pipeline = 'direct';
    end

    addpath(pwd, fullfile(pwd, 'analysis'), fullfile(pwd, 'config'), fullfile(pwd, 'scripts'));
    cfg = load_config('config/hongtang_config.json');
    cfg.wim.vendor = 'zhichen';
    cfg.wim.bridge = 'hongtang';
    cfg.wim.pipeline = pipeline;
    cfg.wim.output_root = fullfile(pwd, 'outputs', 'wim_quarter_test');

    if isfield(cfg, 'wim_plot') && isstruct(cfg.wim_plot)
        cfg.wim_plot.enabled = false;
    end
    if isfield(cfg.wim, 'plot') && isstruct(cfg.wim.plot)
        cfg.wim.plot.enabled = false;
    end

    month_ids = month_strings(start_date, end_date);
    if use_sample
        sample_dir = fullfile(pwd, 'outputs', 'wim_quarter_test', 'samples');
        if ~exist(sample_dir, 'dir'), mkdir(sample_dir); end
        for i = 1:numel(month_ids)
            wim_extract_sample(input_dir, month_ids{i}, sample_dir, sample_rows, 'gbk', 'first');
        end
        cfg.wim.input.zhichen.dir = sample_dir;
        cfg.wim.input.zhichen.bcp = sprintf('HS_Data_{yyyymm}_sample_%d.bcp', sample_rows);
        cfg.wim.input.zhichen.fmt = sprintf('HS_Data_{yyyymm}_sample_%d.fmt', sample_rows);
    else
        cfg.wim.input.zhichen.dir = input_dir;
        cfg.wim.input.zhichen.bcp = 'HS_Data_{yyyymm}.bcp';
        cfg.wim.input.zhichen.fmt = 'HS_Data_{yyyymm}.fmt';
    end

    analyze_wim_reports(pwd, start_date, end_date, cfg);
    fprintf('[WIM] Quarter smoke test complete. Output root: %s\n', cfg.wim.output_root);
end

function ids = month_strings(start_date, end_date)
    start_dt = dateshift(datetime(start_date, 'InputFormat', 'yyyy-MM-dd'), 'start', 'month');
    end_dt = dateshift(datetime(end_date, 'InputFormat', 'yyyy-MM-dd'), 'start', 'month');
    ids = {};
    cursor = start_dt;
    while cursor <= end_dt
        ids{end+1, 1} = datestr(cursor, 'yyyymm'); %#ok<AGROW>
        cursor = cursor + calmonths(1);
    end
end
