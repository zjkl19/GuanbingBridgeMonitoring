function plot_temperature_point_curve(root_dir, point_id, start_date, end_date)
% plot_temperature_point_curve 指定测点温度时程曲线
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   point_id: 测点编号，例如 'GB-RTS-G05-001-03'
%   start_date, end_date: 日期范围，'yyyy-MM-dd'

if nargin<1||isempty(root_dir)
    root_dir = 'F:/管柄大桥健康监测数据/';
end
if nargin<2||isempty(point_id)
    error('请提供测点编号 point_id');
end
if nargin<3||isempty(start_date)
    start_date = input('开始日期 (yyyy-MM-dd): ','s');
end
if nargin<4||isempty(end_date)
    end_date   = input('结束日期 (yyyy-MM-dd): ','s');
end

% 开始计时
t0 = tic;

% 转日期并筛选文件夹
dn0 = datenum(start_date,'yyyy-mm-dd');
dn1 = datenum(end_date,  'yyyy-mm-dd');
dinfo = dir(fullfile(root_dir,'20??-??-??'));
folders = {dinfo([dinfo.isdir]).name};
dates  = folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
if isempty(dates)
    error('在指定日期范围内未找到日期文件夹');
end

all_time = [];
all_val  = [];

% 汇总各日数据
for i = 1:numel(dates)
    day      = dates{i};
    dir_path = fullfile(root_dir, day, '特征值');
    if ~exist(dir_path,'dir')
        warning('日期 %s 下不存在 特征值 文件夹，跳过', day);
        continue;
    end
    files = dir(fullfile(dir_path,'*.csv'));
    % 匹配文件
    idxs = arrayfun(@(f) contains(f.name, point_id), files);
    matches = files(idxs);
    if isempty(matches)
        warning('日期 %s 未找到匹配 %s 的文件', day, point_id);
        continue;
    elseif numel(matches) > 1
        warning('日期 %s 找到多个匹配文件，仅使用第1个: %s', day, matches(1).name);
    end
    fname    = matches(1).name;
    fullpath = fullfile(dir_path, fname);
    % 检测头部前50行
    fid    = fopen(fullpath,'rt');
    header = 0; found = false;
    for j = 1:50
        if feof(fid), break; end
        line = fgetl(fid);
        header = header + 1;
        if contains(line,'[绝对时间]')
            found = true;
            break;
        end
    end
    fclose(fid);
    if ~found
        warning('文件 %s 未检测到头部，已跳过', fname);
        continue;
    end
    % 读取数据
    T = readtable(fullpath, 'Delimiter', ',', 'HeaderLines', header, 'Format', '%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
    all_time = [all_time; T{:,1}];
    all_val  = [all_val;  T{:,2}];
end
% 排序
[all_time, sort_idx] = sort(all_time);
all_val = all_val(sort_idx);

% 绘图
fig = figure('Position',[100 100 1000 469]);
plot(all_time, all_val, 'LineWidth', 1);
ylim([0,35]);
% 强制显示大约4等分刻度，并包含起止日期
numDivisions = 4;  % 近似4等分
tickNums = linspace(datenum(start_date,'yyyy-mm-dd'), datenum(end_date,'yyyy-mm-dd'), numDivisions+1);
ticks = datetime(tickNums, 'ConvertFrom', 'datenum');
ax = gca;
ax.XLim  = ticks([1 end]);
ax.XTick = ticks;
xtickformat('yyyy-MM-dd');
hold on;
avg_val = mean(all_val);
yl = yline(avg_val, '--r');
yl.Label = sprintf('平均值 %.1f', avg_val);
yl.LabelHorizontalAlignment = 'center';
yl.LabelVerticalAlignment = 'bottom';
yl.FontSize = 12;
grid on; grid minor;
title(sprintf('测点 %s 环境温度时程曲线', point_id));
xlabel('时间');
ylabel('环境温度（℃）');

% 保存图像
timestamp  = datestr(now,'yyyy-mm-dd_HH-MM-SS');
output_dir = fullfile(root_dir,'时程曲线');
if ~exist(output_dir,'dir'), mkdir(output_dir); end
base = sprintf('%s_%s_%s', point_id, datestr(dn0,'yyyymmdd'), datestr(dn1,'yyyymmdd'));
saveas(fig, fullfile(output_dir, [base '_' timestamp '.jpg']));
saveas(fig, fullfile(output_dir, [base '_' timestamp '.emf']));
savefig(fig, fullfile(output_dir, [base '_' timestamp '.fig']), 'compact');
close;
elapsed = toc(t0);
fprintf('时程绘图完成，用时 %.2f 秒', elapsed);
end
