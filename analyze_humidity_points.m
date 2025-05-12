function analyze_humidity_points(root_dir, point_ids, start_date, end_date, excel_file, subfolder)
% analyze_humidity_points 批量绘制测点湿度时程曲线、统计指标并绘制频次分布
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   point_ids: 测点编号 cell 数组，如 {'GB-RHS-G05-001-01',...}
%   start_date,end_date: 日期范围，'yyyy-MM-dd'
%   excel_file: 输出统计 Excel，如 'humidity_stats.xlsx'
%   subfolder: 数据所在子文件夹，默认 '特征值'

if nargin<1||isempty(root_dir),    root_dir = pwd; end
if nargin<2||isempty(point_ids),    error('请提供 point_ids cell 数组'); end
if nargin<3||isempty(start_date),   start_date = input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<4||isempty(end_date),     end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
if nargin<5||isempty(excel_file),   excel_file = 'humidity_stats.xlsx'; end
if nargin<6||isempty(subfolder),    subfolder  = '特征值'; end

% 存储统计
stats = cell(numel(point_ids),4);
for i = 1:numel(point_ids)
    pid = point_ids{i}; fprintf('处理测点 %s ...\n', pid);
    % 提取数据
    [times, vals] = extract_humidity_data(root_dir, subfolder, pid, start_date, end_date);
    if isempty(vals)
        warning('测点 %s 无数据，跳过。', pid); continue;
    end
    % 绘制时程曲线
    plot_humidity_point_curve(times, vals, pid, root_dir, start_date, end_date);
    % 统计最小/最大/平均
    mn = min(vals); mx = max(vals); av = round(mean(vals),1);
    stats{i,1} = pid; stats{i,2} = mn; stats{i,3} = mx; stats{i,4} = av;
    % 绘制频次分布
    plot_humidity_frequency(vals, pid, root_dir, start_date, end_date);
end
% 写入 Excel
T = cell2table(stats,'VariableNames',{'PointID','Min','Max','Mean'});
writetable(T, excel_file);
fprintf('统计结果已保存至 %s\n', excel_file);
end

function [all_time, all_val] = extract_humidity_data(root_dir, subfolder, point_id, start_date, end_date)
% extract_humidity_data 提取指定测点在日期范围内的湿度时间和值数组
all_time = [];
all_val  = [];
% 日期筛选
dn0 = datenum(start_date,'yyyy-mm-dd');
dn1 = datenum(end_date,  'yyyy-mm-dd');
dinfo = dir(fullfile(root_dir,'20??-??-??')); folders = {dinfo([dinfo.isdir]).name};
dates = folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
for j = 1:numel(dates)
    day = dates{j};
    dir_path = fullfile(root_dir, day,  subfolder);
    if ~exist(dir_path,'dir'), continue; end
    files = dir(fullfile(dir_path,'*.csv'));
    matches = files(arrayfun(@(f) contains(f.name, point_id), files));
    if isempty(matches), continue; end
    fullpath = fullfile(dir_path, matches(1).name);
    if numel(matches)>1
        warning('日期 %s 中测点 %s 匹配多个文件，仅使用 %s', day, point_id, matches(1).name);
    end
    % 检测头部前50行, 未找到也继续读取全部内容
    fid = fopen(fullpath,'rt'); header = 0;
    for k = 1:50
        if feof(fid), break; end
        ln = fgetl(fid);
        header = header + 1;
        if contains(ln,'[绝对时间]')
            break;
        end
    end
    fclose(fid);
    % 读取数据，无论是否找到头部都使用 readtable
    T = readtable(fullpath, 'Delimiter', ',', 'HeaderLines', header, 'Format', '%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
    all_time = [all_time; T{:,1}];
    all_val  = [all_val;  T{:,2}];
end
% 排序
[all_time, idx] = sort(all_time);
all_val = all_val(idx);
end

function plot_humidity_point_curve(times, vals,pid,  root_dir, start_date, end_date)
% plot_humidity_point_curve 绘制指定测点湿度时程曲线
% 窗口1000×469，单位% ，4等分刻度，加平均线

% 开始计时
t0 = tic;

if isempty(vals)
    error('测点 %s 无数据，无法绘图', point_id);
end

% 排序保障
dn0 = datenum(start_date,'yyyy-mm-dd');
dn1 = datenum(end_date,  'yyyy-mm-dd');

% 绘图
fig = figure('Position',[100 100 1000 469]);
plot(times, vals, 'LineWidth',1);
% X 轴4等分包含起止
numDivisions = 4;
tickNums = linspace(dn0, dn1, numDivisions+1);
ticks = datetime(tickNums,'ConvertFrom','datenum');
ax = gca;
ax.XLim = ticks([1 end]); ax.XTick = ticks;
xtickformat('yyyy-MM-dd');
hold on;
% 平均线
avg_val = mean(vals);
yl = yline(avg_val,'--r');
yl.Label = sprintf('平均值 %.1f%%', avg_val);
yl.LabelHorizontalAlignment = 'center';
yl.LabelVerticalAlignment = 'bottom';
yl.FontSize = 12;
% 网格与标签
tmp_manual = true;
if tmp_manual, ylim([20,100]); else, ylim auto; end
grid on; grid minor;
title(sprintf('测点 %s 湿度时程曲线', pid));
xlabel('时间');
ylabel('湿度 (%)');


% 保存
timestamp = datestr(now,'yyyy-mm-dd_HH-MM-SS');
output_dir = fullfile(root_dir,'时程曲线_湿度');
if ~exist(output_dir,'dir'), mkdir(output_dir); end
base = sprintf('%s_%s_%s', pid, datestr(dn0,'yyyymmdd'), datestr(dn1,'yyyymmdd'));
saveas(fig, fullfile(output_dir,[base '_' timestamp '.jpg']));
saveas(fig, fullfile(output_dir,[base '_' timestamp '.emf']));
savefig(fig,fullfile(output_dir,[base '_' timestamp '.fig']),'compact');
close(fig);

elapsed = toc(t0);
fprintf('湿度绘图完成，用时 %.2f 秒', elapsed);
end

function plot_humidity_frequency(vals, point_id, root_dir, start_date, end_date)
% plot_humidity_frequency 绘制湿度累积频次分布(%)
%   vals: 湿度值数组
%   区间: 20-30,30-40,...,90-100
bins = 20:10:100;
counts = histcounts(vals, bins);
total = sum(counts);
percent = counts/total*100;

% 绘制柱状图
fig = figure('Position',[100 100 1000 469]);
bar(percent, 'FaceColor','flat');
xticks(1:length(counts));
xticklabels({'20-30','30-40','40-50','50-60','60-70','70-80','80-90','90-100'});
%ylabel('累积持续时间频次 (%)');
%xlabel('湿度区间 (%)');
ylabel('环境湿度累积持续时间频次分布 (%)');
xlabel('环境湿度范围 (%)');
title(sprintf('测点 %s 湿度频次分布', point_id));
grid on; grid minor;
% 添加百分比标注
for k=1:length(percent)
    text(k, percent(k)+1, sprintf('%.2f%%',percent(k)), 'HorizontalAlignment','center');
end
% 保存
timestamp = datestr(now,'yyyy-mm-dd_HH-MM-SS');
outdir = fullfile(root_dir,'频次分布_湿度'); if ~exist(outdir,'dir'), mkdir(outdir); end
fname = sprintf('%s_freq_%s_%s', point_id, datestr(datenum(start_date),'yyyymmdd'), datestr(datenum(end_date),'yyyymmdd'));
saveas(fig, fullfile(outdir,[fname '_' timestamp '.jpg']));
saveas(fig, fullfile(outdir,[fname '_' timestamp '.emf']));
savefig(fig,fullfile(outdir,[fname '_' timestamp '.fig']),'compact');
close(fig);
end
