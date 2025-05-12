function batch_resample_data_parallel1(root_dir, start_date, end_date, resample_ratio, silent, config_file)
% batch_resample_data_parallel 并行批量删除头部并重采样波形及特征值 CSV 数据，另存到新文件夹
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date, end_date: 日期范围，'yyyy-MM-dd'
%   resample_ratio: 重采样比例，如100表示每100条取1条
%   silent: 静默模式（true跳过确认，默认false）
%   config_file: 可选，CSV 配置文件路径，包含 Subfolder,Pattern 两列，用于筛选要处理的文件

if nargin<1 || isempty(root_dir),       root_dir='F:/管柄大桥健康监测数据/'; end
if nargin<2 || isempty(start_date),      start_date=input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<3 || isempty(end_date),        end_date  =input('结束日期 (yyyy-MM-dd): ','s'); end
if nargin<4 || isempty(resample_ratio),  resample_ratio=input('重采样比例 (如100 表示每100条取1条): '); end
if nargin<5,                              silent=false; end
if nargin<6,                              config_file=''; end

% 读取配置文件（可选）
useConfig = false;
if ~isempty(config_file) && exist(config_file,'file')
    cfg = readtable(config_file, 'TextType','string');
    % 期望列名: Subfolder, Pattern
    if all(ismember({'Subfolder','Pattern'}, cfg.Properties.VariableNames))
        useConfig = true;
    else
        warning('配置文件缺少 Subfolder 或 Pattern 列，将忽略配置');
    end
end

% 转为 datenum 并筛选日期文件夹
dn0 = datenum(start_date,'yyyy-mm-dd'); dn1 = datenum(end_date,'yyyy-mm-dd');
finfo = dir(fullfile(root_dir,'20??-??-??')); folders = {finfo([finfo.isdir]).name};
sel = folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
if isempty(sel), error('未找到符合日期范围的文件夹'); end

% 收集所有输入输出路径列表
days = {}; subs = {}; fnames = {}; inPaths = {}; outPaths = {}; c = 0;
for i = 1:numel(sel)
    day = sel{i};
    for sub = {'波形','特征值'}
        in_dir = fullfile(root_dir, day, sub{1});
        if ~exist(in_dir,'dir'), continue; end
        files = dir(fullfile(in_dir,'*.csv'));
        for k = 1:numel(files)
            fname = files(k).name;
            % 配置过滤
            if useConfig
                mask = cfg.Subfolder==sub{1} & contains(fname, cfg.Pattern);
                if ~any(mask)
                    continue; % 不在配置列表中，跳过
                end
            end
            c = c + 1;
            days{c}      = day;
            subs{c}      = sub{1};
            fnames{c}    = fname;
            inPaths{c}   = fullfile(in_dir, fname);
            out_dir = fullfile(root_dir, day, [sub{1} '_重采样']);
            if ~exist(out_dir,'dir'), mkdir(out_dir); end
            outPaths{c}  = fullfile(out_dir, fname);
        end
    end
end
N = c;
if N==0, error('未发现任何符合配置的 CSV 文件'); end

% 估算处理时间（每MB约0.1s）
total_bytes = 0;
for i=1:N, total_bytes = total_bytes + dir(inPaths{i}).bytes; end
est_s = (total_bytes/1e6)*0.1; time_min = est_s/60;
if time_min>3
    if silent
        fprintf('预计处理 %.1f 分钟，静默模式直接开始\n', time_min);
    else
        c0 = input(sprintf('预计处理 %.1f 分钟，是否继续？(y/n): ', time_min),'s');
        if ~strcmpi(c0,'y'), disp('已取消'); return; end
    end
else
    fprintf('预计处理 %.1f 分钟，开始运行\n', time_min);
end

% 并行处理
resultMsgs = cell(N,1);
start_t = tic;
parfor idx = 1:N
    subf = subs{idx}; fname = fnames{idx};
    infile = inPaths{idx}; outfile = outPaths{idx};
    try
        % 限制前50行检测头部
        fid = fopen(infile,'rt'); h=0; found=false;
        for j=1:50
            if feof(fid), break; end
            line = fgetl(fid); h=h+1;
            if contains(line,'[绝对时间]')
                found=true; break;
            end
        end; fclose(fid);
        if ~found
            resultMsgs{idx} = sprintf('%s/%s -> 跳过: 已预处理或无头部', subf, fname);
            continue;
        end
        % 读取并重采样
        T = readtable(infile,'Delimiter',',','HeaderLines',h,'Format','%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
        idx2 = 1:resample_ratio:height(T); T2 = T(idx2,:);
        writetable(T2, outfile, 'Delimiter',',','WriteVariableNames', false);
        resultMsgs{idx} = sprintf('%s/%s -> 重采样完成', subf, fname);
    catch ME
        resultMsgs{idx} = sprintf('%s/%s -> ERROR: %s', subf, fname, ME.message);
    end
end
elapsed = toc(start_t);
delete(gcp('nocreate'));

% 输出结果
if silent
    fprintf('总处理文件: %d，耗时: %.2f 秒\n', N, elapsed);
else
    fprintf('\n处理日志:\n');
    for i=1:N, fprintf('%s\n', resultMsgs{i}); end
    fprintf('总耗时: %.2f 秒\n', elapsed);
end
end
