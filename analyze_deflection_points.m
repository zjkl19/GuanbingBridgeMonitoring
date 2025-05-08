function analyze_deflection_points(root_dir, start_date, end_date, excel_file, subfolder, useMedianFilter)
% analyze_deflection_points 批量绘制主梁位移（挠度）时程曲线并统计指标
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date,end_date: 日期范围，'yyyy-MM-dd'
%   excel_file: 输出统计 Excel，如 'deflection_stats.xlsx'
%   subfolder: 数据所在子文件夹，默认 '特征值_重采样'
%   useMedianFilter: 是否对最终时序做中值滤波 (true/false)，默认 false

if nargin<1||isempty(root_dir),    root_dir = pwd; end
if nargin<2||isempty(start_date),   start_date = input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<3||isempty(end_date),     end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
if nargin<4||isempty(excel_file),   excel_file = 'deflection_stats.xlsx'; end
if nargin<5||isempty(subfolder),    subfolder  = '特征值_重采样'; end
if nargin<6||isempty(useMedianFilter), useMedianFilter = false;      end

% 定义测点分组（Y通道）
groups = { ...
    {'GB-DIS-G05-001-01Y','GB-DIS-G05-001-02Y'}, ...
    {'GB-DIS-G05-002-01Y','GB-DIS-G05-002-02Y','GB-DIS-G05-002-03Y'}, ...
    {'GB-DIS-G05-003-01Y','GB-DIS-G05-003-02Y'}, ...
    {'GB-DIS-G06-001-01Y','GB-DIS-G06-001-02Y'}, ...
    {'GB-DIS-G06-002-01Y','GB-DIS-G06-002-02Y','GB-DIS-G06-002-03Y'}, ...
    {'GB-DIS-G06-003-01Y','GB-DIS-G06-003-02Y'} ...
    };

% 结果存储，行：测点，列：PID, Min, Max, Mean
def_stats = {};
row = 1;
% 遍历每组
for g = 1:numel(groups)
    pid_list = groups{g};
    fprintf('处理组 %d: %s\n', g, strjoin(pid_list, ', '));
    % 先对每个点统计
    for i = 1:numel(pid_list)
        pid = pid_list{i};
        [times, vals] = extract_deflection_data(root_dir, subfolder, pid, start_date, end_date, useMedianFilter);
        if isempty(vals)
            warning('测点 %s 无数据，跳过。', pid);
            continue;
        end
        def_stats(row,1:4) = {pid, round(min(vals),1), round(max(vals),1), round(mean(vals),1)};
        row = row + 1;
    end
    % 然后绘制本组曲线
    plot_deflection_curve(root_dir, subfolder, pid_list, start_date, end_date, g, useMedianFilter);
end

% 写入 Excel
T = cell2table(def_stats, 'VariableNames', {'PointID','Min_mm','Max_mm','Mean_mm'});
writetable(T, excel_file);
fprintf('挠度统计已保存至 %s\n', excel_file);
end

function [all_time, all_val] = extract_deflection_data(root_dir, subfolder, point_id, start_date, end_date, useMedianFilter)
% extract_deflection_data 提取挠度数据（单位 mm）
all_time = [];
all_val  = [];
dn0 = datenum(start_date,'yyyy-mm-dd');
dn1 = datenum(end_date,  'yyyy-mm-dd');
dinfo = dir(fullfile(root_dir,'20??-??-??')); folders = {dinfo([dinfo.isdir]).name};
dates = folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
for j = 1:numel(dates)
    day = dates{j};
    dirp = fullfile(root_dir, day, subfolder);
    if ~exist(dirp,'dir'), continue; end
    files = dir(fullfile(dirp,'*.csv'));
    idx = find(arrayfun(@(f) contains(f.name, point_id), files),1);
    if isempty(idx), continue; end
    fullpath = fullfile(dirp, files(idx).name);
    % 检测头部行数
    fid = fopen(fullpath,'rt'); h = 0;
    for k = 1:50
        if feof(fid), break; end
        ln = fgetl(fid); h = h + 1;
        if contains(ln,'[绝对时间]'), break; end
    end
    fclose(fid);
    % 读取数据
    T = readtable(fullpath, 'Delimiter', ',', 'HeaderLines', h, 'Format', '%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
    
    times = T{:,1}; vals = T{:,2};
    % === 基础清洗 ===
    % 阈值过滤：超出 [-100,100] 置 NaN
    vals = clean_threshold(vals, times, struct('min', 0, 'max', 31, 't_range', []));
    % 去除 0 值
    vals = clean_zero(vals, times, struct('t_range', []));
    % 示例：针对特殊测点额外清洗
    % if strcmp(point_id, 'GB-DIS-G05-001-02Y')
    %     vals = clean_threshold(vals, times, struct('min', -20, 'max', 20, 't_range', [datetime('2025-02-28 20:00:00'), datetime('2025-02-28 23:00:00')]));
    % end
    if strcmp(point_id, 'GB-DIS-G05-001-01Y')
        vals = clean_threshold(vals, times, struct('min', -1, 'max', 26, 't_range', []));
    end
    if strcmp(point_id, 'GB-DIS-G05-001-02Y')
        vals = clean_threshold(vals, times, struct('min', -1, 'max', 22, 't_range', []));
    end
    if strcmp(point_id, 'GB-DIS-G06-001-01Y')
        vals = clean_threshold(vals, times, struct('min', -2, 'max', 19, 't_range', []));
    end
    if strcmp(point_id, 'GB-DIS-G06-001-02Y')
        vals = clean_threshold(vals, times, struct('min', -2, 'max', 19, 't_range', []));
    end
    if strcmp(point_id, 'GB-DIS-G06-003-01Y')
        vals = clean_threshold(vals, times, struct('min', -2, 'max', 20, 't_range', []));
    end
    % =====================
    all_time = [all_time; times];
    all_val  = [all_val;  vals];
end
% 排序
[all_time, idx] = sort(all_time);
all_val = all_val(idx);
% === 新增：中值滤波 ===
if useMedianFilter && numel(all_val)>=3
    % 1) 估算采样频率
    dt = seconds(all_time(2) - all_time(1));  % 单位秒
    fs = 1/dt;                               % 实际采样频率 (Hz)
    
    % 2) 设定时间窗长度（秒），可根据需求调整
    window_sec = 0.5;                        % 半秒窗
    win_len = max(3, round(window_sec * fs));  % 至少 3 点
    if mod(win_len,2)==0
        win_len = win_len + 1;               % 确保为奇数
    end
    
    % 3) 执行零相位中值滤波
    all_val = medfilt1(all_val, win_len);
end
end

function plot_deflection_curve(root_dir, subfolder, pid_list, start_date, end_date, group_idx, useMedianFilter)
% plot_deflection_curve 绘制一组挠度时程曲线
fig = figure('Position',[100 100 1000 469]); hold on;
dn0 = datenum(start_date,'yyyy-mm-dd'); dn1 = datenum(end_date,'yyyy-mm-dd');
% 绘制多条曲线并生成句柄
h = gobjects(numel(pid_list),1);
for i = 1:numel(pid_list)
    [t, v] = extract_deflection_data(root_dir, subfolder, pid_list{i}, start_date, end_date, useMedianFilter);
    h(i) = plot(t, v, 'LineWidth', 1);
end
lg=legend(h, pid_list, 'Location','northeast', 'Box','off');
lg.AutoUpdate = 'off';
% X 刻度
numDiv = 4;
ticks = datetime(linspace(dn0, dn1, numDiv+1), 'ConvertFrom','datenum');
ax = gca; ax.XLim = ticks([1 end]); ax.XTick = ticks; xtickformat('yyyy-MM-dd');
xlabel('时间'); ylabel('主梁位移 (mm)');
title(sprintf('挠度时程曲线 组%d', group_idx));

% 添加二级预警线（黄色）
yline(-21.0, '--', '二级报警值-21.0', 'LabelHorizontalAlignment','left', 'Color',[0.9290 0.6940 0.1250]);
yline( 33.4, '--', '二级报警值33.4',  'LabelHorizontalAlignment','left', 'Color',[0.9290 0.6940 0.1250]);
% 添加三级预警线（红色）
yline(-26.3, '--', '三级报警值-26.3', 'LabelHorizontalAlignment','left', 'Color',[1 0 0]);
yline( 41.7, '--', '三级报警值41.7',  'LabelHorizontalAlignment','left', 'Color',[1 0 0]);

% Y 轴范围切换
tmp_manual = true;
if tmp_manual
    ylim([-40, 50]);
else
    ylim auto;
end
grid on; grid minor;

% 保存 JPG, EMF, FIG
ts = datestr(now,'yyyymmdd_HHMMSS');
out = fullfile(root_dir, '时程曲线_挠度'); if ~exist(out,'dir'), mkdir(out); end
fname = sprintf('Defl_G%d_%s_%s', group_idx, datestr(dn0,'yyyymmdd'), datestr(dn1,'yyyymmdd'));
saveas(fig, fullfile(out, [fname '_' ts '.jpg']));
saveas(fig, fullfile(out, [fname '_' ts '.emf']));
savefig(fig, fullfile(out, [fname '_' ts '.fig']), 'compact');
close(fig);
end
