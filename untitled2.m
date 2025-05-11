function batch_unzip_data_parallel1(root_dir, start_date, end_date, silent)
% batch_unzip_data_parallel 并行批量解压健康监测数据中的 ZIP 文件（使用 PowerShell）
%   batch_unzip_data_parallel(root_dir, start_date, end_date, silent)
%   root_dir: 根目录，例如 'F:\管柄大桥健康监测数据\'
%   start_date, end_date: 日期范围，字符串 'yyyy-MM-dd'
%   silent: 静默模式，如果为 true 则不询问直接运行（默认 false）

if nargin<1 || isempty(root_dir)
    root_dir = 'F:\管柄大桥健康监测数据\';
end
if nargin<2 || isempty(start_date)
    start_date = input('请输入开始日期 (yyyy-MM-dd): ', 's');
end
if nargin<3 || isempty(end_date)
    end_date   = input('请输入结束日期 (yyyy-MM-dd): ', 's');
end
if nargin<4
    silent = false;
end

% 转日期为 datenum 并筛选日期文件夹
dn0 = datenum(start_date, 'yyyy-mm-dd');
dn1 = datenum(end_date,   'yyyy-mm-dd');
info = dir(fullfile(root_dir, '20??-??-??'));
folders = {info([info.isdir]).name};
selected = {};
for i = 1:numel(folders)
    dn = datenum(folders{i}, 'yyyy-mm-dd');
    if dn>=dn0 && dn<=dn1
        selected{end+1} = folders{i};
    end
end
if isempty(selected)
    error('在指定日期范围内未找到任何文件夹');
end

% 收集所有 ZIP 路径和目标解压目录，跳过无 ZIP 的日期
zipList = {};
outDirs = {};
for i = 1:numel(selected)
    day = selected{i};
    countZ = 0;
    for sub = {'波形','特征值'}
        zdir = fullfile(root_dir, day, sub{1});
        zfiles = dir(fullfile(zdir, '*.zip'));
        if ~isempty(zfiles)
            for k = 1:numel(zfiles)
                zipList{end+1} = fullfile(zfiles(k).folder, zfiles(k).name);
                outDirs{end+1} = zfiles(k).folder;
                countZ = countZ + 1;
            end
        end
    end
    if countZ == 0
        fprintf('警告: 日期 %s 未发现任何 ZIP 文件，已跳过\n', day);
    end
end
N = numel(zipList);
if N == 0
    error('未发现任何 ZIP 文件，终止执行');
end

% 估算解压时间（基于慢速 HDD 45MB/s 测速折算）
dirsz     = cellfun(@(f) dir(f).bytes, zipList);
totalMB   = sum(dirsz) / 1e6;
speedMBps = 45/8;  % 折算综合速率（MB/s）
est_time_s = totalMB / speedMBps;
% 环境依赖说明
env_note = sprintf('（基于慢速 HDD 综合速率 %.2f MB/s）', speedMBps);

time_min = est_time_s / 60;
if time_min > 3
    if silent
        fprintf('预计解压 %.1f 分钟 %s，静默模式下直接开始运行\n', time_min, env_note);
    else
        prompt = sprintf('预计解压 %.1f 分钟 %s，超过3分钟，是否继续？(y/n): ', time_min, env_note);
        c = input(prompt, 's');
        if ~strcmpi(c, 'y')
            disp('操作已取消');
            return;
        end
    end
else
    fprintf('预计解压 %.1f 分钟 %s，开始运行\n', time_min, env_note);
end

% 启动并行池
nCores   = feature('numcores');
nWorkers = min(N, nCores);
pool     = gcp('nocreate');
if isempty(pool)
    parpool('local', nWorkers);
elseif pool.NumWorkers ~= nWorkers
    delete(pool);
    parpool('local', nWorkers);
end

% 并行解压
fprintf('并行解压 %d 个 ZIP，使用 %d 个 worker...\n', N, nWorkers);
resultFiles  = cell(N,1);
resultStatus = cell(N,1);
start_t = tic;
parfor idx = 1:N
    zf  = zipList{idx};
    out = outDirs{idx};
    status = '成功';
    cmd = sprintf(['powershell -NoProfile -Command "Expand-Archive -Path ''%s'' ' ...
                   '-DestinationPath ''%s'' -Force"'], zf, out);
    [s,~] = system(cmd);
    if s~=0
        status = '失败';
    else
        delete(zf);
    end
    resultFiles{idx}  = zf;
    resultStatus{idx} = status;
end
elapsed = toc(start_t);

delete(gcp('nocreate'));

% 合并结果
results = [resultFiles, resultStatus];

% 输出日志和耗时
fprintf('\n处理结果:\n');
for i = 1:N
    fprintf('%s -> %s\n', results{i,1}, results{i,2});
end
fprintf('总耗时: %.2f 秒\n', elapsed);
end
