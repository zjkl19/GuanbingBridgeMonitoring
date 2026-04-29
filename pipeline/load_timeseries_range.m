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

    used_range_loader = false;
    if isfield(loader, 'read_range') && isa(loader.read_range, 'function_handle')
        [t, v, used, files] = loader.read_range(root_dir, subfolder, point_id, sensor_type, range);
        if used
            used_range_loader = true;
            if ~isempty(files)
                meta.files = files;
            end
            if ~isempty(v)
                all_t = [all_t; t]; %#ok<AGROW>
                all_v = [all_v; v]; %#ok<AGROW>
            end
        end
    end

    if ~used_range_loader
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
    end

    if isempty(all_t)
        times = []; vals = [];
        return;
    end

    [times, order] = sort(all_t);
    vals = all_v(order);

    if ~isempty(rules.offset_correction) && isnumeric(rules.offset_correction) ...
            && isscalar(rules.offset_correction) && isfinite(rules.offset_correction) ...
            && rules.offset_correction ~= 0
        vals = vals + rules.offset_correction;
        meta.applied_offset_correction = rules.offset_correction;
        try
            offset_correction_registry('record', struct( ...
                'sensor_type', sensor_type, ...
                'point_id', point_id, ...
                'offset_correction', rules.offset_correction, ...
                'start_time', min(times), ...
                'end_time', max(times), ...
                'sample_count', numel(vals), ...
                'files', {meta.files}));
        catch
        end
    else
        meta.applied_offset_correction = [];
    end

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
        case {'hongtang'}
            loader = make_hongtang_loader(cfg);
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

function loader = make_hongtang_loader(cfg)
    loader = make_donghua_loader(cfg);
    loader.read_range = @(root_dir, subfolder, point_id, sensor_type, range) ...
        hongtang_read_range(root_dir, subfolder, point_id, sensor_type, range, cfg);
end

function loader = make_jiulongjiang_loader(cfg)
    adapter = get_jlj_adapter(cfg);
    loader.get_day_dir = @(root_dir, day, subfolder, sensor_type, meta) jlj_get_day_dir(root_dir, day, adapter, meta);
    loader.find_file = @(dirp, point_id, sensor_type, varargin) jlj_find_file(dirp, point_id);
    loader.read_file = @(fp, sensor_type, point_id, varargin) jlj_read_file(fp, sensor_type, point_id, adapter, varargin{:});
end

function [t, v, used, files] = hongtang_read_range(root_dir, ~, point_id, sensor_type, range, cfg)
    t = [];
    v = [];
    used = false;
    files = {};

    adapter = get_hongtang_lowfreq_adapter(cfg);
    if ~hongtang_lowfreq_supports_sensor(adapter, sensor_type)
        return;
    end
    if ~adapter.enabled
        return;
    end

    xlsx_path = resolve_hongtang_lowfreq_file(root_dir, adapter.file);
    if isempty(xlsx_path) || ~exist(xlsx_path, 'file')
        return;
    end

    used = true;
    files = {xlsx_path};
    [t, v] = read_hongtang_lowfreq_series(xlsx_path, point_id, adapter);
    if isempty(t) || isempty(v)
        return;
    end

    if ~isempty(range) && isfield(range, 'start') && isfield(range, 'end')
        mask = t >= range.start & t < range.end;
        t = t(mask);
        v = v(mask);
    end
end

function adapter = get_hongtang_lowfreq_adapter(cfg)
    adapter = struct();
    if isfield(cfg, 'data_adapter') && isstruct(cfg.data_adapter)
        if isfield(cfg.data_adapter, 'hongtang_lowfreq') && isstruct(cfg.data_adapter.hongtang_lowfreq)
            adapter = cfg.data_adapter.hongtang_lowfreq;
        elseif isfield(cfg.data_adapter, 'lowfreq') && isstruct(cfg.data_adapter.lowfreq)
            adapter = cfg.data_adapter.lowfreq;
        end
    end

    adapter.enabled = get_field_default(adapter, 'enabled', false);
    adapter.file = get_field_default(adapter, 'file', fullfile('lowfreq', 'data.xlsx'));
    adapter.sheet = get_field_default(adapter, 'sheet', 'auto_first_non_empty');
    adapter.time_column = get_field_default(adapter, 'time_column', 'SamplingTime');
    adapter.sensor_types = get_field_default(adapter, 'sensor_types', {'bearing_displacement'});
    adapter.missing_tokens = get_field_default(adapter, 'missing_tokens', {'--', ''});
    adapter.abs_max_valid = get_field_default(adapter, 'abs_max_valid', 500);

    if ~isfield(adapter, 'cache') || ~isstruct(adapter.cache)
        adapter.cache = struct();
    end
    adapter.cache.enabled = get_field_default(adapter.cache, 'enabled', true);
    adapter.cache.dir = get_field_default(adapter.cache, 'dir', 'cache');
    adapter.cache.validate = get_field_default(adapter.cache, 'validate', 'mtime_size');
end

function tf = hongtang_lowfreq_supports_sensor(adapter, sensor_type)
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
    tf = any(strcmpi(types, sensor_type)) || any(strcmpi(types, 'all'));
end

function p = resolve_hongtang_lowfreq_file(root_dir, p)
    if isempty(p), return; end
    if isstring(p), p = char(p); end
    if ~ischar(p), p = ''; return; end
    if ~isabsolute(p)
        p = fullfile(root_dir, p);
    end
end

function [t, v] = read_hongtang_lowfreq_series(xlsx_path, point_id, adapter)
    t = [];
    v = [];

    cache_path = make_hongtang_cache_file(xlsx_path, point_id, adapter);
    if ~isempty(cache_path) && can_use_hongtang_cache(cache_path, xlsx_path, adapter.cache.validate)
        S = load(cache_path, 'times', 'vals');
        if isfield(S, 'times') && isfield(S, 'vals')
            t = S.times;
            v = S.vals;
            return;
        end
    end

    [T, time_col] = read_hongtang_lowfreq_table_cached(xlsx_path, adapter);
    if isempty(T) || isempty(time_col)
        return;
    end

    point_col = pick_column_case_sensitive(T.Properties.VariableNames, point_id);
    if isempty(point_col)
        return;
    end

    t = parse_hongtang_time(T.(time_col));
    v = to_hongtang_numeric(T.(point_col), adapter.missing_tokens);
    valid_t = ~isnat(t);
    t = t(valid_t);
    v = v(valid_t);

    max_abs = adapter.abs_max_valid;
    if isnumeric(max_abs) && isscalar(max_abs) && isfinite(max_abs) && max_abs > 0
        v(abs(v) > max_abs) = NaN;
    end

    if ~isempty(cache_path)
        times = t; %#ok<NASGU>
        vals = v; %#ok<NASGU>
        meta = struct('mtime', file_mtime(xlsx_path), 'size', file_size(xlsx_path)); %#ok<NASGU>
        save(cache_path, 'times', 'vals', 'meta');
    end
end

function [T, time_col] = read_hongtang_lowfreq_table_cached(xlsx_path, adapter)
    T = table();
    time_col = '';

    persistent wb_cache
    if isempty(wb_cache)
        wb_cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    end

    sheet = pick_hongtang_sheet(xlsx_path, adapter);
    if isempty(sheet)
        return;
    end

    key = sprintf('%s|%.12f|%d|%s', xlsx_path, file_mtime(xlsx_path), file_size(xlsx_path), sheet);
    if isKey(wb_cache, key)
        S = wb_cache(key);
        T = S.T;
        time_col = S.time_col;
        return;
    end

    T = readtable(xlsx_path, 'Sheet', sheet, 'VariableNamingRule', 'preserve', 'TextType', 'string');
    if isempty(T)
        return;
    end

    time_col = pick_column_case_sensitive(T.Properties.VariableNames, adapter.time_column);
    if isempty(time_col)
        return;
    end

    wb_cache(key) = struct('T', T, 'time_col', time_col);
end

function sheet = pick_hongtang_sheet(xlsx_path, adapter)
    sheet = '';
    s = adapter.sheet;
    if isstring(s), s = char(s); end
    if ischar(s) && ~isempty(s) && ~strcmpi(s, 'auto_first_non_empty')
        sheet = s;
        return;
    end

    names = sheetnames(xlsx_path);
    for i = 1:numel(names)
        try
            C = readcell(xlsx_path, 'Sheet', names{i}, 'Range', 'A1:C5');
            if any(cellfun(@is_nonempty_cell_value, C(:)))
                sheet = names{i};
                return;
            end
        catch
            % try next sheet
        end
    end
    if ~isempty(names)
        sheet = names{1};
    end
end

function tf = is_nonempty_cell_value(x)
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

function name = pick_column_case_sensitive(vars, target)
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

function t = parse_hongtang_time(raw)
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
            % keep trying
        end
    end
end

function v = to_hongtang_numeric(raw, missing_tokens)
    if isnumeric(raw)
        v = double(raw);
        return;
    end
    s = strtrim(strrep(string(raw), '"', ''));
    miss = false(size(s));
    for i = 1:numel(s)
        miss(i) = ismissing_token(s(i), missing_tokens);
    end
    v = str2double(s);
    v(miss) = NaN;
end

function tf = ismissing_token(s, tokens)
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

function cache_path = make_hongtang_cache_file(xlsx_path, point_id, adapter)
    cache_path = '';
    if ~adapter.cache.enabled
        return;
    end
    cache_dir = adapter.cache.dir;
    if isstring(cache_dir), cache_dir = char(cache_dir); end
    if isempty(cache_dir) || ~ischar(cache_dir)
        return;
    end
    if ~isabsolute(cache_dir)
        cache_dir = fullfile(fileparts(xlsx_path), cache_dir);
    end
    if ~exist(cache_dir, 'dir')
        mkdir(cache_dir);
    end
    [~, fn, ~] = fileparts(xlsx_path);
    cache_path = fullfile(cache_dir, sprintf('%s__%s.mat', sanitize_cache_name(fn), sanitize_cache_name(point_id)));
end

function ok = can_use_hongtang_cache(cache_path, src_path, validate_mode)
    ok = false;
    if ~exist(cache_path, 'file')
        return;
    end
    if strcmpi(validate_mode, 'none')
        ok = true;
        return;
    end

    src_mtime = file_mtime(src_path);
    src_size = file_size(src_path);
    mat_mtime = file_mtime(cache_path);
    if strcmpi(validate_mode, 'mtime')
        ok = mat_mtime > src_mtime;
        return;
    end
    if strcmpi(validate_mode, 'mtime_size')
        try
            S = load(cache_path, 'meta');
            if isfield(S, 'meta') && isstruct(S.meta) && ...
                    isfield(S.meta, 'mtime') && isfield(S.meta, 'size')
                ok = (S.meta.mtime == src_mtime) && (S.meta.size == src_size);
                return;
            end
        catch
            ok = false;
        end
    end
    ok = mat_mtime > src_mtime;
end

function s = sanitize_cache_name(s)
    if isstring(s), s = char(s); end
    if ~ischar(s), s = 'cache'; end
    s = regexprep(s, '[^\w\-]', '_');
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
                   'outlier_window_sec', [], 'outlier_threshold_factor', [], ...
                   'offset_correction', []);
    shared_sensor = resolve_shared_sensor_type(sensor_type);
    if isfield(cfg, 'defaults') && isfield(cfg.defaults, sensor_type)
        def = cfg.defaults.(sensor_type);
        if isfield(def, 'thresholds'), rules.thresholds = def.thresholds; end
        if isfield(def, 'zero_to_nan'), rules.zero_to_nan = logical(def.zero_to_nan); end
        if isfield(def, 'outlier') && isstruct(def.outlier)
            if isfield(def.outlier, 'window_sec'), rules.outlier_window_sec = def.outlier.window_sec; end
            if isfield(def.outlier, 'threshold_factor'), rules.outlier_threshold_factor = def.outlier.threshold_factor; end
        end
        if isfield(def, 'offset_correction'), rules.offset_correction = parse_offset_value(def.offset_correction); end
    elseif ~isempty(shared_sensor) && isfield(cfg, 'defaults') && isfield(cfg.defaults, shared_sensor)
        def = cfg.defaults.(shared_sensor);
        if isfield(def, 'thresholds'), rules.thresholds = def.thresholds; end
        if isfield(def, 'zero_to_nan'), rules.zero_to_nan = logical(def.zero_to_nan); end
        if isfield(def, 'outlier') && isstruct(def.outlier)
            if isfield(def.outlier, 'window_sec'), rules.outlier_window_sec = def.outlier.window_sec; end
            if isfield(def.outlier, 'threshold_factor'), rules.outlier_threshold_factor = def.outlier.threshold_factor; end
        end
        if isfield(def, 'offset_correction'), rules.offset_correction = parse_offset_value(def.offset_correction); end
    end
    safe_id = strrep(point_id, '-', '_');
    if isfield(cfg, 'per_point') && isfield(cfg.per_point, sensor_type) ...
            && isfield(cfg.per_point.(sensor_type), safe_id)
        pt = cfg.per_point.(sensor_type).(safe_id);
        rules = apply_point_rules(rules, pt);
    elseif ~isempty(shared_sensor) && isfield(cfg, 'per_point') && isfield(cfg.per_point, shared_sensor) ...
            && isfield(cfg.per_point.(shared_sensor), safe_id)
        pt = cfg.per_point.(shared_sensor).(safe_id);
        rules = apply_point_rules(rules, pt);
    end

    % Wind mapping lives under per_point.wind; allow shared cleaning rules.
    if strncmp(sensor_type, 'wind_', 5) && isfield(cfg, 'per_point') ...
            && isfield(cfg.per_point, 'wind') && isfield(cfg.per_point.wind, safe_id)
        pt = cfg.per_point.wind.(safe_id);
        rules = apply_point_rules(rules, pt);
    end
end

function shared_sensor = resolve_shared_sensor_type(sensor_type)
    shared_sensor = '';
    if strncmp(sensor_type, 'gnss_', 5)
        shared_sensor = 'gnss';
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
    if isfield(pt, 'offset_correction')
        pt_offset = parse_offset_value(pt.offset_correction);
        if ~isempty(pt_offset)
            rules.offset_correction = pt_offset;
        end
    end
end

function offset = parse_offset_value(raw)
    offset = [];
    if isempty(raw)
        return;
    end
    if ischar(raw) || isstring(raw)
        raw = str2double(raw);
    end
    if isnumeric(raw) && isscalar(raw) && isfinite(raw)
        offset = double(raw);
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
    if fid < 0
        times = []; vals = [];
        return;
    end
    h = 0;
    found = false;
    buf = {};
    while h < 200 && ~feof(fid)
        ln = fgetl(fid); h = h + 1;
        if ~(ischar(ln) || isstring(ln))
            break;
        end
        ln = char(ln);
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
    adapter.zip.glob = get_field_default(adapter.zip, 'glob', 'data_jlj_*.zip');
    adapter.zip.date_pattern = get_field_default(adapter.zip, 'date_pattern', 'data_jlj_(\\d{4})-(\\d{2})-(\\d{2})');
    adapter.zip.subdir = get_field_default(adapter.zip, 'subdir', fullfile('data','jlj','csv'));
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
    layouts = get_jlj_layout_candidates(dt, start_str, end_str, adapter);

    for i = 1:numel(layouts)
        direct_folder = fullfile(root_dir, layouts(i).folder_name, layouts(i).subdir);
        if exist(direct_folder, 'dir')
            dirp = direct_folder;
            meta.cache_dir = resolve_jlj_cache_dir(direct_folder, adapter);
            return;
        end
    end

    for i = 1:numel(layouts)
        zip_path = fullfile(root_dir, [layouts(i).folder_name '.zip']);
        if exist(zip_path, 'file')
            [dirp, meta] = extract_jlj_zip(zip_path, layouts(i).subdir, adapter, meta);
            if ~isempty(dirp)
                return;
            end
        end
    end

    zip_path = find_jlj_zip(root_dir, dt, adapter.zip);
    if ~isempty(zip_path)
        [~, base, ~] = fileparts(zip_path);
        subdir = adapter.zip.subdir;
        if startsWith(base, 'jljData', 'IgnoreCase', true)
            subdir = fullfile('data', 'csv');
        end
        [dirp, meta] = extract_jlj_zip(zip_path, subdir, adapter, meta);
    end
end

function layouts = get_jlj_layout_candidates(dt, start_str, end_str, adapter)
    day_str = datestr(dt, 'yyyy-mm-dd');
    layouts = struct( ...
        'folder_name', { ...
            sprintf('data_jlj_%s', day_str), ...
            sprintf('jljData%s-%s', start_str, end_str)}, ...
        'subdir', { ...
            adapter.zip.subdir, ...
            fullfile('data', 'csv')});
end

function [dirp, meta] = extract_jlj_zip(zip_path, subdir, adapter, meta)
    dirp = '';
    staging_root = resolve_jlj_path(adapter.zip.staging_root);
    if ~exist(staging_root, 'dir'), mkdir(staging_root); end
    [~, base, ~] = fileparts(zip_path);
    dest = fullfile(staging_root, base);
    if ~exist(fullfile(dest, subdir), 'dir')
        if ~exist(dest, 'dir'), mkdir(dest); end
        unzip(zip_path, dest);
    end
    candidate = fullfile(dest, subdir);
    if exist(candidate, 'dir')
        dirp = candidate;
        meta.cache_dir = resolve_jlj_cache_dir(dirp, adapter);
    end
end

function zip_path = find_jlj_zip(root_dir, dt, zip_cfg)
    zip_path = '';
    globs = normalize_patterns(zip_cfg.glob);
    if isempty(globs)
        globs = {'*.zip'};
    end
    pats = normalize_patterns(zip_cfg.date_pattern);
    start_str = datestr(dt, 'yyyymmdd');
    day_str = datestr(dt, 'yyyy-mm-dd');

    for g = 1:numel(globs)
        files = dir(fullfile(root_dir, globs{g}));
        for i = 1:numel(files)
            name = files(i).name;
            matched = false;
            for p = 1:numel(pats)
                tokens = regexp(name, pats{p}, 'tokens', 'once');
                if isempty(tokens)
                    continue;
                end
                if numel(tokens) == 1 && strcmp(tokens{1}, start_str)
                    matched = true;
                    break;
                end
                if numel(tokens) >= 3
                    iso = sprintf('%s-%s-%s', tokens{1}, tokens{2}, tokens{3});
                    if strcmp(iso, day_str)
                        matched = true;
                        break;
                    end
                end
            end
            if matched
                zip_path = fullfile(files(i).folder, name);
                return;
            end
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

    cache_ok = false;
    if ~isempty(cache_path) && use_jlj_cache(cache_path, fp, adapter.cache.validate)
        try
            S = load(cache_path, 'ts', 'valx', 'valy', 'valz', 'meta');
            [t, v] = pick_cached_channel(S, sensor_type, point_id);
            cache_ok = true;
        catch
            cache_ok = false;
            try
                delete(cache_path);
            catch
            end
        end
    end

    if ~cache_ok
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
        warn_state = warning('off', 'all');
        warn_cleanup = onCleanup(@() warning(warn_state)); %#ok<NASGU>
        meta_info = whos('-file', cache_path, 'meta');
        if isempty(meta_info)
            return;
        end
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
    elseif st == "gnss_x"
        col = 'value_x';
    elseif st == "gnss_y"
        col = 'value_y';
    elseif st == "gnss_z"
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
