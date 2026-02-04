function [times, vals, meta] = load_timeseries_range(root_dir, subfolder, point_id, start_date, end_date, cfg, sensor_type)
%LOAD_TIMESERIES_RANGE Load and clean time series over a date range using config rules.
%   [times, vals, meta] = load_timeseries_range(root_dir, subfolder, point_id, ...
%       start_date, end_date, cfg, sensor_type)
%
%   root_dir   : root folder containing YYYY-MM-DD subfolders
%   subfolder  : subfolder under each date that holds CSV files
%   point_id   : point ID pattern to match in file names
%   start_date : string 'yyyy-MM-dd'
%   end_date   : string 'yyyy-MM-dd'
%   cfg        : configuration struct from load_config
%   sensor_type: 'deflection','acceleration','strain','tilt','crack', etc.
%
%   Returns times (datetime), vals (double), meta struct:
%     meta.files : cell array of file paths loaded
%     meta.applied_rules : struct of cleaning rules applied

    if nargin < 7 || isempty(sensor_type)
        sensor_type = 'generic';
    end
    if nargin < 6 || isempty(cfg)
        cfg = load_config();
    end

    meta = struct();
    meta.files = {};

    date_list = build_date_list(start_date, end_date);
    range = struct( ...
        'start', datetime(start_date, 'InputFormat','yyyy-MM-dd'), ...
        'end',   datetime(end_date,   'InputFormat','yyyy-MM-dd') + days(1));
    all_t = [];
    all_v = [];

    loader = get_vendor_loader(cfg);

    rules = build_rules(cfg, sensor_type, point_id);
    meta.applied_rules = rules;

    for i = 1:numel(date_list)
        day = date_list{i};
        day_meta = struct('day', day, 'range', range);
        if isfield(loader, 'get_day_dir')
            [dirp, day_meta] = loader.get_day_dir(root_dir, day, subfolder, sensor_type, day_meta);
            if isempty(dirp), continue; end
        else
            dirp = fullfile(root_dir, day, subfolder);
            if ~exist(dirp, 'dir'), continue; end
        end

        fp = loader.find_file(dirp, point_id, sensor_type, day, day_meta);
        if isempty(fp), continue; end

        [t, v] = loader.read_file(fp, sensor_type, point_id, day, day_meta);
        if isempty(v), continue; end
        meta.files{end+1} = fp; %#ok<AGROW>
        all_t = [all_t; t]; %#ok<AGROW>
        all_v = [all_v; v]; %#ok<AGROW>
    end

    if isempty(all_t)
        times = []; vals = [];
        return;
    end

    [times, order] = sort(all_t);
    vals = all_v(order);

    % === cleaning pipeline ===
    % 1) 阈值过滤：超出 min/max 置 NaN。
    % 2) 零值过滤：zero_to_nan=true 时，值为 0 置 NaN（适合部分传感器“掉线写 0”场景）。
    % 3) 滑窗异常值：以窗口 w 点的 movmedian 为基准，isoutlier 判断，超出则置 NaN。
    %    例：fs=20 Hz，outlier_window_sec=10，则 w=round(20*10)=200 点。
    %    假设某段 vals=[1 1 1 10 1 1 1 ...]，movmedian≈1，若 threshold_factor=3，
    %    则 10 会被判为异常置 NaN，其余保留。
    vals = apply_thresholds(vals, times, rules.thresholds);
    if rules.zero_to_nan
        vals(vals == 0) = NaN;
    end
    if ~isempty(rules.outlier_window_sec) && ~isempty(rules.outlier_threshold_factor) && numel(times) >= 2
        fs = 1/median(seconds(diff(times)));          % 估计采样率 (Hz)
        w = max(1, round(fs * rules.outlier_window_sec)); % 窗口点数
        mask = isoutlier(vals, 'movmedian', w, ...
            'ThresholdFactor', rules.outlier_threshold_factor);
        vals(mask) = NaN;
    end
end

% -------------------------------------------------------------------------
function loader = get_vendor_loader(cfg)
    vendor = 'default';
    if isfield(cfg,'vendor') && ~isempty(cfg.vendor)
        vendor = lower(string(cfg.vendor));
    end
    switch vendor
        case {'donghua'}
            loader = make_donghua_loader(cfg);
        case {'jiulongjiang','jiulong'}
            loader = make_jiulongjiang_loader(cfg);
        otherwise
            loader = make_donghua_loader(cfg); % fallback
    end
end

function loader = make_donghua_loader(cfg)
    loader.find_file = @(dirp, point_id, sensor_type, varargin) find_file_for_point(dirp, point_id, cfg, sensor_type);
    loader.read_file = @(fp, sensor_type, varargin) load_single_file(fp, cfg.defaults.header_marker); %#ok<NASGU>
end

function loader = make_jiulongjiang_loader(cfg)
    adapter = get_jlj_adapter(cfg);
    loader.get_day_dir = @(root_dir, day, subfolder, sensor_type, meta) jlj_get_day_dir(root_dir, day, adapter, meta);
    loader.find_file = @(dirp, point_id, sensor_type, varargin) jlj_find_file(dirp, point_id);
    loader.read_file = @(fp, sensor_type, point_id, varargin) jlj_read_file(fp, sensor_type, point_id, adapter, varargin{:});
end

% -------------------------------------------------------------------------
function fp = find_file_for_point(dirp, point_id, cfg, sensor_type)
    fp = '';
    patterns = {};
    safe_id = strrep(point_id, '-', '_');
    file_id = get_file_id(cfg, sensor_type, safe_id, point_id);
    if isfield(cfg, 'file_patterns') && isfield(cfg.file_patterns, sensor_type)
        ft = cfg.file_patterns.(sensor_type);
        if isfield(ft, 'default')
            patterns = [patterns; normalize_patterns(ft.default)];
        end
        if isfield(ft, 'per_point') && isfield(ft.per_point, safe_id)
            pt_pat = ft.per_point.(safe_id);
            patterns = [normalize_patterns(pt_pat); patterns]; % point-specific takes priority
        end
    end

    for k = 1:numel(patterns)
        pat = patterns{k};
        pat = strrep(pat, '{point}', point_id);
        pat = strrep(pat, '{file_id}', file_id);
        matches = dir(fullfile(dirp, pat));
        if ~isempty(matches)
            fp = fullfile(matches(1).folder, matches(1).name);
            return;
        end
    end

    % fallback to contains (legacy)
    files = dir(fullfile(dirp, '*.csv'));
    idx = find(arrayfun(@(f) contains(f.name, file_id), files), 1);
    if isempty(idx)
        idx = find(arrayfun(@(f) contains(f.name, point_id), files), 1);
    end
    if ~isempty(idx)
        fp = fullfile(files(idx).folder, files(idx).name);
    end
end

% Normalize pattern input to a cell array of pattern strings
function pats = normalize_patterns(p)
    if isstring(p)
        pats = cellstr(p(:));
    elseif ischar(p)
        pats = {p};
    elseif iscell(p)
        pats = cellstr(p(:));
    else
        pats = {};
    end
end

% -------------------------------------------------------------------------
function rules = build_rules(cfg, sensor_type, point_id)
    rules = struct('thresholds', [], 'zero_to_nan', false, ...
                   'outlier_window_sec', [], 'outlier_threshold_factor', []);
    if isfield(cfg, 'defaults') && isfield(cfg.defaults, sensor_type)
        def = cfg.defaults.(sensor_type);
        if isfield(def, 'thresholds'), rules.thresholds = def.thresholds; end
        if isfield(def, 'zero_to_nan'), rules.zero_to_nan = logical(def.zero_to_nan); end
        if isfield(def, 'outlier') && isstruct(def.outlier)
            if isfield(def.outlier, 'window_sec'), rules.outlier_window_sec = def.outlier.window_sec; end
            if isfield(def.outlier, 'threshold_factor'), rules.outlier_threshold_factor = def.outlier.threshold_factor; end
        end
    end
    safe_id = strrep(point_id, '-', '_');
    if isfield(cfg, 'per_point') && isfield(cfg.per_point, sensor_type) ...
            && isfield(cfg.per_point.(sensor_type), safe_id)
        pt = cfg.per_point.(sensor_type).(safe_id);
        rules = apply_point_rules(rules, pt);
    end

    % Wind mapping lives under per_point.wind; allow shared cleaning rules.
    if strncmp(sensor_type, 'wind_', 5) && isfield(cfg, 'per_point') ...
            && isfield(cfg.per_point, 'wind') && isfield(cfg.per_point.wind, safe_id)
        pt = cfg.per_point.wind.(safe_id);
        rules = apply_point_rules(rules, pt);
    end
end

function rules = apply_point_rules(rules, pt)
    if isfield(pt, 'thresholds') && ~isempty(pt.thresholds)
        % Execute defaults then point thresholds; normalize to column vectors.
        if isempty(rules.thresholds)
            rules.thresholds = pt.thresholds;
        else
            rules.thresholds = [rules.thresholds(:); pt.thresholds(:)];
        end
    end
    if isfield(pt, 'zero_to_nan')
        rules.zero_to_nan = logical(pt.zero_to_nan);
    end
    if isfield(pt, 'outlier') && isstruct(pt.outlier)
        if isfield(pt.outlier, 'window_sec'), rules.outlier_window_sec = pt.outlier.window_sec; end
        if isfield(pt.outlier, 'threshold_factor'), rules.outlier_threshold_factor = pt.outlier.threshold_factor; end
    end
end

function file_id = get_file_id(cfg, sensor_type, safe_id, point_id)
    file_id = point_id;
    if ~isfield(cfg, 'per_point')
        return;
    end

    if strncmp(sensor_type, 'wind_', 5) && isfield(cfg.per_point, 'wind') ...
            && isfield(cfg.per_point.wind, safe_id)
        pt = cfg.per_point.wind.(safe_id);
        key = '';
        if strcmp(sensor_type, 'wind_speed')
            key = 'speed_point_id';
        elseif strcmp(sensor_type, 'wind_direction')
            key = 'dir_point_id';
        end
        if ~isempty(key) && isfield(pt, key) && ~isempty(pt.(key))
            alias = pt.(key);
            if isstring(alias)
                alias = char(alias);
            end
            if ischar(alias)
                file_id = alias;
            end
        end
        return;
    end

    if strncmp(sensor_type, 'eq_', 3) && isfield(cfg.per_point, 'eq') ...
            && isfield(cfg.per_point.eq, safe_id)
        pt = cfg.per_point.eq.(safe_id);
        if isfield(pt, 'file_id') && ~isempty(pt.file_id)
            alias = pt.file_id;
            if isstring(alias)
                alias = char(alias);
            end
            if ischar(alias)
                file_id = alias;
            end
        end
        return;
    end
end

% -------------------------------------------------------------------------
function [times, vals] = load_single_file(fp, header_marker)
    if nargin < 2 || isempty(header_marker)
        header_marker = '[绝对时间]';
    end

    if ~isfile(fp)
        times = []; vals = [];
        return;
    end

    % detect header lines (marker or first parsable data line)
    fid = fopen(fp, 'rt');
    h = 0;
    found = false;
    buf = {};
    while h < 200 && ~feof(fid)
        ln = fgetl(fid); h = h + 1;
        buf{end+1} = ln; %#ok<AGROW>
        if contains(ln, header_marker)
            found = true;
            break;
        end
    end
    fclose(fid);
    if ~found
        % find first line like "yyyy-mm-dd HH:MM:SS[.fff],"
        pat = '^\s*\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(\.\d+)?\s*,';
        idx = find(~cellfun(@isempty, regexp(buf, pat, 'once')), 1);
        if ~isempty(idx)
            h = idx - 1;
        else
            h = 0;
        end
    end

    cacheDir = fullfile(fileparts(fp), 'cache');
    if ~exist(cacheDir, 'dir'), mkdir(cacheDir); end
    [~, name, ~] = fileparts(fp);
    cacheFile = fullfile(cacheDir, [name '.mat']);

    useCache = false;
    if exist(cacheFile, 'file')
        infoCSV = dir(fp);
        infoMAT = dir(cacheFile);
        if datenum(infoMAT.date) > datenum(infoCSV.date)
            try
                tmp = load(cacheFile, 'times', 'vals');
                times = tmp.times;
                vals = tmp.vals;
                useCache = true;
            catch
                useCache = false;
            end
        end
    end

    if ~useCache
        [times, vals, ok] = read_with_fallback(fp, h);
        if ~ok
            times = []; vals = [];
            return;
        end
        save(cacheFile, 'times', 'vals');
    end
end

% -------------------------------------------------------------------------
function [times, vals, ok] = read_with_fallback(fp, header_lines)
    times = []; vals = []; ok = false;
    fmts = { ...
        '%{yyyy-MM-dd HH:mm:ss.SSS}D%f', ...
        '%{yyyy-MM-dd HH:mm:ss}D%f' ...
        };
    % try auto-detect first (MATLAB will use BOM/default), then UTF-8, then UTF-16LE
    encs = {'auto','UTF-8','UTF-16LE'};

    % 1) readtable 尝试多编码、多格式
    for ei = 1:numel(encs)
        enc = encs{ei};
        for fi = 1:numel(fmts)
            fmt = fmts{fi};
            try
                T = readtable(fp, ...
                    'Delimiter', ',', ...
                    'HeaderLines', header_lines, ...
                    'ReadVariableNames', false, ...
                    'FileEncoding', enc, ...
                    'Format', fmt);
                if size(T,2) < 2, continue; end
                times = T{:,1};
                vals  = T{:,2};
                ok = true;
                return;
            catch
                % try next
            end
        end
    end

    % 2) textscan 兼容旧版本/特殊编码
    for ei = 1:numel(encs)
        enc = encs{ei};
        try
            fid = fopen(fp,'r','n',enc);
            if fid==-1, continue; end
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
            for k = 1:header_lines
                if feof(fid), break; end
                fgetl(fid);
            end
            C = textscan(fid,'%s %f','Delimiter',',','CollectOutput',true);
            if isempty(C) || numel(C)<2, continue; end
            times = datetime(C{1}, 'InputFormat','yyyy-MM-dd HH:mm:ss.SSS');
            vals  = C{2};
            if numel(times) == numel(vals)
                ok = true;
                return;
            end
        catch
            % continue
        end
    end
end

% -------------------------------------------------------------------------
function vals = apply_thresholds(vals, times, thresholds)
    if isempty(thresholds), return; end
    for k = 1:numel(thresholds)
        th = thresholds(k);
        tmask = true(size(vals));
        if isfield(th, 't_range_start') && isfield(th, 't_range_end') ...
                && ~isempty(th.t_range_start) && ~isempty(th.t_range_end)
            t0 = datetime(th.t_range_start, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
            t1 = datetime(th.t_range_end,   'InputFormat', 'yyyy-MM-dd HH:mm:ss');
            tmask = (times >= t0) & (times <= t1);
        end
        if isfield(th, 'min') && ~isempty(th.min)
            vals(tmask & vals < th.min) = NaN;
        end
        if isfield(th, 'max') && ~isempty(th.max)
            vals(tmask & vals > th.max) = NaN;
        end
    end
end

% -------------------------------------------------------------------------
function list = build_date_list(start_date, end_date)
    dn0 = datenum(start_date, 'yyyy-mm-dd');
    dn1 = datenum(end_date,   'yyyy-mm-dd');
    dnums = dn0:dn1;
    list = cell(numel(dnums),1);
    for i = 1:numel(dnums)
        list{i} = datestr(dnums(i), 'yyyy-mm-dd');
    end
end

% -------------------------------------------------------------------------
% Jiulongjiang adapter helpers
function adapter = get_jlj_adapter(cfg)
    adapter = struct();
    if isfield(cfg, 'data_adapter') && isstruct(cfg.data_adapter)
        adapter = cfg.data_adapter;
    end
    if ~isfield(adapter, 'zip') || ~isstruct(adapter.zip)
        adapter.zip = struct();
    end
    if ~isfield(adapter, 'csv') || ~isstruct(adapter.csv)
        adapter.csv = struct();
    end
    adapter.zip.glob = get_field_default(adapter.zip, 'glob', 'jljData*.zip');
    adapter.zip.date_pattern = get_field_default(adapter.zip, 'date_pattern', 'jljData(\\d{8})-(\\d{8})');
    adapter.zip.subdir = get_field_default(adapter.zip, 'subdir', fullfile('data','csv'));
    adapter.zip.staging_root = get_field_default(adapter.zip, 'staging_root', fullfile('outputs','_staging','jlj'));
    adapter.csv.encoding = get_field_default(adapter.csv, 'encoding', 'UTF-8');
    adapter.csv.delimiter = get_field_default(adapter.csv, 'delimiter', ',');
    adapter.csv.time_column = get_field_default(adapter.csv, 'time_column', 'ts');
    adapter.csv.time_format = get_field_default(adapter.csv, 'time_format', 'yyyy-MM-dd HH:mm:ss.SSS');
    adapter.csv.strip_quotes = get_field_default(adapter.csv, 'strip_quotes', true);
    if ~isfield(adapter, 'cache') || ~isstruct(adapter.cache)
        adapter.cache = struct();
    end
    adapter.cache.enabled = get_field_default(adapter.cache, 'enabled', true);
    adapter.cache.dir = get_field_default(adapter.cache, 'dir', 'cache');
    adapter.cache.validate = get_field_default(adapter.cache, 'validate', 'mtime_size');
end

function [dirp, meta] = jlj_get_day_dir(root_dir, day, adapter, meta)
    dirp = '';
    if nargin < 4 || isempty(meta)
        meta = struct();
    end
    if isempty(root_dir) || ~exist(root_dir, 'dir')
        return;
    end
    dt = datetime(day, 'InputFormat','yyyy-MM-dd');
    start_str = datestr(dt, 'yyyymmdd');
    end_str = datestr(dt + days(1), 'yyyymmdd');
    folder_name = sprintf('jljData%s-%s', start_str, end_str);
    direct_folder = fullfile(root_dir, folder_name, adapter.zip.subdir);
    if exist(direct_folder, 'dir')
        dirp = direct_folder;
        meta.cache_dir = resolve_jlj_cache_dir(direct_folder, adapter);
        return;
    end
    zip_path = fullfile(root_dir, [folder_name '.zip']);
    if ~exist(zip_path, 'file')
        zip_path = find_jlj_zip(root_dir, start_str, adapter.zip);
    end
    if isempty(zip_path)
        return;
    end
    staging_root = resolve_jlj_path(adapter.zip.staging_root);
    if ~exist(staging_root, 'dir'), mkdir(staging_root); end
    [~, base, ~] = fileparts(zip_path);
    dest = fullfile(staging_root, base);
    if ~exist(fullfile(dest, adapter.zip.subdir), 'dir')
        if ~exist(dest, 'dir'), mkdir(dest); end
        unzip(zip_path, dest);
    end
    dirp = fullfile(dest, adapter.zip.subdir);
    meta.cache_dir = resolve_jlj_cache_dir(dirp, adapter);
end

function zip_path = find_jlj_zip(root_dir, start_str, zip_cfg)
    zip_path = '';
    files = dir(fullfile(root_dir, zip_cfg.glob));
    if isempty(files)
        return;
    end
    pat = zip_cfg.date_pattern;
    for i = 1:numel(files)
        name = files(i).name;
        tokens = regexp(name, pat, 'tokens', 'once');
        if isempty(tokens)
            continue;
        end
        if numel(tokens) >= 1 && strcmp(tokens{1}, start_str)
            zip_path = fullfile(files(i).folder, name);
            return;
        end
    end
end

function fp = jlj_find_file(dirp, point_id)
    fp = '';
    if isempty(dirp) || ~exist(dirp, 'dir')
        return;
    end
    base = regexprep(point_id, '[-_][XYZ]$', '');
    cand = fullfile(dirp, [base '.csv']);
    if exist(cand, 'file')
        fp = cand;
        return;
    end
    files = dir(fullfile(dirp, '*.csv'));
    idx = find(arrayfun(@(f) contains(f.name, base), files), 1);
    if ~isempty(idx)
        fp = fullfile(files(idx).folder, files(idx).name);
    end
end

function [t, v] = jlj_read_file(fp, sensor_type, point_id, adapter, varargin)
    t = []; v = [];
    if isempty(fp) || ~exist(fp, 'file')
        return;
    end
    enc = adapter.csv.encoding;
    delim = adapter.csv.delimiter;
    cache_dir = resolve_cache_dir_from_meta(adapter, varargin{:});
    cache_path = '';
    if adapter.cache.enabled && ~isempty(cache_dir)
        if ~exist(cache_dir, 'dir'), mkdir(cache_dir); end
        [~, base, ~] = fileparts(fp);
        cache_path = fullfile(cache_dir, [base '.mat']);
    end

    if ~isempty(cache_path) && use_jlj_cache(cache_path, fp, adapter.cache.validate)
        S = load(cache_path, 'ts', 'valx', 'valy', 'valz', 'meta');
        [t, v] = pick_cached_channel(S, sensor_type, point_id);
    else
        T = readtable(fp, 'Delimiter', delim, 'FileEncoding', enc, ...
            'TextType','string', 'VariableNamingRule','preserve');
        vars = T.Properties.VariableNames;
        tcol = pick_var(vars, adapter.csv.time_column);
        if isempty(tcol)
            return;
        end
        ts = string(T.(tcol));
        if adapter.csv.strip_quotes
            ts = strrep(ts, '"', '');
        end
        ts = strtrim(ts);
        t = parse_jlj_time(ts, adapter.csv.time_format);
        valx = extract_numeric_column(T, vars, 'value_x');
        valy = extract_numeric_column(T, vars, 'value_y');
        valz = extract_numeric_column(T, vars, 'value_z');
        if ~isempty(cache_path)
            meta = struct('src', fp, 'mtime', file_mtime(fp), 'size', file_size(fp));
            ts = t; %#ok<NASGU>
            save(cache_path, 'ts', 'valx', 'valy', 'valz', 'meta');
        end
        [t, v] = pick_channel_from_arrays(t, valx, valy, valz, sensor_type, point_id);
    end
    range = extract_range(varargin{:});
    if ~isempty(range) && isfield(range, 'start') && isfield(range, 'end')
        mask = t >= range.start & t < range.end;
        t = t(mask);
        v = v(mask);
    end
end

function cache_dir = resolve_jlj_cache_dir(csv_dir, adapter)
    cache_dir = '';
    if ~adapter.cache.enabled
        return;
    end
    base = adapter.cache.dir;
    if isempty(base)
        return;
    end
    if isabsolute(base)
        cache_dir = base;
    else
        cache_dir = fullfile(csv_dir, base);
    end
end

function cache_dir = resolve_cache_dir_from_meta(adapter, varargin)
    cache_dir = '';
    for i = 1:numel(varargin)
        if isstruct(varargin{i}) && isfield(varargin{i}, 'cache_dir')
            cache_dir = varargin{i}.cache_dir;
            return;
        end
    end
end

function ok = use_jlj_cache(cache_path, src_path, validate_mode)
    ok = false;
    if isempty(cache_path) || ~exist(cache_path, 'file')
        return;
    end
    if strcmpi(validate_mode, 'none')
        ok = true;
        return;
    end
    try
        S = load(cache_path, 'meta');
        if ~isfield(S, 'meta') || ~isstruct(S.meta)
            return;
        end
        mtime = file_mtime(src_path);
        fsize = file_size(src_path);
        ok = isfield(S.meta,'mtime') && isfield(S.meta,'size') && ...
            S.meta.mtime == mtime && S.meta.size == fsize;
    catch
        ok = false;
    end
end

function [t, v] = pick_cached_channel(S, sensor_type, point_id)
    if isfield(S, 'ts')
        t = S.ts;
    else
        t = [];
    end
    valx = get_field_default(S, 'valx', []);
    valy = get_field_default(S, 'valy', []);
    valz = get_field_default(S, 'valz', []);
    [t, v] = pick_channel_from_arrays(t, valx, valy, valz, sensor_type, point_id);
end

function [t, v] = pick_channel_from_arrays(t, valx, valy, valz, sensor_type, point_id)
    col = resolve_jlj_value_column(sensor_type, point_id);
    switch lower(col)
        case 'value_y'
            v = valy;
        case 'value_z'
            v = valz;
        otherwise
            v = valx;
    end
end

function vec = extract_numeric_column(T, vars, name)
    vec = [];
    vcol = pick_var(vars, name);
    if isempty(vcol)
        return;
    end
    v = T.(vcol);
    if isstring(v) || iscellstr(v)
        vec = str2double(string(v));
    else
        vec = double(v);
    end
end

function out = file_mtime(fp)
    d = dir(fp);
    if isempty(d)
        out = 0;
    else
        out = d(1).datenum;
    end
end

function out = file_size(fp)
    d = dir(fp);
    if isempty(d)
        out = 0;
    else
        out = d(1).bytes;
    end
end

function col = resolve_jlj_value_column(sensor_type, point_id)
    col = 'value_x';
    st = lower(string(sensor_type));
    if st == "wind_direction"
        col = 'value_y';
    elseif st == "humidity"
        col = 'value_y';
    elseif st == "wind_speed"
        col = 'value_x';
    elseif st == "temperature"
        col = 'value_x';
    elseif st == "tilt"
        if contains(point_id, '-Y') || contains(point_id, '_Y')
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
    else
        col = 'value_x';
    end
end

function t = parse_jlj_time(ts, fmt)
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

function v = pick_var(vars, name)
    v = '';
    idx = find(strcmpi(vars, name), 1);
    if ~isempty(idx)
        v = vars{idx};
    end
end

function range = extract_range(varargin)
    range = [];
    for i = 1:numel(varargin)
        if isstruct(varargin{i}) && isfield(varargin{i}, 'range')
            range = varargin{i}.range;
            return;
        end
    end
end

function out = get_field_default(s, field, default)
    if isstruct(s) && isfield(s, field)
        out = s.(field);
    else
        out = default;
    end
end

function p = resolve_jlj_path(p)
    if isempty(p), return; end
    if isstring(p), p = char(p); end
    if ischar(p) && ~isabsolute(p)
        proj_root = fileparts(fileparts(mfilename('fullpath')));
        p = fullfile(proj_root, p);
    end
end

function tf = isabsolute(p)
    tf = false;
    if isempty(p) || ~ischar(p)
        return;
    end
    if numel(p) >= 2 && p(2) == ':'
        tf = true;
    elseif startsWith(p, filesep)
        tf = true;
    end
end
