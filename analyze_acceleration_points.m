function analyze_acceleration_points(root_dir, start_date, end_date, excel_file, subfolder, auto_detect_fs)
% analyze_acceleration_points 批量绘制加速度时程曲线并统计指标
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date,end_date: 日期范围，'yyyy-MM-dd'
%   excel_file: 输出统计 Excel，如 'accel_stats.xlsx'
%   subfolder: 数据所在子文件夹，默认 '波形_重采样'
%   auto_detect_fs: 是否自动检测采样频率，true：自动检测，false（默认）：100 Hz

if nargin<1||isempty(root_dir),    root_dir = pwd; end
if nargin<2||isempty(start_date),   start_date = input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<3||isempty(end_date),     end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
if nargin<4||isempty(excel_file),   excel_file = 'accel_stats.xlsx'; end
if nargin<5||isempty(subfolder),    subfolder  = '波形_重采样'; end
if nargin<6 || isempty(auto_detect_fs)
    auto_detect_fs = false;
end

% 记录开始时间
time_start = datetime('now');
fprintf('开始时间: %s\n', datestr(time_start,'yyyy-mm-dd HH:MM:SS'));

% 测点列表
tpts = { ...
    'GB-VIB-G04-001-01','GB-VIB-G05-001-01','GB-VIB-G05-002-01','GB-VIB-G05-003-01', ...
    'GB-VIB-G06-001-01','GB-VIB-G06-002-01','GB-VIB-G06-003-01','GB-VIB-G07-001-01'};

% 初始化统计
stats = cell(numel(tpts),6);

for i = 1:numel(tpts)
    pid = tpts{i}; fprintf('处理测点 %s ...\n', pid);
    [times, vals] = extract_accel_data(root_dir, subfolder, pid, start_date, end_date);
    if isempty(vals)
        warning('测点 %s 无数据，跳过。', pid);
        continue;
    end
    % === 计算采样频率和窗口长度 ===
    if auto_detect_fs
        % 先确保 times 是 datetime 向量并且有至少 2 个点
        dts = seconds(diff(times));
        fs = 1 / median(dts);  % 用中值更健壮
        fprintf('自动检测采样频率: %.2f Hz\n', fs);
    else
        fs = 100;  % 默认采样频率
        fprintf('使用默认采样频率: %d Hz\n', fs);
    end
    window_sec = 10 * 60;          % 10 分钟
    win_len    = round(window_sec * fs);

    % 统计值 (保留3位小数)
    mn = round(min(vals),3);
    mx = round(max(vals),3);
    av = round(mean(vals),3);
    % 10min RMS 最大值
    if numel(vals) >= win_len
        rms_vals = sqrt(movmean(vals.^2, win_len, 'Endpoints','shrink'));
        [rms_max, idx] = max(rms_vals);
        rms_max = round(rms_max,3);
        rms_time = times(idx);
    else
        rms_max = NaN;
        rms_time = NaT;
    end
    stats(i,:) = {pid, mn, mx, av, rms_max,rms_time};
    % 绘图
    plot_accel_curve(root_dir,pid, times, vals, mn, mx);
    
    % === 新增：10 min RMS 全时程曲线（独立出图） ===
    plot_accel_rms_curve(root_dir, pid, times, vals, fs, start_date, end_date);
end

% 写入 Excel
T = cell2table(stats, 'VariableNames',{'PointID','Min','Max','Mean','RMS10minMax','RMSStartTime'});
writetable(T, excel_file);
fprintf('统计结果已保存至 %s\n', excel_file);

% 记录结束时间并输出总耗时
time_end = datetime('now');
fprintf('结束时间: %s\n', datestr(time_end,'yyyy-mm-dd HH:MM:SS'));
elapsed = seconds(time_end - time_start);
fprintf('总用时: %.2f 秒\n', elapsed);
end

function [all_time, all_val] = extract_accel_data(root_dir, subfolder, point_id, start_date, end_date)
% 提取加速度数据
all_time=[]; all_val=[];
dn0 = datenum(start_date,'yyyy-mm-dd'); dn1 = datenum(end_date,'yyyy-mm-dd');
dinfo = dir(fullfile(root_dir,'20??-??-??')); folders={dinfo([dinfo.isdir]).name};
dates = folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
for j=1:numel(dates)
    day = dates{j};
    dirp = fullfile(root_dir, day, subfolder);
    if ~exist(dirp,'dir'), continue; end
    files = dir(fullfile(dirp,'*.csv'));
    idx = find(arrayfun(@(f) contains(f.name, point_id), files),1);
    if isempty(idx), continue; end
    fp = fullfile(dirp, files(idx).name);
    % 头部检测
    fid = fopen(fp,'rt');
    h = 0;
    found = false;               % ← 初始化 found
    for k=1:50
        if feof(fid), break; end
        ln = fgetl(fid); h=h+1;
        if contains(ln,'[绝对时间]')
            found = true; 
            break;
        end
    end
    if ~found
       warning('提示：文件 %s 未检测到头部标记 “[绝对时间]”，使用 h=0 读取全部作为数据', fp);
       h = 0;                  % ← 避免把所有行当成 header 跳过
    end
    fclose(fid);
    
% ==== 缓存机制开始 =========================
    cacheDir = fullfile(dirp,'cache');
    if ~exist(cacheDir,'dir'), mkdir(cacheDir); end

    [~,name,~] = fileparts(fp);
    cacheFile  = fullfile(cacheDir,[name '.mat']);
    useCache   = false;

    if exist(cacheFile,'file')
        infoCSV = dir(fp);
        infoMAT = dir(cacheFile);
        % 仅当 MAT 更新且较新才使用
        if datenum(infoMAT.date) > datenum(infoCSV.date)
            tmp      = load(cacheFile,'times','vals');
            times    = tmp.times;
            vals     = tmp.vals;
            useCache = true;
        end
    end

    if ~useCache
        % 从 CSV 读取并写缓存
        T = readtable(fp, ...
            'Delimiter',',', ...
            'HeaderLines',h, ...
            'Format','%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
        times = T{:,1};
        vals  = T{:,2};
        save(cacheFile,'times','vals');
    end
    % ==== 缓存机制结束 =========================================
    
    % === 基础清洗 ===
        % 示例：针对特殊测点额外清洗
        % if strcmp(point_id, 'GB-DIS-G05-001-02Y')
        %     vals = clean_threshold(vals, times, struct('min', -20, 'max', 20, 't_range', [datetime('2025-02-28 20:00:00'), datetime('2025-02-28 23:00:00')]));
        % end
         if strcmp(point_id, 'GB-VIB-G06-002-01')
            vals = clean_threshold(vals, times, struct('min', -500, 'max', 400, 't_range', []));
         end
         if strcmp(point_id, 'GB-VIB-G04-001-01')
            vals = clean_threshold(vals, times, struct('min', -400, 'max', 400, 't_range', []));
         end
         if strcmp(point_id, 'GB-VIB-G05-001-01')
            vals = clean_threshold(vals, times, struct('min', -300, 'max', 300, 't_range', []));
         end
         if strcmp(point_id, 'GB-VIB-G05-002-01')
            vals = clean_threshold(vals, times, struct('min', -300, 'max', 300, 't_range', []));
         end
         if strcmp(point_id, 'GB-VIB-G05-003-01')
            vals = clean_threshold(vals, times, struct('min', -500, 'max', 300, 't_range', []));
         end
          if strcmp(point_id, 'GB-VIB-G06-001-01')
            vals = clean_threshold(vals, times, struct('min', -300, 'max', 300, 't_range', []));
          end
          if strcmp(point_id, 'GB-VIB-G06-003-01')
            vals = clean_threshold(vals, times, struct('min', -300, 'max', 300, 't_range', []));
          end 
        if strcmp(point_id, 'GB-VIB-G07-001-01')
            vals = clean_threshold(vals, times, struct('min', -400, 'max', 400, 't_range', []));
        end
        % =====================
    all_time = [all_time; times];
    all_val  = [all_val;  vals];

end
[all_time,ix]=sort(all_time); all_val=all_val(ix);
end

function plot_accel_curve(root_dir,pid, times, vals, mn, mx)
% 绘制加速度时程曲线及标注
fig = figure('Position',[100 100 1000 469]);
plot(times, vals, 'LineWidth',1);
xlabel('时间'); ylabel('主梁竖向振动加速度 (mm/s^2)');
% Y 轴范围切换
tmp_manual=true;
if tmp_manual
    ylim([-500,500]);
else
    ylim auto;
end
hold on;
% 添加红色虚线及左侧标签
h1 = yline(mx, '--r'); h1.Label = sprintf('最大值 %.3f', mx);
h1.LabelHorizontalAlignment = 'left';
h2 = yline(mn, '--r'); h2.Label = sprintf('最小值 %.3f', mn);
h2.LabelHorizontalAlignment = 'left';
% X 刻度 4 等分
dn0 = datenum(times(1)); dn1 = datenum(times(end));
numDiv = 4;
ticks = datetime(linspace(dn0, dn1, numDiv+1), 'ConvertFrom','datenum');
ax = gca; ax.XLim = ticks([1 end]); ax.XTick = ticks; xtickformat('yyyy-MM-dd');
grid on; grid minor;
title(['加速度时程 ' pid]);
% 保存
ts = datestr(now,'yyyymmdd_HHMMSS');
out = fullfile(root_dir,'时程曲线_加速度'); if ~exist(out,'dir'), mkdir(out); end
fname = [pid '_' datestr(times(1),'yyyymmdd') '_' datestr(times(end),'yyyymmdd')];
saveas(fig, fullfile(out, [fname '_' ts '.jpg']));
saveas(fig, fullfile(out, [fname '_' ts '.emf']));
savefig(fig, fullfile(out, [fname '_' ts '.fig']), 'compact');
close(fig);
end

function plot_accel_rms_curve(root_dir, pid, times, vals, fs, start_date, end_date)
% 10 min RMS 全时程曲线（含峰值红线与时间标注，健壮的刻度处理）

if isempty(vals) || numel(times) ~= numel(vals)
    return;
end

% --- 计算 10min 滑动 RMS ---
win_len = max(1, round(600 * fs));  % 10 min
valid_cnt = movsum(~isnan(vals) & isfinite(vals), win_len, 'Endpoints','shrink');
rms_series = sqrt(movmean(vals.^2, win_len, 'omitnan', 'Endpoints','shrink'));
min_need = max(1, round(0.7 * win_len));      % 至少 70% 有效样本
rms_series(valid_cnt < min_need) = NaN;

% 峰值与时间
[rms_max, idx_max] = max(rms_series, [], 'omitnan');
t_max = NaT;
if ~isempty(idx_max) && ~isnan(rms_max)
    t_max = times(idx_max);
end

% --- 绘图 ---
fig = figure('Position',[100 100 1000 469]);
plot(times, rms_series, 'LineWidth', 1.2);
xlabel('时间'); ylabel('10 min RMS (mm/s^2)');
% Y 轴范围切换
tmp_manual=true;
if tmp_manual
    ylim([0,80]);
else
    ylim auto;
end

title(sprintf('10 min RMS 时程 %s', pid));
grid on; grid minor; hold on;

% 峰值红线与标注
if ~isnan(rms_max)
    h1 = yline(rms_max, '--r');
    h1.Label = sprintf('最大值 %.3f', rms_max);
    h1.LabelHorizontalAlignment = 'left';
    if ~isnat(t_max)
        plot(t_max, rms_max, 'ro', 'MarkerFaceColor','r');
        %text(t_max, rms_max, sprintf('  %s', datestr(t_max,'yyyy-mm-dd HH:MM:ss')), ...
        %    'VerticalAlignment','bottom', 'FontSize',9, 'Color','r');
    end
end

% --- X 轴范围与刻度（健壮处理） ---
ax = gca;

% 以实际数据范围为准
xmin = min(times);
xmax = max(times);

% 如果全部时间相同，给一个1分钟缓冲，避免范围退化
if xmin == xmax
    xmin = xmin - minutes(1);
    xmax = xmax + minutes(1);
end
ax.XLim = [xmin xmax];

% 尝试从“数据范围”生成 5 个刻度（一定递增）
ticks = datetime(linspace(datenum(xmin), datenum(xmax), 5), 'ConvertFrom','datenum');
% 去重并确认严格递增
ticks = unique(ticks,'stable');
if numel(ticks) >= 2 && all(diff(ticks) > duration(0,0,0))
    ax.XTick = ticks;
else
    % 回退：由 MATLAB 自动选择刻度，避免 DatetimeRuler 报错
    ax.XTickMode = 'auto';
end
% 根据跨度自动选择格式（天级用日期，小时级用日期+时间）
if days(xmax - xmin) >= 1
    xtickformat('yyyy-MM-dd');
else
    xtickformat('MM-dd HH:mm');
end

% --- 保存 ---
ts = datestr(now,'yyyymmdd_HHMMSS');
out = fullfile(root_dir,'时程曲线_加速度_RMS10min'); 
if ~exist(out,'dir'), mkdir(out); end
fname = sprintf('AccelRMS10_%s_%s_%s', pid, datestr(min(times),'yyyymmdd'), datestr(max(times),'yyyymmdd'));
saveas(fig, fullfile(out, [fname '_' ts '.jpg']));
saveas(fig, fullfile(out, [fname '_' ts '.emf']));
savefig(fig, fullfile(out, [fname '_' ts '.fig']), 'compact');
close(fig);
end
