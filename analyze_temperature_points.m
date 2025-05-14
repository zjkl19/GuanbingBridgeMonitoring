function analyze_temperature_points(root_dir, point_ids, start_date, end_date, excel_file, subfolder)
% analyze_temperature_points 批量绘制多个测点温度时程曲线并统计基本指标（合并至单文件）
%   root_dir: 根目录，例如 'G:/BaiduNetdiskDownload/管柄大桥数据'
%   point_ids: 测点编号 cell 数组，例如 {'GB-RTS-G05-001-01','GB-RTS-G05-001-02'}
%   start_date,end_date: 日期范围，'yyyy-MM-dd'
%   excel_file: 输出统计 Excel 路径，例如 'temp_stats.xlsx'
%   subfolder: 数据所在子文件夹，默认 '特征值'

if nargin<1||isempty(root_dir),    root_dir = pwd; end
if nargin<2||isempty(point_ids),    error('请提供 point_ids cell 数组'); end
if nargin<3||isempty(start_date),   start_date = input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<4||isempty(end_date),     end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
if nargin<5||isempty(excel_file),   excel_file = 'temperature_stats.xlsx'; end

nPts = numel(point_ids);
stats = cell(nPts,4);

dn0 = datenum(start_date,'yyyy-mm-dd');
dn1 = datenum(end_date,  'yyyy-mm-dd');
% 通用存图目录
timestamp = datestr(now,'yyyymmdd_HHMMSS');
outDir = fullfile(root_dir,'时程曲线_温度');
if ~exist(outDir,'dir'), mkdir(outDir); end

for i = 1:nPts
    pid = point_ids{i};
    fprintf('Processing %s...\n', pid);
    % 提取数据
    [all_time, all_val] = extract_point_data(root_dir, subfolder,pid, dn0, dn1);
    if isempty(all_val)
        warning('测点 %s 无数据, 跳过', pid);
        continue;
    end
    % 绘图
    fig = figure('Position',[100 100 1000 469]); hold on;
    plot(all_time, all_val,'LineWidth',1);
    % 均值横线
    avg_val = round(mean(all_val),1);
    yline(avg_val,'--r',sprintf('平均值 %.1f',avg_val),...
        'LabelHorizontalAlignment','center','LabelVerticalAlignment','bottom');
    % 刻度和格式
    numDiv = 4;
    tk = linspace(dn0,dn1,numDiv+1);
    xt = datetime(tk,'ConvertFrom','datenum');
    ax = gca;
    ax.XLim = [xt(1) xt(end)];
    ax.XTick = xt;
    xtickformat('yyyy-MM-dd');
    xlabel('时间'); ylabel('环境温度（℃）');
    tmp_manual = true;
    if tmp_manual, ylim([0,35]); else, ylim auto; end
    grid on; grid minor;
    title(sprintf('测点 %s 温度时程曲线', pid));
    % 保存
    base = sprintf('%s_%s_%s', pid, datestr(dn0,'yyyymmdd'), datestr(dn1,'yyyymmdd'));
    saveas(fig, fullfile(outDir,[base '_' timestamp '.jpg']));
    saveas(fig, fullfile(outDir,[base '_' timestamp '.emf']));
    savefig(fig, fullfile(outDir,[base '_' timestamp '.fig']), 'compact');
    close(fig);
    % 统计
    mn = min(all_val);
    mx = max(all_val);
    stats{i,1} = pid;
    stats{i,2} = mn;
    stats{i,3} = mx;
    stats{i,4} = avg_val;
end
% 写 Excel
T = cell2table(stats,'VariableNames',{'PointID','Min','Max','Mean'});
writetable(T,excel_file);
fprintf('统计结果已保存至 %s\n',excel_file);
end

function [all_time, all_val] = extract_point_data(root_dir,subfolder, point_id, dn0, dn1)
% extract_point_data: 按日期范围收集单测点温度数据
all_time = [];
all_val  = [];
info = dir(fullfile(root_dir,'20??-??-??'));
folders = {info([info.isdir]).name};
valid = folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
for j = 1:numel(valid)
    dirp = fullfile(root_dir, valid{j}, subfolder);
    if ~exist(dirp,'dir'), continue; end
    files = dir(fullfile(dirp,'*.csv'));
    idx = find(arrayfun(@(f) contains(f.name, point_id), files),1);
    if isempty(idx), continue; end
    fp = fullfile(files(idx).folder, files(idx).name);

    [~, name, ~] = fileparts(fp);

    % ---- 以下是新增的缓存逻辑 ----
    cache_dir = fullfile(files(idx).folder, 'cache');
    if ~exist(cache_dir,'dir')
        mkdir(cache_dir);
    end
    cacheFile = fullfile(cache_dir, [name '.mat']);

    useCache = false;
    if exist(cacheFile,'file')
        infoCSV = dir(fp);
        infoMAT = dir(cacheFile);
        % 只有当 MAT 更新于 CSV 时才使用缓存
        if datenum(infoMAT.date) > datenum(infoCSV.date)
            useCache = true;
        end
    end
    
    if useCache
        S = load(cacheFile,'T');
        T = S.T;
    else
        % 读 CSV
        fid = fopen(fp,'rt'); h=0;
        while h<50 && ~feof(fid)
            ln = fgetl(fid); h=h+1;
            if contains(ln,'[绝对时间]'), break; end
        end
        fclose(fid);
        T = readtable(fp, ...
            'Delimiter',',', ...
            'HeaderLines',h, ...
            'Format','%{yyyy-MM-dd HH:mm:ss.SSS}D%f');

        % 写缓存
        save(cacheFile,'T');
        S.T = T;
    end
    % ---- 缓存逻辑结束 ----
    all_time = [all_time; T{:,1}];
    all_val  = [all_val;  T{:,2}];
end
[all_time, ix] = sort(all_time);
all_val = all_val(ix);
end
