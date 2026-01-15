function batch_rename_csv(root_dir, start_date, end_date, silent)
% batch_rename_csv 批量重命名“波形”和“特征值”子文件夹中的CSV文件
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date, end_date: 日期范围，格式 'yyyy-MM-dd'
%   silent: 静默模式，如果为 true 则不询问直接运行（默认 false）

if nargin<1 || isempty(root_dir)
    root_dir = 'F:\管柄数据\管柄6月数据\动应变';
end
if nargin<2 || isempty(start_date)
    start_date = input('开始日期 (yyyy-MM-dd): ', 's');
end
if nargin<3 || isempty(end_date)
    end_date = input('结束日期 (yyyy-MM-dd): ', 's');
end
if nargin<4
    silent = false;
end

% 转换日期为 datenum 并筛选日期文件夹
dn0 = datenum(start_date, 'yyyy-mm-dd');
dn1 = datenum(end_date,   'yyyy-mm-dd');
dinfo = dir(fullfile(root_dir, '20??-??-??'));
folders = {dinfo([dinfo.isdir]).name};
sel = {};
for i = 1:numel(folders)
    d = datenum(folders{i}, 'yyyy-mm-dd');
    if d >= dn0 && d <= dn1
        sel{end+1} = folders{i};
    end
end

% 估算重命名预计时间（每文件约0.01s）
total_files = 0;
for i = 1:numel(sel)
    for sub = {'波形', '特征值'}
        dir_path = fullfile(root_dir, sel{i}, sub{1});
        if exist(dir_path, 'dir')
            files = dir(fullfile(dir_path, '*.csv'));
            total_files = total_files + numel(files);
        end
    end
end
est_time = total_files * 0.01; % 秒

time_min = est_time / 60;
if time_min > 3
    if silent
        fprintf('预计重命名时间 %.1f 分钟，静默模式下直接开始运行\n', time_min);
    else
        c = input(sprintf('预计重命名时间 %.1f 分钟，超过3分钟，是否继续？(y/n): ', time_min), 's');
        if ~strcmpi(c, 'y')
            disp('已取消');
            return;
        end
    end
else
    fprintf('预计重命名时间 %.1f 分钟，开始运行\n', time_min);
end

% 执行重命名
start_tic = tic;
log = {};
for i = 1:numel(sel)
    day = sel{i};
    for sub = {'波形', '特征值'}
        sub_dir = fullfile(root_dir, day, sub{1});
        if ~exist(sub_dir, 'dir')
            fprintf('警告: %s 下不存在 %s 文件夹，跳过\n', day, sub{1});
            continue;
        end
        fprintf('处理 %s / %s 文件夹\n', day, sub{1});
        files = dir(fullfile(sub_dir, '*.csv'));
        for k = 1:numel(files)
            old_name = files(k).name;
            base = old_name(1:end-4);
            % 删除 "_原始数据" 到末尾
            newbase = regexprep(base, '_原始数据.*', '');
            % 连续 5 位数字改为3-2
            newbase = regexprep(newbase, '(?<!\d)(\d{3})(\d{2})(?!\d)', '$1-$2');
            new_name = [newbase '.csv'];
            if strcmp(old_name, new_name)
                log{end+1} = sprintf('%s (%s) -> 跳过: 文件名已正确', old_name, sub{1});
                continue;
            end
            old_full = fullfile(sub_dir, old_name);
            new_full = fullfile(sub_dir, new_name);
            try
                movefile(old_full, new_full);
                log{end+1} = sprintf('%s (%s) -> %s', old_name, sub{1}, new_name);
            catch ME
                log{end+1} = sprintf('%s (%s) -> FAILED: %s', old_name, sub{1}, ME.message);
            end
        end
    end
end
elapsed = toc(start_tic);

% 输出日志和耗时
fprintf('\n重命名结果：\n');
for j = 1:numel(log)
    fprintf('%s\n', log{j});
end
fprintf('实际运行时间: %.2f 秒\n', elapsed);
end
