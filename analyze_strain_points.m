function analyze_strain_points(root_dir, start_date, end_date, excel_file, subfolder)
% analyze_strain_points 批量绘制主梁应变时程曲线并统计指标
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date,end_date: 日期范围，'yyyy-MM-dd'
%   excel_file: 输出统计 Excel，如 'strain_stats.xlsx'
%   subfolder: 数据所在子文件夹，默认 '特征值'

if nargin<1||isempty(root_dir),    root_dir = pwd; end
if nargin<2||isempty(start_date),   start_date = input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<3||isempty(end_date),     end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
if nargin<4||isempty(excel_file),   excel_file = 'strain_stats.xlsx'; end
if nargin<5||isempty(subfolder),    subfolder  = '特征值'; end

% 定义测点分组
groups = { ...
    {'GB-RSG-G05-001-01', 'GB-RSG-G05-001-02', 'GB-RSG-G05-001-03', 'GB-RSG-G05-001-04', 'GB-RSG-G05-001-05', 'GB-RSG-G05-001-06'}, ...
    {'GB-RSG-G06-001-01', 'GB-RSG-G06-001-02', 'GB-RSG-G06-001-03', 'GB-RSG-G06-001-04', 'GB-RSG-G06-001-05', 'GB-RSG-G06-001-06'} ...
    };

% 结果存表：PID, Min, Max, Mean
stats = {};
row = 1;
% 提取并统计
for gi = 1:numel(groups)
    for i = 1:numel(groups{gi})
        pid = groups{gi}{i};
        [t, v] = extract_strain_data(root_dir, subfolder, pid, start_date, end_date);
        if isempty(v)
            warning('无 %s 数据', pid);
            continue;
        end
        stats(row,:) = {pid, round(min(v)), round(max(v)), round(mean(v))};
        row = row + 1;
    end
end
% 写 Excel
T = cell2table(stats, 'VariableNames', {'PointID','Min','Max','Mean'});
writetable(T, excel_file);
fprintf('应变统计已保存至 %s\n', excel_file);

% 通用时间刻度
dt0 = datetime(start_date,'InputFormat','yyyy-MM-dd');
dt1 = datetime(end_date,  'InputFormat','yyyy-MM-dd');
ticks = datetime(linspace(datenum(dt0), datenum(dt1),5),'ConvertFrom','datenum');

% 绘图
for gi = 1:numel(groups)
    pid_list = groups{gi};
    fig=figure('Position',[100 100 1000 469]); hold on;
    N = numel(pid_list);
    % 5条及以上的手动配色（第6条线红色，满足你的要求）
    colors_6 = {
        [0 0 0],         % 黑色
        [0 0 1],         % 蓝色
        [0 0.7 0],       % 绿色
        [1 0.4 0.8],     % 粉红色
        [1 0.6 0],       % 橙色
        [1 0 0]          % 红色
    };
    
    for i = 1:N
        [t, v] = extract_strain_data(root_dir, subfolder, pid_list{i}, start_date, end_date);
        if N == 5 || N == 6
            c = colors_6{i};
            plot(t, v, 'LineWidth', 1.0, 'Color', c);
        else
            plot(t, v, 'LineWidth', 1.0); % 默认颜色
        end
    end
    legend(pid_list,'Location','northeast','Box','off');
    xlabel('时间'); ylabel('主梁应变 (με)');
    % 组别对应手动 YLim
    manual_ylims = {[-200,200], [-350,200]}; % 可根据需要自行调整每组 YLim

    tmp_manual = true;
    if tmp_manual
        ylim(manual_ylims{gi});
    else
        ylim auto;
    end
    ax=gca; ax.XLim=[ticks(1) ticks(end)]; ax.XTick=ticks; xtickformat('yyyy-MM-dd');
    grid on; grid minor;
    title(sprintf('应变时程曲线 组%d',gi));
    ts=datestr(now,'yyyymmdd_HHMMSS'); out=fullfile(root_dir,'时程曲线_应变'); if ~exist(out,'dir'), mkdir(out); end
    fname=sprintf('StrainG%d_%s_%s',gi,datestr(dt0,'yyyyMMdd'),datestr(dt1,'yyyyMMdd'));
    saveas(fig,fullfile(out,[fname '_' ts '.jpg']));
    saveas(fig,fullfile(out,[fname '_' ts '.emf']));
    savefig(fig,fullfile(out,[fname '_' ts '.fig']), 'compact'); close(fig);
end
end

function [all_t, all_v] = extract_strain_data(root_dir, subfolder, pid, start_date, end_date)
all_t=[]; all_v=[];
dn0=datenum(start_date,'yyyy-mm-dd'); dn1=datenum(end_date,'yyyy-mm-dd');
info=dir(fullfile(root_dir,'20??-??-??')); folders={info([info.isdir]).name};
dates=folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
for j=1:numel(dates)
    dirp=fullfile(root_dir,dates{j},subfolder);
    if ~exist(dirp,'dir'), continue; end
    files=dir(fullfile(dirp,'*.csv'));
    idx=find(arrayfun(@(f) contains(f.name,pid),files),1);
    if isempty(idx), continue; end
    fp=fullfile(files(idx).folder,files(idx).name);
    fid = fopen(fp,'rt');
    h = 0;
    found = false;               % ← 初始化 found
    while h<50 && ~feof(fid)
        ln=fgetl(fid); h=h+1;
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
    T=readtable(fp,'Delimiter',',','HeaderLines',h,'Format','%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
    times = T{:,1}; vals = T{:,2};
    % === 数据清洗 ===
    vals = clean_threshold(vals, times, struct('min', -400, 'max', 200, 't_range', []));
    if strcmp(pid, 'GB-RSG-G05-001-03')
        vals = clean_threshold(vals, times, struct('min', -350, 'max', 20, 't_range', []));
        vals = clean_threshold(vals, times, struct('min', 0, 'max', 0, 't_range', [datetime('2025-04-26 00:00:00'), datetime('2025-05-10 00:00:00')]));
    end
     if strcmp(pid, 'GB-RSG-G05-001-02')
        vals = clean_threshold(vals, times, struct('min', -350, 'max', 20, 't_range', []));
        vals = clean_threshold(vals, times, struct('min', -30, 'max', 20, 't_range', []));
     end
    if strcmp(pid, 'GB-RSG-G05-001-06')
        vals = clean_threshold(vals, times, struct('min', 50, 'max', 70, 't_range', [datetime('2025-05-13 15:00:00'), datetime('2025-05-13 16:00:00')]));
    end
    % === === ===
    all_t=[all_t;times]; all_v=[all_v;vals];
end
[all_t,ix]=sort(all_t); all_v=all_v(ix);
all_v = apply_lowpass(all_t, all_v);

end
