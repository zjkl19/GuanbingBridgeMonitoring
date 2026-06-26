function summaries = separate_zhishan_from_hongtang_months(varargin)
%SEPARATE_ZHISHAN_FROM_HONGTANG_MONTHS Extract Zhishan data from Hongtang exports.
%   This is the operational entry point for the April/May 2026 mixed export.
%   It delegates the whitelist extraction logic to stage_zhishan_subset.
%
%   Example:
%       separate_zhishan_from_hongtang_months('DryRun', true)
%       separate_zhishan_from_hongtang_months('DryRun', false)

    scriptDir = fileparts(mfilename('fullpath'));
    addpath(scriptDir, '-begin');
    rootDir = fileparts(scriptDir);
    defaultConfig = fullfile(rootDir, 'config', 'zhishan_config.json');

    p = inputParser;
    addParameter(p, 'ConfigPath', defaultConfig, @(s)ischar(s)||isstring(s));
    addParameter(p, 'DryRun', false, @(x)islogical(x)||isnumeric(x));
    addParameter(p, 'Overwrite', false, @(x)islogical(x)||isnumeric(x));
    parse(p, varargin{:});

    configPath = char(string(p.Results.ConfigPath));
    dryRun = logical(p.Results.DryRun);
    overwrite = logical(p.Results.Overwrite);

    tasks = {
        'E:\洪塘大桥数据\2026年4月', 'D:\芝山大桥数据\2026年4月', '2026-04-01', '2026-04-30';
        'E:\洪塘大桥数据\2026年5月', 'D:\芝山大桥数据\2026年5月', '2026-05-01', '2026-05-31';
    };

    summaries = struct([]);
    for i = 1:size(tasks, 1)
        fprintf('Separating Zhishan data: %s -> %s (%s to %s)\n', ...
            tasks{i, 1}, tasks{i, 2}, tasks{i, 3}, tasks{i, 4});
        oneSummary = stage_zhishan_subset( ...
            'SourceRoot', tasks{i, 1}, ...
            'TargetRoot', tasks{i, 2}, ...
            'ConfigPath', configPath, ...
            'StartDate', tasks{i, 3}, ...
            'EndDate', tasks{i, 4}, ...
            'Subfolder', '波形', ...
            'SourceMode', 'auto', ...
            'DryRun', dryRun, ...
            'Overwrite', overwrite);
        summaries = [summaries; oneSummary]; %#ok<AGROW>
    end

    totalSourceFiles = sum([summaries.source_files]);
    totalCopied = sum([summaries.copied_files]);
    totalExtracted = sum([summaries.extracted_files]);
    totalWouldCopy = sum([summaries.would_copy_files]);
    totalWouldExtract = sum([summaries.would_extract_files]);
    totalExisting = sum([summaries.existing_files]);
    fprintf('Zhishan separation total: source files %d, copied %d, extracted %d, would copy %d, would extract %d, existing %d\n', ...
        totalSourceFiles, totalCopied, totalExtracted, totalWouldCopy, totalWouldExtract, totalExisting);
end
