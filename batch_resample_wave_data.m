function batch_resample_wave_data(root_dir, start_date, end_date, resample_ratio)
% batch_resample_wave_data 批量删除头部并重采样波形 CSV 数据，另存到新文件夹
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date, end_date: 日期范围，'yyyy-MM-dd'
%   resample_ratio: 重采样比例, 如 100 表示每100条取1条

if nargin<1||isempty(root_dir), root_dir='F:/管柄大桥健康监测数据/'; end
if nargin<2||isempty(start_date), start_date=input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<3||isempty(end_date),   end_date  =input('结束日期 (yyyy-MM-dd): ','s'); end
if nargin<4||isempty(resample_ratio), resample_ratio = input('重采样比例 (如100表示每100条取1条): '); end

dn0 = datenum(start_date,'yyyy-mm-dd');
dn1 = datenum(end_date,'yyyy-mm-dd');
dinfo = dir(fullfile(root_dir,'20??-??-??'));
folders = {dinfo([dinfo.isdir]).name};

% 筛选日期范围
sel = {};
for i = 1:numel(folders)
    dn = datenum(folders{i},'yyyy-mm-dd');
    if dn>=dn0 && dn<=dn1
        sel{end+1} = folders{i};
    end
end

% 估算处理时间（基于文件大小）
total_bytes = 0;
speed_MB_per_s = 1.44; % 经验读取+写入速度
for i = 1:numel(sel)
    wave_dir = fullfile(root_dir, sel{i}, '波形');
    files = dir(fullfile(wave_dir, '*.csv'));
    total_bytes = total_bytes + sum([files.bytes]);
end

total_MB = total_bytes / 1e6;
est_time = total_MB / speed_MB_per_s; % 秒
if est_time/60 > 3
    c = input(sprintf('预计处理 %.1f 分钟, 超过3分钟，是否继续？(y/n): ', est_time/60),'s');
    if ~strcmpi(c,'y'), disp('已取消'); return; end
else
    fprintf('预计处理 %.1f 分钟，开始运行。', est_time/60);
end

% 检查覆盖风险
overwrite_flag = false;
for i = 1:numel(sel)
    res_dir = fullfile(root_dir, sel{i}, '波形_重采样');
    if exist(res_dir, 'dir') && ~isempty(dir(fullfile(res_dir, '*.csv')))
        overwrite_flag = true;
        break;
    end
end
if overwrite_flag
    c2 = input('检测到目标文件夹中已有文件，可能被覆盖，是否继续？(y/n): ', 's');
    if ~strcmpi(c2,'y'), disp('已取消'); return; end
end

start_t0 = tic;
log = {};

for i = 1:numel(sel)
    day = sel{i};
    fprintf('处理日期 %s', day);
    wave_dir = fullfile(root_dir, day, '波形');
    res_dir  = fullfile(root_dir, day, '波形_重采样');
    if ~exist(res_dir,'dir'), mkdir(res_dir); end
    files = dir(fullfile(wave_dir,'*.csv'));
    for k = 1:numel(files)
        old_full = fullfile(wave_dir, files(k).name);
        new_full = fullfile(res_dir, files(k).name);
        fprintf('  处理文件 %s...', files(k).name);
        try
            process_file(old_full, resample_ratio, new_full);
            log{end+1} = sprintf('%s -> %s', old_full, new_full);
        catch ME
            log{end+1} = sprintf('%s -> ERROR: %s', files(k).name, ME.message);
        end
    end
end

elapsed = toc(start_t0);

fprintf('重采样结果：');
for j = 1:numel(log)
    fprintf('%s\n', log{j});
end
fprintf('总耗时: %.2f 秒\n', elapsed);
end

function process_file(infile, ratio, outfile)
    % 删除头部并重采样，另存为 outfile
    fid = fopen(infile,'rt'); header = 0;
    for L = 1:50
        ln = fgetl(fid); header = header+1;
        if contains(ln,'[绝对时间]'), break; end
    end
    fclose(fid);
    T = readtable(infile, 'Delimiter', ',', 'HeaderLines', header, 'Format', '%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
    idx = 1:ratio:height(T);
    T2 = T(idx,:);
    writetable(T2, outfile, 'Delimiter', ',', 'WriteVariableNames', false);
end
