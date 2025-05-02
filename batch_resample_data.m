function batch_resample_data(root_dir, start_date, end_date, resample_ratio, silent)
% batch_resample_data 批量删除头部并重采样波形及特征值 CSV 数据，另存到新文件夹
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date, end_date: 日期范围，'yyyy-MM-dd'
%   resample_ratio: 重采样比例，如100表示每100条取1条
%   silent: 静默模式（true跳过确认，默认false）

if nargin<1||isempty(root_dir),   root_dir='F:/管柄大桥健康监测数据/'; end
if nargin<2||isempty(start_date),  start_date=input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<3||isempty(end_date),    end_date  =input('结束日期 (yyyy-mm-dd): ','s'); end
if nargin<4||isempty(resample_ratio), resample_ratio=input('重采样比例 (如100表示每100条取1条): '); end
if nargin<5, silent=false; end

% 转为datenum并筛选日期文件夹
dn0=datenum(start_date,'yyyy-mm-dd'); dn1=datenum(end_date,'yyyy-mm-dd');
finfo=dir(fullfile(root_dir,'20??-??-??')); folders={finfo([finfo.isdir]).name};
sel=folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
if isempty(sel), error('未找到符合日期范围的文件夹'); end

% 估算处理时间（每MB约0.1s）
total_bytes=0;
for i=1:numel(sel)
    for sub={'波形','特征值'}
        d=dir(fullfile(root_dir,sel{i},sub{1},'*.csv'));
        total_bytes=total_bytes+sum([d.bytes]);
    end
end
total_MB=total_bytes/1e6; est_s=total_MB*0.1;
time_min=est_s/60;
if time_min>3
    if silent
        fprintf('预计处理 %.1f 分钟，静默模式直接开始\n',time_min);
    else
        c=input(sprintf('预计处理 %.1f 分钟，超过3分钟，是否继续？(y/n): ',time_min),'s');
        if ~strcmpi(c,'y'), disp('已取消'); return; end
    end
else
    fprintf('预计处理 %.1f 分钟，开始运行\n',time_min);
end

% 检查覆盖风险
overwrite=false;
for i=1:numel(sel)
    if exist(fullfile(root_dir,sel{i},'波形_重采样'),'dir') && ~isempty(dir(fullfile(root_dir,sel{i},'波形_重采样','*.csv')))
        overwrite=true; break;
    end
end
if overwrite && ~silent
    c2=input('检测到已有重采样结果，可能覆盖，是否继续？(y/n): ','s');
    if ~strcmpi(c2,'y'), disp('已取消'); return; end
end

% 处理
start_t=tic; log={};
for i=1:numel(sel)
    day=sel{i};
    for sub={'波形','特征值'}
        in_dir = fullfile(root_dir,day,sub{1});
        out_dir= fullfile(root_dir,day,[sub{1} '_重采样']);
        if ~exist(out_dir,'dir'), mkdir(out_dir); end
        files=dir(fullfile(in_dir,'*.csv'));
        for k=1:numel(files)
            fname=files(k).name;
            fprintf('处理 %s/%s/%s\n',day,sub{1},fname);
            infile=fullfile(in_dir,fname);
            outfile=fullfile(out_dir,fname);
            try
                % 检测头部
                fid=fopen(infile,'rt'); h=0;
                while ~feof(fid), ln=fgetl(fid); h=h+1; if contains(ln,'[绝对时间]'), break; end; end; fclose(fid);
                % 读取并重采样
                T=readtable(infile,'Delimiter',',','HeaderLines',h,'Format','%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
                idx=1:resample_ratio:height(T); T2=T(idx,:);
                % 保存
                writetable(T2,outfile,'Delimiter',',','WriteVariableNames',false);
                log{end+1}=sprintf('%s/%s -> %s',sub{1},fname,outfile);
            catch ME
                log{end+1}=sprintf('%s/%s ERROR: %s',sub{1},fname,ME.message);
            end
        end
    end
end
elapsed=toc(start_t);

% 输出
fprintf('\n处理日志:\n'); for j=1:numel(log), fprintf('%s\n',log{j}); end
fprintf('总耗时: %.2f 秒\n',elapsed);
end
