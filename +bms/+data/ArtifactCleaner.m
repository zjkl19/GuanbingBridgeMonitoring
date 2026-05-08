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

        function summary = planForModules(root, manifestOrPath, moduleKeys, category)
            if nargin < 4 || isempty(category), category = 'all'; end
            files = bms.data.ArtifactCleaner.filesForModules(root, manifestOrPath, moduleKeys, category);
            summary = bms.data.ArtifactCleaner.planFromFiles(root, files, category);
        end

        function result = cleanForModules(root, manifestOrPath, moduleKeys, category, dryRun)
            if nargin < 4 || isempty(category), category = 'all'; end
            if nargin < 5, dryRun = true; end
            files = bms.data.ArtifactCleaner.filesForModules(root, manifestOrPath, moduleKeys, category);
            result = bms.data.ArtifactCleaner.deleteFiles(root, files, dryRun);
        end

        function files = filesForModules(root, manifestOrPath, moduleKeys, category)
            if nargin < 4 || isempty(category), category = 'all'; end
            manifest = bms.data.ArtifactCleaner.loadManifest(manifestOrPath);
            files = {};
            if isempty(manifest) || ~isstruct(manifest), return; end
            if nargin < 3 || isempty(moduleKeys)
                moduleKeys = {};
            elseif ischar(moduleKeys) || isstring(moduleKeys)
                moduleKeys = cellstr(string(moduleKeys));
            end
            if ~iscell(moduleKeys), moduleKeys = {moduleKeys}; end
            moduleKeys = cellfun(@char, moduleKeys, 'UniformOutput', false);
            records = {};
            if isfield(manifest, 'module_results')
                records = bms.app.ManifestReader.recordsToCell(manifest.module_results);
            elseif isfield(manifest, 'module_logs')
                records = bms.app.ManifestReader.recordsToCell(manifest.module_logs);
            elseif isfield(manifest, 'module_artifacts')
                records = bms.app.ManifestReader.recordsToCell(manifest.module_artifacts);
            end
            for i = 1:numel(records)
                rec = records{i};
                if ~isstruct(rec), continue; end
                key = '';
                if isfield(rec, 'key') && ~isempty(rec.key), key = char(string(rec.key)); end
                if ~isempty(moduleKeys) && ~ismember(key, moduleKeys), continue; end
                if ~isfield(rec, 'artifacts') || isempty(rec.artifacts), continue; end
                artifacts = bms.app.ManifestReader.recordsToCell(rec.artifacts);
                for j = 1:numel(artifacts)
                    artifact = artifacts{j};
                    if ~isstruct(artifact) || ~isfield(artifact, 'path'), continue; end
                    p = char(string(artifact.path));
                    if isempty(p) || ~isfile(p), continue; end
                    if ~bms.data.ArtifactCleaner.categoryMatchesArtifact(category, artifact, p), continue; end
                    try
                        fileFull = bms.data.ArtifactCleaner.canonical(p);
                        rootFull = bms.data.ArtifactCleaner.canonical(root);
                        if bms.data.ArtifactCleaner.isInside(fileFull, rootFull)
                            files{end+1} = fileFull; %#ok<AGROW>
                        end
                    catch
                    end
                end
            end
            files = unique(files, 'stable');
        end

        function summary = planFromFiles(root, files, category)
            if nargin < 3 || isempty(category), category = 'all'; end
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
            summary = struct('root', char(string(root)), 'category', char(string(category)), ...
                'recursive', false, 'count', numel(files), 'bytes', totalBytes, ...
                'files', {files}, 'rows', {rows});
        end

        function manifest = loadManifest(manifestOrPath)
            manifest = struct();
            if isempty(manifestOrPath), return; end
            if isstruct(manifestOrPath)
                manifest = manifestOrPath;
            else
                p = char(string(manifestOrPath));
                if isfile(p)
                    manifest = jsondecode(fileread(p));
                end
            end
        end

        function tf = categoryMatchesArtifact(category, artifact, pathValue)
            category = lower(char(string(category)));
            kind = '';
            if isstruct(artifact) && isfield(artifact, 'kind') && ~isempty(artifact.kind)
                kind = lower(char(string(artifact.kind)));
            end
            [~,~,ext] = fileparts(pathValue);
            ext = lower(ext);
            switch category
                case {'image','images','figures'}
                    tf = strcmp(kind, 'figure') || ismember(ext, {'.jpg','.jpeg','.png','.emf','.fig'});
                case {'stats','excel'}
                    tf = strcmp(kind, 'stats') || ismember(ext, {'.xlsx','.xls','.csv'});
                case {'report','reports'}
                    tf = ismember(ext, {'.docx','.pdf'});
                case {'cache'}
                    tf = ismember(ext, {'.mat','.json'});
                otherwise
                    tf = true;
            end
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
