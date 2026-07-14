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
            if ~isempty(cachePath) && bms.data.JiulongjiangCsvDataSource.useCache(cachePath, fp, adapter)
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
                T = readtable(fp, 'Delimiter', adapter.csv.delimiter, ...
                    'FileEncoding', adapter.csv.encoding, ...
                    'TextType', 'string', 'VariableNamingRule', 'preserve');
                vars = T.Properties.VariableNames;
                timeCol = bms.data.JiulongjiangCsvDataSource.pickVar(vars, adapter.csv.time_column);
                if isempty(timeCol)
                    return;
                end
                tsText = string(T.(timeCol));
                if adapter.csv.strip_quotes
                    tsText = strrep(tsText, '"', '');
                end
                tsText = strtrim(tsText);
                t = bms.data.JiulongjiangCsvDataSource.parseTime(tsText, adapter.csv.time_format);
                valx = bms.data.JiulongjiangCsvDataSource.extractNumericColumn(T, vars, 'value_x');
                valy = bms.data.JiulongjiangCsvDataSource.extractNumericColumn(T, vars, 'value_y');
                valz = bms.data.JiulongjiangCsvDataSource.extractNumericColumn(T, vars, 'value_z');
                if ~isempty(cachePath)
                    meta = struct('src', fp, ...
                        'mtime', bms.data.JiulongjiangCsvDataSource.fileMtime(fp), ...
                        'size', bms.data.JiulongjiangCsvDataSource.fileSize(fp)); %#ok<NASGU>
                    ts = t; %#ok<NASGU>
                    save(cachePath, 'ts', 'valx', 'valy', 'valz', 'meta');
                    try
                        bms.data.CacheManager.writeMetadata(cachePath, {fp}, adapter, 'jlj_csv_v2');
                    catch
                    end
                end
                [t, v] = bms.data.JiulongjiangCsvDataSource.pickChannelFromArrays(t, valx, valy, valz, sensorType, pointId);
            end

            [t, v] = bms.data.JiulongjiangCsvDataSource.applyRange(t, v, varargin{:});
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
