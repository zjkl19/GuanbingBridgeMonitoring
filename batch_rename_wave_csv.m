function batch_rename_wave_csv(root_dir, start_date, end_date)
% batch_rename_wave_csv 批量重命名“波形”子文件夹中的CSV文件
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date, end_date: 日期范围，格式 'yyyy-MM-dd'

if nargin<1||isempty(root_dir), root_dir='F:/管柄大桥健康监测数据/'; end
if nargin<2||isempty(start_date), start_date=input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<3||isempty(end_date),   end_date  =input('结束日期 (yyyy-MM-dd): ','s'); end

dn0=datenum(start_date,'yyyy-mm-dd'); dn1=datenum(end_date,'yyyy-mm-dd');
dinfo=dir(fullfile(root_dir,'20??-??-??')); folders={dinfo([dinfo.isdir]).name};
sel={}; for i=1:numel(folders)
  d=datenum(folders{i},'yyyy-mm-dd'); if d>=dn0&&d<=dn1, sel{end+1}=folders{i}; end
end

% 估算重命名预计时间
total_files=0;
for i=1:numel(sel)
  wave_dir=fullfile(root_dir,sel{i},'波形');
  files=dir(fullfile(wave_dir,'*.csv'));
  total_files=total_files+numel(files);
end
est_time= total_files*0.01; % 假设每文件0.01s
if est_time>180
  c=input(sprintf('预计重命名时间%.1f分钟，超3分钟，继续? (y/n): ',est_time/60),'s');
  if ~strcmpi(c,'y'), disp('已取消'); return; end
else
  fprintf('预计重命名时间%.1f分钟，开始运行',est_time/60);
end

start_tic=tic;
log={};
for i=1:numel(sel)
  day=sel{i}; fprintf('处理日期 %s',day);
  wave_dir=fullfile(root_dir,day,'波形');
  files=dir(fullfile(wave_dir,'*.csv'));
  for k=1:numel(files)
    old=files(k).name;
    base=old(1:end-4);
    % 删除 "_原始数据" 到末尾
    newbase=regexprep(base,'_原始数据.*','');
    % 五位连续数字改3-2
    newbase=regexprep(newbase,'(?<!\d)(\d{3})(\d{2})(?!\d)','$1-$2');
    new=[newbase '.csv'];
    try
      movefile(fullfile(wave_dir,old),fullfile(wave_dir,new));
      log{end+1}=sprintf('%s -> %s',old,new);
    catch
      log{end+1}=sprintf('%s -> FAILED',old);
    end
  end
end
elapsed=toc(start_tic);
% 输出日志
fprintf('\n重命名结果:\n');
for j=1:numel(log), fprintf('%s\n',log{j}); end
fprintf('实际运行时间: %.2f秒\n',elapsed);
end
