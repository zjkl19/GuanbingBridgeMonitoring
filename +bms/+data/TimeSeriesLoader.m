classdef TimeSeriesLoader
    %TIMESERIESLOADER Shared CSV time-series loading helper.

    methods (Static)
        function T = readCsv(path)
            if nargin < 1 || isempty(path) || ~isfile(path)
                error('TimeSeriesLoader:InputMissing', 'CSV file not found: %s', char(path));
            end
            opts = detectImportOptions(path, 'VariableNamingRule', 'preserve');
            T = readtable(path, opts);
        end

        function name = detectTimeColumn(T)
            name = '';
            if ~istable(T) || isempty(T.Properties.VariableNames)
                return;
            end
            names = T.Properties.VariableNames;
            preferred = {'time','Time','timestamp','Timestamp','datetime','DateTime','date_time','日期','时间'};
            for i = 1:numel(preferred)
                idx = find(strcmpi(names, preferred{i}), 1);
                if ~isempty(idx)
                    name = names{idx};
                    return;
                end
            end
            for i = 1:numel(names)
                col = T.(names{i});
                if isdatetime(col) || isduration(col)
                    name = names{i};
                    return;
                end
            end
        end

        function name = detectValueColumn(T, preferredNames)
            if nargin < 2
                preferredNames = {};
            end
            name = '';
            if ~istable(T), return; end
            names = T.Properties.VariableNames;
            if ischar(preferredNames) || isstring(preferredNames)
                preferredNames = cellstr(string(preferredNames));
            end
            for i = 1:numel(preferredNames)
                idx = find(strcmpi(names, preferredNames{i}), 1);
                if ~isempty(idx) && isnumeric(T.(names{idx}))
                    name = names{idx};
                    return;
                end
            end
            timeName = bms.data.TimeSeriesLoader.detectTimeColumn(T);
            for i = 1:numel(names)
                if strcmp(names{i}, timeName), continue; end
                if isnumeric(T.(names{i}))
                    name = names{i};
                    return;
                end
            end
        end

        function [t, v] = columns(T, preferredValueNames)
            if nargin < 2, preferredValueNames = {}; end
            timeName = bms.data.TimeSeriesLoader.detectTimeColumn(T);
            valueName = bms.data.TimeSeriesLoader.detectValueColumn(T, preferredValueNames);
            if isempty(timeName) || isempty(valueName)
                error('TimeSeriesLoader:ColumnMissing', 'Cannot detect time/value columns.');
            end
            t = T.(timeName);
            v = T.(valueName);
            if ~isdatetime(t)
                t = bms.data.TimeSeriesLoader.toDatetime(t);
            end
        end

        function names = detectNumericColumns(T, excludeNames)
            if nargin < 2, excludeNames = {}; end
            if ischar(excludeNames) || isstring(excludeNames)
                excludeNames = cellstr(string(excludeNames));
            end
            names = {};
            if ~istable(T), return; end
            vars = T.Properties.VariableNames;
            for i = 1:numel(vars)
                if ismember(vars{i}, excludeNames), continue; end
                if isnumeric(T.(vars{i}))
                    names{end+1} = vars{i}; %#ok<AGROW>
                end
            end
        end

        function series = readSeries(path, preferredValueNames, startDate, endDate)
            if nargin < 2, preferredValueNames = {}; end
            T = bms.data.TimeSeriesLoader.readCsv(path);
            [t, v] = bms.data.TimeSeriesLoader.columns(T, preferredValueNames);
            if nargin >= 4 && ~isempty(startDate) && ~isempty(endDate)
                [t, v] = bms.data.TimeSeriesLoader.clip(t, v, startDate, endDate);
            end
            series = struct();
            series.path = char(string(path));
            series.time = t;
            series.value = v;
            series.time_column = bms.data.TimeSeriesLoader.detectTimeColumn(T);
            series.value_column = bms.data.TimeSeriesLoader.detectValueColumn(T, preferredValueNames);
            series.sample_count = numel(v);
            series.valid_count = sum(~isnan(v));
        end

        function [times, vals, meta] = readCachedCsvSeries(path, headerMarker, opts)
            %READCACHEDCSVSERIES Load a two-column CSV series with local MAT cache.
            if nargin < 2 || isempty(headerMarker)
                headerMarker = '[绝对时间]';
            end
            if nargin < 3 || isempty(opts), opts = struct(); end

            times = [];
            vals = [];
            meta = struct('path', char(string(path)), 'cache_path', '', ...
                'header_lines', 0, 'cache_hit', false, 'read_ok', false);
            if nargin < 1 || isempty(path) || ~isfile(path)
                return;
            end

            cacheDir = bms.data.TimeSeriesLoader.optionValue(opts, 'cache_dir', ...
                bms.data.CacheManager.cacheDir(fileparts(char(path))));
            if ~exist(cacheDir, 'dir'), mkdir(cacheDir); end
            [~, name, ~] = fileparts(char(path));
            cacheFile = fullfile(cacheDir, [name '.mat']);
            meta.cache_path = cacheFile;
            cacheVersion = char(string(bms.data.TimeSeriesLoader.optionValue(opts, 'cache_version', 'csv_timeseries_v2')));

            if bms.data.TimeSeriesLoader.canUseSeriesCache(cacheFile, path, cacheVersion)
                try
                    tmp = load(cacheFile, 'times', 'vals');
                    if isfield(tmp, 'times') && isfield(tmp, 'vals')
                        times = tmp.times;
                        vals = tmp.vals;
                        meta.cache_hit = true;
                        meta.read_ok = true;
                        return;
                    end
                catch
                end
            end

            headerLines = bms.data.TimeSeriesLoader.detectHeaderLines(path, headerMarker);
            meta.header_lines = headerLines;
            [times, vals, ok] = bms.data.TimeSeriesLoader.readCsvSeriesWithFallback(path, headerLines);
            if ~ok
                times = [];
                vals = [];
                return;
            end
            meta.read_ok = true;
            try
                save(cacheFile, 'times', 'vals');
                bms.data.CacheManager.writeMetadata(cacheFile, {path}, struct(), cacheVersion);
            catch
            end
        end

        function fp = findCsvForPoint(dirp, pointId, cfg, sensorType)
            %FINDCSVFORPOINT Resolve a configured point ID to a CSV file path.
            fp = '';
            if nargin < 4 || isempty(sensorType)
                sensorType = 'generic';
            end
            if isempty(dirp) || ~exist(dirp, 'dir')
                return;
            end
            if nargin < 3 || isempty(cfg)
                cfg = struct();
            end

            sensorType = char(string(sensorType));
            pointId = char(string(pointId));
            fileId = bms.data.TimeSeriesLoader.resolveFileId(cfg, sensorType, pointId);
            patterns = {};
            regexes = {};
            if isstruct(cfg) && isfield(cfg, 'file_patterns') && isstruct(cfg.file_patterns) ...
                    && isfield(cfg.file_patterns, sensorType)
                ft = cfg.file_patterns.(sensorType);
                if isstruct(ft) && isfield(ft, 'default')
                    patterns = [patterns; bms.data.TimeSeriesLoader.normalizePatterns(ft.default)]; %#ok<AGROW>
                end
                if isstruct(ft) && isfield(ft, 'regex')
                    regexes = [regexes; bms.data.TimeSeriesLoader.normalizePatterns(ft.regex)]; %#ok<AGROW>
                end
                if isstruct(ft) && isfield(ft, 'per_point') && isstruct(ft.per_point)
                    [ok, pointPatterns] = bms.data.PointResolver.getPointConfig(ft.per_point, pointId, cfg);
                    if ok
                        patterns = [bms.data.TimeSeriesLoader.normalizePatterns(pointPatterns); patterns]; %#ok<AGROW>
                    end
                end
                if isstruct(ft) && isfield(ft, 'per_point_regex') && isstruct(ft.per_point_regex)
                    [ok, pointRegexes] = bms.data.PointResolver.getPointConfig(ft.per_point_regex, pointId, cfg);
                    if ok
                        regexes = [bms.data.TimeSeriesLoader.normalizePatterns(pointRegexes); regexes]; %#ok<AGROW>
                    end
                end
            end

            for k = 1:numel(patterns)
                pat = patterns{k};
                pat = strrep(pat, '{point}', pointId);
                pat = strrep(pat, '{file_id}', fileId);
                matches = dir(fullfile(dirp, pat));
                if ~isempty(matches)
                    fp = fullfile(matches(1).folder, matches(1).name);
                    return;
                end
                matches = bms.data.TimeSeriesLoader.findRecursiveMatches(dirp, pat);
                if ~isempty(matches)
                    fp = fullfile(matches(1).folder, matches(1).name);
                    return;
                end
            end

            for k = 1:numel(regexes)
                expr = regexes{k};
                expr = strrep(expr, '{point}', regexptranslate('escape', pointId));
                expr = strrep(expr, '{file_id}', regexptranslate('escape', fileId));
                matches = bms.data.TimeSeriesLoader.findRecursiveRegexMatches(dirp, expr);
                if ~isempty(matches)
                    fp = fullfile(matches(1).folder, matches(1).name);
                    return;
                end
            end

            files = dir(fullfile(dirp, '*.csv'));
            idx = find(arrayfun(@(f) contains(f.name, fileId), files), 1);
            if isempty(idx)
                idx = find(arrayfun(@(f) contains(f.name, pointId), files), 1);
            end
            if ~isempty(idx)
                fp = fullfile(files(idx).folder, files(idx).name);
                return;
            end

            files = bms.data.TimeSeriesLoader.findRecursiveMatches(dirp, '*.csv');
            idx = find(arrayfun(@(f) contains(f.name, fileId), files), 1);
            if isempty(idx)
                idx = find(arrayfun(@(f) contains(f.name, pointId), files), 1);
            end
            if ~isempty(idx)
                fp = fullfile(files(idx).folder, files(idx).name);
            end
        end

        function fileId = resolveFileId(cfg, sensorType, pointId)
            fileId = char(string(pointId));
            if nargin < 2 || isempty(sensorType)
                sensorType = 'generic';
            end
            sensorType = char(string(sensorType));
            if ~isstruct(cfg) || ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point)
                return;
            end

            if strncmp(sensorType, 'wind_', 5) && isfield(cfg.per_point, 'wind') ...
                    && isstruct(cfg.per_point.wind)
                [ok, pt] = bms.data.PointResolver.getPointConfig(cfg.per_point.wind, fileId, cfg);
                if ~ok
                    return;
                end
                key = '';
                if strcmp(sensorType, 'wind_speed')
                    key = 'speed_point_id';
                elseif strcmp(sensorType, 'wind_direction')
                    key = 'dir_point_id';
                end
                fileId = bms.data.TimeSeriesLoader.resolveAlias(pt, key, fileId);
                return;
            end

            if strncmp(sensorType, 'eq_', 3) && isfield(cfg.per_point, 'eq') ...
                    && isstruct(cfg.per_point.eq)
                [ok, pt] = bms.data.PointResolver.getPointConfig(cfg.per_point.eq, fileId, cfg);
                if ok
                    fileId = bms.data.TimeSeriesLoader.resolveAlias(pt, 'file_id', fileId);
                end
                return;
            end

            if isfield(cfg.per_point, sensorType) && isstruct(cfg.per_point.(sensorType))
                [ok, pt] = bms.data.PointResolver.getPointConfig(cfg.per_point.(sensorType), pointId, cfg);
                if ok
                    fileId = bms.data.TimeSeriesLoader.resolveAlias(pt, 'file_id', fileId);
                end
            end
        end

        function patterns = normalizePatterns(value)
            if isstring(value)
                patterns = cellstr(value(:));
            elseif ischar(value)
                patterns = {value};
            elseif iscell(value)
                patterns = cellstr(string(value(:)));
            else
                patterns = {};
            end
        end

        function value = resolveAlias(pointCfg, fieldName, fallback)
            value = fallback;
            if isempty(fieldName) || ~isstruct(pointCfg) || ~isfield(pointCfg, fieldName) || isempty(pointCfg.(fieldName))
                return;
            end
            alias = pointCfg.(fieldName);
            if isstring(alias), alias = char(alias); end
            if ischar(alias)
                value = alias;
            end
        end

        function matches = findRecursiveMatches(dirp, pattern)
            matches = [];
            if isempty(dirp) || ~exist(dirp, 'dir') || isempty(pattern)
                return;
            end
            matches = dir(fullfile(dirp, '**', char(string(pattern))));
            if ~isempty(matches)
                matches = matches(~[matches.isdir]);
            end
        end

        function matches = findRecursiveRegexMatches(dirp, expr)
            matches = [];
            if isempty(dirp) || ~exist(dirp, 'dir') || isempty(expr)
                return;
            end
            files = dir(fullfile(dirp, '**', '*.csv'));
            if isempty(files)
                return;
            end
            files = files(~[files.isdir]);
            keep = arrayfun(@(f) ~isempty(regexp(f.name, char(string(expr)), 'once')), files);
            matches = files(keep);
        end

        function headerLines = detectHeaderLines(path, headerMarker)
            headerLines = 0;
            if nargin < 2 || isempty(headerMarker)
                headerMarker = '[绝对时间]';
            end
            if nargin < 1 || isempty(path) || ~isfile(path)
                return;
            end

            encs = bms.data.TimeSeriesLoader.preferredEncodings(path);
            if strcmp(encs{1}, 'auto')
                fid = fopen(path, 'rt');
            else
                fid = fopen(path, 'rt', 'n', encs{1});
            end
            if fid < 0
                return;
            end
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
            found = false;
            buf = {};
            h = 0;
            while h < 200 && ~feof(fid)
                ln = fgetl(fid);
                h = h + 1;
                if ~(ischar(ln) || isstring(ln))
                    break;
                end
                ln = char(ln);
                buf{end+1} = ln; %#ok<AGROW>
                if contains(ln, headerMarker)
                    found = true;
                    break;
                end
            end
            if found
                headerLines = h;
                return;
            end

            pat = '^\s*\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(\.\d+)?\s*,';
            idx = find(~cellfun(@isempty, regexp(buf, pat, 'once')), 1);
            if ~isempty(idx)
                headerLines = idx - 1;
            end
        end

        function [times, vals, ok] = readCsvSeriesWithFallback(path, headerLines)
            times = [];
            vals = [];
            ok = false;
            if nargin < 2 || isempty(headerLines), headerLines = 0; end

            fmts = { ...
                '%{yyyy-MM-dd HH:mm:ss.SSS}D%f', ...
                '%{yyyy-MM-dd HH:mm:ss}D%f' ...
                };
            encs = bms.data.TimeSeriesLoader.preferredEncodings(path);

            for ei = 1:numel(encs)
                enc = encs{ei};
                [times, vals, ok] = bms.data.TimeSeriesLoader.readCsvSeriesWithTextscan(path, headerLines, enc);
                if ok
                    return;
                end
            end

            for ei = 1:numel(encs)
                enc = encs{ei};
                for fi = 1:numel(fmts)
                    fmt = fmts{fi};
                    try
                        T = readtable(path, ...
                            'Delimiter', ',', ...
                            'HeaderLines', headerLines, ...
                            'ReadVariableNames', false, ...
                            'FileEncoding', enc, ...
                            'Format', fmt);
                        if size(T, 2) < 2
                            continue;
                        end
                        times = T{:, 1};
                        vals = T{:, 2};
                        ok = true;
                        return;
                    catch
                    end
                end
            end

            for ei = 1:numel(encs)
                enc = encs{ei};
                try
                    fid = fopen(path, 'r', 'n', enc);
                    if fid == -1, continue; end
                    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
                    for k = 1:headerLines
                        if feof(fid), break; end
                        fgetl(fid);
                    end
                    C = textscan(fid, '%s %f', 'Delimiter', ',', 'CollectOutput', true);
                    if isempty(C) || numel(C) < 2
                        continue;
                    end
                    times = datetime(C{1}, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
                    vals = C{2};
                    if numel(times) == numel(vals)
                        ok = true;
                        return;
                    end
                catch
                end
            end
        end

        function [times, vals, ok] = readCsvSeriesWithTextscan(path, headerLines, enc)
            times = [];
            vals = [];
            ok = false;
            if nargin < 2 || isempty(headerLines), headerLines = 0; end
            if nargin < 3 || isempty(enc), enc = 'auto'; end

            try
                if strcmpi(char(enc), 'auto')
                    fid = fopen(path, 'rt');
                else
                    fid = fopen(path, 'rt', 'n', char(enc));
                end
                if fid == -1
                    return;
                end
                cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
                for k = 1:headerLines
                    if feof(fid), break; end
                    fgetl(fid);
                end
                C = textscan(fid, '%s%f', ...
                    'Delimiter', ',', ...
                    'CollectOutput', false, ...
                    'ReturnOnError', false);
                if isempty(C) || numel(C) < 2 || isempty(C{1}) || isempty(C{2})
                    return;
                end
                rawTimes = string(C{1});
                rawTimes = erase(rawTimes, char(65279));
                rawTimes = strtrim(rawTimes);
                vals = C{2};
                if numel(rawTimes) ~= numel(vals)
                    times = [];
                    vals = [];
                    return;
                end
                formats = {'yyyy-MM-dd HH:mm:ss.SSS', 'yyyy-MM-dd HH:mm:ss'};
                for fi = 1:numel(formats)
                    try
                        times = datetime(rawTimes, 'InputFormat', formats{fi});
                        if numel(times) == numel(vals)
                            ok = true;
                            return;
                        end
                    catch
                    end
                end
                times = [];
                vals = [];
            catch
                times = [];
                vals = [];
            end
        end

        function encs = preferredEncodings(path)
            encs = {'auto','UTF-8','UTF-16LE'};
            if nargin < 1 || isempty(path) || ~isfile(path)
                return;
            end
            fid = fopen(path, 'r');
            if fid < 0
                return;
            end
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
            bytes = fread(fid, 3, 'uint8=>uint8').';
            if numel(bytes) >= 2 && isequal(bytes(1:2), uint8([255 254]))
                encs = {'UTF-16LE'};
            elseif numel(bytes) >= 3 && isequal(bytes(1:3), uint8([239 187 191]))
                encs = {'UTF-8','auto'};
            end
        end

        function [t, v] = clipClosedRange(t, v, rangeStart, rangeEnd)
            if ~isdatetime(t)
                t = bms.data.TimeSeriesLoader.toDatetime(t);
            end
            if ~isdatetime(rangeStart), rangeStart = bms.data.TimeSeriesLoader.toDatetime(rangeStart); end
            if ~isdatetime(rangeEnd), rangeEnd = bms.data.TimeSeriesLoader.toDatetime(rangeEnd); end
            mask = t >= rangeStart & t <= rangeEnd;
            t = t(mask);
            v = v(mask);
        end

        function summary = summarize(t, v)
            if ~isdatetime(t)
                t = bms.data.TimeSeriesLoader.toDatetime(t);
            end
            summary = struct();
            summary.sample_count = numel(v);
            summary.nan_count = sum(isnan(v));
            summary.valid_count = sum(~isnan(v));
            summary.start_time = '';
            summary.end_time = '';
            summary.min_value = NaN;
            summary.max_value = NaN;
            summary.mean_value = NaN;
            if ~isempty(t)
                summary.start_time = datestr(min(t), 'yyyy-mm-dd HH:MM:ss');
                summary.end_time = datestr(max(t), 'yyyy-mm-dd HH:MM:ss');
            end
            if ~isempty(v)
                summary.min_value = min(v, [], 'omitnan');
                summary.max_value = max(v, [], 'omitnan');
                summary.mean_value = mean(v, 'omitnan');
            end
        end

        function [t, v] = clip(t, v, startDate, endDate)
            if ~isdatetime(t)
                t = bms.data.TimeSeriesLoader.toDatetime(t);
            end
            s = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
            e = datetime(endDate, 'InputFormat', 'yyyy-MM-dd') + days(1) - seconds(1);
            mask = t >= s & t <= e;
            t = t(mask);
            v = v(mask);
        end

        function t = toDatetime(raw)
            if isdatetime(raw)
                t = raw;
            elseif isnumeric(raw)
                t = datetime(raw, 'ConvertFrom', 'datenum');
            else
                txt = string(raw);
                try
                    t = datetime(txt, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
                catch
                    t = datetime(txt);
                end
            end
        end

        function ok = canUseSeriesCache(cacheFile, sourcePath, cacheVersion)
            ok = false;
            if isempty(cacheFile) || ~isfile(cacheFile)
                return;
            end
            if bms.data.CacheManager.metadataMatchesFull(cacheFile, {sourcePath}, struct(), cacheVersion)
                ok = true;
                return;
            end
            if isfile(sourcePath)
                cacheInfo = dir(cacheFile);
                sourceInfo = dir(sourcePath);
                ok = cacheInfo.datenum > sourceInfo.datenum;
            end
        end

        function value = optionValue(opts, field, defaultValue)
            value = defaultValue;
            if isstruct(opts) && isfield(opts, field) && ~isempty(opts.(field))
                value = opts.(field);
            end
        end
    end
end
