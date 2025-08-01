function precheck_zip_count(root_dir, start_date, end_date)
% precheck_zip_count  预检查：波形/特征值 子目录内 ZIP 数必须各=1
%
%   precheck_zip_count(root_dir, start_date, end_date)
%
%   如果发现 0 个或 >1 个 ZIP，列出全部异常并抛出 error 终止。
%
%   作者：ChatGPT  (2025-07-31)

%% ---------- 参数检查 ----------
if nargin < 1 || isempty(root_dir)
    root_dir = 'F:\管柄大桥健康监测数据\';
end
if nargin < 2 || isempty(start_date)
    error('必须指定 start_date');
end
if nargin < 3 || isempty(end_date)
    error('必须指定 end_date');
end

dn0 = datenum(start_date, 'yyyy-mm-dd');
dn1 = datenum(end_date,   'yyyy-mm-dd');

%% ---------- 收集日期目录 ----------
info = dir(fullfile(root_dir, '20??-??-??'));
dateDirs = {info([info.isdir]).name};

%% ---------- 逐日逐子目录检查 ----------
badList = struct('day', {}, 'subdir', {}, 'count', {}, 'zips', {});

for i = 1:numel(dateDirs)
    day = dateDirs{i};
    dn  = datenum(day, 'yyyy-mm-dd');
    if dn < dn0 || dn > dn1
        continue;
    end

    for sub = {'波形','特征值'}
        subDirName = sub{1};
        zfiles = dir(fullfile(root_dir, day, subDirName, '*.zip'));
        cnt    = numel(zfiles);

        if cnt ~= 1        % 0 个或 >1 个都视为异常
            badList(end+1).day    = day;           %#ok<SAGROW>
            badList(end).subdir   = subDirName;
            badList(end).count    = cnt;
            badList(end).zips     = arrayfun(@(f) fullfile(f.folder,f.name), ...
                                             zfiles, 'UniformOutput', false);
        end
    end
end

%% ---------- 打印结果 / 抛错 ----------
if isempty(badList)
    fprintf('[预检查] 波形 / 特征值 子目录 ZIP 数量均为 1 —— 检查通过。\n');
    return;
end

fprintf('[预检查] 检测到 ZIP 数量异常的子目录如下：\n');
for i = 1:numel(badList)
    bd = badList(i);
    fprintf('  日期 %s  子目录 <%s>  ZIP 数 = %d\n', ...
            bd.day, bd.subdir, bd.count);
    for j = 1:numel(bd.zips)
        fprintf('     · %s\n', bd.zips{j});
    end
end
error('ZIP 文件数量异常，已终止运行，请先排查以上日期子目录。');
end
