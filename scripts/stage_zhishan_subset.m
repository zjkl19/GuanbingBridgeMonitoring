function summary = stage_zhishan_subset(varargin)
%STAGE_ZHISHAN_SUBSET Stage Zhishan CSV files from a mixed Hongtang export.
%   The source tree is left untouched. SourceMode="files" copies from an
%   already extracted day/subfolder tree. SourceMode="zip" extracts only the
%   configured Zhishan CSV entries from day/subfolder/*.zip. SourceMode="auto"
%   prefers extracted CSVs and falls back to zip extraction.

    rootDir = fileparts(fileparts(mfilename('fullpath')));
    defaultConfig = fullfile(rootDir, 'config', 'zhishan_config.json');

    p = inputParser;
    addParameter(p, 'SourceRoot', 'E:\洪塘大桥数据\2026年1-3月', @(s)ischar(s)||isstring(s));
    addParameter(p, 'TargetRoot', 'D:\芝山大桥数据\2026年3月', @(s)ischar(s)||isstring(s));
    addParameter(p, 'ConfigPath', defaultConfig, @(s)ischar(s)||isstring(s));
    addParameter(p, 'StartDate', '2026-03-01', @(s)ischar(s)||isstring(s));
    addParameter(p, 'EndDate', '2026-03-31', @(s)ischar(s)||isstring(s));
    addParameter(p, 'Subfolder', '波形', @(s)ischar(s)||isstring(s));
    addParameter(p, 'SourceMode', 'auto', @(s)ischar(s)||isstring(s));
    addParameter(p, 'Overwrite', false, @(x)islogical(x)||isnumeric(x));
    addParameter(p, 'DryRun', false, @(x)islogical(x)||isnumeric(x));
    addParameter(p, 'IncludeDesignOnly', false, @(x)islogical(x)||isnumeric(x));
    parse(p, varargin{:});

    sourceRoot = char(string(p.Results.SourceRoot));
    targetRoot = char(string(p.Results.TargetRoot));
    configPath = char(string(p.Results.ConfigPath));
    subfolder = char(string(p.Results.Subfolder));
    sourceMode = validatestring(char(lower(string(p.Results.SourceMode))), {'auto', 'files', 'zip'});
    overwrite = logical(p.Results.Overwrite);
    dryRun = logical(p.Results.DryRun);

    cfg = load_config(configPath);
    fileIds = local_collect_file_ids(cfg, logical(p.Results.IncludeDesignOnly));

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
    summary.source_mode = sourceMode;
    summary.overwrite = overwrite;
    summary.dry_run = dryRun;
    summary.file_ids = fileIds(:).';
    summary.date_count = numel(dates);
    summary.source_date_count = 0;
    summary.missing_dates = {};
    summary.copied_files = 0;
    summary.would_copy_files = 0;
    summary.extracted_files = 0;
    summary.would_extract_files = 0;
    summary.existing_files = 0;
    summary.source_files = 0;
    summary.zip_files = 0;
    summary.bad_zip_files = {};
    summary.missing_point_files = {};
    summary.copied_paths = {};

    if ~isfolder(sourceRoot)
        error('stage_zhishan_subset:MissingSourceRoot', 'SourceRoot does not exist: %s', sourceRoot);
    end
    if ~dryRun && ~isfolder(targetRoot)
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
        if ~dryRun && ~isfolder(dstDir)
            mkdir(dstDir);
        end

        resolvedMode = local_resolve_source_mode(srcDir, fileIds, sourceMode);
        if strcmp(resolvedMode, 'files')
            summary = local_stage_extracted_files(summary, srcDir, dstDir, dayText, fileIds, overwrite, dryRun);
        else
            summary = local_stage_zip_files(summary, srcDir, dstDir, dayText, fileIds, overwrite, dryRun);
        end
    end

    fprintf('Zhishan staging: mode=%s, dryRun=%d, dates %d/%d, source files %d, copied %d, extracted %d, existing %d, missing dates %d\n', ...
        summary.source_mode, summary.dry_run, summary.source_date_count, summary.date_count, summary.source_files, ...
        summary.copied_files, summary.extracted_files, summary.existing_files, numel(summary.missing_dates));
    if dryRun
        fprintf('Dry-run pending actions: would copy %d, would extract %d\n', ...
            summary.would_copy_files, summary.would_extract_files);
    end
end

function mode = local_resolve_source_mode(srcDir, fileIds, sourceMode)
    if ~strcmp(sourceMode, 'auto')
        mode = sourceMode;
        return;
    end
    for k = 1:numel(fileIds)
        if ~isempty(dir(fullfile(srcDir, [fileIds{k} '_*.csv'])))
            mode = 'files';
            return;
        end
    end
    if ~isempty(dir(fullfile(srcDir, '*.zip')))
        mode = 'zip';
    else
        mode = 'files';
    end
end

function summary = local_stage_extracted_files(summary, srcDir, dstDir, dayText, fileIds, overwrite, dryRun)
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
            summary = local_copy_csv(summary, src, dst, overwrite, dryRun);
        end
    end
end

function summary = local_stage_zip_files(summary, srcDir, dstDir, dayText, fileIds, overwrite, dryRun)
    zipFiles = dir(fullfile(srcDir, '*.zip'));
    if isempty(zipFiles)
        for k = 1:numel(fileIds)
            summary.missing_point_files{end+1, 1} = sprintf('%s/%s', dayText, fileIds{k}); %#ok<AGROW>
        end
        return;
    end
    [~, zipOrder] = sort([zipFiles.bytes], 'descend');
    zipFiles = zipFiles(zipOrder);

    foundById = zeros(numel(fileIds), 1);
    for z = 1:numel(zipFiles)
        if all(foundById > 0)
            break;
        end
        zipPath = fullfile(zipFiles(z).folder, zipFiles(z).name);
        summary.zip_files = summary.zip_files + 1;
        try
            entries = local_zip_entry_names(zipPath);
        catch ME
            summary.bad_zip_files{end+1, 1} = sprintf('%s: %s', zipPath, ME.message); %#ok<AGROW>
            continue;
        end
        pendingEntries = {};
        pendingDsts = {};
        for e = 1:numel(entries)
            entryName = entries{e};
            baseName = local_zip_base_name(entryName);
            fileIdx = local_matching_file_id_index(baseName, fileIds);
            if fileIdx < 1
                continue;
            end
            if foundById(fileIdx) > 0
                continue;
            end
            foundById(fileIdx) = foundById(fileIdx) + 1;
            summary.source_files = summary.source_files + 1;
            dst = fullfile(dstDir, baseName);
            if isfile(dst) && ~overwrite
                summary.existing_files = summary.existing_files + 1;
            elseif dryRun
                summary.would_extract_files = summary.would_extract_files + 1;
            else
                pendingEntries{end+1, 1} = entryName; %#ok<AGROW>
                pendingDsts{end+1, 1} = dst; %#ok<AGROW>
            end
        end
        if ~dryRun && ~isempty(pendingEntries)
            local_extract_zip_entries(zipPath, pendingEntries, dstDir, pendingDsts);
            summary.extracted_files = summary.extracted_files + numel(pendingEntries);
            summary.copied_paths = [summary.copied_paths; pendingDsts(:)]; %#ok<AGROW>
        end
    end

    for k = 1:numel(fileIds)
        if foundById(k) == 0
            summary.missing_point_files{end+1, 1} = sprintf('%s/%s', dayText, fileIds{k}); %#ok<AGROW>
        end
    end
end

function summary = local_copy_csv(summary, src, dst, overwrite, dryRun)
    if isfile(dst) && ~overwrite
        summary.existing_files = summary.existing_files + 1;
        return;
    end
    if dryRun
        summary.would_copy_files = summary.would_copy_files + 1;
        return;
    end
    copyfile(src, dst);
    summary.copied_files = summary.copied_files + 1;
    summary.copied_paths{end+1, 1} = dst; %#ok<AGROW>
end

function fileIds = local_collect_file_ids(cfg, includeDesignOnly)
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
    if includeDesignOnly && isfield(cfg, 'design_points_pending') && isstruct(cfg.design_points_pending)
        pendingModules = fieldnames(cfg.design_points_pending);
        for i = 1:numel(pendingModules)
            rows = cfg.design_points_pending.(pendingModules{i});
            if ~isstruct(rows)
                continue;
            end
            for j = 1:numel(rows)
                rec = rows(j);
                if isfield(rec, 'file_id') && ~isempty(rec.file_id)
                    fileIds{end+1, 1} = char(string(rec.file_id)); %#ok<AGROW>
                end
            end
        end
    end
    fileIds = unique(fileIds, 'stable');
end

function names = local_zip_entry_names(zipPath)
    try
        names = local_tar_zip_entry_names(zipPath);
    catch
        names = local_java_zip_entry_names(zipPath);
    end
end

function baseName = local_zip_base_name(entryName)
    normalized = strrep(char(entryName), '\', '/');
    parts = regexp(normalized, '/', 'split');
    baseName = parts{end};
end

function fileIdx = local_matching_file_id_index(baseName, fileIds)
    fileIdx = 0;
    if ~endsWith(lower(baseName), '.csv')
        return;
    end
    for i = 1:numel(fileIds)
        fileId = fileIds{i};
        if startsWith(baseName, [fileId '_']) || strcmpi(baseName, [fileId '.csv'])
            fileIdx = i;
            return;
        end
    end
end

function local_extract_zip_entries(zipPath, entryNames, dstDir, dstPaths)
    try
        local_extract_zip_entries_tar(zipPath, entryNames, dstDir, dstPaths);
    catch
        local_extract_zip_entries_java(zipPath, entryNames, dstPaths);
    end
end

function local_extract_zip_entries_java(zipPath, entryNames, dstPaths)
    zf = java.util.zip.ZipFile(zipPath);
    cleanupZip = onCleanup(@() zf.close()); %#ok<NASGU>
    for i = 1:numel(entryNames)
        entryName = entryNames{i};
        dst = dstPaths{i};
        entry = zf.getEntry(entryName);
        if isempty(entry)
            error('stage_zhishan_subset:MissingZipEntry', 'Zip entry not found: %s in %s', entryName, zipPath);
        end
        parentDir = fileparts(dst);
        if ~isfolder(parentDir)
            mkdir(parentDir);
        end
        inStream = zf.getInputStream(entry);
        cleanupStream = onCleanup(@() inStream.close()); %#ok<NASGU>
        targetPath = java.io.File(dst).toPath();
        options = javaArray('java.nio.file.CopyOption', 1);
        options(1) = java.nio.file.StandardCopyOption.REPLACE_EXISTING;
        java.nio.file.Files.copy(inStream, targetPath, options);
        clear cleanupStream;
    end
end

function names = local_java_zip_entry_names(zipPath)
    zf = java.util.zip.ZipFile(zipPath);
    cleanup = onCleanup(@() zf.close()); %#ok<NASGU>
    entries = zf.entries();
    names = {};
    while entries.hasMoreElements()
        entry = entries.nextElement();
        if ~entry.isDirectory()
            names{end+1, 1} = char(entry.getName()); %#ok<AGROW>
        end
    end
end

function names = local_tar_zip_entry_names(zipPath)
    cmd = sprintf('tar -tf %s', local_cmd_quote(zipPath));
    [status, out] = system(cmd);
    if status ~= 0
        error('stage_zhishan_subset:ZipListFailed', 'Could not list zip entries: %s%s%s', zipPath, newline, out);
    end
    if isempty(strtrim(out))
        names = {};
    else
        names = regexp(strtrim(out), '\r\n|\n|\r', 'split');
        names = names(:);
    end
end

function local_extract_zip_entries_tar(zipPath, entryNames, dstDir, dstPaths)
    if ~isfolder(dstDir)
        mkdir(dstDir);
    end
    entryArgs = cellfun(@local_cmd_quote, entryNames(:).', 'UniformOutput', false);
    cmd = sprintf('tar -xf %s -C %s %s', ...
        local_cmd_quote(zipPath), local_cmd_quote(dstDir), strjoin(entryArgs, ' '));
    [status, out] = system(cmd);
    if status ~= 0
        error('stage_zhishan_subset:ZipExtractFailed', 'Could not extract zip entries: %s%s%s', zipPath, newline, out);
    end
    for i = 1:numel(dstPaths)
        if isfile(dstPaths{i})
            continue;
        end
        extractedPath = fullfile(dstDir, strrep(strrep(entryNames{i}, '/', filesep), '\', filesep));
        if isfile(extractedPath)
            parentDir = fileparts(dstPaths{i});
            if ~isfolder(parentDir)
                mkdir(parentDir);
            end
            movefile(extractedPath, dstPaths{i});
        end
        if ~isfile(dstPaths{i})
            error('stage_zhishan_subset:ZipExtractMissingOutput', ...
                'Zip extraction finished but output is missing: %s', dstPaths{i});
        end
    end
end

function value = local_cmd_quote(value)
    value = ['"' strrep(char(value), '"', '\"') '"'];
end
