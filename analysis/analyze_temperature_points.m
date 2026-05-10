function analyze_temperature_points(root_dir, point_ids, start_date, end_date, excel_file, subfolder, cfg)
% analyze_temperature_points 批量绘制多个测点温度时程并统计
    if nargin < 7, cfg = []; end
    if nargin < 6, subfolder = []; end
    if nargin < 5, excel_file = []; end
    if nargin < 4, end_date = []; end
    if nargin < 3, start_date = []; end
    if nargin < 2, point_ids = []; end
    if nargin < 1, root_dir = []; end

    args = bms.analyzer.ScalarSeriesService.resolveInputs(root_dir, point_ids, start_date, end_date, ...
        excel_file, subfolder, cfg, 'temperature', 'temperature_stats.xlsx', '特征值');
    root_dir = args.root_dir;
    point_ids = args.point_ids;
    start_date_str = args.start_date;
    end_date_str = args.end_date;
    excel_file = args.excel_file;
    subfolder = args.subfolder;
    cfg = args.cfg;
    style = args.style;

    nPts = numel(point_ids);
    stats = cell(nPts,4);

    range = bms.analyzer.ScalarSeriesService.dateRange(start_date_str, end_date_str);
    timestamp = datestr(now,'yyyymmdd_HHMMSS');
    outDir = fullfile(root_dir,'时程曲线_温度');
    bms.core.PathResolver.ensureDir(outDir);

    for i = 1:nPts
        pid = point_ids{i};
        fprintf('Processing %s...\n', pid);
        [all_time, all_val] = load_timeseries_range(root_dir, subfolder, pid, start_date_str, end_date_str, cfg, 'temperature');
        if isempty(all_val)
            warning('测点 %s 无数据，跳过', pid);
            continue;
        end
        fig = figure('Position',[100 100 1000 469]); hold on;
        [time_plot, val_plot] = prepare_plot_series(all_time, all_val);
        plot(time_plot, val_plot,'LineWidth',1, 'Color', bms.analyzer.ScalarSeriesService.color(style,1));
        finite_val = bms.analyzer.ScalarSeriesService.finiteValues(all_val);
        if isempty(finite_val)
            avg_val = NaN;
        else
            avg_val = round(mean(finite_val),1);
            yline(avg_val,'--r',sprintf('平均值 %.1f',avg_val),...
                'LabelHorizontalAlignment','center','LabelVerticalAlignment','bottom');
        end
        xt = bms.analyzer.ScalarSeriesService.dateTicks(range, 5);
        ax = gca;
        ax.XLim = [xt(1) xt(end)];
        ax.XTick = xt;
        xtickformat('yyyy-MM-dd');
        xlabel('时间'); ylabel(bms.analyzer.ScalarSeriesService.styleField(style,'ylabel','温度 (°C)'));
        bms.analyzer.ScalarSeriesService.applyYLim(style, pid, false);
        grid on; grid minor;
        title(sprintf('%s %s', bms.analyzer.ScalarSeriesService.styleField(style,'title_prefix','温度时程'), pid));
        base = sprintf('%s_%s_%s', pid, datestr(range.dn0,'yyyymmdd'), datestr(range.dn1,'yyyymmdd'));
        bms.plot.PlotService.saveModuleBundle(fig, outDir, [base '_' timestamp], cfg);
        stats(i,:) = bms.analyzer.ScalarSeriesService.basicStatsRow(pid, finite_val, 1);
    end
    T = bms.analyzer.ScalarSeriesService.basicStatsTable(stats);
    bms.io.StatsWriter.writeModuleTableChecked(T, excel_file, 'temperature');
    fprintf('统计结果已保存至 %s\n',excel_file);
end
