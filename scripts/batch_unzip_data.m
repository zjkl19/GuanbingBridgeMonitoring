function batch_unzip_data(root_dir, start_date, end_date)
% batch_unzip_data 批量解压健康监测数据中的 ZIP 文件
%   batch_unzip_data(root_dir, start_date, end_date)
%   root_dir: 根目录，例如 'F:\管柄大桥健康监测数据\'
%   start_date, end_date: 日期范围，字符串 'yyyy-MM-dd'

if nargin < 1 || isempty(root_dir)
    root_dir = 'F:\管柄大桥健康监测数据\';
end
if nargin < 2 || isempty(start_date)
    start_date = input('请输入开始日期 (yyyy-MM-dd): ', 's');
end
if nargin < 3 || isempty(end_date)
    end_date = input('请输入结束日期 (yyyy-MM-dd): ', 's');
end

% 转换为 datenum
dn_start = datenum(start_date, 'yyyy-mm-dd');
dn_end   = datenum(end_date,   'yyyy-mm-dd');

% 列出根目录下的日期文件夹，匹配 20YY-MM-DD 格式
dinfo = dir(fullfile(root_dir, '20??-??-??'));
folders = {dinfo([dinfo.isdir]).name};

% 筛选在日期范围之内的文件夹
selected = {};
for i = 1:numel(folders)
    dn = datenum(folders{i}, 'yyyy-mm-dd');
    if dn >= dn_start && dn <= dn_end
        selected{end+1} = folders{i};
    end
end

% 估算总解压大小
total_bytes = 0;
speed_per_mb = 0.05; % 每MB解压0.05秒
for i = 1:numel(selected)
    date_folder = fullfile(root_dir, selected{i});
    for sub = {'波形','特征值'}
        zfile = dir(fullfile(date_folder, sub{1}, '*.zip'));
        if ~isempty(zfile)
            total_bytes = total_bytes + sum([zfile.bytes]);
        end
    end
end

total_mb = total_bytes / 1e6;
est_time = total_mb * speed_per_mb;
if est_time > 180
    prompt = sprintf('预计解压时间 %.1f 分钟, 超过3分钟。是否继续？(y/n): ', est_time/60);
    c = input(prompt, 's');
    if ~strcmpi(c, 'y')
        fprintf('操作已取消。\n');
        return;
    end
else
    fprintf('预计解压时间 %.1f 分钟，开始运行。\n', est_time/60);
end

% 记录实际开始时间
start_time = tic;

% 逐个日期文件夹解压
results = cell(numel(selected), 2);
for i = 1:numel(selected)
    name = selected{i};
    fprintf('正在处理 %s\n', name);
    date_folder = fullfile(root_dir, name);
    status = '成功';
    try
        for sub = {'波形','特征值'}
            zip_path = fullfile(date_folder, sub{1});
            zfile = dir(fullfile(zip_path, '*.zip'));
            if ~isempty(zfile)
                zip_full = fullfile(zip_path, zfile(1).name);
                unzip(zip_full, zip_path);
                delete(zip_full);
            end
        end
    catch ME
        status = ['失败: ', ME.message];
    end
    results{i,1} = name;
    results{i,2} = status;
end

% 输出处理结果
fprintf('\n处理结果:\n');
fprintf('%-12s  %-s\n', '日期', '状态');
for i = 1:size(results,1)
    fprintf('%-12s  %-s\n', results{i,1}, results{i,2});
end

% 显示实际运行时间
elapsed = toc(start_time);
fprintf('\n实际运行时间: %.2f 秒\n', elapsed);
end
