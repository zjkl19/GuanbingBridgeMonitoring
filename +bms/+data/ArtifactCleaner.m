classdef ArtifactCleaner
    %ARTIFACTCLEANER Safe listing/deletion of generated output artifacts.

    methods (Static)
        function files = list(root, category, recursive)
            if nargin < 2 || isempty(category), category = 'all'; end
            if nargin < 3, recursive = true; end
            patterns = bms.data.ArtifactCleaner.patterns(category);
            files = {};
            for i = 1:numel(patterns)
                if recursive
                    d = dir(fullfile(char(root), '**', patterns{i}));
                else
                    d = dir(fullfile(char(root), patterns{i}));
                end
                d = d(~[d.isdir]);
                for j = 1:numel(d)
                    files{end+1} = fullfile(d(j).folder, d(j).name); %#ok<AGROW>
                end
            end
            files = unique(files, 'stable');
        end

        function patterns = patterns(category)
            switch lower(char(category))
                case {'image','images','figures'}
                    patterns = {'*.jpg','*.jpeg','*.png','*.emf','*.fig'};
                case {'stats','excel'}
                    patterns = {'*.xlsx','*.xls','*.csv'};
                case {'cache'}
                    patterns = {'*.mat','*.meta.json'};
                case {'report','reports'}
                    patterns = {'*.docx','*.pdf'};
                otherwise
                    patterns = {'*.jpg','*.jpeg','*.png','*.emf','*.fig','*.xlsx','*.xls','*.csv','*.docx','*.pdf'};
            end
        end

        function result = deleteFiles(root, files, dryRun)
            if nargin < 3, dryRun = true; end
            if ischar(files) || isstring(files), files = cellstr(string(files)); end
            rootFull = bms.data.ArtifactCleaner.canonical(root);
            result = struct('dry_run', logical(dryRun), 'deleted', {{}}, 'skipped', {{}});
            for i = 1:numel(files)
                fileFull = bms.data.ArtifactCleaner.canonical(files{i});
                if ~bms.data.ArtifactCleaner.isInside(fileFull, rootFull) || ~isfile(fileFull)
                    result.skipped{end+1} = char(files{i}); %#ok<AGROW>
                    continue;
                end
                if ~dryRun
                    delete(fileFull);
                end
                result.deleted{end+1} = fileFull; %#ok<AGROW>
            end
        end

        function result = clean(root, category, dryRun)
            if nargin < 2 || isempty(category), category = 'all'; end
            if nargin < 3, dryRun = true; end
            files = bms.data.ArtifactCleaner.list(root, category, true);
            result = bms.data.ArtifactCleaner.deleteFiles(root, files, dryRun);
        end

        function summary = plan(root, category, recursive)
            if nargin < 2 || isempty(category), category = 'all'; end
            if nargin < 3, recursive = true; end
            files = bms.data.ArtifactCleaner.list(root, category, recursive);
            totalBytes = 0;
            rows = {};
            for i = 1:numel(files)
                info = dir(files{i});
                bytes = 0;
                modified = '';
                if ~isempty(info)
                    bytes = double(info(1).bytes);
                    modified = datestr(info(1).datenum, 'yyyy-mm-dd HH:MM:ss');
                end
                totalBytes = totalBytes + bytes;
                rows(end+1, :) = {files{i}, bytes, modified}; %#ok<AGROW>
            end
            summary = struct( ...
                'root', char(string(root)), ...
                'category', char(string(category)), ...
                'recursive', logical(recursive), ...
                'count', numel(files), ...
                'bytes', totalBytes, ...
                'files', {files}, ...
                'rows', {rows});
        end

        function p = canonical(pathValue)
            p = char(java.io.File(char(pathValue)).getCanonicalPath());
        end

        function tf = isInside(pathValue, rootValue)
            pathValue = char(pathValue);
            rootValue = char(rootValue);
            if ispc
                pathValue = lower(pathValue);
                rootValue = lower(rootValue);
            end
            tf = strcmp(pathValue, rootValue) || startsWith(pathValue, [rootValue filesep]);
        end
    end
end
