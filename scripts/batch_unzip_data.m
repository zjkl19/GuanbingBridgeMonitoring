function batch_unzip_data(root_dir, start_date, end_date)
% batch_unzip_data  批量解压监测数据 ZIP。
%   兼容两种目录口径：
%   1) 旧口径：<root>\YYYY-MM-DD\波形|特征值\*.zip
%   2) 九龙江新口径：<root>\data_jlj_YYYY-MM-DD.zip

if nargin < 1 || isempty(root_dir)
    root_dir = pwd;
end
if nargin < 2 || isempty(start_date)
    start_date = input('请输入开始日期 (yyyy-MM-dd): ', 's');
end
if nargin < 3 || isempty(end_date)
    end_date = input('请输入结束日期 (yyyy-MM-dd): ', 's');
end

dn0 = datenum(start_date, 'yyyy-mm-dd');
dn1 = datenum(end_date, 'yyyy-mm-dd');

zipList = {};
outDirs = {};

% 旧口径
dinfo = dir(fullfile(root_dir, '20??-??-??'));
folders = {dinfo([dinfo.isdir]).name};
for i = 1:numel(folders)
    dn = datenum(folders{i}, 'yyyy-mm-dd');
    if dn < dn0 || dn > dn1
        continue;
    end
    date_folder = fullfile(root_dir, folders{i});
    for sub = {'波形', '特征值'}
        zdir = fullfile(date_folder, sub{1});
        zfiles = dir(fullfile(zdir, '*.zip'));
        for k = 1:numel(zfiles)
            zipList{end+1} = fullfile(zfiles(k).folder, zfiles(k).name); %#ok<AGROW>
            outDirs{end+1} = zfiles(k).folder; %#ok<AGROW>
        end
    end
end

% 九龙江新口径
if isempty(zipList)
    zfiles = dir(fullfile(root_dir, 'data_jlj_*.zip'));
    for i = 1:numel(zfiles)
        tok = regexp(zfiles(i).name, '^data_jlj_(\d{4})-(\d{2})-(\d{2})\.zip$', 'tokens', 'once');
        if isempty(tok)
            continue;
        end
        day = sprintf('%s-%s-%s', tok{1}, tok{2}, tok{3});
        dn = datenum(day, 'yyyy-mm-dd');
        if dn < dn0 || dn > dn1
            continue;
        end
        zipList{end+1} = fullfile(zfiles(i).folder, zfiles(i).name); %#ok<AGROW>
        outDirs{end+1} = fullfile(root_dir, sprintf('data_jlj_%s', day)); %#ok<AGROW>
    end
end

if isempty(zipList)
    error('未找到 %s 到 %s 范围内的日期文件夹，且未找到 data_jlj_YYYY-MM-DD.zip', start_date, end_date);
end

fprintf('共发现 %d 个 ZIP，开始解压。\n', numel(zipList));
start_t = tic;
for i = 1:numel(zipList)
    zf = zipList{i};
    out = outDirs{i};
    if ~exist(out, 'dir')
        mkdir(out);
    end
    fprintf('解压 %s -> %s\n', zf, out);
    unzip(zf, out);
    delete(zf);
end
fprintf('完成，总耗时 %.2f 秒。\n', toc(start_t));
end
