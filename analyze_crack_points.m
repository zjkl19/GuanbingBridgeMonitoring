function analyze_crack_points(root_dir, start_date, end_date, excel_file, subfolder)
% analyze_crack_points_refactored 批量绘制并统计裂缝宽度与温度时程曲线（方案A重构）
%   保持绘图函数独立，只提取一次数据，避免不必要的 I/O

if nargin<1||isempty(root_dir),  root_dir = pwd;               end
if nargin<2||isempty(start_date), start_date = input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<3||isempty(end_date),   end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
if nargin<4||isempty(excel_file), excel_file = 'crack_stats.xlsx';end
if nargin<5||isempty(subfolder),  subfolder  = '特征值';         end

% 分组定义
groups = { ...
    {'GB-CRK-G05-001-01','GB-CRK-G05-001-02','GB-CRK-G05-001-03','GB-CRK-G05-001-04'}, ...
    {'GB-CRK-G06-001-01','GB-CRK-G06-001-02','GB-CRK-G06-001-03','GB-CRK-G06-001-04'} ...
    };

% 手动指定每组的 YLim 范围
manual_ylims = {[-0.25, 0.25], [-0.3, 0.3]};  % 每组的 YLim 范围，可以根据实际需要调整

% 初始化统计表
stats = {};
row = 1;
for gi = 1:numel(groups)
    pid_list = groups{gi};
    % 一次读取：存放每个测点的裂缝与温度数据
    N = numel(pid_list);
    crack_times = cell(N,1);
    crack_vals  = cell(N,1);
    temp_times  = cell(N,1);
    temp_vals   = cell(N,1);
    for i = 1:N
        pid = pid_list{i};
        [tc, vc] = extract_crack_data(root_dir, subfolder, pid,   start_date, end_date);
        [tt, vt] = extract_crack_data(root_dir, subfolder, [pid '-t'], start_date, end_date);
        crack_times{i} = tc;  crack_vals{i} = vc;
        temp_times{i}  = tt;  temp_vals{i}  = vt;
        % 统计
        stats(row,:) = {
            pid, ...
            round(min(vc),3), round(max(vc),3), round(mean(vc),3), ...
            round(min(vt),3), round(max(vt),3), round(mean(vt),3)};
        row = row + 1;
    end
    % 绘制裂缝宽度曲线，传递手动指定的 YLim 范围
    plot_group_curve(crack_times, crack_vals, pid_list, '裂缝宽度 (mm)', ...
        fullfile(root_dir,'时程曲线_裂缝宽度 (mm)'), gi, start_date, end_date, manual_ylims{gi});
    % 绘制温度曲线，传递手动指定的 YLim 范围
    plot_group_curve(temp_times, temp_vals, pid_list, '裂缝温度 (℃)', ...
        fullfile(root_dir,'时程曲线_裂缝温度 (℃)'), gi, start_date, end_date, manual_ylims{gi});

end
% 写Excel
T = cell2table(stats, 'VariableNames',{'PointID','CrkMin','CrkMax','CrkMean','TmpMin','TmpMax','TmpMean'});
writetable(T, excel_file);
fprintf('统计结果已保存至 %s\n', excel_file);
end

function plot_group_curve(times_cell, vals_cell, labels, ylabel_str, out_dir, group_idx, start_date, end_date, ylim_range)

% 通用组曲线绘制
if ~exist(out_dir,'dir'), mkdir(out_dir); end
fig = figure('Position',[100 100 1000 469]); hold on;
N = numel(labels);
colors_4 = {
    [0 0 0],    % 黑色
    [1 0 0],    % 红色
    [0 0 1],    % 蓝色
    [0 0.7 0]   % 绿色
    };
for i = 1:N
    if N == 4
        plot(times_cell{i}, vals_cell{i}, 'LineWidth', 1.0, 'Color', colors_4{i});
    else
        plot(times_cell{i}, vals_cell{i}, 'LineWidth', 1.0); % 默认颜色
    end
end

legend(labels,'Location','northeast','Box','off');
xlabel('时间'); ylabel(ylabel_str);
% 时间刻度
dt0 = datetime(start_date,'InputFormat','yyyy-MM-dd');
dt1 = datetime(end_date,  'InputFormat','yyyy-MM-dd');
ticks = datetime(linspace(datenum(dt0),datenum(dt1),5),'ConvertFrom','datenum');
ax = gca; ax.XLim = [dt0 dt1]; ax.XTick = ticks;
xtickformat('yyyy-MM-dd'); grid on; grid minor;
% 设置 Y 轴范围
if ~isempty(ylim_range)
    ylim(ylim_range);  % 使用手动设置的 YLim 范围
else
    ylim auto;         % 否则自动调整
end
% 保存
ts = datestr(now,'yyyymmdd_HHMMSS');
fname = sprintf('%s_G%d_%s_%s', ylabel_str, group_idx, datestr(dt0,'yyyymmdd'), datestr(dt1,'yyyymmdd'));
saveas(fig, fullfile(out_dir, [fname '_' ts '.jpg']));
saveas(fig, fullfile(out_dir, [fname '_' ts '.emf']));
savefig(fig,fullfile(out_dir,[fname '_' ts '.fig']),'compact');
close(fig);
end
function [all_time, all_val] = extract_crack_data(root_dir, subfolder, point_id, start_date, end_date)
all_time = [];
all_val  = [];
dn0 = datenum(start_date,'yyyy-mm-dd'); dn1 = datenum(end_date,'yyyy-mm-dd');
info = dir(fullfile(root_dir,'20??-??-??'));
folders = {info([info.isdir]).name};
dates = folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
is_temp = endsWith(point_id,'-t');
for j = 1:numel(dates)
    dirp = fullfile(root_dir, dates{j}, subfolder);
    if ~exist(dirp,'dir'), continue; end
    files = dir(fullfile(dirp,'*.csv'));
    if is_temp
        idx = find(contains({files.name}, point_id),1);
        if isempty(idx)
            fprintf('DEBUG [%s]: 温度文件未找到，point_id="%s", dir="%s"\n', mfilename, point_id, dirp);
            fprintf('    可用文件列表：\n');
            for kk=1:numel(files)
                fprintf('      %s\n', files(kk).name);
            end
            continue;
        end
    else
        names = {files.name};
        valid_idx = find(contains(names, point_id) & ~contains(names,'-t') & ~contains(names,'-hz'));
        if isempty(valid_idx)
            fprintf('DEBUG [%s]: 裂缝文件未找到，point_id="%s", dir="%s"\n', mfilename, point_id, dirp);
            fprintf('    可用文件列表：\n');
            for kk=1:numel(names)
                fprintf('      %s\n', names{kk});
            end
            continue;
        end
        idx = valid_idx(1);
    end
    if isempty(idx), continue; end
    fp = fullfile(files(idx).folder, files(idx).name);

    fid = fopen(fp,'rt');
    h = 0;
    found = false;               % ← 初始化 found
    while h < 50 && ~feof(fid)
        ln = fgetl(fid); h = h + 1;
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
% ================= 缓存机制 =================
    cacheDir = fullfile(dirp, 'cache');
    if ~exist(cacheDir,'dir'), mkdir(cacheDir); end
    [~,name,~] = fileparts(fp);
    cacheFile  = fullfile(cacheDir, [name '.mat']);
    useCache   = false;

    if exist(cacheFile,'file')
        infoCSV = dir(fp);
        infoMAT = dir(cacheFile);
        if datenum(infoMAT.date) > datenum(infoCSV.date)
            tmp   = load(cacheFile, 'times','vals');
            times = tmp.times;
            vals  = tmp.vals;
            useCache = true;
        end
    end

    if ~useCache
        fid = fopen(fp,'rt');
        h = 0;
        found = false;               % 初始化 found
        while h < 50 && ~feof(fid)
            ln = fgetl(fid);
            h = h + 1;
            if contains(ln,'[绝对时间]')
                found = true;
                break;
            end
        end
        if ~found
            warning('提示：文件 %s 未检测到头部标记 “[绝对时间]”，使用 h=0 读取全部作为数据', fp);
            h = 0; % 避免把所有行当成 header 跳过
        end
        fclose(fid);

        T = readtable(fp,'Delimiter',',','HeaderLines',h, ...
            'Format','%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
        times = T{:,1};
        vals  = T{:,2};
        save(cacheFile, 'times','vals');
    end
    % ==================缓存机制结束===========================
    %bug：温度一起清洗了
    % === 基础清洗 ===
    % 示例：针对特殊测点额外清洗
    % if strcmp(point_id, 'GB-DIS-G05-001-02Y')
    %     vals = clean_threshold(vals, times, struct('min', -20, 'max', 20, 't_range', [datetime('2025-02-28 20:00:00'), datetime('2025-02-28 23:00:00')]));
    % end
    vals = clean_threshold(vals, times, struct('min', -0.30, 'max', 0.30, 't_range', []));
    if strcmp(point_id, 'GB-CRK-G05-001-01')
        vals = clean_threshold(vals, times, struct('min', -0.22, 'max', -0.1, 't_range', []));
    end
    if strcmp(point_id, 'GB-CRK-G05-001-02')
        vals = clean_threshold(vals, times, struct('min', -100, 'max', -0.05, 't_range', []));
    end
    if strcmp(point_id, 'GB-CRK-G06-001-01')
        vals = clean_threshold(vals, times, struct('min', -0.25, 'max', 0.05, 't_range', []));
    end
    % =====================

    all_time = [all_time; times]; all_val = [all_val; vals];
end
[all_time, ix] = sort(all_time); all_val = all_val(ix);
end