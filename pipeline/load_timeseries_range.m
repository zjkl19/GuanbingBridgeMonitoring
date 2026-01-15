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
    all_t = [];
    all_v = [];

    rules = build_rules(cfg, sensor_type, point_id);
    meta.applied_rules = rules;

    for i = 1:numel(date_list)
        day = date_list{i};
        dirp = fullfile(root_dir, day, subfolder);
        if ~exist(dirp, 'dir'), continue; end

        fp = find_file_for_point(dirp, point_id, cfg, sensor_type);
        if isempty(fp), continue; end

        [t, v] = load_single_file(fp, cfg.defaults.header_marker);
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
    vals = apply_thresholds(vals, times, rules.thresholds);
    if rules.zero_to_nan
        vals(vals == 0) = NaN;
    end
    if ~isempty(rules.outlier_window_sec) && ~isempty(rules.outlier_threshold_factor) && numel(times) >= 2
        fs = 1/median(seconds(diff(times)));
        w = max(1, round(fs * rules.outlier_window_sec));
        mask = isoutlier(vals, 'movmedian', w, 'ThresholdFactor', rules.outlier_threshold_factor);
        vals(mask) = NaN;
    end
end

% -------------------------------------------------------------------------
function fp = find_file_for_point(dirp, point_id, cfg, sensor_type)
    fp = '';
    patterns = {};
    if isfield(cfg, 'file_patterns') && isfield(cfg.file_patterns, sensor_type)
        ft = cfg.file_patterns.(sensor_type);
        if isfield(ft, 'default')
            patterns = [patterns; cellstr(ft.default(:))];
        end
        if isfield(ft, 'per_point') && isfield(ft.per_point, point_id)
            pt_pat = ft.per_point.(point_id);
            patterns = [cellstr(pt_pat(:)); patterns]; % point-specific takes priority
        end
    end

    for k = 1:numel(patterns)
        pat = patterns{k};
        pat = strrep(pat, '{point}', point_id);
        matches = dir(fullfile(dirp, pat));
        if ~isempty(matches)
            fp = fullfile(matches(1).folder, matches(1).name);
            return;
        end
    end

    % fallback to contains (legacy)
    files = dir(fullfile(dirp, '*.csv'));
    idx = find(arrayfun(@(f) contains(f.name, point_id), files), 1);
    if ~isempty(idx)
        fp = fullfile(files(idx).folder, files(idx).name);
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
        if isfield(def, 'outlier')
            if isfield(def.outlier, 'window_sec'), rules.outlier_window_sec = def.outlier.window_sec; end
            if isfield(def.outlier, 'threshold_factor'), rules.outlier_threshold_factor = def.outlier.threshold_factor; end
        end
    end
    if isfield(cfg, 'per_point') && isfield(cfg.per_point, sensor_type) ...
            && isfield(cfg.per_point.(sensor_type), point_id)
        pt = cfg.per_point.(sensor_type).(point_id);
        if isfield(pt, 'thresholds')
            % point-specific thresholds override defaults (append)
            rules.thresholds = pt.thresholds;
        end
        if isfield(pt, 'zero_to_nan'), rules.zero_to_nan = logical(pt.zero_to_nan); end
        if isfield(pt, 'outlier')
            if isfield(pt.outlier, 'window_sec'), rules.outlier_window_sec = pt.outlier.window_sec; end
            if isfield(pt.outlier, 'threshold_factor'), rules.outlier_threshold_factor = pt.outlier.threshold_factor; end
        end
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

    % detect header lines
    fid = fopen(fp, 'rt');
    h = 0;
    found = false;
    while h < 50 && ~feof(fid)
        ln = fgetl(fid); h = h + 1;
        if contains(ln, header_marker)
            found = true;
            break;
        end
    end
    fclose(fid);
    if ~found
        h = 0;
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
        T = readtable(fp, 'Delimiter', ',', 'HeaderLines', h, ...
            'Format', '%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
        times = T{:,1};
        vals  = T{:,2};
        save(cacheFile, 'times', 'vals');
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
