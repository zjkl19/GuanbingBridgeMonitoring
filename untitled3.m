function analyze_strain_points(root_dir, start_date, end_date, excel_file, subfolder)
% analyze_strain_points_refactored 批量绘制主梁应变时程曲线并统计指标（按组缓存并释放）
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date,end_date: 日期范围，'yyyy-MM-dd'
%   excel_file: 输出统计 Excel，如 'strain_stats.xlsx'
%   subfolder: 数据所在子文件夹，默认 '特征值'

if nargin<1||isempty(root_dir),   root_dir = pwd;              end
if nargin<2||isempty(start_date), start_date = input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<3||isempty(end_date),   end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
if nargin<4||isempty(excel_file), excel_file = 'strain_stats.xlsx'; end
if nargin<5||isempty(subfolder),  subfolder  = '特征值';         end

% 定义测点分组
groups = { ...
    {'GB-RSG-G05-001-01','GB-RSG-G05-001-02','GB-RSG-G05-001-03','GB-RSG-G05-001-04','GB-RSG-G05-001-05','GB-RSG-G05-001-06'}, ...
    {'GB-RSG-G06-001-01','GB-RSG-G06-001-02','GB-RSG-G06-001-03','GB-RSG-G06-001-04','GB-RSG-G06-001-05','GB-RSG-G06-001-06'} ...
};

% 统计准备
stats = {};
row = 1;

% 按组提取、统计、绘图，并及时释放缓存
for gi = 1:numel(groups)
    pid_list = groups{gi};
    fprintf('处理组 %d: %s\n', gi, strjoin(pid_list, ', '));
    N = numel(pid_list);
    times_cell = cell(N,1);
    vals_cell  = cell(N,1);
    % 提取并统计本组数据
    for i = 1:N
        pid = pid_list{i};
        [t, v] = extract_strain_data(root_dir, subfolder, pid, start_date, end_date);
        if isempty(v)
            warning('无 %s 数据，跳过。', pid);
            continue;
        end
        times_cell{i} = t;
        vals_cell{i}  = v;
        stats(row,:) = { pid, round(min(v)), round(max(v)), round(mean(v)) };
        row = row + 1;
    end
    % 绘制并释放本组缓存
    plot_group_strain(times_cell, vals_cell, pid_list, fullfile(root_dir,'时程曲线_应变'), gi, start_date, end_date);
    clear times_cell vals_cell
end

% 写入 Excel
T = cell2table(stats, 'VariableNames', {'PointID','Min','Max','Mean'});
writetable(T, excel_file);
fprintf('应变统计已保存至 %s\n', excel_file);
end

function plot_group_strain(times_cell, vals_cell, labels, out_dir, group_idx, start_date, end_date)
% plot_group_strain 绘制一组应变曲线
if ~exist(out_dir,'dir'), mkdir(out_dir); end
fig = figure('Position',[100 100 1000 469]); hold on;
for i = 1:numel(labels)
    plot(times_cell{i}, vals_cell{i}, 'LineWidth',1);
end
legend(labels,'Location','northeast','Box','off');
xlabel('时间'); ylabel('主梁应变 (με)');
% 时间刻度
 dt0 = datetime(start_date,'InputFormat','yyyy-MM-dd');
 dt1 = datetime(end_date,  'InputFormat','yyyy-MM-dd');
 ticks = datetime(linspace(datenum(dt0),datenum(dt1),5),'ConvertFrom','datenum');
 ax = gca; ax.XLim = [dt0 dt1]; ax.XTick = ticks; xtickformat('yyyy-MM-dd');
grid on; grid minor;
title(sprintf('应变时程曲线 组%%d',group_idx));
% 保存
 ts = datestr(now,'yyyymmdd_HHMMSS');
 fname = sprintf('StrainG%%d_%%s_%%s',group_idx,datestr(dt0,'yyyymmdd'),datestr(dt1, 'yyyymmdd'));
 saveas(fig,fullfile(out_dir,[fname '_' ts '.jpg']));
 saveas(fig,fullfile(out_dir,[fname '_' ts '.emf']));
 savefig(fig,fullfile(out_dir,[fname '_' ts '.fig']),'compact');
 close(fig);
end

function [t, v] = extract_strain_data(root_dir, subfolder, pid, start_date, end_date)
% extract_strain_data 提取并返回一个测点的时间和值，无其它副作用
    t = []; v = [];
    dn0 = datenum(start_date,'yyyy-mm-dd'); dn1 = datenum(end_date,'yyyy-mm-dd');
    info = dir(fullfile(root_dir,'20??-??-??'));
    folders = {info([info.isdir]).name};
    dates = folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
    for j = 1:numel(dates)
        dirp = fullfile(root_dir, dates{j}, subfolder);
        if ~exist(dirp,'dir'), continue; end
        files = dir(fullfile(dirp,'*.csv'));
        idx = find(arrayfun(@(f) contains(f.name,pid), files),1);
        if isempty(idx), continue; end
        fp = fullfile(files(idx).folder, files(idx).name);
        fid = fopen(fp,'rt'); h = 0;
        while h<50 && ~feof(fid)
            ln = fgetl(fid); h = h+1;
            if contains(ln,'[绝对时间]'), break; end
        end; fclose(fid);
        T = readtable(fp,'Delimiter',',','HeaderLines',h,'Format','%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
        t = [t; T{:,1}]; v = [v; T{:,2}];
    end
    [t,order] = sort(t); v = v(order);
end
