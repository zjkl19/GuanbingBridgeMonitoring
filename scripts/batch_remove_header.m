function batch_remove_header(root_dir, start_date, end_date, silent)
% batch_remove_header 并行批量删除“波形”和“特征值”CSV文件头部信息
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date, end_date: 日期范围，格式 'yyyy-MM-dd'
%   silent: 静默模式(true: 只输出总耗时及总文件数, 默认 false)

if nargin<1 || isempty(root_dir)
    root_dir = 'F:/管柄大桥健康监测数据/';
end
if nargin<2 || isempty(start_date)
    start_date = input('开始日期 (yyyy-MM-dd): ', 's');
end
if nargin<3 || isempty(end_date)
    end_date   = input('结束日期 (yyyy-mm-dd): ', 's');
end
if nargin<4
    silent = false;
end

% 转换为 datenum 并筛选日期文件夹
dn0 = datenum(start_date, 'yyyy-mm-dd');
dn1 = datenum(end_date,   'yyyy-mm-dd');
dinfo = dir(fullfile(root_dir, '20??-??-??'));
folders = {dinfo([dinfo.isdir]).name};
sel = {};
for i = 1:numel(folders)
    if datenum(folders{i}, 'yyyy-mm-dd') >= dn0 && datenum(folders{i}, 'yyyy-mm-dd') <= dn1
        sel{end+1} = folders{i};
    end
end
if isempty(sel)
    error('在指定日期范围内未找到任何文件夹');
end

% 收集所有待处理文件列表
days = {}; subs = {}; fnames = {}; fullPaths = {}; c = 0;
for i = 1:numel(sel)
    day = sel{i};
    for sub = {'波形','特征值'}
        dir_path = fullfile(root_dir, day, sub{1});
        if ~exist(dir_path, 'dir'), continue; end
        files = dir(fullfile(dir_path, '*.csv'));
        for k = 1:numel(files)
            c = c + 1;
            days{c}      = day;
            subs{c}      = sub{1};
            fnames{c}    = files(k).name;
            fullPaths{c} = fullfile(dir_path, files(k).name);
        end
    end
end
N = numel(fullPaths);
if N == 0
    error('未发现任何待处理的 CSV 文件');
end

% 并行处理
tic;
resultMsgs = cell(N,1);
parfor idx = 1:N
    subf  = subs{idx};
    fname = fnames{idx};
    fp    = fullPaths{idx};
    try
        % 限制前50行内检测头部
        fid = fopen(fp, 'rt');
        header = 0;
        found  = false;
        for j = 1:50
            if feof(fid), break; end
            line = fgetl(fid);
            header = header + 1;
            if contains(line, '[绝对时间]')
                found = true;
                break;
            end
        end
        fclose(fid);
        if ~found
            % 已处理或无头部，跳过
            resultMsgs{idx} = sprintf('%s/%s -> 跳过: 无需删除头部', subf, fname);
            continue;
        end
        % 读取并覆盖写回
        T = readtable(fp, 'Delimiter', ',', 'HeaderLines', header, 'Format', '%s%f');
        writetable(T, fp, 'Delimiter', ',', 'WriteVariableNames', false);
        resultMsgs{idx} = sprintf('%s/%s -> 已删除头部', subf, fname);
    catch ME
        resultMsgs{idx} = sprintf('%s/%s -> ERROR: %s', subf, fname, ME.message);
    end
end
elapsed = toc;

delete(gcp('nocreate'));

% 输出结果
if silent
    fprintf('总处理文件: %d，耗时: %.2f 秒\n', N, elapsed);
else
    fprintf('\n处理日志：\n');
    for j = 1:N
        fprintf('%s\n', resultMsgs{j});
    end
    fprintf('总耗时: %.2f 秒\n', elapsed);
end
end
