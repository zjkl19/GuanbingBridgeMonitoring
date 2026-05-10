function analyze_humidity_points(root_dir, point_ids, start_date, end_date, excel_file, subfolder, cfg)
% analyze_humidity_points 批量绘制测点湿度时程、统计指标并绘制频次分布

    if nargin < 7, cfg = []; end
    if nargin < 6, subfolder = []; end
    if nargin < 5, excel_file = []; end
    if nargin < 4, end_date = []; end
    if nargin < 3, start_date = []; end
    if nargin < 2, point_ids = []; end
    if nargin < 1, root_dir = []; end

    args = bms.analyzer.ScalarSeriesService.resolveInputs(root_dir, point_ids, start_date, end_date, ...
        excel_file, subfolder, cfg, 'humidity', 'humidity_stats.xlsx', '特征值');
    root_dir = args.root_dir;
    point_ids = args.point_ids;
    start_date_str = args.start_date;
    end_date_str = args.end_date;
    excel_file = args.excel_file;
    subfolder = args.subfolder;
    cfg = args.cfg;
    style = args.style;

    stats = cell(numel(point_ids),4);
    for i = 1:numel(point_ids)
        pid = point_ids{i}; fprintf('处理测点 %s ...\n', pid);
        [times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date_str, end_date_str, cfg, 'humidity');
        if isempty(vals)
            warning('测点 %s 无数据，跳过', pid); continue;
        end
        valid_vals = bms.analyzer.ScalarSeriesService.finiteValues(vals);
        if isempty(valid_vals)
            warning('Point %s contains only NaN values, skipping', pid); continue;
        end
        plot_humidity_point_curve(times, vals, pid, root_dir, start_date_str, end_date_str, style, cfg);
        stats(i,:) = bms.analyzer.ScalarSeriesService.basicStatsRow(pid, valid_vals, 1);
        plot_humidity_frequency(valid_vals, pid, root_dir, start_date_str, end_date_str, cfg);
    end
    T = bms.analyzer.ScalarSeriesService.basicStatsTable(stats);
    bms.io.StatsWriter.writeModuleTableChecked(T, excel_file, 'humidity');
    fprintf('统计结果已保存至 %s\n', excel_file);
end

function plot_humidity_point_curve(times, vals, pid, root_dir, start_date, end_date, style, cfg)
if nargin < 8
    cfg = struct();
end
if isempty(vals)
    error('测点 %s 无数据，无法绘图', pid);
end

range = bms.analyzer.ScalarSeriesService.dateRange(start_date, end_date);

fig = figure('Position',[100 100 1000 469]);
[times_plot, vals_plot] = prepare_plot_series(times, vals);
plot(times_plot, vals_plot, 'LineWidth',1, 'Color', bms.analyzer.ScalarSeriesService.color(style,1));
ticks = bms.analyzer.ScalarSeriesService.dateTicks(range, 5);
ax = gca;
ax.XLim = [range.dt0 range.dt1]; ax.XTick = ticks;
xtickformat('yyyy-MM-dd');
hold on;
avg_val = mean(vals, 'omitnan');
if ~isnan(avg_val)
    yl = yline(avg_val,'--r');
    yl.Label = sprintf('平均值 %.1f%%', avg_val);
    yl.LabelHorizontalAlignment = 'center';
    yl.LabelVerticalAlignment = 'bottom';
    yl.FontSize = 12;
end
bms.analyzer.ScalarSeriesService.applyYLim(style, pid, false);
grid on; grid minor;
title(sprintf('%s %s', bms.analyzer.ScalarSeriesService.styleField(style,'title_prefix','湿度时程'), pid));
xlabel('时间');
ylabel(bms.analyzer.ScalarSeriesService.styleField(style,'ylabel','湿度 (%)'));

timestamp = char(datetime('now','Format','yyyy-MM-dd_HH-mm-ss'));
output_dir = fullfile(root_dir,'时程曲线_湿度');
bms.core.PathResolver.ensureDir(output_dir);
base = sprintf('%s_%s_%s', pid, datestr(range.dn0,'yyyymmdd'), datestr(range.dn1,'yyyymmdd'));
bms.plot.PlotService.saveModuleBundle(fig, output_dir, [base '_' timestamp], cfg);
end

function plot_humidity_frequency(vals, point_id, root_dir, start_date, end_date, cfg)
if nargin < 6
    cfg = struct();
end
bins = 20:10:100;
counts = histcounts(vals, bins);
total = sum(counts);
percent = counts/total*100;

fig = figure('Position',[100 100 1000 469]);
bar(percent, 'FaceColor','flat');
xticks(1:length(counts));
xticklabels({'20-30','30-40','40-50','50-60','60-70','70-80','80-90','90-100'});
ylabel('环境湿度累计持续时间频次分布 (%)');
xlabel('环境湿度范围 (%)');
title(sprintf('测点 %s 湿度频次分布', point_id));
grid on; grid minor;
for k=1:length(percent)
    text(k, percent(k)+1, sprintf('%.2f%%',percent(k)), 'HorizontalAlignment','center');
end
timestamp = char(datetime('now','Format','yyyy-MM-dd_HH-mm-ss'));
outdir = fullfile(root_dir,'频次分布_湿度'); if ~exist(outdir,'dir'), mkdir(outdir); end
range = bms.analyzer.ScalarSeriesService.dateRange(start_date, end_date);
fname = sprintf('%s_freq_%s_%s', point_id, datestr(range.dn0,'yyyymmdd'), datestr(range.dn1,'yyyymmdd'));
bms.plot.PlotService.saveModuleBundle(fig, outdir, [fname '_' timestamp], cfg);
end
