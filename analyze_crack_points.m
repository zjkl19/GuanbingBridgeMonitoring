function analyze_crack_points(root_dir, start_date, end_date, excel_file, subfolder)
% analyze_crack_points 批量绘制按分组的裂缝宽度和温度时程曲线并统计指标
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date,end_date: 日期范围，'yyyy-MM-dd'
%   excel_file: 输出统计 Excel，如 'crack_stats.xlsx'
%   subfolder: 数据所在子文件夹，默认 '特征值'

if nargin<1||isempty(root_dir),    root_dir = pwd; end
if nargin<2||isempty(start_date),   start_date = input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<3||isempty(end_date),     end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
if nargin<4||isempty(excel_file),   excel_file = 'crack_stats.xlsx'; end
if nargin<5||isempty(subfolder),    subfolder  = '特征值'; end

% 定义测点分组
groups = { ...
    {'GB-CRK-G05-001-01','GB-CRK-G05-001-02','GB-CRK-G05-001-03','GB-CRK-G05-001-04'}, ...
    {'GB-CRK-G06-001-01','GB-CRK-G06-001-02','GB-CRK-G06-001-03','GB-CRK-G06-001-04'} ...
};

def_stats = {};
row = 1;

% 统计指标
for gi = 1:numel(groups)
    pid_list = groups{gi};
    for i = 1:numel(pid_list)
        pid = pid_list{i};
        [~, v_c] = extract_crack_data(root_dir, subfolder, pid, start_date, end_date);
        [~, v_t] = extract_crack_data(root_dir, subfolder, [pid '-t'], start_date, end_date);
        if isempty(v_c), mn_c=NaN; mx_c=NaN; av_c=NaN; else mn_c=round(min(v_c),3); mx_c=round(max(v_c),3); av_c=round(mean(v_c),3); end
        if isempty(v_t), mn_t=NaN; mx_t=NaN; av_t=NaN; else mn_t=round(min(v_t),3); mx_t=round(max(v_t),3); av_t=round(mean(v_t),3); end
        def_stats(row,:) = {pid,mn_c,mx_c,av_c,mn_t,mx_t,av_t};
        row = row + 1;
    end
end
% 写 Excel
T = cell2table(def_stats, 'VariableNames',{'PointID','CrackMin','CrackMax','CrackMean','TempMin','TempMax','TempMean'});
writetable(T, excel_file);
fprintf('统计结果已保存至 %s\n', excel_file);

% 时间刻度基础值
dt0 = datetime(start_date,'InputFormat','yyyy-MM-dd');
dt1 = datetime(end_date,  'InputFormat','yyyy-MM-dd');
ticks = linspace(datenum(dt0), datenum(dt1), 5);

% 绘图：裂缝宽度按组
for gi = 1:numel(groups)
    pid_list = groups{gi};
    fig = figure('Position',[100 100 1000 469]); hold on;
    for i = 1:numel(pid_list)
        pid = pid_list{i};
        [t_c, v_c] = extract_crack_data(root_dir, subfolder, pid, start_date, end_date);
        plot(t_c, v_c, 'LineWidth',1);
    end
    legend(pid_list,'Location','northeast');
    xlabel('时间'); ylabel('裂缝宽度 (mm)');
    ytickformat('%.2f');
    tmp_manual = true;
    if tmp_manual, ylim([-0.20,0.20]); else, ylim auto; end
    ax = gca; ax.XLim = [dt0 dt1]; ax.XTick = datetime(ticks,'ConvertFrom','datenum'); xtickformat('yyyy-MM-dd');
    grid on; grid minor;
    title(sprintf('裂缝宽度 时程 组%d', gi));
    ts = datestr(now,'yyyymmdd_HHMMSS');
    out = fullfile(root_dir,'时程曲线_裂缝宽度 (mm)'); if ~exist(out,'dir'), mkdir(out); end
    fname = sprintf('CrkG%d_%s_%s', gi, datestr(dt0,'yyyyMMdd'), datestr(dt1,'yyyyMMdd'));
    saveas(fig, fullfile(out, [fname '_' ts '.jpg']));
    saveas(fig, fullfile(out, [fname '_' ts '.emf']));
    savefig(fig, fullfile(out, [fname '_' ts '.fig']), 'compact');
    close(fig);
end

% 绘图：温度按组
for gi = 1:numel(groups)
    pid_list = groups{gi};
    fig = figure('Position',[100 100 1000 469]); hold on;
    for i = 1:numel(pid_list)
        pid = pid_list{i};
        [t_t, v_t] = extract_crack_data(root_dir, subfolder, [pid '-t'], start_date, end_date);
        plot(t_t, v_t, 'LineWidth',1);
    end
    legend(pid_list,'Location','northeast');
    xlabel('时间'); ylabel('温度 (℃)');
    tmp_manual = true; if tmp_manual, ylim([-5,40]); else, ylim auto; end
    ax = gca; ax.XLim = [dt0 dt1]; ax.XTick = datetime(ticks,'ConvertFrom','datenum'); xtickformat('yyyy-MM-dd');
    grid on; grid minor;
    title(sprintf('裂缝温度 时程 组%d', gi));
    ts = datestr(now,'yyyymmdd_HHMMSS');
    out = fullfile(root_dir,'时程曲线_裂缝温度 (℃)'); if ~exist(out,'dir'), mkdir(out); end
    fname = sprintf('TmpG%d_%s_%s', gi, datestr(dt0,'yyyyMMdd'), datestr(dt1,'yyyyMMdd'));
    saveas(fig, fullfile(out, [fname '_' ts '.jpg']));
    saveas(fig, fullfile(out, [fname '_' ts '.emf']));
    savefig(fig, fullfile(out, [fname '_' ts '.fig']), 'compact');
    close(fig);
end
end
% ========== Subfunctions ==========

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
        else
            names = {files.name}; valid_idx = find(contains(names, point_id) & ~contains(names,'-t') & ~contains(names,'-hz'));
            idx = valid_idx(1);
        end
        if isempty(idx), continue; end
        fp = fullfile(files(idx).folder, files(idx).name);
        fid = fopen(fp,'rt'); h = 0;
        while h < 50 && ~feof(fid)
            ln = fgetl(fid); h = h + 1;
            if contains(ln,'[绝对时间]'), break; end
        end
        fclose(fid);
        T = readtable(fp,'Delimiter',',','HeaderLines',h,'Format','%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
        times = T{:,1}; vals = T{:,2};
        %bug：温度一起清洗了
        % === 基础清洗 ===
        % 示例：针对特殊测点额外清洗
        % if strcmp(point_id, 'GB-DIS-G05-001-02Y')
        %     vals = clean_threshold(vals, times, struct('min', -20, 'max', 20, 't_range', [datetime('2025-02-28 20:00:00'), datetime('2025-02-28 23:00:00')]));
        % end
        vals = clean_threshold(vals, times, struct('min', -0.22, 'max', 0.20, 't_range', []));
         if strcmp(point_id, 'GB-CRK-G05-001-01')
            vals = clean_threshold(vals, times, struct('min', -0.22, 'max', 0.045, 't_range', []));
        end
        if strcmp(point_id, 'GB-CRK-G06-001-01')
            vals = clean_threshold(vals, times, struct('min', -0.22, 'max', 0.00, 't_range', []));
        end
        % =====================

        all_time = [all_time; times]; all_val = [all_val; vals];
    end
    [all_time, ix] = sort(all_time); all_val = all_val(ix);
end
