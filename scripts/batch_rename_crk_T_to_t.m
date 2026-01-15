function batch_rename_crk_T_to_t(root_dir, start_date, end_date, silent)
% batch_rename_crk_T_to_t 简化版：批量将 GB-CRK-...-T*.csv 重命名为 -t*.csv
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date, end_date: 日期范围，'yyyy-MM-dd'
%   silent: 静默模式，如果 true 则不询问（默认 false）

if nargin<1 || isempty(root_dir)
    root_dir = pwd;
end
if nargin<2 || isempty(start_date)
    start_date = input('开始日期 (yyyy-MM-dd): ', 's');
end
if nargin<3 || isempty(end_date)
    end_date = input('结束日期 (yyyy-MM-dd): ', 's');
end
if nargin<4 || isempty(silent)
    silent = false;
end

% 筛选日期文件夹
dn0 = datenum(start_date,'yyyy-mm-dd');
dn1 = datenum(end_date,  'yyyy-mm-dd');
dinfo = dir(fullfile(root_dir,'20??-??-??'));
folders = {dinfo([dinfo.isdir]).name};
sel = folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
if isempty(sel)
    error('未找到符合日期范围的文件夹');
end

% 收集待重命名文件
subdirs = {'波形','波形_重采样','特征值','特征值_重采样'};
files_to_rename = {};
for i=1:numel(sel)
    for k=1:numel(subdirs)
        dir_path = fullfile(root_dir, sel{i}, subdirs{k});
        if ~exist(dir_path,'dir'), continue; end
        % 匹配 -T_*.csv 和 -T.csv 两种情况
        Z1 = dir(fullfile(dir_path,'GB-CRK-*-T_*.csv'));
        Z2 = dir(fullfile(dir_path,'GB-CRK-*-T.csv'));
        Z = [Z1; Z2];
        for j=1:numel(Z)
            files_to_rename{end+1} = fullfile(Z(j).folder, Z(j).name);
        end
    end
end
N = numel(files_to_rename);
if N==0
    fprintf('未发现任何符合 "-T" 的 GB-CRK 文件。');
    return;
end

% 预估时间（每文件约0.01s）
est_s = N * 0.01;
if est_s/60 > 3 && ~silent
    resp = input(sprintf('预计重命名 %d 个文件，约 %.1f 分钟，是否继续？(y/n): ', N, est_s/60), 's');
    if ~strcmpi(resp,'y')
        disp('已取消'); return;
    end
else
    fprintf('将重命名 %d 个文件，预计耗时 %.1f 分钟。', N, est_s/60);
end

% 执行重命名
t0 = tic;
for i=1:N
    oldf = files_to_rename{i};
    [p,name,ext] = fileparts(oldf);
    % 全局替换 -T 为 -t
    new_name = regexprep(name, '-T', '-t');
    newf = fullfile(p, [new_name, ext]);
    try
        if ~strcmp(oldf,newf)
            % 临时重命名流程：先改到临时文件，再改回目标名，避免同名冲突
            tmp_name = [name '_tmp'];
            tmpf = fullfile(p, [tmp_name, ext]);
            % 第一步：重命名旧文件到临时名
            movefile(oldf, tmpf);
            % 第二步：再从临时名改到新文件名
            movefile(tmpf, newf);
            fprintf('%s -> %s\n', name, new_name);
        else
            fprintf('%s 跳过(无需重命名)\n', name);
        end
    catch ME
        fprintf('%s -> FAILED: %s\n', name, ME.message);
    end
end
elapsed = toc(t0);
fprintf('共处理 %d 个文件，耗时 %.2f 秒', N, elapsed);
end
