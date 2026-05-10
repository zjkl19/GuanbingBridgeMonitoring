function analyze_rainfall_points(root_dir, point_ids, start_date, end_date, excel_file, subfolder, cfg)
% analyze_rainfall_points 批量绘制雨量计时程并统计降雨强度/累计降雨量
    if nargin < 7, cfg = []; end
    if nargin < 6, subfolder = []; end
    if nargin < 5, excel_file = []; end
    if nargin < 4, end_date = []; end
    if nargin < 3, start_date = []; end
    if nargin < 2, point_ids = []; end
    if nargin < 1, root_dir = []; end

    args = bms.analyzer.ScalarSeriesService.resolveInputs(root_dir, point_ids, start_date, end_date, ...
        excel_file, subfolder, cfg, 'rainfall', 'rainfall_stats.xlsx', '特征值');
    root_dir = args.root_dir;
    point_ids = args.point_ids;
    start_date = args.start_date;
    end_date = args.end_date;
    excel_file = args.excel_file;
    subfolder = args.subfolder;
    cfg = args.cfg;
    style = args.style;

    nPts = numel(point_ids);
    stats = cell(nPts, 7);
    range = bms.analyzer.ScalarSeriesService.dateRange(start_date, end_date);
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    outDir = fullfile(root_dir, bms.analyzer.ScalarSeriesService.styleField(style, 'output_dir', '时程曲线_雨量'));
    bms.core.PathResolver.ensureDir(outDir);

    for i = 1:nPts
        pid = point_ids{i};
        fprintf('Processing rainfall %s...\n', pid);
        [all_time, all_val] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'rainfall');
        if isempty(all_val) || isempty(all_time)
            warning('雨量测点 %s 无有效数据，跳过', pid);
            stats{i,1} = pid;
            continue;
        end
        valid = isfinite(all_val) & ~isnat(all_time);
        if ~any(valid)
            warning('雨量测点 %s 无有效数据，跳过', pid);
            stats{i,1} = pid;
            continue;
        end

        t_valid = all_time(valid);
        v_valid = all_val(valid);
        total_mm = calc_total_rainfall_mm(t_valid, v_valid);
        max_val = max(v_valid);
        mean_val = mean(v_valid);

        fig = figure('Position', [100 100 1000 469]); hold on;
        [time_plot, val_plot] = prepare_plot_series(all_time, all_val);
        plot(time_plot, val_plot, 'LineWidth', 1, 'Color', bms.analyzer.ScalarSeriesService.color(style, 1));
        avg_val = round(mean_val, 2);
        yline(avg_val, '--r', sprintf('平均降雨强度 %.2f mm/h', avg_val), ...
            'LabelHorizontalAlignment', 'center', 'LabelVerticalAlignment', 'bottom');

        xt = bms.analyzer.ScalarSeriesService.dateTicks(range, 5);
        ax = gca;
        ax.XLim = [xt(1) xt(end)];
        ax.XTick = xt;
        xtickformat('yyyy-MM-dd');
        xlabel('时间');
        ylabel(bms.analyzer.ScalarSeriesService.styleField(style, 'ylabel', '降雨强度 (mm/h)'));
        bms.analyzer.ScalarSeriesService.applyYLimAutoFirst(style, pid, true);
        grid on; grid minor;
        title(sprintf('%s %s', bms.analyzer.ScalarSeriesService.styleField(style, 'title_prefix', '降雨强度时程'), pid));

        base = sprintf('Rainfall_%s_%s_%s', pid, datestr(range.dn0, 'yyyymmdd'), datestr(range.dn1, 'yyyymmdd'));
        bms.plot.PlotService.saveModuleBundle(fig, outDir, [base '_' timestamp], cfg);

        stats{i,1} = pid;
        stats{i,2} = format_time(min(t_valid));
        stats{i,3} = format_time(max(t_valid));
        stats{i,4} = sum(valid);
        stats{i,5} = max_val;
        stats{i,6} = mean_val;
        stats{i,7} = total_mm;
    end

    T = cell2table(stats, 'VariableNames', ...
        {'PointID','StartTime','EndTime','ValidCount','Max_mm_h','Mean_mm_h','Total_mm'});
    bms.io.StatsWriter.writeModuleTableChecked(T, excel_file, 'rainfall');
    fprintf('雨量统计结果已保存至 %s\n', excel_file);
end

function total_mm = calc_total_rainfall_mm(t, v)
    total_mm = NaN;
    if isempty(t) || isempty(v)
        return;
    end
    [t, order] = sort(t(:));
    v = v(order);
    valid = ~isnat(t) & isfinite(v);
    t = t(valid);
    v = v(valid);
    if numel(v) < 2
        total_mm = 0;
        return;
    end
    dt_hours = hours(diff(t));
    good = isfinite(dt_hours) & dt_hours >= 0;
    if ~any(good)
        total_mm = 0;
        return;
    end
    vv = (v(1:end-1) + v(2:end)) / 2;
    total_mm = sum(vv(good) .* dt_hours(good));
end

function s = format_time(t)
    if isempty(t) || isnat(t)
        s = '';
    else
        s = datestr(t, 'yyyy-mm-dd HH:MM:SS');
    end
end
