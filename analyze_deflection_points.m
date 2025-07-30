function analyze_deflection_points(root_dir, start_date, end_date, excel_file, subfolder)
% analyze_deflection_points 批量绘制主梁位移（挠度）时程曲线并统计原始及中值滤波数据指标
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date,end_date: 日期范围，'yyyy-mm-dd'
%   excel_file: 输出统计 Excel，如 'deflection_stats.xlsx'
%   subfolder: 数据所在子文件夹，默认 '特征值_重采样'

if nargin<1||isempty(root_dir),    root_dir = pwd; end
if nargin<2||isempty(start_date),   start_date = input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<3||isempty(end_date),     end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
if nargin<4||isempty(excel_file),   excel_file = 'deflection_stats.xlsx'; end
if nargin<5||isempty(subfolder),    subfolder  = '特征值_重采样'; end

% 定义测点分组（Y通道）
groups = { ...
    {'GB-DIS-G05-001-01Y','GB-DIS-G05-001-02Y'}, ...
    {'GB-DIS-G05-002-01Y','GB-DIS-G05-002-02Y','GB-DIS-G05-002-03Y'}, ...
    {'GB-DIS-G05-003-01Y','GB-DIS-G05-003-02Y'}, ...
    {'GB-DIS-G06-001-01Y','GB-DIS-G06-001-02Y'}, ...
    {'GB-DIS-G06-002-01Y','GB-DIS-G06-002-02Y','GB-DIS-G06-002-03Y'}, ...
    {'GB-DIS-G06-003-01Y','GB-DIS-G06-003-02Y'} ...
    };

% 初始化统计：PointID, OrigMin, OrigMax, OrigMean, FiltMin, FiltMax, FiltMean
stats = {};
row = 1;
for g = 1:numel(groups)
    pid_list = groups{g};
    fprintf('处理组 %d: %s\n', g, strjoin(pid_list, ', '));
    % 准备存储原始与滤波数据
    N = numel(pid_list);
    orig_times = cell(N,1);
    orig_vals  = cell(N,1);
    filt_times = cell(N,1);
    filt_vals  = cell(N,1);
    for i = 1:N
        pid = pid_list{i};
        [times, vals] = extract_deflection_data(root_dir, subfolder, pid, start_date, end_date);
        if isempty(vals)
            warning('测点 %s 无数据，跳过。', pid);
            continue;
        end
         % 动态计算中值滤波窗口长度
        if numel(times) >= 2
            dts = seconds(diff(times));
            fs = 1/median(dts);
            win_samps = round(fs * 10);        % x 秒窗口

            window_sec = 10*60;                        % 10分钟窗
            %win_len = max(201, round(window_sec * fs));  % 至少201点
            win_len =  round(window_sec * fs);
            if mod(win_len,2)==0, win_len = win_len + 1; end
        else
            win_len=201;
        end
        disp("第" + i+ "个测点采样频率 "+fs+"Hz");
       disp(['中值滤波窗口长度: ', num2str(win_len)]);
        % 中值滤波
        
        %vals_f = medfilt1(vals, win_len);
        win_samps = round(fs * 10*600);
        vals_f =movmedian(vals, win_samps, 'omitnan');
        % 统计（都忽略 NaN）
        orig_times{i} = times;    orig_vals{i} = vals;
        filt_times{i} = times;    filt_vals{i} = vals_f;
        % 统计
        stats(row, :) = {
            pid, ...
            round(min(vals),1), round(max(vals),1), round(mean(vals,  'omitnan'), 1), ...
            round(min(vals_f),1), round(max(vals_f),1), round(mean(vals_f,  'omitnan'), 1)};
        row = row + 1;
    end
    % 绘制原始数据组曲线
    plot_deflection_curve(orig_times, orig_vals, pid_list, root_dir, start_date, end_date, g);
    % 绘制滤波后数据组曲线
    plot_deflection_curve(filt_times, filt_vals, pid_list, root_dir, start_date, end_date, g);
    
     clear orig_times orig_vals filt_times filt_vals
end
% 写入 Excel
T = cell2table(stats, 'VariableNames', ...
    {'PointID','OrigMin_mm','OrigMax_mm','OrigMean_mm','FiltMin_mm','FiltMax_mm','FiltMean_mm'});
writetable(T, excel_file);
fprintf('挠度统计已保存至 %s\n', excel_file);
end

function [all_time, all_val] = extract_deflection_data(root_dir, subfolder, point_id, start_date, end_date)
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
    % ==== 缓存机制开始 ====
    cacheDir = fullfile(dirp, 'cache');
    if ~exist(cacheDir,'dir'), mkdir(cacheDir); end

    [~, name, ~] = fileparts(fullpath);
    cacheFile = fullfile(cacheDir, [name '.mat']);
    useCache = false;

    if exist(cacheFile,'file')
        infoCSV = dir(fullpath);
        infoMAT = dir(cacheFile);
        % 只有当 MAT 比 CSV 新时才用缓存
        if datenum(infoMAT.date) > datenum(infoCSV.date)
            tmp = load(cacheFile, 'times','vals');
            times = tmp.times;
            vals  = tmp.vals;
            useCache = true;
        end
    end

    if ~useCache
        % 从 CSV 读
        T = readtable(fullpath, ...
            'Delimiter',',', ...
            'HeaderLines',h, ...
            'Format','%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
        times = T{:,1};
        vals  = T{:,2};
        % 写入缓存
        save(cacheFile, 'times','vals');
    end
    % ==== 缓存机制结束 ====

    % === 基础清洗 ===
    % 阈值过滤：超出 [-100,100] 置 NaN
    vals = clean_threshold(vals, times, struct('min', -3, 'max', 31, 't_range', []));
    % 去除 0 值
    vals = clean_zero(vals, times, struct('t_range', []));

   % === 去除短时尖刺（秒窗口移动中值法）===
   if numel(vals)>=2
       % 估计采样频率 fs
            dts = seconds(diff(times));
            fs = 1/median(dts);
       win_samps = round(fs * 15);        % x 秒窗口
       % 找出移动中值离群点
       mask = isoutlier(vals, 'movmedian', win_samps,'ThresholdFactor', 3);
       vals(mask) = NaN;
   end
   % =====================
    % 示例：针对特殊测点额外清洗
    
     if strcmp(point_id, 'GB-DIS-G05-001-02Y')
         vals = clean_threshold(vals, times, struct('min', 4.0, 'max', 25, 't_range', [datetime('2025-04-10 20:00:00'), datetime('2025-04-10 22:00:00')]));
         vals = clean_threshold(vals, times, struct('min', -1.5, 'max', 22, 't_range', [datetime('2025-04-14 00:00:00'), datetime('2025-04-14 08:00:00')]));
     end
    % if strcmp(point_id, 'GB-DIS-G05-001-01Y')
    %     vals = clean_threshold(vals, times, struct('min', -1, 'max', 26, 't_range', []));
    %     vals = clean_threshold(vals, times, struct('min', -20, 'max', 13.5, 't_range', [datetime('2025-03-29 13:00:00'), datetime('2025-04-01 20:00:00')]));
    % end
    % if strcmp(point_id, 'GB-DIS-G05-001-02Y')
    %     vals = clean_threshold(vals, times, struct('min', -1, 'max', 22, 't_range', []));
    %     vals = clean_threshold(vals, times, struct('min', -20, 'max', 13.5, 't_range', [datetime('2025-03-29 13:00:00'), datetime('2025-04-01 20:00:00')]));
    % end
    % if strcmp(point_id, 'GB-DIS-G05-002-03Y')
    %     vals = clean_threshold(vals, times, struct('min', 2, 'max', 40, 't_range', [datetime('2025-04-09 00:00:00'), datetime('2025-04-21 23:00:00')]));
    % end
    if strcmp(point_id, 'GB-DIS-G05-003-01Y')
        vals = clean_threshold(vals, times, struct('min', 0.1, 'max', 40, 't_range', [datetime('2025-04-03 00:00:00'), datetime('2025-04-20 08:00:00')]));
    end
    % if strcmp(point_id, 'GB-DIS-G05-003-02Y')
    %     vals = clean_threshold(vals, times, struct('min', 2, 'max', 40, 't_range', [datetime('2025-04-02 00:00:00'), datetime('2025-04-20 23:00:00')]));
    % end
    if ismember(point_id, {'GB-DIS-G06-001-01Y','GB-DIS-G06-001-02Y'})
        vals = clean_threshold(vals, times, struct('min', -2, 'max', 9, 't_range', [datetime('2025-04-20 00:00:00'), datetime('2025-04-22 08:00:00')]));
    end
    if strcmp(point_id, 'GB-DIS-G06-001-02Y')
        vals = clean_threshold(vals, times, struct('min', -2, 'max', 20, 't_range', []));
    end
    if ismember(point_id, {'GB-DIS-G06-002-01Y','GB-DIS-G06-002-02Y', 'GB-DIS-G06-002-03Y'})
        vals = clean_threshold(vals, times, struct('min', -2, 'max', 25.0, 't_range', [datetime('2025-04-07 22:00:00'), datetime('2025-04-25 08:00:00')]));
        vals = clean_threshold(vals, times, struct('min', -2, 'max', 18.0, 't_range', [datetime('2025-04-19 22:40:00'), datetime('2025-04-25 08:00:00')]));
    end

    if ismember(point_id, {'GB-DIS-G06-003-01Y','GB-DIS-G06-003-02Y'})
        vals = clean_threshold(vals, times, struct('min', -2, 'max', 16, 't_range', [datetime('2025-04-05 00:00:00'), datetime('2025-04-25 08:00:00')]));
        vals = clean_threshold(vals, times, struct('min', -2, 'max', 12, 't_range', [datetime('2025-04-19 09:00:00'), datetime('2025-04-25 08:00:00')]));
    end
    % if strcmp(point_id, 'GB-DIS-G06-002-01Y')
    %     vals = clean_threshold(vals, times, struct('min', -3, 'max', 28, 't_range', []));
    %     vals = clean_threshold(vals, times, struct('min', -3, 'max', 25, 't_range', [datetime('2025-04-23 00:00:00'), datetime('2025-04-25 23:00:00')]));
    % end
    % if strcmp(point_id, 'GB-DIS-G06-002-02Y')
    %     vals = clean_threshold(vals, times, struct('min', -3, 'max', 26, 't_range', []));
    %     vals = clean_threshold(vals, times, struct('min', -3, 'max', 25, 't_range', [datetime('2025-04-23 00:00:00'), datetime('2025-04-25 23:00:00')]));
    % end
    % if strcmp(point_id, 'GB-DIS-G06-002-03Y')
    %     vals = clean_threshold(vals, times, struct('min', -2, 'max', 27, 't_range', []));
    %     vals = clean_threshold(vals, times, struct('min', -3, 'max', 25, 't_range', [datetime('2025-04-23 00:00:00'), datetime('2025-04-25 23:00:00')]));
    % end
    % if strcmp(point_id, 'GB-DIS-G06-003-01Y')
    %     vals = clean_threshold(vals, times, struct('min', -2, 'max', 16, 't_range', []));
    % end
    % if strcmp(point_id, 'GB-DIS-G06-003-02Y')
    %     vals = clean_threshold(vals, times, struct('min', -2, 'max', 16, 't_range', []));
    % end
    % =====================
    all_time = [all_time; times];
    all_val  = [all_val;  vals];
end
% 排序
[all_time, idx] = sort(all_time);
all_val = all_val(idx);

end

function plot_deflection_curve(times_list, vals_list, pid_list,  root_dir, start_date, end_date, group_idx)
% plot_deflection_curve 绘制一组挠度时程曲线
fig = figure('Position',[100 100 1000 469]); hold on;
dn0 = datenum(start_date,'yyyy-mm-dd'); dn1 = datenum(end_date,'yyyy-mm-dd');
% 绘制多条曲线并生成句柄
h = gobjects(numel(pid_list),1);

N = numel(pid_list);

% 2条线：蓝、绿；3条线：紫、蓝、绿
colors_2 = {[0 0 1], [0 0.7 0]};                  % 蓝，绿
colors_3 = {[0.5 0 0.7], [0 0 1], [0 0.7 0]};     % 紫，蓝，绿

for i = 1:N
    if N == 2
        c = colors_2{i};
    elseif N == 3
        c = colors_3{i};
    else
        cmap = lines(N);   % 默认Matlab配色
        c = cmap(i,:);
    end
    plot(times_list{i}, vals_list{i}, 'LineWidth', 1.0, 'Color', c);
end

lg=legend(pid_list,'Location','northeast','Box','off');
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
