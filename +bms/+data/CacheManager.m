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
