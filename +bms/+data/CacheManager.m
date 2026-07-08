classdef CacheManager
    %CACHEMANAGER Small helpers for cache file freshness checks.

    methods (Static)
        function p = cacheDir(folder), p = fullfile(char(folder), 'cache'); end

        function tf = isFresh(cacheFile, sourceFiles, cfg, version)
            if nargin < 3, cfg = []; end
            if nargin < 4, version = ''; end
            if ~isfile(cacheFile)
                tf = false;
                return;
            end
            c = dir(cacheFile);
            if ischar(sourceFiles) || isstring(sourceFiles), sourceFiles = cellstr(string(sourceFiles)); end
            tf = true;
            for i = 1:numel(sourceFiles)
                src = char(string(sourceFiles{i}));
                if isfile(src)
                    d = dir(src);
                    if d.datenum > c.datenum
                        tf = false;
                        return;
                    end
                end
            end
            if nargin >= 3 && (~isempty(cfg) || ~isempty(version))
                tf = bms.data.CacheManager.metadataMatches(cacheFile, cfg, version);
            end
        end

        function metaPath = metadataPath(cacheFile)
            metaPath = [char(cacheFile) '.meta.json'];
        end

        function meta = buildMetadata(sourceFiles, cfg, version)
            if nargin < 1 || isempty(sourceFiles), sourceFiles = {}; end
            if nargin < 2, cfg = []; end
            if nargin < 3, version = ''; end
            if ischar(sourceFiles) || isstring(sourceFiles), sourceFiles = cellstr(string(sourceFiles)); end
            meta = struct();
            meta.schema_version = 1;
            meta.cache_version = char(string(version));
            meta.config_hash = bms.data.CacheManager.configHash(cfg);
            meta.source_files = cellfun(@char, sourceFiles, 'UniformOutput', false);
            meta.source_mtimes = bms.data.CacheManager.sourceMtimes(sourceFiles);
            meta.source_records = bms.data.CacheManager.buildSourceRecords(sourceFiles);
            meta.written_at = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss');
        end

        function writeMetadata(cacheFile, sourceFiles, cfg, version)
            metaPath = bms.data.CacheManager.metadataPath(cacheFile);
            meta = bms.data.CacheManager.buildMetadata(sourceFiles, cfg, version);
            bms.core.Logger.writeJson(metaPath, meta);
        end

        function tf = metadataMatches(cacheFile, cfg, version)
            metaPath = bms.data.CacheManager.metadataPath(cacheFile);
            if ~isfile(metaPath)
                tf = false;
                return;
            end
            try
                meta = jsondecode(fileread(metaPath));
            catch
                tf = false;
                return;
            end
            expectedHash = bms.data.CacheManager.configHash(cfg);
            expectedVersion = char(string(version));
            tf = isfield(meta, 'config_hash') && strcmp(char(string(meta.config_hash)), expectedHash) ...
                && isfield(meta, 'cache_version') && strcmp(char(string(meta.cache_version)), expectedVersion);
        end

        function tf = metadataMatchesFull(cacheFile, sourceFiles, cfg, version)
            if nargin < 2, sourceFiles = {}; end
            if nargin < 3, cfg = []; end
            if nargin < 4, version = ''; end
            tf = bms.data.CacheManager.metadataMatches(cacheFile, cfg, version);
            if ~tf, return; end
            tf = bms.data.CacheManager.sourcesMatch(cacheFile, sourceFiles);
        end

        function tf = sourcesMatch(cacheFile, sourceFiles)
            if nargin < 2, sourceFiles = {}; end
            if ischar(sourceFiles) || isstring(sourceFiles), sourceFiles = cellstr(string(sourceFiles)); end
            metaPath = bms.data.CacheManager.metadataPath(cacheFile);
            if ~isfile(metaPath)
                tf = false;
                return;
            end
            try
                meta = jsondecode(fileread(metaPath));
            catch
                tf = false;
                return;
            end
            expected = bms.data.CacheManager.buildSourceRecords(sourceFiles);
            if isfield(meta, 'source_records')
                actual = bms.data.CacheManager.normalizeSourceRecords(meta.source_records);
                expected = bms.data.CacheManager.normalizeSourceRecords(expected);
                tf = isequal(actual, expected) || bms.data.CacheManager.sourceFingerprintsMatch(actual, expected);
            elseif isfield(meta, 'source_files') && isfield(meta, 'source_mtimes')
                tf = isequal(cellstr(string({expected.path})), cellstr(string(meta.source_files))) ...
                    && isequal(cellstr(string({expected.modified_at})), cellstr(string(meta.source_mtimes)));
            else
                tf = isempty(sourceFiles);
            end
        end

        function h = configHash(cfg)
            if nargin < 1 || isempty(cfg)
                txt = '';
            else
                try
                    txt = jsonencode(cfg, 'ConvertInfAndNaN', true);
                catch
                    txt = char(string(evalc('disp(cfg)')));
                end
            end
            h = sprintf('len%d_sum%d', strlength(string(txt)), sum(double(char(txt))));
            try
                md = java.security.MessageDigest.getInstance('SHA-256');
                md.update(uint8(txt));
                bytes = typecast(md.digest(), 'uint8');
                h = lower(reshape(dec2hex(bytes, 2).', 1, []));
            catch
            end
        end

        function mtimes = sourceMtimes(sourceFiles)
            if ischar(sourceFiles) || isstring(sourceFiles), sourceFiles = cellstr(string(sourceFiles)); end
            mtimes = cell(1, numel(sourceFiles));
            for i = 1:numel(sourceFiles)
                p = char(string(sourceFiles{i}));
                if isfile(p)
                    d = dir(p);
                    mtimes{i} = datestr(d.datenum, 'yyyy-mm-dd HH:MM:ss');
                else
                    mtimes{i} = '';
                end
            end
        end

        function records = buildSourceRecords(sourceFiles)
            if nargin < 1 || isempty(sourceFiles), sourceFiles = {}; end
            if ischar(sourceFiles) || isstring(sourceFiles), sourceFiles = cellstr(string(sourceFiles)); end
            records = struct('path', {}, 'exists', {}, 'bytes', {}, 'modified_at', {});
            for i = 1:numel(sourceFiles)
                p = char(string(sourceFiles{i}));
                rec = struct('path', p, 'exists', false, 'bytes', 0, 'modified_at', '');
                if isfile(p)
                    d = dir(p);
                    rec.exists = true;
                    rec.bytes = double(d.bytes);
                    rec.modified_at = datestr(d.datenum, 'yyyy-mm-dd HH:MM:ss');
                end
                records(end+1) = rec; %#ok<AGROW>
            end
        end

        function records = normalizeSourceRecords(records)
            if isempty(records)
                records = struct('path', {}, 'exists', {}, 'bytes', {}, 'modified_at', {});
                return;
            end
            if isstruct(records) && ~isfield(records, 'path')
                records = struct('path', {}, 'exists', {}, 'bytes', {}, 'modified_at', {});
                return;
            end
            for i = 1:numel(records)
                if ~isfield(records, 'exists'), records(i).exists = false; end
                if ~isfield(records, 'bytes'), records(i).bytes = 0; end
                if ~isfield(records, 'modified_at'), records(i).modified_at = ''; end
                records(i).path = char(string(records(i).path));
                records(i).exists = logical(records(i).exists);
                records(i).bytes = double(records(i).bytes);
                records(i).modified_at = char(string(records(i).modified_at));
            end
        end

        function tf = sourceFingerprintsMatch(actual, expected)
            % Some older Windows cache metadata stored Chinese path text with a
            % wrong code page. Keep raw cache reusable when source fingerprints
            % still prove that the same CSV produced the MAT cache.
            tf = false;
            if numel(actual) ~= numel(expected)
                return;
            end
            if isempty(actual)
                tf = true;
                return;
            end
            actualKeys = bms.data.CacheManager.sourceFingerprintKeys(actual);
            expectedKeys = bms.data.CacheManager.sourceFingerprintKeys(expected);
            if isempty(actualKeys) || isempty(expectedKeys)
                return;
            end
            tf = isequal(sort(actualKeys), sort(expectedKeys));
        end

        function keys = sourceFingerprintKeys(records)
            keys = strings(0, 1);
            for i = 1:numel(records)
                rec = records(i);
                if ~isfield(rec, 'exists') || ~logical(rec.exists) ...
                        || ~isfield(rec, 'bytes') || ~isfield(rec, 'modified_at') ...
                        || ~isfield(rec, 'path')
                    keys = strings(0, 1);
                    return;
                end
                [~, base, ext] = fileparts(char(string(rec.path)));
                if isempty(base) || isempty(ext) || isempty(rec.modified_at)
                    keys = strings(0, 1);
                    return;
                end
                keys(end+1, 1) = sprintf('%s%s|%.0f|%s', base, ext, double(rec.bytes), char(string(rec.modified_at))); %#ok<AGROW>
            end
        end

        function files = listCacheFiles(folder, pattern)
            if nargin < 2 || isempty(pattern), pattern = '*'; end
            cacheRoot = bms.data.CacheManager.cacheDir(folder);
            files = bms.core.Logger.listFiles(cacheRoot, pattern);
        end

        function removed = invalidate(folder, pattern)
            if nargin < 2 || isempty(pattern), pattern = '*'; end
            files = bms.data.CacheManager.listCacheFiles(folder, pattern);
            removed = {};
            for i = 1:numel(files)
                p = files{i};
                if isfile(p)
                    delete(p);
                    removed{end+1} = p; %#ok<AGROW>
                end
            end
        end
    end
end
