function summary = batch_unzip_data_parallel(root_dir, start_date, end_date, silent, cfg)
% batch_unzip_data_parallel 安全批量解压监测数据 ZIP。
%   summary = batch_unzip_data_parallel(root_dir, start_date, end_date, silent, cfg)
%
% 兼容旧入口，但实际工作统一交给 ArchiveExtractService：
% - 默认保留原 ZIP；
% - 空间不足直接失败；
% - 每个 ZIP 先解到临时目录，条目数和总字节闭合后再原子发布；
% - 已有目录必须带有效解压清单才能复用；
% - 任意 ZIP 失败都会让整个步骤失败。
%
% silent 仅为旧 GUI 调用兼容参数。安全门槛不会因 silent=true 降级。
if nargin < 1 || isempty(root_dir)
    error('BMS:ArchiveExtract:RootRequired', '必须指定数据根目录。');
end
if nargin < 2 || isempty(start_date)
    start_date = input('请输入开始日期 (yyyy-MM-dd): ', 's');
end
if nargin < 3 || isempty(end_date)
    end_date = input('请输入结束日期 (yyyy-MM-dd): ', 's');
end
if nargin < 4, silent = false; end %#ok<NASGU>
if nargin < 5 || isempty(cfg), cfg = struct(); end

summary = bms.data.ArchiveExtractService.run( ...
    char(string(root_dir)), char(string(start_date)), char(string(end_date)), cfg);

fprintf(['[批量解压] 完成：共 %d 个 ZIP，新解压 %d，复用 %d，失败 %d；' ...
    '并发请求 %s，实际 %d；原压缩包默认保留。\n'], ...
    summary.archive_count, summary.extracted_count, summary.reused_count, ...
    summary.failed_count, char(string(summary.requested_workers)), ...
    summary.effective_workers);
end
