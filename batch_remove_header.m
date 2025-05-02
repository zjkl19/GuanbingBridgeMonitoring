function batch_remove_header(root_dir, start_date, end_date, silent)
% batch_remove_header 批量删除“波形”和“特征值”CSV文件头部信息
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date, end_date: 日期范围，格式 'yyyy-MM-dd'
%   silent: 静默模式(true: 不输出中间日志，默认 false)

if nargin<1||isempty(root_dir)
    root_dir = 'F:/管柄大桥健康监测数据/';
end
if nargin<2||isempty(start_date)
    start_date = input('开始日期 (yyyy-MM-dd): ','s');
end
if nargin<3||isempty(end_date)
    end_date   = input('结束日期 (yyyy-MM-dd): ','s');
end
if nargin<4
    silent = false;
end

% 转换为 datenum 并筛选日期文件夹
dn0 = datenum(start_date,'yyyy-mm-dd');
dn1 = datenum(end_date,  'yyyy-mm-dd');
dinfo = dir(fullfile(root_dir,'20??-??-??'));
folders = {dinfo([dinfo.isdir]).name};
sel = {}; for i=1:numel(folders)
    d = datenum(folders{i},'yyyy-mm-dd');
    if d>=dn0 && d<=dn1, sel{end+1}=folders{i}; end
end
if isempty(sel)
    error('在指定日期范围内未找到任何文件夹');
end

log = {};
start_t = tic;
for i=1:numel(sel)
    day = sel{i};
    for sub = {'波形','特征值'}
        dir_path = fullfile(root_dir, day, sub{1});
        if ~exist(dir_path,'dir')
            if ~silent, fprintf('警告: %s 下不存在 %s 文件夹，跳过\n', day, sub{1}); end
            continue;
        end
        files = dir(fullfile(dir_path,'*.csv'));
        for k=1:numel(files)
            fname    = files(k).name;
            fullpath = fullfile(dir_path, fname);
            if ~silent, fprintf('处理 %s / %s / %s\n', day, sub{1}, fname); end
            try
                % 自动检测头部行数
                fid = fopen(fullpath,'rt'); header=0;
                while ~feof(fid)
                    line = fgetl(fid); header=header+1;
                    if contains(line,'[绝对时间]'), break; end
                end; fclose(fid);
                % 读取剩余数据并覆盖写回
                T = readtable(fullpath,'Delimiter',',','HeaderLines',header,'Format','%s%f');
                writetable(T, fullpath,'Delimiter',',','WriteVariableNames',false);
                log{end+1} = sprintf('%s/%s -> 已删除头部', sub{1}, fname);
            catch ME
                log{end+1} = sprintf('%s/%s -> ERROR: %s', sub{1}, fname, ME.message);
            end
        end
    end
end
elapsed = toc(start_t);

% 输出日志和总耗时
if silent
    fprintf('总处理文件: %d，耗时: %.2f 秒\n', numel(log), elapsed);
else
    fprintf('\n处理日志：\n');
    for j=1:numel(log), fprintf('%s\n', log{j}); end
    fprintf('总耗时: %.2f 秒\n', elapsed);
end
end
