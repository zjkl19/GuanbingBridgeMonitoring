function batch_unzip_data_parallel(root_dir, start_date, end_date, silent)
% batch_unzip_data_parallel  批量解压监测数据 ZIP（PowerShell Expand-Archive）。
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
        selected{end+1} = folders{i}; %#ok<AGROW>
    end
end
if isempty(selected)
    error('指定日期范围内未找到日期文件夹');
end

% 收集 ZIP 列表
zipList = {};
outDirs = {};
for i = 1:numel(selected)
    day = selected{i}; countZ = 0;
    for sub = {'波形','特征值'}
        zdir = fullfile(root_dir, day, sub{1});
        zfiles = dir(fullfile(zdir, '*.zip'));
        if ~isempty(zfiles)
            for k = 1:numel(zfiles)
                zipList{end+1} = fullfile(zfiles(k).folder, zfiles(k).name); %#ok<AGROW>
                outDirs{end+1} = zfiles(k).folder; %#ok<AGROW>
                countZ = countZ + 1;
            end
        end
    end
    if countZ == 0
        fprintf('警告: 日期 %s 未找到 ZIP, 已跳过\n', day);
    end
end
N = numel(zipList);
if N == 0
    error('未发现任何 ZIP 文件，终止执行');
end

% 预估磁盘与时间
[totalGB, freeGB, fileObj] = estimate_space(zipList, root_dir);
check_disk_space(freeGB, totalGB, silent);
estimate_time(totalGB, silent);

% 并行池（限制在本地集群上限，失败回退串行）
nCores = feature('numcores');
cl = parcluster('local');
maxWorkers = cl.NumWorkers;
nWorkers = min([N, nCores, maxWorkers]);
pool = gcp('nocreate');
try
    if nWorkers >= 2
        if isempty(pool) || pool.NumWorkers ~= nWorkers
            if ~isempty(pool), delete(pool); end
            parpool(cl, nWorkers);
        end
    else
        if ~isempty(pool), delete(pool); end
        pool = [];
    end
catch ME
    warning('启用并行池失败（%s），改为串行展开。', ME.message);
    if ~isempty(pool), delete(pool); end
    pool = [];
    nWorkers = 0;
end

% 展开
fprintf('展开 %d 个 ZIP，使用 worker 数: %d (最大允许 %d)...\n', N, nWorkers, maxWorkers);
resultFiles  = cell(N,1);
resultStatus = cell(N,1);
start_t = tic;
if nWorkers >= 2
    parfor idx = 1:N
        [resultFiles{idx}, resultStatus{idx}] = unzip_one(zipList{idx}, outDirs{idx});
    end
else
    for idx = 1:N
        [resultFiles{idx}, resultStatus{idx}] = unzip_one(zipList{idx}, outDirs{idx});
    end
end
elapsed = toc(start_t);

delete(gcp('nocreate'));

% 解压后磁盘空间
freeBytes2 = fileObj.getFreeSpace(); freeGB2 = freeBytes2/1e9;
fprintf('解压完成，剩余空间 %.2f GB\n', freeGB2);

% 日志
fprintf('\n处理结果:\n');
for i = 1:N
    fprintf('%s -> %s\n', resultFiles{i}, resultStatus{i});
end
fprintf('总耗时: %.2f 秒\n', elapsed);
end

function [zf, status] = unzip_one(zf, out)
    status = '成功';
    cmd = sprintf(['powershell -NoProfile -Command "Expand-Archive -Path ''%s'' ' ...
                   '-DestinationPath ''%s'' -Force"'], zf, out);
    [s,~] = system(cmd);
    if s~=0
        status = '失败';
    else
        delete(zf);
    end
end

function [totalGB, freeGB, fileObj] = estimate_space(zipList, root_dir)
    totalBytes = 0;
    for i = 1:numel(zipList)
        zfPath = zipList{i};
        jz = java.util.zip.ZipFile(zfPath);
        entries = jz.entries();
        while entries.hasMoreElements()
            entry = entries.nextElement();
            totalBytes = totalBytes + entry.getSize();
        end
        jz.close();
    end
    totalGB = totalBytes / 1e9;
    drive = root_dir(1:3);
    fileObj = java.io.File(drive);
    freeGB = fileObj.getFreeSpace()/1e9;
    fprintf('当前磁盘空余: %.2f GB，预计解压需 %.2f GB\n', freeGB, totalGB);
end

function check_disk_space(freeGB, totalGB, silent)
    if freeGB < totalGB + 10
        if silent
            warning('可用空间可能不足 10GB 余量，仍继续。');
        else
            c = input('磁盘富余可能不足 10GB，是否继续?(y/n): ', 's');
            if ~strcmpi(c,'y')
                error('用户取消。');
            end
        end
    end
end

function estimate_time(totalGB, silent)
    speedMBps = 45/8;  % 约 45MB/s HDD
    est_time_s = totalGB*1024/speedMBps;
    time_min = est_time_s/60;
    if time_min > 3 && ~silent
        c = input(sprintf('预计耗时 %.1f 分钟，是否继续?(y/n): ', time_min), 's');
        if ~strcmpi(c,'y')
            error('用户取消。');
        end
    else
        fprintf('预计耗时 %.1f 分钟，开始运行。\n', time_min);
    end
end
