function analyze_humidity_points(root_dir, point_ids, start_date, end_date, excel_file, subfolder, cfg)
% analyze_humidity_points 批量绘制测点湿度时程、统计指标并绘制频次分布

    if nargin<1||isempty(root_dir),    root_dir = pwd; end
    if nargin<2||isempty(point_ids),    error('请提供 point_ids cell 数组'); end
    if nargin<3||isempty(start_date),   start_date = input('开始日期(yyyy-MM-dd): ','s'); end
    if nargin<4||isempty(end_date),     end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
    if nargin<5||isempty(excel_file),   excel_file = 'humidity_stats.xlsx'; end
    if nargin<6||isempty(subfolder)
        cfg_tmp = load_config();
        if isfield(cfg_tmp,'subfolders') && isfield(cfg_tmp.subfolders,'humidity')
            subfolder = cfg_tmp.subfolders.humidity;
        else
            subfolder = '特征值';
        end
    end
    if nargin<7||isempty(cfg),          cfg = load_config(); end

    stats = cell(numel(point_ids),4);
    for i = 1:numel(point_ids)
        pid = point_ids{i}; fprintf('处理测点 %s ...\n', pid);
        [times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'humidity');
        if isempty(vals)
            warning('测点 %s 无数据，跳过', pid); continue;
        end
        plot_humidity_point_curve(times, vals, pid, root_dir, start_date, end_date);
        mn = min(vals); mx = max(vals); av = round(mean(vals),1);
        stats{i,1} = pid; stats{i,2} = mn; stats{i,3} = mx; stats{i,4} = av;
        plot_humidity_frequency(vals, pid, root_dir, start_date, end_date);
    end
    T = cell2table(stats,'VariableNames',{'PointID','Min','Max','Mean'});
    writetable(T, excel_file);
    fprintf('统计结果已保存至 %s\n', excel_file);
end

function plot_humidity_point_curve(times, vals, pid, root_dir, start_date, end_date)
% plot_humidity_point_curve 绘制指定测点湿度时程曲线

if isempty(vals)
    error('测点 %s 无数据，无法绘图', pid);
end

dt0 = datetime(start_date,'InputFormat','yyyy-MM-dd');
dt1 = datetime(end_date,  'InputFormat','yyyy-MM-dd');

fig = figure('Position',[100 100 1000 469]);
plot(times, vals, 'LineWidth',1);
numDivisions = 4;
ticks = dt0 + (dt1 - dt0) * (0:numDivisions) / numDivisions;
ax = gca;
ax.XLim = [dt0 dt1]; ax.XTick = ticks;
xtickformat('yyyy-MM-dd');
hold on;
avg_val = mean(vals);
yl = yline(avg_val,'--r');
yl.Label = sprintf('平均值 %.1f%%', avg_val);
yl.LabelHorizontalAlignment = 'center';
yl.LabelVerticalAlignment = 'bottom';
yl.FontSize = 12;
tmp_manual = true;
if tmp_manual, ylim([20,100]); else, ylim auto; end
grid on; grid minor;
title(sprintf('测点 %s 湿度时程曲线', pid));
xlabel('时间');
ylabel('湿度 (%)');

timestamp = char(datetime('now','Format','yyyy-MM-dd_HH-mm-ss'));
output_dir = fullfile(root_dir,'时程曲线_湿度');
if ~exist(output_dir,'dir'), mkdir(output_dir); end
base = sprintf('%s_%s_%s', pid, datestr(dt0,'yyyymmdd'), datestr(dt1,'yyyymmdd'));
saveas(fig, fullfile(output_dir,[base '_' timestamp '.jpg']));
saveas(fig, fullfile(output_dir,[base '_' timestamp '.emf']));
savefig(fig,fullfile(output_dir,[base '_' timestamp '.fig']),'compact');
close(fig);
end

function plot_humidity_frequency(vals, point_id, root_dir, start_date, end_date)
% plot_humidity_frequency 绘制湿度累计频次分布(%)

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
dt0 = datetime(start_date,'InputFormat','yyyy-MM-dd');
dt1 = datetime(end_date,  'InputFormat','yyyy-MM-dd');
fname = sprintf('%s_freq_%s_%s', point_id, datestr(dt0,'yyyymmdd'), datestr(dt1,'yyyymmdd'));
saveas(fig, fullfile(outdir,[fname '_' timestamp '.jpg']));
saveas(fig, fullfile(outdir,[fname '_' timestamp '.emf']));
savefig(fig,fullfile(outdir,[fname '_' timestamp '.fig']),'compact');
close(fig);
end
