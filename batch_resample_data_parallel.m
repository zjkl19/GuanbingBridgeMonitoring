function batch_resample_data_parallel(root_dir, start_date, end_date, default_ratio, silent, config_file)
% batch_resample_data_parallel 并行批量重采样波形及特征值 CSV 数据
%   root_dir       根目录，例如 'F:/监测数据/'
%   start_date     开始日期 'yyyy-MM-dd'
%   end_date       结束日期 'yyyy-MM-dd'
%   default_ratio  默认重采样比例, 仅当配置文件未指定某文件时备用
%   silent         静默模式 true: 不交互确认, 默认 false
%   config_file    CSV 配置文件路径, 必选, 包含 Subfolder,Pattern,Ratio 三列

% 参数校验
if nargin<1||isempty(root_dir),      error('参数 root_dir 必须指定'); end
if nargin<2||isempty(start_date),    error('参数 start_date 必须指定'); end
if nargin<3||isempty(end_date),      error('参数 end_date 必须指定'); end
if nargin<4||isempty(default_ratio), error('参数 default_ratio 必须指定'); end
if nargin<5,                          silent = false; end
if nargin<6||isempty(config_file),   error('参数 config_file 必须指定'); end
if ~exist(config_file,'file'),        error('配置文件 %s 不存在', config_file); end

% 计时开始
timerStart = tic;

% 读取配置文件
cfg = readtable(config_file,'TextType','string');
required = {'Subfolder','Pattern','Ratio'};
if ~all(ismember(required,cfg.Properties.VariableNames))
    error('配置文件必须包含列: %s', strjoin(required,','));
end

% 筛选日期文件夹
dn0 = datenum(start_date,'yyyy-mm-dd');
dn1 = datenum(end_date,  'yyyy-mm-dd');
finfo = dir(fullfile(root_dir,'20??-??-??'));
folders = {finfo([finfo.isdir]).name};
sel = folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
if isempty(sel), error('未找到 %s 到 %s 范围内的日期文件夹', start_date, end_date); end

% 收集待处理文件
inPaths = {}; outPaths = {}; ratios = [];
subs = {}; fnames = {};
c = 0;
for d = sel
    day = d{1};
    for sub = {'波形','特征值'}
        dir_in = fullfile(root_dir,day,sub{1});
        if ~exist(dir_in,'dir'), continue; end
        files = dir(fullfile(dir_in,'*.csv'));
        for k=1:numel(files)
            fname = files(k).name;
            % 只处理在配置中列出的项目
            subcfg = cfg(cfg.Subfolder==sub{1},:);
            matchIdx = find(contains(fname, subcfg.Pattern));
            if isempty(matchIdx)
                continue;  % 跳过未配置的文件
            end
            if numel(matchIdx)>1 && ~silent
                warning('文件%s匹配多条配置，使用第一条',fname);
                matchIdx = matchIdx(1);
            end
            ratio = subcfg.Ratio(matchIdx(1));

            c = c + 1;
            subs{c}    = sub{1};
            fnames{c}  = fname;
            inPaths{c} = fullfile(dir_in, fname);
            outDir = fullfile(root_dir,day,[sub{1} '_重采样']);
            if ~exist(outDir,'dir'), mkdir(outDir); end
            outPaths{c}= fullfile(outDir, fname);
            ratios(c) = ratio;
            if ~silent, fprintf('排入队列: %s/%s (ratio=%d)\n',sub{1},fname,ratio); end
        end
    end
end
N = c;
if N==0, error('未发现任何匹配配置的 CSV 文件'); end

% 估算处理时间
bytes = cellfun(@(p) dir(p).bytes,inPaths);
estSec = sum(bytes)/1e6*0.1;
if estSec/60>3 && ~silent
    yn = input(sprintf('预计处理%.1f分钟, 是否继续?(y/n): ',estSec/60),'s');
    if ~strcmpi(yn,'y'), disp('已取消'); return; end
else
    fprintf('预计处理%.1f分钟, 开始运行\n',estSec/60);
end

% 并行重采样
fprintf('开始并行重采样 %d 个文件...\n',N);
msg = cell(N,1);
parfor i=1:N
    try
        fprintf('正在处理 %d/%d: %s\n',i,N,fnames{i});
        infile = inPaths{i}; outfile = outPaths{i}; r = ratios(i);
        % 检测头部
        fid = fopen(infile,'rt'); h=0; found=false;
        while h<50 && ~feof(fid)
            line = fgetl(fid); h=h+1;
            if contains(line,'[绝对时间]'), found=true; break; end
        end; fclose(fid);
        if ~found
            msg{i} = sprintf('%s 跳过: 无可检测头部',fnames{i}); continue;
        end
        % 读取并重采样
        T = readtable(infile,'Delimiter',',','HeaderLines',h,'Format','%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
        idx2 = 1:r:height(T);
        writetable(T(idx2,:),outfile,'Delimiter',',','WriteVariableNames',false);
        msg{i} = sprintf('%s 重采样完成 (ratio=%d)',fnames{i},r);
    catch ME
        msg{i} = sprintf('%s ERROR: %s',fnames{i},ME.message);
    end
end

% 输出日志及耗时
tElap = toc(timerStart);
if ~silent
    fprintf('\n处理日志:\n');
    for i=1:N, fprintf('%s\n',msg{i}); end
end
fprintf('总耗时: %.2f秒\n',tElap);
end
