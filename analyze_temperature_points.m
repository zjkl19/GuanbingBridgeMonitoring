function analyze_temperature_points(root_dir, point_ids, start_date, end_date, excel_file)
% analyze_temperature_points 批量绘制多个测点温度时程曲线并统计基本指标
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   point_ids: 测点编号字符串 cell 数组，例如 {'GB-RTS-G05-001-01','GB-RTS-G05-001-02'}
%   start_date, end_date: 日期范围，'yyyy-MM-dd'
%   excel_file: 输出 Excel 路径，例如 'temperature_stats.xlsx'

if nargin<1||isempty(root_dir),    root_dir = pwd; end
if nargin<2||isempty(point_ids),  error('请提供 point_ids cell 数组'); end
if nargin<3||isempty(start_date), start_date = input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<4||isempty(end_date),   end_date   = input('结束日期 (yyyy-mm-dd): ','s'); end
if nargin<5||isempty(excel_file), excel_file = 'temperature_stats.xlsx'; end

% 结果存储
stats = cell(numel(point_ids),4);

for i = 1:numel(point_ids)
    pid = point_ids{i};
    fprintf('处理测点 %s ...\n', pid);
    % 提取数据
    [times, vals] = extract_point_data(root_dir, pid, start_date, end_date);
    if isempty(vals)
        warning('测点 %s 无数据，跳过。', pid);
        continue;
    end
    % 绘图
    plot_temperature_point_curve(root_dir, pid, start_date, end_date);
    % 统计
    mn = min(vals);
    mx = max(vals);
    av = mean(vals);
    av = round(mean(vals), 1);  % 平均值保留1位小数
    stats{i,1} = pid;
    stats{i,2} = mn;
    stats{i,3} = mx;
    stats{i,4} = av;
end

% 汇总为 table
T = cell2table(stats, 'VariableNames', {'PointID','Min','Max','Mean'});
% 写入 Excel
writetable(T, excel_file);
fprintf('统计结果已保存至 %s\n', excel_file);

end

function [all_time, all_val] = extract_point_data(root_dir, point_id, start_date, end_date)
% extract_point_data 提取指定测点在日期范围内的时间和值数组
all_time = [];
all_val  = [];
% 同 plot 函数的日期筛选逻辑
dn0 = datenum(start_date,'yyyy-mm-dd'); dn1 = datenum(end_date,'yyyy-mm-dd');
dinfo = dir(fullfile(root_dir,'20??-??-??')); folders = {dinfo([dinfo.isdir]).name};
dates = folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
for j = 1:numel(dates)
    day = dates{j};
    dir_path = fullfile(root_dir, day, '特征值');
    if ~exist(dir_path,'dir'), continue; end
    files = dir(fullfile(dir_path,'*.csv'));
    matches = files(arrayfun(@(f) contains(f.name, point_id), files));
    if isempty(matches), continue; end
    fullpath = fullfile(dir_path, matches(1).name);
    % 检测头部
    fid = fopen(fullpath,'rt'); header = 0; found = false;
    for k = 1:50
        if feof(fid), break; end
        ln = fgetl(fid); header = header + 1;
        if contains(ln,'[绝对时间]'), found = true; break; end
    end
    fclose(fid);
    if ~found, continue; end
    % 读取
    T = readtable(fullpath,'Delimiter',',','HeaderLines',header,'Format','%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
    all_time = [all_time; T{:,1}];
    all_val  = [all_val;  T{:,2}];
end
% 排序
[all_time, idx] = sort(all_time);
all_val = all_val(idx);
end
