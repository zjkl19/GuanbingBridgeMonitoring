function summary = stage_zhishan_subset(varargin)
%STAGE_ZHISHAN_SUBSET Copy Zhishan Bridge CSV files from the mixed Hongtang export.
%   The source tree is left untouched. Existing staged files are skipped
%   unless Overwrite is true.

    rootDir = fileparts(fileparts(mfilename('fullpath')));
    defaultConfig = fullfile(rootDir, 'config', 'zhishan_config.json');

    p = inputParser;
    addParameter(p, 'SourceRoot', 'E:\洪塘大桥数据\2026年1-3月', @(s)ischar(s)||isstring(s));
    addParameter(p, 'TargetRoot', 'D:\芝山大桥数据\2026年3月', @(s)ischar(s)||isstring(s));
    addParameter(p, 'ConfigPath', defaultConfig, @(s)ischar(s)||isstring(s));
    addParameter(p, 'StartDate', '2026-03-01', @(s)ischar(s)||isstring(s));
    addParameter(p, 'EndDate', '2026-03-31', @(s)ischar(s)||isstring(s));
    addParameter(p, 'Subfolder', '波形', @(s)ischar(s)||isstring(s));
    addParameter(p, 'Overwrite', false, @(x)islogical(x)||isnumeric(x));
    parse(p, varargin{:});

    sourceRoot = char(string(p.Results.SourceRoot));
    targetRoot = char(string(p.Results.TargetRoot));
    configPath = char(string(p.Results.ConfigPath));
    subfolder = char(string(p.Results.Subfolder));
    overwrite = logical(p.Results.Overwrite);

    cfg = load_config(configPath);
    fileIds = local_collect_file_ids(cfg);

    startDate = datetime(p.Results.StartDate, 'InputFormat', 'yyyy-MM-dd');
    endDate = datetime(p.Results.EndDate, 'InputFormat', 'yyyy-MM-dd');
    dates = startDate:days(1):endDate;

    summary = struct();
    summary.source_root = sourceRoot;
    summary.target_root = targetRoot;
    summary.config_path = configPath;
    summary.start_date = char(string(p.Results.StartDate));
    summary.end_date = char(string(p.Results.EndDate));
    summary.subfolder = subfolder;
    summary.file_ids = fileIds(:).';
    summary.date_count = numel(dates);
    summary.source_date_count = 0;
    summary.missing_dates = {};
    summary.copied_files = 0;
    summary.existing_files = 0;
    summary.source_files = 0;
    summary.missing_point_files = {};
    summary.copied_paths = {};

    if ~isfolder(sourceRoot)
        error('stage_zhishan_subset:MissingSourceRoot', 'SourceRoot does not exist: %s', sourceRoot);
    end
    if ~isfolder(targetRoot)
        mkdir(targetRoot);
    end

    for i = 1:numel(dates)
        dayText = char(datestr(dates(i), 'yyyy-mm-dd'));
        srcDir = fullfile(sourceRoot, dayText, subfolder);
        if ~isfolder(srcDir)
            summary.missing_dates{end+1, 1} = dayText; %#ok<AGROW>
            continue;
        end
        summary.source_date_count = summary.source_date_count + 1;

        dstDir = fullfile(targetRoot, dayText, subfolder);
        if ~isfolder(dstDir)
            mkdir(dstDir);
        end

        for k = 1:numel(fileIds)
            fileId = fileIds{k};
            matches = dir(fullfile(srcDir, [fileId '_*.csv']));
            if isempty(matches)
                summary.missing_point_files{end+1, 1} = sprintf('%s/%s', dayText, fileId); %#ok<AGROW>
                continue;
            end
            summary.source_files = summary.source_files + numel(matches);
            for m = 1:numel(matches)
                src = fullfile(matches(m).folder, matches(m).name);
                dst = fullfile(dstDir, matches(m).name);
                if isfile(dst) && ~overwrite
                    summary.existing_files = summary.existing_files + 1;
                    continue;
                end
                copyfile(src, dst);
                summary.copied_files = summary.copied_files + 1;
                summary.copied_paths{end+1, 1} = dst; %#ok<AGROW>
            end
        end
    end

    fprintf('Zhishan staging: dates %d/%d, source files %d, copied %d, existing %d, missing dates %d\n', ...
        summary.source_date_count, summary.date_count, summary.source_files, ...
        summary.copied_files, summary.existing_files, numel(summary.missing_dates));
end

function fileIds = local_collect_file_ids(cfg)
    fileIds = {};
    modules = {'strain', 'bearing_displacement', 'acceleration', 'cable_accel'};
    if ~isstruct(cfg) || ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point)
        return;
    end
    for i = 1:numel(modules)
        moduleKey = modules{i};
        if ~isfield(cfg.per_point, moduleKey) || ~isstruct(cfg.per_point.(moduleKey))
            continue;
        end
        points = cfg.per_point.(moduleKey);
        names = fieldnames(points);
        for j = 1:numel(names)
            rec = points.(names{j});
            if isstruct(rec) && isfield(rec, 'file_id') && ~isempty(rec.file_id)
                fileIds{end+1, 1} = char(string(rec.file_id)); %#ok<AGROW>
            end
        end
    end
    fileIds = unique(fileIds, 'stable');
end
