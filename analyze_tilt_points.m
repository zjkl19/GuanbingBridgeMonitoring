function analyze_tilt_points(root_dir, start_date, end_date, excel_file, subfolder)
% analyze_tilt_points 批量绘制倾角时程曲线并统计指标（重构）
%   root_dir:      根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date:    开始日期 'yyyy-MM-dd'
%   end_date:      结束日期 'yyyy-MM-dd'
%   excel_file:    输出统计 Excel，如 'tilt_stats.xlsx'
%   subfolder:     数据所在子文件夹，默认 '波形_重采样'

if nargin<1||isempty(root_dir),    root_dir  = pwd;           end
if nargin<2||isempty(start_date),  start_date = input('开始日期: ','s'); end
if nargin<3||isempty(end_date),    end_date   = input('结束日期: ','s'); end
if nargin<4||isempty(excel_file),  excel_file = 'tilt_stats.xlsx';end
if nargin<5||isempty(subfolder),   subfolder  = '波形_重采样';    end

% 测点分组
groupX = {'GB-DIS-P04-001-01-X','GB-DIS-P05-001-01-X','GB-DIS-P06-001-01-X'};
groupY = {'GB-DIS-P04-001-01-Y','GB-DIS-P05-001-01-Y','GB-DIS-P06-001-01-Y'};

% 处理 X 组
[statsX, dataX] = process_group(root_dir, subfolder, groupX, start_date, end_date, 'X');
plot_tilt_curve(dataX, start_date, end_date, 'X');

% 处理 Y 组
[statsY, dataY] = process_group(root_dir, subfolder, groupY, start_date, end_date, 'Y');
plot_tilt_curve(dataY, start_date, end_date, 'Y');

% 写入 Excel
T_X = cell2table(statsX, 'VariableNames', {'PointID','Min','Max','Mean'});
T_Y = cell2table(statsY, 'VariableNames', {'PointID','Min','Max','Mean'});
writetable(T_X, excel_file, 'Sheet','Tilt_X');
writetable(T_Y, excel_file, 'Sheet','Tilt_Y');
fprintf('倾角统计已保存至 %s\n', excel_file);
end


function [stats, dataList] = process_group(root, subfolder, pids, t0, t1, suffix)
% 一次性抽取所有 PID 的 times/vals 并统计
n = numel(pids);
stats    = cell(n,4);
dataList = struct('pid',cell(n,1),'times',[],'vals',[]);
for i = 1:n
    pid = pids{i};
    fprintf('抽取 %s ...\n', pid);
    [times, vals] = extract_tilt_data(root, subfolder, pid, t0, t1);
    if isempty(vals)
        warning('测点 %s 无数据，跳过。', pid);
        continue;
    end
    stats(i,:) = {pid, round(min(vals),3), round(max(vals),3), round(mean(vals),3)};
    dataList(i).pid   = pid;
    dataList(i).times = times;
    dataList(i).vals  = vals;
end
end


function plot_tilt_curve(dataList, t0, t1, suffix)
% plot_tilt_curve 绘制一组倾角曲线（不再重复 I/O）
fig = figure('Position',[100 100 1000 469]); hold on;

dn0 = datenum(t0,'yyyy-mm-dd'); dn1 = datenum(t1,'yyyy-mm-dd');

% 多条曲线
hLines = gobjects(numel(dataList),1);
for i = 1:numel(dataList)
    d = dataList(i);
    if isempty(d.vals), continue; end
    hLines(i) = plot(d.times, d.vals, 'LineWidth',1);
end
legend(hLines, {dataList.pid}, 'Location','northeast','Box','off');
lg = legend; lg.AutoUpdate = 'off';

% X 轴刻度
numDiv = 4;
ticks = datetime(linspace(dn0,dn1,numDiv+1),'ConvertFrom','datenum');
ax = gca; ax.XLim = ticks([1 end]); ax.XTick = ticks;
xtickformat('yyyy-MM-dd');
xlabel('时间'); ylabel('倾角 (°)');
title(['倾角时程曲线 ' suffix]);

% 报警线
yVals = [-0.126,0.126,-0.155,0.155];
labels = {'二级报警值-0.126','二级报警值0.126','三级报警值-0.155','三级报警值0.155'};
colors = [0.9290 0.6940 0.1250;0.9290 0.6940 0.1250;1 0 0;1 0 0];
for k = 1:4
    yl = yline(yVals(k), '--');
    yl.Color = colors(k,:);
    yl.Label = labels{k};
    yl.LabelHorizontalAlignment = 'left';
end

% Y 范围
tmp_manual = true;
if tmp_manual, ylim([-0.17,0.17]); else, ylim auto; end

grid on; grid minor;

% 保存
ts = datestr(now,'yyyymmdd_HHMMSS');
out = fullfile(pwd, ['时程曲线_倾角_' suffix]); if ~exist(out,'dir'), mkdir(out); end
fname = sprintf('Tilt_%s_%s_%s', suffix, datestr(dn0,'yyyymmdd'), datestr(dn1,'yyyymmdd'));
saveas(fig, fullfile(out, [fname '_' ts '.jpg']));
saveas(fig, fullfile(out, [fname '_' ts '.emf']));
savefig(fig, fullfile(out, [fname '_' ts '.fig']), 'compact');
close(fig);
end


function [times, vals] = extract_tilt_data(root, subfolder, pid, t0, t1)
% extract_tilt_data 提取倾角数据
all_t = []; all_v = [];
dn0 = datenum(t0,'yyyy-mm-dd'); dn1 = datenum(t1,'yyyy-mm-dd');
dinfo = dir(fullfile(root,'20??-??-??')); folders = {dinfo([dinfo.isdir]).name};
dates = folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
for j = 1:numel(dates)
    dirp = fullfile(root, dates{j}, subfolder);
    if ~exist(dirp,'dir'), continue; end
    files = dir(fullfile(dirp,'*.csv'));
    idx = find(arrayfun(@(f) contains(f.name,pid),files),1);
    if isempty(idx), continue; end
    fp = fullfile(files(idx).folder, files(idx).name);
    fid = fopen(fp,'rt'); h=0;
    while h<50 && ~feof(fid)
        ln = fgetl(fid); h=h+1;
        if contains(ln,'[绝对时间]'), break; end
    end; fclose(fid);
    T = readtable(fp,'Delimiter',',','HeaderLines',h,'Format','%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
    all_t = [all_t; T{:,1}]; all_v = [all_v; T{:,2}];
end
[times, ix] = sort(all_t); vals = all_v(ix);
end
