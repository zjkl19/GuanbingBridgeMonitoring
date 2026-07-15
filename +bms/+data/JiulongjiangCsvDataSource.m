classdef JiulongjiangCsvDataSource < bms.data.BaseDataSource
    %JIULONGJIANGCSVDATASOURCE Jiulongjiang data_jlj_yyyy-mm-dd export layout.

    methods
        function obj = JiulongjiangCsvDataSource(root, cfg)
            if nargin < 2, cfg = struct(); end
            obj@bms.data.BaseDataSource(root, cfg, 'jlj_daily_export');
        end

        function folders = dateFolders(obj, startDate, endDate)
            folders = bms.data.ZipDailyExportAdapter.dateFolders(obj.Root, startDate, endDate, obj.Config);
        end

        function folders = candidateDirs(obj, subfolder, startDate, endDate)
            csvDirs = bms.data.ZipDailyExportAdapter.csvDirs(obj.Root, startDate, endDate, obj.Config);
            subfolder = char(string(subfolder));
            folders = {};
            for i = 1:numel(csvDirs)
                candidates = {csvDirs{i}};
                if ~isempty(subfolder)
                    candidates = [{fullfile(csvDirs{i}, subfolder)}, candidates]; %#ok<AGROW>
                end
                for j = 1:numel(candidates)
                    if isfolder(candidates{j})
                        folders{end+1} = candidates{j}; %#ok<AGROW>
                        break;
                    end
                end
            end
            folders = bms.data.BaseDataSource.uniqueExistingFolders(folders);
        end

        function [dirp, meta] = dayDir(obj, day, meta)
            dirp = '';
            if nargin < 3 || isempty(meta)
                meta = struct();
            end
            if isempty(obj.Root) || ~exist(obj.Root, 'dir')
                return;
            end

            adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(obj.Config);
            try
                dirs = obj.candidateDirs('', day, day);
                meta.data_source = class(obj);
                meta.candidate_dirs = dirs;
                if ~isempty(dirs)
                    dirp = dirs{1};
                    meta.cache_dir = bms.data.JiulongjiangCsvDataSource.resolveCacheDir(dirp, adapter);
                    return;
                end
            catch
            end

            dt = datetime(day, 'InputFormat', 'yyyy-MM-dd');
            startText = datestr(dt, 'yyyymmdd');
            endText = datestr(dt + days(1), 'yyyymmdd');
            layouts = bms.data.JiulongjiangCsvDataSource.layoutCandidates(dt, startText, endText, adapter);

            for i = 1:numel(layouts)
                directFolder = fullfile(obj.Root, layouts(i).folder_name, layouts(i).subdir);
                if exist(directFolder, 'dir')
                    dirp = directFolder;
                    meta.cache_dir = bms.data.JiulongjiangCsvDataSource.resolveCacheDir(directFolder, adapter);
                    return;
                end
            end

            for i = 1:numel(layouts)
                zipPath = fullfile(obj.Root, [layouts(i).folder_name '.zip']);
                if exist(zipPath, 'file')
                    [dirp, meta] = bms.data.JiulongjiangCsvDataSource.extractZip(zipPath, layouts(i).subdir, adapter, meta);
                    if ~isempty(dirp)
                        return;
                    end
                end
            end

            zipPath = bms.data.ZipDailyExportAdapter.findZip(obj.Root, dt, adapter.zip);
            if ~isempty(zipPath)
                [~, base, ~] = fileparts(zipPath);
                subdir = adapter.zip.subdir;
                if startsWith(base, 'jljData', 'IgnoreCase', true)
                    subdir = fullfile('data', 'csv');
                end
                [dirp, meta] = bms.data.JiulongjiangCsvDataSource.extractZip(zipPath, subdir, adapter, meta);
            end
        end
    end

    methods (Static)
        function adapter = adapterFromConfig(cfg)
            adapter = bms.data.ZipDailyExportAdapter.resolve(cfg);
        end

        function [dirp, meta] = getDayDir(root, day, cfg, meta)
            if nargin < 4 || isempty(meta)
                meta = struct();
            end
            src = bms.data.JiulongjiangCsvDataSource(root, cfg);
            [dirp, meta] = src.dayDir(day, meta);
        end

        function fp = findFile(dirp, pointId, sensorType, cfg)
            fp = '';
            if isempty(dirp) || ~exist(dirp, 'dir')
                return;
            end
            if nargin < 3 || isempty(sensorType)
                sensorType = 'generic';
            end
            if nargin < 4
                cfg = struct();
            end

            fileId = bms.data.TimeSeriesLoader.resolveFileId(cfg, sensorType, pointId);
            candidates = bms.data.PointResolver.uniqueText({ ...
                regexprep(fileId, '[-_][XYZxyz]$', ''), ...
                regexprep(pointId, '[-_][XYZxyz]$', '')});
            mode = bms.data.TimeSeriesLoader.seriesSourceMode(cfg);
            switch mode
                case 'mat_only'
                    fp = bms.data.JiulongjiangCsvDataSource.findMatCacheFile(dirp, candidates, cfg);
                case 'prefer_mat'
                    fp = bms.data.JiulongjiangCsvDataSource.findMatCacheFile(dirp, candidates, cfg);
                    if ~isempty(fp) && ~bms.data.JiulongjiangCsvDataSource.isUsableStandaloneCache( ...
                            fp, sensorType, pointId, cfg)
                        fp = '';
                    end
                    if isempty(fp)
                        fp = bms.data.JiulongjiangCsvDataSource.findCsvFile(dirp, candidates);
                    end
                case 'csv_cache'
                    fp = bms.data.JiulongjiangCsvDataSource.findCsvFile(dirp, candidates);
                otherwise
                    % Preserve the established contract when CSV is present;
                    % only promote a jlj_csv_v2 MAT cache when the CSV export
                    % itself is unavailable.
                    fp = bms.data.JiulongjiangCsvDataSource.findCsvFile(dirp, candidates);
                    if isempty(fp)
                        fp = bms.data.JiulongjiangCsvDataSource.findMatCacheFile(dirp, candidates, cfg);
                    end
            end
        end

        function fp = findCsvFallback(dirp, pointId, sensorType, cfg)
            if nargin < 3 || isempty(sensorType), sensorType = 'generic'; end
            if nargin < 4, cfg = struct(); end
            fileId = bms.data.TimeSeriesLoader.resolveFileId(cfg, sensorType, pointId);
            candidates = bms.data.PointResolver.uniqueText({ ...
                regexprep(fileId, '[-_][XYZxyz]$', ''), ...
                regexprep(pointId, '[-_][XYZxyz]$', '')});
            fp = bms.data.JiulongjiangCsvDataSource.findCsvFile(dirp, candidates);
        end

        function [t, v] = readFile(fp, sensorType, pointId, cfg, varargin)
            t = [];
            v = [];
            if isempty(fp) || ~exist(fp, 'file')
                return;
            end

            adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(cfg);
            [~, ~, sourceExt] = fileparts(char(string(fp)));
            if strcmpi(sourceExt, '.mat')
                [t, v] = bms.data.JiulongjiangCsvDataSource.readStandaloneCache( ...
                    fp, sensorType, pointId, cfg, adapter);
                [t, v] = bms.data.JiulongjiangCsvDataSource.applyRange(t, v, varargin{:});
                return;
            end

            cacheDir = bms.data.JiulongjiangCsvDataSource.resolveCacheDirFromMeta(adapter, varargin{:});
            cachePath = '';
            if adapter.cache.enabled && ~isempty(cacheDir)
                if ~exist(cacheDir, 'dir'), mkdir(cacheDir); end
                [~, base, ~] = fileparts(fp);
                cachePath = fullfile(cacheDir, [base '.mat']);
            end

            cacheOk = false;
            if ~isempty(cachePath) && bms.data.JiulongjiangCsvDataSource.isReusableRawCache( ...
                    cachePath, fp, adapter)
                try
                    S = load(cachePath, 'ts', 'valx', 'valy', 'valz', 'meta');
                    [t, v] = bms.data.JiulongjiangCsvDataSource.pickCachedChannel(S, sensorType, pointId);
                    cacheOk = true;
                catch
                    cacheOk = false;
                    try
                        delete(cachePath);
                    catch
                    end
                end
            end

            if ~cacheOk
                [~, payload] = bms.data.JiulongjiangCsvDataSource.buildCacheForFile( ...
                    fp, cfg, cacheDir, true);
                t = payload.ts;
                [t, v] = bms.data.JiulongjiangCsvDataSource.pickChannelFromArrays( ...
                    t, payload.valx, payload.valy, payload.valz, sensorType, pointId);
            end

            [t, v] = bms.data.JiulongjiangCsvDataSource.applyRange(t, v, varargin{:});
        end

        function [info, payload] = buildCacheForFile(fp, cfg, cacheDir, forceRebuild, faultInjection)
            %BUILDCACHEFORFILE Parse one raw CSV and atomically create its MAT cache.
            %   The stored payload is the unmodified parsed source: ts, valx,
            %   valy and valz. No cleaning, filtering or downsampling occurs.
            if nargin < 2 || isempty(cfg), cfg = struct(); end
            if nargin < 3, cacheDir = ''; end
            if nargin < 4 || isempty(forceRebuild), forceRebuild = false; end
            if nargin < 5, faultInjection = ''; end
            faultInjection = char(string(faultInjection));
            supportedFaults = {'after_mat_publish', 'after_mat_publish_abrupt'};
            if ~isempty(faultInjection) && ~any(strcmp(faultInjection, supportedFaults))
                error('BMS:JljCachePrebuild:InvalidFaultInjection', ...
                    'Unsupported cache commit fault injection: %s', faultInjection);
            end

            fp = char(string(fp));
            cacheDir = char(string(cacheDir));
            if isempty(fp) || ~isfile(fp)
                error('BMS:JljCachePrebuild:SourceMissing', ...
                    'CSV source file does not exist: %s', fp);
            end

            adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(cfg);
            if isempty(cacheDir) && adapter.cache.enabled
                cacheDir = bms.data.JiulongjiangCsvDataSource.resolveCacheDir(fileparts(fp), adapter);
            end

            sourceBefore = bms.data.CacheManager.buildSourceRecords({fp});
            info = bms.data.JiulongjiangCsvDataSource.emptyCacheBuildInfo(fp);
            info.source_bytes = sourceBefore(1).bytes;
            info.source_modified_at = sourceBefore(1).modified_at;
            payload = struct('ts', [], 'valx', [], 'valy', [], 'valz', []);

            cachePath = '';
            if adapter.cache.enabled && ~isempty(cacheDir)
                if ~isfolder(cacheDir), mkdir(cacheDir); end
                [~, base, ~] = fileparts(fp);
                cachePath = fullfile(cacheDir, [base '.mat']);
            end
            info.cache_path = cachePath;
            if ~isempty(cachePath)
                info.metadata_path = bms.data.CacheManager.metadataPath(cachePath);
                cacheLock = bms.data.JiulongjiangCsvDataSource.acquireBuildLock( ...
                    [cachePath '.build.lock']); %#ok<NASGU>
                bms.data.JiulongjiangCsvDataSource.recoverInterruptedTransactions( ...
                    cachePath, fp, adapter);
            end

            cacheExisted = ~isempty(cachePath) && (isfile(cachePath) ...
                || isfile(bms.data.CacheManager.metadataPath(cachePath)));
            if cacheExisted && ~logical(forceRebuild) ...
                    && bms.data.JiulongjiangCsvDataSource.isReusableRawCache(cachePath, fp, adapter)
                info.status = 'reused';
                info.cache_bytes = bms.data.JiulongjiangCsvDataSource.cachePairBytes(cachePath);
                return;
            end

            payload = bms.data.JiulongjiangCsvDataSource.parseRawCsv(fp, adapter);
            sourceAfterParse = bms.data.CacheManager.buildSourceRecords({fp});
            if ~bms.data.JiulongjiangCsvDataSource.sameSourceRecord(sourceBefore, sourceAfterParse)
                error('BMS:JljCachePrebuild:SourceChanged', ...
                    'CSV source changed while it was being parsed: %s', fp);
            end

            if isempty(cachePath)
                info.status = 'parsed';
                return;
            end

            pairId = char(java.util.UUID.randomUUID());
            meta = struct('src', fp, ...
                'mtime', bms.data.JiulongjiangCsvDataSource.fileMtime(fp), ...
                'size', bms.data.JiulongjiangCsvDataSource.fileSize(fp), ...
                'pair_id', pairId); %#ok<NASGU>
            ts = payload.ts; %#ok<NASGU>
            valx = payload.valx; %#ok<NASGU>
            valy = payload.valy; %#ok<NASGU>
            valz = payload.valz; %#ok<NASGU>

            transactionDir = bms.data.JiulongjiangCsvDataSource.createTransactionDir(cachePath);
            transactionCleanup = onCleanup(@() ...
                bms.data.JiulongjiangCsvDataSource.cleanupTransactionDir( ...
                    transactionDir, false)); %#ok<NASGU>
            tempMat = fullfile(transactionDir, 'new.mat');
            save(tempMat, 'ts', 'valx', 'valy', 'valz', 'meta');
            cacheMeta = bms.data.CacheManager.buildMetadata({fp}, adapter, 'jlj_csv_v2');
            cacheMeta.pair_id = pairId;
            tempInfo = dir(tempMat);
            cacheMeta.mat_bytes = double(tempInfo(1).bytes);
            bms.core.Logger.writeJson( ...
                bms.data.CacheManager.metadataPath(tempMat), cacheMeta);
            if ~bms.data.JiulongjiangCsvDataSource.isReusableRawCache(tempMat, fp, adapter)
                error('BMS:JljCachePrebuild:TempValidationFailed', ...
                    'Temporary cache validation failed for source: %s', fp);
            end

            sourceBeforeCommit = bms.data.CacheManager.buildSourceRecords({fp});
            if ~bms.data.JiulongjiangCsvDataSource.sameSourceRecord(sourceBefore, sourceBeforeCommit)
                error('BMS:JljCachePrebuild:SourceChanged', ...
                    'CSV source changed before its cache could be committed: %s', fp);
            end

            bms.data.JiulongjiangCsvDataSource.commitCachePair( ...
                tempMat, cachePath, fp, adapter, faultInjection);
            if cacheExisted
                info.status = 'rebuilt';
            else
                info.status = 'created';
            end
            info.cache_bytes = bms.data.JiulongjiangCsvDataSource.cachePairBytes(cachePath);
        end

        function payload = parseRawCsv(fp, adapter)
            %PARSERAWCSV Parse without applying any analytical transformation.
            T = readtable(fp, 'Delimiter', adapter.csv.delimiter, ...
                'FileEncoding', adapter.csv.encoding, ...
                'TextType', 'string', 'VariableNamingRule', 'preserve');
            vars = T.Properties.VariableNames;
            timeCol = bms.data.JiulongjiangCsvDataSource.pickVar(vars, adapter.csv.time_column);
            if isempty(timeCol)
                error('BMS:JljCachePrebuild:MissingTimeColumn', ...
                    'CSV source has no required time column "%s": %s', ...
                    adapter.csv.time_column, fp);
            end
            if height(T) == 0
                error('BMS:JljCachePrebuild:EmptyCsv', 'CSV source has no rows: %s', fp);
            end

            tsText = string(T.(timeCol));
            if adapter.csv.strip_quotes
                tsText = strrep(tsText, '"', '');
            end
            tsText = strtrim(tsText);
            ts = bms.data.JiulongjiangCsvDataSource.parseTime(tsText, adapter.csv.time_format);
            valx = bms.data.JiulongjiangCsvDataSource.extractNumericColumn(T, vars, 'value_x');
            valy = bms.data.JiulongjiangCsvDataSource.extractNumericColumn(T, vars, 'value_y');
            valz = bms.data.JiulongjiangCsvDataSource.extractNumericColumn(T, vars, 'value_z');
            values = {valx, valy, valz};
            if all(cellfun(@isempty, values))
                error('BMS:JljCachePrebuild:MissingValueColumns', ...
                    'CSV source has no value_x/value_y/value_z columns: %s', fp);
            end
            for i = 1:numel(values)
                if ~isempty(values{i}) && numel(values{i}) ~= numel(ts)
                    error('BMS:JljCachePrebuild:LengthMismatch', ...
                        'CSV time/value length mismatch: %s', fp);
                end
            end
            if all(isnat(ts))
                error('BMS:JljCachePrebuild:InvalidTime', ...
                    'CSV source has no parseable timestamps: %s', fp);
            end
            payload = struct('ts', ts, 'valx', valx, 'valy', valy, 'valz', valz);
        end

        function fp = findCsvFile(dirp, candidates)
            fp = '';
            for i = 1:numel(candidates)
                cand = fullfile(dirp, [candidates{i} '.csv']);
                if exist(cand, 'file')
                    fp = cand;
                    return;
                end
            end

            files = dir(fullfile(dirp, '*.csv'));
            for i = 1:numel(candidates)
                idx = find(arrayfun(@(f) contains(f.name, candidates{i}), files), 1);
                if ~isempty(idx)
                    fp = fullfile(files(idx).folder, files(idx).name);
                    return;
                end
            end
        end

        function fp = findMatCacheFile(dirp, candidates, cfg)
            fp = '';
            adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(cfg);
            cacheDir = bms.data.JiulongjiangCsvDataSource.resolveCacheDir(dirp, adapter);
            if isempty(cacheDir) || ~exist(cacheDir, 'dir')
                return;
            end

            for i = 1:numel(candidates)
                cand = fullfile(cacheDir, [candidates{i} '.mat']);
                if exist(cand, 'file')
                    fp = cand;
                    return;
                end
            end

            files = dir(fullfile(cacheDir, '*.mat'));
            for i = 1:numel(candidates)
                idx = find(arrayfun(@(f) contains(f.name, candidates{i}), files), 1);
                if ~isempty(idx)
                    fp = fullfile(files(idx).folder, files(idx).name);
                    return;
                end
            end
        end

        function [t, v] = readStandaloneCache(cachePath, sensorType, pointId, cfg, adapter)
            t = [];
            v = [];
            requireMetadata = bms.data.TimeSeriesLoader.seriesCacheRequireMetadata(cfg);
            if requireMetadata && ~bms.data.CacheManager.metadataMatches( ...
                    cachePath, adapter, 'jlj_csv_v2')
                return;
            end

            try
                S = load(cachePath, 'ts', 'valx', 'valy', 'valz', 'meta');
                if ~isfield(S, 'meta') || ~isstruct(S.meta)
                    return;
                end
                [t, v] = bms.data.JiulongjiangCsvDataSource.pickCachedChannel( ...
                    S, sensorType, pointId);
                if isempty(t) || isempty(v) || numel(t) ~= numel(v)
                    t = [];
                    v = [];
                    return;
                end
                t = t(:);
                v = v(:);
            catch
                t = [];
                v = [];
            end
        end

        function ok = isUsableStandaloneCache(cachePath, sensorType, pointId, cfg)
            ok = false;
            if isempty(cachePath) || ~exist(cachePath, 'file')
                return;
            end
            adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(cfg);
            requireMetadata = bms.data.TimeSeriesLoader.seriesCacheRequireMetadata(cfg);
            if requireMetadata && ~bms.data.CacheManager.metadataMatches( ...
                    cachePath, adapter, 'jlj_csv_v2')
                return;
            end
            col = bms.data.JiulongjiangCsvDataSource.resolveValueColumn(sensorType, pointId);
            valueField = strrep(col, 'value_', 'val');
            try
                warnState = warning('off', 'all');
                warnCleanup = onCleanup(@() warning(warnState)); %#ok<NASGU>
                info = whos('-file', cachePath);
                names = {info.name};
                required = {'ts', 'meta', valueField};
                if ~all(ismember(required, names))
                    return;
                end
                tsInfo = info(strcmp(names, 'ts'));
                valueInfo = info(strcmp(names, valueField));
                if isempty(tsInfo) || isempty(valueInfo) ...
                        || prod(valueInfo(1).size) <= 0
                    return;
                end
                % MATLAB may report an empty ``whos -file`` size for saved
                % datetime objects.  Treat that as unknown here; the actual
                % cache reader still enforces a non-empty, equal-length pair.
                if ~isempty(tsInfo(1).size) ...
                        && (prod(tsInfo(1).size) <= 0 ...
                        || prod(tsInfo(1).size) ~= prod(valueInfo(1).size))
                    return;
                end
                valueClasses = {'double', 'single', 'int8', 'uint8', 'int16', ...
                    'uint16', 'int32', 'uint32', 'int64', 'uint64', 'logical'};
                if ~strcmp(tsInfo(1).class, 'datetime') ...
                        || ~ismember(valueInfo(1).class, valueClasses)
                    return;
                end
                S = load(cachePath, 'meta');
                ok = isfield(S, 'meta') && isstruct(S.meta);
            catch
                ok = false;
            end
        end

        function [t, v] = applyRange(t, v, varargin)
            range = bms.data.JiulongjiangCsvDataSource.extractRange(varargin{:});
            if ~isempty(range) && isfield(range, 'start') && isfield(range, 'end') ...
                    && ~isempty(t)
                mask = t >= range.start & t <= range.end;
                t = t(mask);
                v = v(mask);
            end
        end

        function layouts = layoutCandidates(dt, startText, endText, adapter)
            dayText = datestr(dt, 'yyyy-mm-dd');
            prefixes = {'jlj'};
            if isfield(adapter, 'prefixes') && ~isempty(adapter.prefixes)
                prefixes = adapter.prefixes;
            end
            layouts = struct('folder_name', {}, 'subdir', {});
            for i = 1:numel(prefixes)
                layouts(end+1) = struct('folder_name', sprintf('data_%s_%s', prefixes{i}, dayText), ...
                    'subdir', fullfile('data', prefixes{i}, 'csv')); %#ok<AGROW>
            end
            layouts(end+1) = struct('folder_name', sprintf('jljData%s-%s', startText, endText), ...
                'subdir', fullfile('data', 'csv'));
        end

        function [dirp, meta] = extractZip(zipPath, subdir, adapter, meta)
            dirp = '';
            stagingRoot = bms.data.JiulongjiangCsvDataSource.resolveProjectPath(adapter.zip.staging_root);
            if ~exist(stagingRoot, 'dir'), mkdir(stagingRoot); end
            [~, base, ~] = fileparts(zipPath);
            dest = fullfile(stagingRoot, base);
            if ~exist(fullfile(dest, subdir), 'dir')
                if ~exist(dest, 'dir'), mkdir(dest); end
                unzip(zipPath, dest);
            end
            candidate = fullfile(dest, subdir);
            if exist(candidate, 'dir')
                dirp = candidate;
                meta.cache_dir = bms.data.JiulongjiangCsvDataSource.resolveCacheDir(dirp, adapter);
            end
        end

        function cacheDir = resolveCacheDir(csvDir, adapter)
            cacheDir = '';
            if ~adapter.cache.enabled
                return;
            end
            base = adapter.cache.dir;
            if isempty(base)
                return;
            end
            if bms.data.JiulongjiangCsvDataSource.isAbsolutePath(base)
                cacheDir = base;
            else
                cacheDir = fullfile(csvDir, base);
            end
        end

        function cacheDir = resolveCacheDirFromMeta(~, varargin)
            cacheDir = '';
            for i = 1:numel(varargin)
                if isstruct(varargin{i}) && isfield(varargin{i}, 'cache_dir')
                    cacheDir = varargin{i}.cache_dir;
                    return;
                end
            end
        end

        function ok = useCache(cachePath, srcPath, adapter)
            ok = false;
            if isempty(cachePath) || ~exist(cachePath, 'file')
                return;
            end
            validateMode = 'mtime_size';
            if isstruct(adapter) && isfield(adapter, 'cache') && isstruct(adapter.cache) && isfield(adapter.cache, 'validate')
                validateMode = adapter.cache.validate;
            elseif ischar(adapter) || isstring(adapter)
                validateMode = char(adapter);
                adapter = struct();
            end
            if strcmpi(validateMode, 'none')
                ok = true;
                return;
            end
            if strcmpi(validateMode, 'metadata')
                ok = bms.data.CacheManager.metadataMatchesFull(cachePath, {srcPath}, adapter, 'jlj_csv_v2');
                return;
            end
            try
                warnState = warning('off', 'all');
                warnCleanup = onCleanup(@() warning(warnState)); %#ok<NASGU>
                metaInfo = whos('-file', cachePath, 'meta');
                if isempty(metaInfo)
                    return;
                end
                S = load(cachePath, 'meta');
                if ~isfield(S, 'meta') || ~isstruct(S.meta)
                    return;
                end
                mtime = bms.data.JiulongjiangCsvDataSource.fileMtime(srcPath);
                fsize = bms.data.JiulongjiangCsvDataSource.fileSize(srcPath);
                ok = isfield(S.meta, 'mtime') && isfield(S.meta, 'size') && ...
                    S.meta.mtime == mtime && S.meta.size == fsize;
            catch
                ok = false;
            end
        end

        function [t, v] = pickCachedChannel(S, sensorType, pointId)
            if isfield(S, 'ts')
                t = S.ts;
            else
                t = [];
            end
            valx = bms.data.JiulongjiangCsvDataSource.getFieldDefault(S, 'valx', []);
            valy = bms.data.JiulongjiangCsvDataSource.getFieldDefault(S, 'valy', []);
            valz = bms.data.JiulongjiangCsvDataSource.getFieldDefault(S, 'valz', []);
            [t, v] = bms.data.JiulongjiangCsvDataSource.pickChannelFromArrays(t, valx, valy, valz, sensorType, pointId);
        end

        function [t, v] = pickChannelFromArrays(t, valx, valy, valz, sensorType, pointId)
            col = bms.data.JiulongjiangCsvDataSource.resolveValueColumn(sensorType, pointId);
            switch lower(col)
                case 'value_y'
                    v = valy;
                case 'value_z'
                    v = valz;
                otherwise
                    v = valx;
            end
        end

        function vec = extractNumericColumn(T, vars, name)
            vec = [];
            valueCol = bms.data.JiulongjiangCsvDataSource.pickVar(vars, name);
            if isempty(valueCol)
                return;
            end
            raw = T.(valueCol);
            if isstring(raw) || iscellstr(raw)
                vec = str2double(string(raw));
            else
                vec = double(raw);
            end
        end

        function col = resolveValueColumn(sensorType, pointId)
            col = 'value_x';
            st = lower(string(sensorType));
            if st == "wind_direction"
                col = 'value_y';
            elseif st == "humidity"
                col = 'value_y';
            elseif st == "wind_speed"
                col = 'value_x';
            elseif st == "temperature"
                col = 'value_x';
            elseif st == "tilt"
                if contains(pointId, '-Y') || contains(pointId, '_Y')
                    col = 'value_y';
                else
                    col = 'value_x';
                end
            elseif st == "eq_x"
                col = 'value_x';
            elseif st == "eq_y"
                col = 'value_y';
            elseif st == "eq_z"
                col = 'value_z';
            elseif st == "gnss_x"
                col = 'value_x';
            elseif st == "gnss_y"
                col = 'value_y';
            elseif st == "gnss_z"
                col = 'value_z';
            elseif ismember(st, ["acceleration", "cable_accel", "deflection", "bearing_displacement", "strain"])
                if endsWith(string(pointId), "-Y") || endsWith(string(pointId), "_Y")
                    col = 'value_y';
                elseif endsWith(string(pointId), "-Z") || endsWith(string(pointId), "_Z")
                    col = 'value_z';
                end
            else
                col = 'value_x';
            end
        end

        function t = parseTime(ts, fmt)
            try
                t = datetime(ts, 'InputFormat', fmt);
            catch
                try
                    t = datetime(ts, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
                catch
                    t = NaT(size(ts));
                end
            end
        end

        function value = pickVar(vars, name)
            value = '';
            idx = find(strcmpi(vars, name), 1);
            if ~isempty(idx)
                value = vars{idx};
            end
        end

        function range = extractRange(varargin)
            range = [];
            for i = 1:numel(varargin)
                if isstruct(varargin{i}) && isfield(varargin{i}, 'range')
                    range = varargin{i}.range;
                    return;
                end
            end
        end

        function ok = isReusableRawCache(cachePath, srcPath, adapter)
            ok = false;
            if isempty(cachePath) || ~isfile(cachePath) ...
                    || ~bms.data.JiulongjiangCsvDataSource.useCache(cachePath, srcPath, adapter) ...
                    || ~bms.data.CacheManager.metadataMatchesFull( ...
                        cachePath, {srcPath}, adapter, 'jlj_csv_v2')
                return;
            end
            try
                info = whos('-file', cachePath);
                names = {info.name};
                required = {'ts', 'valx', 'valy', 'valz', 'meta'};
                if ~all(ismember(required, names))
                    return;
                end
                tsInfo = info(strcmp(names, 'ts'));
                if isempty(tsInfo) || ~strcmp(tsInfo(1).class, 'datetime')
                    return;
                end
                nonemptyValues = false;
                for field = {'valx', 'valy', 'valz'}
                    valueInfo = info(strcmp(names, field{1}));
                    if isempty(valueInfo)
                        return;
                    end
                    if bms.data.JiulongjiangCsvDataSource.variableElementCount(valueInfo(1)) > 0
                        nonemptyValues = true;
                    end
                end
                if ~nonemptyValues
                    return;
                end
                S = load(cachePath, 'meta');
                if ~isfield(S, 'meta') || ~isstruct(S.meta) ...
                        || ~isfield(S.meta, 'mtime') || ~isfield(S.meta, 'size')
                    return;
                end
                jsonMeta = jsondecode(fileread(bms.data.CacheManager.metadataPath(cachePath)));
                matHasPair = isfield(S.meta, 'pair_id') && ~isempty(S.meta.pair_id);
                jsonHasPair = isfield(jsonMeta, 'pair_id') && ~isempty(jsonMeta.pair_id);
                if xor(matHasPair, jsonHasPair)
                    return;
                end
                if matHasPair && ~strcmp(char(string(S.meta.pair_id)), ...
                        char(string(jsonMeta.pair_id)))
                    return;
                end
                if isfield(jsonMeta, 'mat_bytes')
                    d = dir(cachePath);
                    if isempty(d) || double(d(1).bytes) ~= double(jsonMeta.mat_bytes)
                        return;
                    end
                end
                ok = true;
            catch
                ok = false;
            end
        end

        function count = variableElementCount(info)
            count = 0;
            if isempty(info) || ~isfield(info, 'size') || isempty(info.size)
                return;
            end
            count = prod(double(info.size));
        end

        function tf = sameSourceRecord(left, right)
            tf = numel(left) == 1 && numel(right) == 1 ...
                && logical(left(1).exists) && logical(right(1).exists) ...
                && double(left(1).bytes) == double(right(1).bytes) ...
                && strcmp(char(string(left(1).modified_at)), char(string(right(1).modified_at)));
        end

        function bytes = cachePairBytes(cachePath)
            bytes = 0;
            paths = {cachePath, bms.data.CacheManager.metadataPath(cachePath)};
            for i = 1:numel(paths)
                if isfile(paths{i})
                    d = dir(paths{i});
                    bytes = bytes + double(d(1).bytes);
                end
            end
        end

        function info = emptyCacheBuildInfo(sourcePath)
            info = struct( ...
                'source_path', char(string(sourcePath)), ...
                'source_bytes', 0, ...
                'source_modified_at', '', ...
                'cache_path', '', ...
                'metadata_path', '', ...
                'cache_bytes', 0, ...
                'status', 'pending', ...
                'error_identifier', '', ...
                'error_message', '');
        end

        function cleanupTempCache(tempMat)
            paths = {tempMat, bms.data.CacheManager.metadataPath(tempMat)};
            bms.data.JiulongjiangCsvDataSource.cleanupFiles(paths);
        end

        function cleanup = acquireBuildLock(lockPath)
            %ACQUIREBUILDLOCK Atomically reject overlapping cache writers.
            % A same-host lock whose owning PID has exited is reclaimed so a
            % hard-killed task can be restarted immediately.
            lockPath = char(string(lockPath));
            token = char(java.util.UUID.randomUUID());
            acquired = false;
            for attempt = 1:2
                try
                    acquired = logical(java.io.File(lockPath).createNewFile());
                catch ME
                    error('BMS:JljCachePrebuild:LockCreateFailed', ...
                        'Unable to create cache build lock %s: %s', lockPath, ME.message);
                end
                if acquired
                    break;
                end
                if attempt == 1 && bms.data.JiulongjiangCsvDataSource.isBuildLockStale(lockPath)
                    try
                        delete(lockPath);
                    catch
                    end
                    continue;
                end
            end
            if ~acquired
                error('BMS:JljCachePrebuild:Locked', ...
                    'Another cache build owns the lock: %s', lockPath);
            end
            owner = struct('token', token, ...
                'created_at', char(datetime('now', ...
                    'Format', 'yyyy-MM-dd HH:mm:ss')), ...
                'host', bms.data.JiulongjiangCsvDataSource.localHostName(), ...
                'pid', bms.data.JiulongjiangCsvDataSource.currentPid());
            try
                bms.core.Logger.writeJson(lockPath, owner);
            catch ME
                try
                    delete(lockPath);
                catch
                end
                rethrow(ME);
            end
            cleanup = onCleanup(@() ...
                bms.data.JiulongjiangCsvDataSource.releaseBuildLock(lockPath, token));
        end

        function recoverInterruptedTransactions(cachePath, srcPath, adapter)
            cacheDir = fileparts(cachePath);
            [~, base, ~] = fileparts(cachePath);
            transactions = dir(fullfile(cacheDir, ['.' base '.cachetxn.*']));
            for i = 1:numel(transactions)
                if ~transactions(i).isdir || any(strcmp(transactions(i).name, {'.','..'}))
                    continue;
                end
                transactionDir = fullfile(transactions(i).folder, transactions(i).name);
                if bms.data.JiulongjiangCsvDataSource.isReusableRawCache( ...
                        cachePath, srcPath, adapter)
                    bms.data.JiulongjiangCsvDataSource.cleanupTransactionDir( ...
                        transactionDir, true);
                    continue;
                end
                backupMat = fullfile(transactionDir, 'backup.mat');
                backupMeta = bms.data.CacheManager.metadataPath(backupMat);
                if bms.data.JiulongjiangCsvDataSource.isReusableRawCache( ...
                        backupMat, srcPath, adapter)
                    bms.data.JiulongjiangCsvDataSource.copyChecked( ...
                        backupMat, cachePath, 'interrupted cache MAT recovery');
                    bms.data.JiulongjiangCsvDataSource.copyChecked( ...
                        backupMeta, bms.data.CacheManager.metadataPath(cachePath), ...
                        'interrupted cache metadata recovery');
                    if ~bms.data.JiulongjiangCsvDataSource.isReusableRawCache( ...
                            cachePath, srcPath, adapter)
                        error('BMS:JljCachePrebuild:RecoveryValidationFailed', ...
                            'Recovered cache pair validation failed for source: %s', srcPath);
                    end
                else
                    bms.data.JiulongjiangCsvDataSource.cleanupFiles( ...
                        {cachePath, bms.data.CacheManager.metadataPath(cachePath)});
                end
                bms.data.JiulongjiangCsvDataSource.cleanupTransactionDir( ...
                    transactionDir, true);
            end
        end

        function transactionDir = createTransactionDir(cachePath)
            cacheDir = fileparts(cachePath);
            [~, base, ~] = fileparts(cachePath);
            suffix = regexprep(char(java.util.UUID.randomUUID()), '-', '');
            transactionDir = fullfile(cacheDir, ['.' base '.cachetxn.' suffix]);
            [ok, message] = mkdir(transactionDir);
            if ~ok
                error('BMS:JljCachePrebuild:TransactionCreateFailed', ...
                    'Unable to create cache transaction directory %s: %s', ...
                    transactionDir, message);
            end
        end

        function commitCachePair(tempMat, cachePath, srcPath, adapter, faultInjection)
            tempMeta = bms.data.CacheManager.metadataPath(tempMat);
            finalMeta = bms.data.CacheManager.metadataPath(cachePath);
            transactionDir = fileparts(tempMat);
            backupMat = fullfile(transactionDir, 'backup.mat');
            backupMeta = bms.data.CacheManager.metadataPath(backupMat);
            hadMat = isfile(cachePath);
            hadMeta = isfile(finalMeta);

            if hadMat
                bms.data.JiulongjiangCsvDataSource.copyChecked( ...
                    cachePath, backupMat, 'cache MAT backup');
            end
            if hadMeta
                bms.data.JiulongjiangCsvDataSource.copyChecked( ...
                    finalMeta, backupMeta, 'cache metadata backup');
            end

            try
                bms.data.JiulongjiangCsvDataSource.moveChecked( ...
                    tempMat, cachePath, 'cache MAT publish');
                if strcmp(faultInjection, 'after_mat_publish')
                    error('BMS:JljCachePrebuild:InjectedCommitFailure', ...
                        'Injected failure after MAT publish and before metadata publish.');
                elseif strcmp(faultInjection, 'after_mat_publish_abrupt')
                    bms.core.Logger.writeJson(fullfile(transactionDir, 'preserve.json'), ...
                        struct('reason', 'simulated_abrupt_exit'));
                    error('BMS:JljCachePrebuild:InjectedAbruptCommitFailure', ...
                        'Simulated abrupt exit after MAT publish and before metadata publish.');
                end
                bms.data.JiulongjiangCsvDataSource.moveChecked( ...
                    tempMeta, finalMeta, 'cache metadata publish');
                if ~bms.data.JiulongjiangCsvDataSource.isReusableRawCache( ...
                        cachePath, srcPath, adapter)
                    error('BMS:JljCachePrebuild:FinalValidationFailed', ...
                        'Committed cache pair validation failed for source: %s', srcPath);
                end
            catch ME
                if strcmp(faultInjection, 'after_mat_publish_abrupt')
                    rethrow(ME);
                end
                rollbackErrors = bms.data.JiulongjiangCsvDataSource.rollbackCachePair( ...
                    cachePath, finalMeta, backupMat, backupMeta, hadMat, hadMeta);
                if ~isempty(rollbackErrors)
                    error('BMS:JljCachePrebuild:RollbackFailed', ...
                        'Cache commit failed (%s) and rollback failed: %s', ...
                        ME.message, strjoin(rollbackErrors, ' | '));
                end
                rethrow(ME);
            end
        end

        function cleanupTransactionDir(transactionDir, force)
            if nargin < 2, force = false; end
            if ~isfolder(transactionDir), return; end
            if ~force && isfile(fullfile(transactionDir, 'preserve.json'))
                return;
            end
            try
                rmdir(transactionDir, 's');
            catch
            end
        end

        function releaseBuildLock(lockPath, token)
            if ~isfile(lockPath), return; end
            try
                owner = jsondecode(fileread(lockPath));
                if ~isfield(owner, 'token') ...
                        || ~strcmp(char(string(owner.token)), char(string(token)))
                    return;
                end
                delete(lockPath);
            catch
            end
        end

        function stale = isBuildLockStale(lockPath)
            stale = false;
            try
                owner = jsondecode(fileread(lockPath));
                sameHost = isfield(owner, 'host') && strcmpi( ...
                    char(string(owner.host)), ...
                    bms.data.JiulongjiangCsvDataSource.localHostName());
                if sameHost && isfield(owner, 'pid') && isfinite(double(owner.pid)) ...
                        && (ispc || double(owner.pid) == ...
                            bms.data.JiulongjiangCsvDataSource.currentPid())
                    stale = ~bms.data.JiulongjiangCsvDataSource.isProcessAlive(double(owner.pid));
                    return;
                end
            catch
            end
            % A malformed/foreign-host lock is not reclaimed while recent;
            % this closes the tiny create-before-owner-write race.
            d = dir(lockPath);
            if ~isempty(d)
                lockTime = datetime(d(1).datenum, 'ConvertFrom', 'datenum');
                stale = hours(datetime('now') - lockTime) >= 24;
            end
        end

        function alive = isProcessAlive(pid)
            alive = false;
            if ~isfinite(pid) || pid <= 0 || pid ~= floor(pid)
                return;
            end
            if pid == bms.data.JiulongjiangCsvDataSource.currentPid()
                alive = true;
                return;
            end
            if ispc
                try
                    process = System.Diagnostics.Process.GetProcessById(int32(pid));
                    alive = ~logical(process.HasExited);
                catch
                    alive = false;
                end
            end
        end

        function pid = currentPid()
            try
                pid = double(feature('getpid'));
            catch
                pid = NaN;
            end
        end

        function host = localHostName()
            try
                host = char(java.net.InetAddress.getLocalHost().getHostName());
            catch
                host = char(string(getenv('COMPUTERNAME')));
            end
        end

        function errors = rollbackCachePair(cachePath, finalMeta, backupMat, backupMeta, hadMat, hadMeta)
            errors = {};
            try
                if hadMat
                    bms.data.JiulongjiangCsvDataSource.copyChecked( ...
                        backupMat, cachePath, 'cache MAT rollback');
                elseif isfile(cachePath)
                    delete(cachePath);
                end
            catch ME
                errors{end+1} = ['MAT: ' ME.message]; %#ok<AGROW>
            end
            try
                if hadMeta
                    bms.data.JiulongjiangCsvDataSource.copyChecked( ...
                        backupMeta, finalMeta, 'cache metadata rollback');
                elseif isfile(finalMeta)
                    delete(finalMeta);
                end
            catch ME
                errors{end+1} = ['metadata: ' ME.message]; %#ok<AGROW>
            end
        end

        function copyChecked(source, destination, operation)
            [ok, message] = copyfile(source, destination, 'f');
            if ~ok
                error('BMS:JljCachePrebuild:CommitFailed', ...
                    'Unable to perform %s (%s -> %s): %s', ...
                    operation, source, destination, message);
            end
        end

        function moveChecked(source, destination, operation)
            [ok, message] = movefile(source, destination, 'f');
            if ~ok
                error('BMS:JljCachePrebuild:CommitFailed', ...
                    'Unable to perform %s (%s -> %s): %s', ...
                    operation, source, destination, message);
            end
        end

        function cleanupFiles(paths)
            for i = 1:numel(paths)
                if isfile(paths{i})
                    try
                        delete(paths{i});
                    catch
                    end
                end
            end
        end

        function out = getFieldDefault(s, field, default)
            if isstruct(s) && isfield(s, field)
                out = s.(field);
            else
                out = default;
            end
        end

        function out = fileMtime(pathValue)
            d = dir(pathValue);
            if isempty(d)
                out = 0;
            else
                out = d(1).datenum;
            end
        end

        function out = fileSize(pathValue)
            d = dir(pathValue);
            if isempty(d)
                out = 0;
            else
                out = d(1).bytes;
            end
        end

        function p = resolveProjectPath(p)
            if isempty(p), return; end
            if isstring(p), p = char(p); end
            if ischar(p) && ~bms.data.JiulongjiangCsvDataSource.isAbsolutePath(p)
                projectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
                p = fullfile(projectRoot, p);
            end
        end

        function tf = isAbsolutePath(pathValue)
            tf = false;
            if isempty(pathValue) || ~ischar(pathValue)
                return;
            end
            if numel(pathValue) >= 2 && pathValue(2) == ':'
                tf = true;
            elseif startsWith(pathValue, filesep)
                tf = true;
            end
        end
    end
end
