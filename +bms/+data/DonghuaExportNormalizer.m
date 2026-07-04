classdef DonghuaExportNormalizer
    %DONGHUAEXPORTNORMALIZER Stage nested Donghua CSV exports for legacy steps.
    %
    % Some Donghua packages store CSV files under date/subfolder/GUID/*.csv,
    % while the legacy preprocessing scripts expect date/subfolder/*.csv.
    % This helper moves missing nested CSVs to the direct subfolder and
    % canonicalizes Donghua raw export names while keeping only one raw CSV
    % copy on disk. If a canonical direct CSV already exists, identical nested
    % duplicates are deleted and conflicting files are left untouched.

    methods (Static)
        function summary = normalizeFolder(folderPath, varargin)
            opts = bms.data.DonghuaExportNormalizer.parseOptions(varargin{:});
            folderPath = char(string(folderPath));
            summary = struct( ...
                'folder', folderPath, ...
                'source_count', 0, ...
                'direct_count', 0, ...
                'copied', 0, ...
                'would_copy', 0, ...
                'moved', 0, ...
                'would_move', 0, ...
                'renamed', 0, ...
                'would_rename', 0, ...
                'deleted_duplicates', 0, ...
                'would_delete_duplicates', 0, ...
                'removed_empty_dirs', 0, ...
                'skipped_existing', 0, ...
                'collisions', 0, ...
                'dry_run', opts.DryRun, ...
                'messages', {{}} );

            if isempty(folderPath) || exist(folderPath, 'dir') ~= 7
                return;
            end

            [directNames, directFiles] = bms.data.DonghuaExportNormalizer.buildDirectNameMap(folderPath);
            summary.direct_count = numel(directFiles);

            for i = 1:numel(directFiles)
                oldName = directFiles(i).name;
                newName = bms.data.DonghuaExportNormalizer.canonicalFileName(oldName);
                if strcmp(oldName, newName)
                    continue;
                end

                oldFull = fullfile(folderPath, oldName);
                newFull = fullfile(folderPath, newName);
                newKey = lower(newName);
                oldKey = lower(oldName);

                if isKey(directNames, newKey)
                    summary = bms.data.DonghuaExportNormalizer.handleExistingTarget( ...
                        summary, directNames, oldKey, oldFull, newKey, newFull, opts, 'rename');
                    continue;
                end

                if opts.DryRun
                    summary.would_rename = summary.would_rename + 1;
                else
                    try
                        movefile(oldFull, newFull);
                        summary.renamed = summary.renamed + 1;
                    catch ME
                        summary.collisions = summary.collisions + 1;
                        summary.messages{end+1} = sprintf('rename failed: %s -> %s (%s)', oldFull, newFull, ME.message); %#ok<AGROW>
                        continue;
                    end
                end

                if isKey(directNames, oldKey)
                    remove(directNames, oldKey);
                end
                directNames(newKey) = bms.data.DonghuaExportNormalizer.fileRecord(newFull, directFiles(i).bytes);
                if opts.Verbose
                    summary.messages{end+1} = sprintf('renamed: %s -> %s', oldFull, newFull); %#ok<AGROW>
                end
            end

            nestedFiles = dir(fullfile(folderPath, '**', '*.csv'));
            for i = 1:numel(nestedFiles)
                src = fullfile(nestedFiles(i).folder, nestedFiles(i).name);
                if bms.data.DonghuaExportNormalizer.sameFolder(nestedFiles(i).folder, folderPath)
                    continue;
                end

                summary.source_count = summary.source_count + 1;
                dstName = bms.data.DonghuaExportNormalizer.canonicalFileName(nestedFiles(i).name);
                dstKey = lower(dstName);
                dst = fullfile(folderPath, dstName);

                if isKey(directNames, dstKey)
                    summary = bms.data.DonghuaExportNormalizer.handleExistingTarget( ...
                        summary, directNames, '', src, dstKey, dst, opts, 'nested');
                    if ~opts.DryRun
                        summary.removed_empty_dirs = summary.removed_empty_dirs + ...
                            bms.data.DonghuaExportNormalizer.pruneEmptyParents(nestedFiles(i).folder, folderPath);
                    end
                    continue;
                end

                if opts.DryRun
                    summary.would_move = summary.would_move + 1;
                    directNames(dstKey) = bms.data.DonghuaExportNormalizer.fileRecord(src, nestedFiles(i).bytes);
                    continue;
                end

                try
                    movefile(src, dst);
                    summary.moved = summary.moved + 1;
                    summary.removed_empty_dirs = summary.removed_empty_dirs + ...
                        bms.data.DonghuaExportNormalizer.pruneEmptyParents(nestedFiles(i).folder, folderPath);
                    directNames(dstKey) = bms.data.DonghuaExportNormalizer.fileRecord(dst, nestedFiles(i).bytes);
                    if opts.Verbose
                        summary.messages{end+1} = sprintf('moved: %s -> %s', src, dst); %#ok<AGROW>
                    end
                catch ME
                    summary.collisions = summary.collisions + 1;
                    summary.messages{end+1} = sprintf('move failed: %s -> %s (%s)', src, dst, ME.message); %#ok<AGROW>
                end
            end
        end

        function newName = canonicalFileName(fileName)
            [~, base, ext] = fileparts(char(string(fileName)));
            normalRawMarker = ['_' char([hex2dec('539F') hex2dec('59CB') hex2dec('6570') hex2dec('636E')])];
            markers = {normalRawMarker, '_鍘熷鏁版嵁', '_閸樼喎顫愰弫鐗堝祦'};
            newBase = base;
            for i = 1:numel(markers)
                idx = strfind(newBase, markers{i});
                if ~isempty(idx)
                    newBase = newBase(1:idx(1)-1);
                    break;
                end
            end
            newBase = regexprep(newBase, '(?<!\d)(\d{3})(\d{2})(?!\d)', '$1-$2');
            newName = [newBase ext];
        end
    end

    methods (Static, Access = private)
        function opts = parseOptions(varargin)
            opts = struct('DryRun', false, 'Verbose', false);
            if mod(numel(varargin), 2) ~= 0
                error('DonghuaExportNormalizer:InvalidOptions', 'Options must be name/value pairs.');
            end
            for i = 1:2:numel(varargin)
                name = char(string(varargin{i}));
                value = varargin{i + 1};
                switch lower(name)
                    case 'dryrun'
                        opts.DryRun = logical(value);
                    case 'verbose'
                        opts.Verbose = logical(value);
                    otherwise
                        error('DonghuaExportNormalizer:UnknownOption', 'Unknown option: %s', name);
                end
            end
        end

        function summary = handleExistingTarget(summary, directNames, oldKey, src, dstKey, dst, opts, action)
            summary.skipped_existing = summary.skipped_existing + 1;
            existing = directNames(dstKey);
            if bms.data.DonghuaExportNormalizer.sameFileContent(src, existing.path)
                if opts.DryRun
                    summary.would_delete_duplicates = summary.would_delete_duplicates + 1;
                else
                    try
                        delete(src);
                        summary.deleted_duplicates = summary.deleted_duplicates + 1;
                        if ~isempty(oldKey) && isKey(directNames, oldKey)
                            remove(directNames, oldKey);
                        end
                    catch ME
                        summary.collisions = summary.collisions + 1;
                        summary.messages{end+1} = sprintf('delete duplicate failed: %s (%s)', src, ME.message); %#ok<AGROW>
                    end
                end
                return;
            end

            summary.collisions = summary.collisions + 1;
            summary.messages{end+1} = sprintf('%s conflict, target differs: %s -> %s', action, src, dst); %#ok<AGROW>
        end

        function [directNames, directFiles] = buildDirectNameMap(folderPath)
            directFiles = dir(fullfile(folderPath, '*.csv'));
            directNames = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for i = 1:numel(directFiles)
                directNames(lower(directFiles(i).name)) = bms.data.DonghuaExportNormalizer.fileRecord( ...
                    fullfile(directFiles(i).folder, directFiles(i).name), directFiles(i).bytes);
            end
        end

        function record = fileRecord(path, bytes)
            record = struct('path', char(string(path)), 'bytes', double(bytes));
        end

        function tf = sameFileContent(a, b)
            tf = false;
            if isempty(a) || isempty(b) || exist(a, 'file') ~= 2 || exist(b, 'file') ~= 2
                return;
            end

            da = dir(a);
            db = dir(b);
            if isempty(da) || isempty(db) || da.bytes ~= db.bytes
                return;
            end

            fida = fopen(a, 'rb');
            if fida < 0
                return;
            end
            cleanupA = onCleanup(@() fclose(fida)); %#ok<NASGU>

            fidb = fopen(b, 'rb');
            if fidb < 0
                return;
            end
            cleanupB = onCleanup(@() fclose(fidb)); %#ok<NASGU>

            chunkSize = 1024 * 1024;
            while true
                ba = fread(fida, chunkSize, '*uint8');
                bb = fread(fidb, chunkSize, '*uint8');
                if numel(ba) ~= numel(bb) || any(ba ~= bb)
                    return;
                end
                if feof(fida) && feof(fidb)
                    tf = true;
                    return;
                end
            end
        end

        function removed = pruneEmptyParents(startFolder, stopFolder)
            removed = 0;
            current = char(string(startFolder));
            stopFolder = bms.data.DonghuaExportNormalizer.normalizeComparePath(stopFolder);
            while ~bms.data.DonghuaExportNormalizer.sameFolder(current, stopFolder)
                if exist(current, 'dir') ~= 7
                    current = fileparts(current);
                    continue;
                end
                entries = dir(current);
                entries = entries(~ismember({entries.name}, {'.', '..'}));
                if ~isempty(entries)
                    return;
                end
                parent = fileparts(current);
                try
                    rmdir(current);
                    removed = removed + 1;
                catch
                    return;
                end
                current = parent;
            end
        end

        function tf = sameFolder(a, b)
            a = bms.data.DonghuaExportNormalizer.normalizeComparePath(a);
            b = bms.data.DonghuaExportNormalizer.normalizeComparePath(b);
            tf = strcmpi(a, b);
        end

        function p = normalizeComparePath(p)
            p = char(string(p));
            p = strrep(p, '/', filesep);
            while numel(p) > 1 && (p(end) == '/' || p(end) == '\')
                p(end) = [];
            end
        end
    end
end
