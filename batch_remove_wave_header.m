function batch_remove_wave_header(root_dir, start_date, end_date)
% batch_remove_wave_header 批量删除“波形”CSV文件头部信息
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date, end_date: 日期范围，格式 'yyyy-MM-dd'

if nargin<1||isempty(root_dir), root_dir='F:/管柄大桥健康监测数据/'; end
if nargin<2||isempty(start_date), start_date=input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<3||isempty(end_date),   end_date  =input('结束日期 (yyyy-MM-dd): ','s'); end

dn0 = datenum(start_date,'yyyy-mm-dd');
dn1 = datenum(end_date,  'yyyy-mm-dd');
dinfo = dir(fullfile(root_dir,'20??-??-??'));
folders = {dinfo([dinfo.isdir]).name};

% 筛选日期范围	
sel = {};
for i=1:numel(folders)
    d = datenum(folders{i},'yyyy-mm-dd');
    if d>=dn0 && d<=dn1, sel{end+1}=folders{i}; end
end

log = {};
start_t = tic;
for i=1:numel(sel)
    day = sel{i};
    wave_dir = fullfile(root_dir, day, '波形');
    files = dir(fullfile(wave_dir,'*.csv'));
    for k=1:numel(files)
        fname = files(k).name;
        fullpath = fullfile(wave_dir, fname);
        fprintf('正在处理 %s / %s\n', day, fname);
        try
            % 检测头部行数
            fid = fopen(fullpath,'rt'); header_lines = 0;
            while ~feof(fid)
                tline = fgetl(fid);
                header_lines = header_lines + 1;
                if contains(tline, '[绝对时间]'), break; end
            end
            fclose(fid);
            % 读取并覆盖原文件
            T = readtable(fullpath, 'Delimiter', ',', 'HeaderLines', header_lines, 'Format', '%s%f');
            writetable(T, fullpath, 'Delimiter', ',', 'WriteVariableNames', false);
            log{end+1} = sprintf('%s -> 已删除头部', fullpath);
        catch ME
            log{end+1} = sprintf('%s -> ERROR: %s', fullpath, ME.message);
        end
    end
end
elapsed = toc(start_t);

% 输出日志
fprintf('\n处理日志：\n');
for j=1:numel(log)
    fprintf('%s\n', log{j});
end
fprintf('总耗时: %.2f 秒\n', elapsed);
end
