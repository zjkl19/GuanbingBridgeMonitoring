classdef DonghuaExportNormalizer
    %DONGHUAEXPORTNORMALIZER Stage nested Donghua CSV exports for legacy steps.
    %
    % Some Donghua packages store CSV files under date/subfolder/GUID/*.csv,
    % while the legacy preprocessing scripts expect date/subfolder/*.csv.
    % This helper copies missing nested CSVs to the direct subfolder and
    % canonicalizes Donghua raw export names without deleting the original
    % nested files, so both old and new package layouts remain supported.

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
                'renamed', 0, ...
                'would_rename', 0, ...
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
                    summary.skipped_existing = summary.skipped_existing + 1;
                    if opts.Verbose
                        summary.messages{end+1} = sprintf('rename skipped, target exists: %s', newFull); %#ok<AGROW>
                    end
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
                directNames(newKey) = directFiles(i).bytes;
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
                    summary.skipped_existing = summary.skipped_existing + 1;
                    continue;
                end

                if opts.DryRun
                    summary.would_copy = summary.would_copy + 1;
                    directNames(dstKey) = nestedFiles(i).bytes;
                    continue;
                end

                try
                    copyfile(src, dst);
                    summary.copied = summary.copied + 1;
                    directNames(dstKey) = nestedFiles(i).bytes;
                    if opts.Verbose
                        summary.messages{end+1} = sprintf('copied: %s -> %s', src, dst); %#ok<AGROW>
                    end
                catch ME
                    summary.collisions = summary.collisions + 1;
                    summary.messages{end+1} = sprintf('copy failed: %s (%s)', src, ME.message); %#ok<AGROW>
                end
            end
        end

        function newName = canonicalFileName(fileName)
            [~, base, ext] = fileparts(char(string(fileName)));
            newBase = regexprep(base, '(_原始数据|_鍘熷鏁版嵁).*', '');
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

        function [directNames, directFiles] = buildDirectNameMap(folderPath)
            directFiles = dir(fullfile(folderPath, '*.csv'));
            directNames = containers.Map('KeyType', 'char', 'ValueType', 'double');
            for i = 1:numel(directFiles)
                directNames(lower(directFiles(i).name)) = directFiles(i).bytes;
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
