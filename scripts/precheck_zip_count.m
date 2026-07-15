function summary = precheck_zip_count(root_dir, start_date, end_date, cfg)
% precheck_zip_count 检查指定日期范围内监测 ZIP 是否完整且无重复。
%   支持两种布局：
%   1) 东华日期目录下的“波形/特征值”ZIP；
%   2) 九龙江/水仙花根目录 data_<bridge>_YYYY-MM-DD.zip。
%
% 旧实现只扫描第 1 种布局；当根目录只有每日 ZIP 时会零检查误报通过。
if nargin < 1 || isempty(root_dir)
    error('BMS:ArchiveExtract:RootRequired', '必须指定数据根目录。');
end
if nargin < 2 || isempty(start_date)
    error('BMS:ArchiveExtract:StartDateRequired', '必须指定 start_date。');
end
if nargin < 3 || isempty(end_date)
    error('BMS:ArchiveExtract:EndDateRequired', '必须指定 end_date。');
end
if nargin < 4 || isempty(cfg), cfg = struct(); end

summary = bms.data.ArchiveExtractService.precheck( ...
    char(string(root_dir)), char(string(start_date)), char(string(end_date)), cfg);
fprintf('[压缩包检查] 通过：%s 至 %s，共 %d 个 ZIP（布局：%s）。\n', ...
    char(string(start_date)), char(string(end_date)), summary.archive_count, summary.layout);
end
