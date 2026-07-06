classdef HongtangLowFreqDataSource < bms.data.BaseDataSource
    %HONGTANGLOWFREQDATASOURCE Hongtang period folder with lowfreq/WIM layout.

    methods
        function obj = HongtangLowFreqDataSource(root, cfg)
            if nargin < 2, cfg = struct(); end
            obj@bms.data.BaseDataSource(root, cfg, 'hongtang_period');
        end

        function folders = candidateDirs(obj, subfolder, startDate, endDate) %#ok<INUSD>
            folders = bms.data.PeriodFolderAdapter.candidateDirs(obj.Root, subfolder, startDate, endDate);
        end

        function p = lowfreqPath(obj)
            p = bms.data.DataLayoutResolver.lowfreqDir(obj.Root);
        end
    end

    methods (Static)
        function [t, v, used, files] = readRange(root, pointId, sensorType, range, cfg)
            t = [];
            v = [];
            used = false;
            files = {};
            if nargin < 5, cfg = struct(); end

            adapter = bms.data.HongtangLowFreqDataSource.adapterFromConfig(cfg);
            if ~bms.data.HongtangLowFreqDataSource.supportsSensor(adapter, sensorType)
                return;
            end
            if ~adapter.enabled
                return;
            end

            xlsxPath = bms.data.HongtangLowFreqDataSource.resolveFile(root, adapter.file);
            if isempty(xlsxPath) || ~exist(xlsxPath, 'file')
                return;
            end

            used = true;
            files = {xlsxPath};
            [t, v] = bms.data.HongtangLowFreqDataSource.readSeries(xlsxPath, pointId, adapter, sensorType);
            if isempty(t) || isempty(v)
                return;
            end

            if ~isempty(range) && isfield(range, 'start') && isfield(range, 'end')
                mask = t >= range.start & t <= range.end;
                t = t(mask);
                v = v(mask);
            end
        end

        function adapter = adapterFromConfig(cfg)
            adapter = struct();
            if isstruct(cfg) && isfield(cfg, 'data_adapter') && isstruct(cfg.data_adapter)
                if isfield(cfg.data_adapter, 'hongtang_lowfreq') && isstruct(cfg.data_adapter.hongtang_lowfreq)
                    adapter = cfg.data_adapter.hongtang_lowfreq;
                elseif isfield(cfg.data_adapter, 'lowfreq') && isstruct(cfg.data_adapter.lowfreq)
                    adapter = cfg.data_adapter.lowfreq;
                end
            end

            adapter.enabled = bms.data.HongtangLowFreqDataSource.getFieldDefault(adapter, 'enabled', false);
            adapter.file = bms.data.HongtangLowFreqDataSource.getFieldDefault(adapter, 'file', fullfile('lowfreq', 'data.xlsx'));
            adapter.sheet = bms.data.HongtangLowFreqDataSource.getFieldDefault(adapter, 'sheet', 'auto_first_non_empty');
            adapter.time_column = bms.data.HongtangLowFreqDataSource.getFieldDefault(adapter, 'time_column', 'SamplingTime');
            adapter.sensor_types = bms.data.HongtangLowFreqDataSource.getFieldDefault(adapter, 'sensor_types', {'bearing_displacement'});
            adapter.missing_tokens = bms.data.HongtangLowFreqDataSource.getFieldDefault(adapter, 'missing_tokens', {'--', ''});
            adapter.abs_max_valid = bms.data.HongtangLowFreqDataSource.getFieldDefault(adapter, 'abs_max_valid', 500);

            if ~isfield(adapter, 'cache') || ~isstruct(adapter.cache)
                adapter.cache = struct();
            end
            adapter.cache.enabled = bms.data.HongtangLowFreqDataSource.getFieldDefault(adapter.cache, 'enabled', true);
            adapter.cache.dir = bms.data.HongtangLowFreqDataSource.getFieldDefault(adapter.cache, 'dir', 'cache');
            adapter.cache.validate = bms.data.HongtangLowFreqDataSource.getFieldDefault(adapter.cache, 'validate', 'mtime_size');
        end

        function tf = supportsSensor(adapter, sensorType)
            tf = false;
            if isempty(adapter) || ~isstruct(adapter) || ~isfield(adapter, 'enabled') || ~adapter.enabled
                return;
            end
            types = adapter.sensor_types;
            if ischar(types) || isstring(types)
                types = cellstr(string(types));
            end
            if ~iscell(types)
                return;
            end
            tf = any(strcmpi(types, sensorType)) || any(strcmpi(types, 'all'));
        end

        function p = resolveFile(root, p)
            if isempty(p), return; end
            if isstring(p), p = char(p); end
            if ~ischar(p), p = ''; return; end
            if ~bms.data.HongtangLowFreqDataSource.isAbsolutePath(p)
                p = fullfile(root, p);
            end
        end

        function [t, v] = readSeries(xlsxPath, pointId, adapter, sensorType)
            t = [];
            v = [];
            if nargin < 4
                sensorType = '';
            end

            cachePath = bms.data.HongtangLowFreqDataSource.cacheFile(xlsxPath, pointId, adapter);
            if ~isempty(cachePath) && bms.data.HongtangLowFreqDataSource.canUseCache(cachePath, xlsxPath, adapter)
                S = load(cachePath, 'times', 'vals');
                if isfield(S, 'times') && isfield(S, 'vals')
                    t = S.times;
                    v = S.vals;
                    v = bms.data.HongtangLowFreqDataSource.applyAbsMaxValid(v, adapter, sensorType);
                    return;
                end
            end

            [T, timeCol] = bms.data.HongtangLowFreqDataSource.readTableCached(xlsxPath, adapter);
            if isempty(T) || isempty(timeCol)
                return;
            end

            pointCol = bms.data.HongtangLowFreqDataSource.pickColumn(T.Properties.VariableNames, pointId);
            if isempty(pointCol)
                return;
            end

            t = bms.data.HongtangLowFreqDataSource.parseTime(T.(timeCol));
            v = bms.data.HongtangLowFreqDataSource.toNumeric(T.(pointCol), adapter.missing_tokens);
            validTime = ~isnat(t);
            t = t(validTime);
            v = v(validTime);

            if ~isempty(cachePath)
                times = t; %#ok<NASGU>
                vals = v; %#ok<NASGU>
                meta = struct('mtime', bms.data.HongtangLowFreqDataSource.fileMtime(xlsxPath), ...
                    'size', bms.data.HongtangLowFreqDataSource.fileSize(xlsxPath), ...
                    'cache_version', bms.data.HongtangLowFreqDataSource.rawCacheVersion()); %#ok<NASGU>
                save(cachePath, 'times', 'vals', 'meta');
                try
                    bms.data.CacheManager.writeMetadata(cachePath, {xlsxPath}, ...
                        bms.data.HongtangLowFreqDataSource.rawCacheConfig(adapter), ...
                        bms.data.HongtangLowFreqDataSource.rawCacheVersion());
                catch
                end
            end

            v = bms.data.HongtangLowFreqDataSource.applyAbsMaxValid(v, adapter, sensorType);
        end

        function [T, timeCol] = readTableCached(xlsxPath, adapter)
            T = table();
            timeCol = '';

            persistent wbCache
            if isempty(wbCache)
                wbCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
            end

            sheet = bms.data.HongtangLowFreqDataSource.pickSheet(xlsxPath, adapter);
            if isempty(sheet)
                return;
            end

            key = sprintf('%s|%.12f|%d|%s', xlsxPath, ...
                bms.data.HongtangLowFreqDataSource.fileMtime(xlsxPath), ...
                bms.data.HongtangLowFreqDataSource.fileSize(xlsxPath), sheet);
            if isKey(wbCache, key)
                S = wbCache(key);
                T = S.T;
                timeCol = S.time_col;
                return;
            end

            T = readtable(xlsxPath, 'Sheet', sheet, 'VariableNamingRule', 'preserve', 'TextType', 'string');
            if isempty(T)
                return;
            end

            timeCol = bms.data.HongtangLowFreqDataSource.pickColumn(T.Properties.VariableNames, adapter.time_column);
            if isempty(timeCol)
                return;
            end

            wbCache(key) = struct('T', T, 'time_col', timeCol);
        end

        function sheet = pickSheet(xlsxPath, adapter)
            sheet = '';
            s = adapter.sheet;
            if isstring(s), s = char(s); end
            if ischar(s) && ~isempty(s) && ~strcmpi(s, 'auto_first_non_empty')
                sheet = s;
                return;
            end

            names = sheetnames(xlsxPath);
            for i = 1:numel(names)
                try
                    C = readcell(xlsxPath, 'Sheet', names{i}, 'Range', 'A1:C5');
                    if any(cellfun(@bms.data.HongtangLowFreqDataSource.isNonemptyCellValue, C(:)))
                        sheet = names{i};
                        return;
                    end
                catch
                end
            end
            if ~isempty(names)
                sheet = names{1};
            end
        end

        function tf = isNonemptyCellValue(x)
            tf = false;
            if isempty(x)
                return;
            end
            if isnumeric(x) && isscalar(x) && isnan(x)
                return;
            end
            if isstring(x)
                if ismissing(x)
                    return;
                end
                tf = strlength(strtrim(x)) > 0;
                return;
            end
            if ischar(x)
                tf = ~isempty(strtrim(x));
                return;
            end
            tf = true;
        end

        function name = pickColumn(vars, target)
            name = '';
            if isstring(target), target = char(target); end
            if ~ischar(target) || isempty(target) || isempty(vars)
                return;
            end
            idx = find(strcmp(vars, target), 1);
            if isempty(idx)
                idx = find(strcmpi(vars, target), 1);
            end
            if ~isempty(idx)
                name = vars{idx};
            end
        end

        function t = parseTime(raw)
            if isdatetime(raw)
                t = raw;
                return;
            end
            if isnumeric(raw)
                t = datetime(raw, 'ConvertFrom', 'excel');
                return;
            end

            s = strtrim(strrep(string(raw), '"', ''));
            fmts = {'yyyy-MM-dd HH:mm:ss.SSS', 'yyyy-MM-dd HH:mm:ss'};
            t = NaT(size(s));
            for i = 1:numel(fmts)
                try
                    tt = datetime(s, 'InputFormat', fmts{i});
                    bad = isnat(t) & ~isnat(tt);
                    t(bad) = tt(bad);
                catch
                end
            end
        end

        function v = toNumeric(raw, missingTokens)
            if isnumeric(raw)
                v = double(raw);
                return;
            end
            s = strtrim(strrep(string(raw), '"', ''));
            miss = false(size(s));
            for i = 1:numel(s)
                miss(i) = bms.data.HongtangLowFreqDataSource.isMissingToken(s(i), missingTokens);
            end
            v = str2double(s);
            v(miss) = NaN;
        end

        function tf = isMissingToken(s, tokens)
            tf = strlength(s) == 0;
            if tf, return; end
            if ischar(tokens) || isstring(tokens)
                tokens = cellstr(tokens);
            end
            if ~iscell(tokens)
                return;
            end
            for i = 1:numel(tokens)
                tok = string(tokens{i});
                if s == tok
                    tf = true;
                    return;
                end
            end
        end

        function cachePath = cacheFile(xlsxPath, pointId, adapter)
            cachePath = '';
            if ~adapter.cache.enabled
                return;
            end
            cacheDir = adapter.cache.dir;
            if isstring(cacheDir), cacheDir = char(cacheDir); end
            if isempty(cacheDir) || ~ischar(cacheDir)
                return;
            end
            if ~bms.data.HongtangLowFreqDataSource.isAbsolutePath(cacheDir)
                cacheDir = fullfile(fileparts(xlsxPath), cacheDir);
            end
            if ~exist(cacheDir, 'dir')
                mkdir(cacheDir);
            end
            [~, fn, ~] = fileparts(xlsxPath);
            cachePath = fullfile(cacheDir, sprintf('%s__%s__raw_v3.mat', ...
                bms.data.HongtangLowFreqDataSource.sanitizeCacheName(fn), ...
                bms.data.HongtangLowFreqDataSource.sanitizeCacheName(pointId)));
        end

        function v = applyAbsMaxValid(v, adapter, sensorType)
            maxAbs = bms.data.HongtangLowFreqDataSource.resolveAbsMaxValid(adapter, sensorType);
            if isnumeric(maxAbs) && isscalar(maxAbs) && isfinite(maxAbs) && maxAbs > 0
                v(abs(v) > maxAbs) = NaN;
            end
        end

        function maxAbs = resolveAbsMaxValid(adapter, sensorType)
            maxAbs = [];
            if ~isstruct(adapter) || ~isfield(adapter, 'abs_max_valid')
                return;
            end
            raw = adapter.abs_max_valid;
            if isstruct(raw)
                sensorKey = char(string(sensorType));
                sensorField = matlab.lang.makeValidName(sensorKey);
                if ~isempty(sensorField) && isfield(raw, sensorField)
                    maxAbs = raw.(sensorField);
                    return;
                end
                if isfield(raw, 'default')
                    maxAbs = raw.default;
                end
                return;
            end
            maxAbs = raw;
        end

        function version = rawCacheVersion()
            version = 'hongtang_lowfreq_raw_v3';
        end

        function cfg = rawCacheConfig(adapter)
            cfg = struct();
            if ~isstruct(adapter)
                return;
            end
            fields = {'sheet', 'time_column', 'missing_tokens'};
            for i = 1:numel(fields)
                field = fields{i};
                if isfield(adapter, field)
                    cfg.(field) = adapter.(field);
                end
            end
        end

        function ok = canUseCache(cachePath, srcPath, adapter)
            ok = false;
            if ~exist(cachePath, 'file')
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
                ok = bms.data.CacheManager.metadataMatchesFull(cachePath, {srcPath}, ...
                    bms.data.HongtangLowFreqDataSource.rawCacheConfig(adapter), ...
                    bms.data.HongtangLowFreqDataSource.rawCacheVersion());
                return;
            end

            srcMtime = bms.data.HongtangLowFreqDataSource.fileMtime(srcPath);
            srcSize = bms.data.HongtangLowFreqDataSource.fileSize(srcPath);
            matMtime = bms.data.HongtangLowFreqDataSource.fileMtime(cachePath);
            if strcmpi(validateMode, 'mtime')
                ok = matMtime > srcMtime;
                return;
            end
            if strcmpi(validateMode, 'mtime_size')
                try
                    S = load(cachePath, 'meta');
                    if isfield(S, 'meta') && isstruct(S.meta) && ...
                            isfield(S.meta, 'mtime') && isfield(S.meta, 'size')
                        ok = (S.meta.mtime == srcMtime) && (S.meta.size == srcSize) ...
                            && isfield(S.meta, 'cache_version') ...
                            && strcmp(char(string(S.meta.cache_version)), ...
                                bms.data.HongtangLowFreqDataSource.rawCacheVersion());
                        return;
                    end
                catch
                    ok = false;
                end
            end
            ok = matMtime > srcMtime;
        end

        function s = sanitizeCacheName(s)
            if isstring(s), s = char(s); end
            if ~ischar(s), s = 'cache'; end
            s = regexprep(s, '[^\w\-]', '_');
        end

        function out = fileMtime(path)
            d = dir(path);
            if isempty(d)
                out = 0;
            else
                out = d(1).datenum;
            end
        end

        function out = fileSize(path)
            d = dir(path);
            if isempty(d)
                out = 0;
            else
                out = d(1).bytes;
            end
        end

        function out = getFieldDefault(s, field, default)
            if isstruct(s) && isfield(s, field)
                out = s.(field);
            else
                out = default;
            end
        end

        function tf = isAbsolutePath(path)
            tf = false;
            if isempty(path) || ~ischar(path)
                return;
            end
            if numel(path) >= 2 && path(2) == ':'
                tf = true;
            elseif startsWith(path, filesep)
                tf = true;
            end
        end
    end
end
