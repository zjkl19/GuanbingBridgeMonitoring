function analyze_wim_reports(root_dir, start_date, end_date, cfg)
% analyze_wim_reports  Process WIM (dynamic weighing) data and generate CSV+Excel reports.
%   Supports vendor adapters: zhichen (bcp/fmt native) and jiulongjiang (Excel).
%   Outputs all reports as CSV and merges them into one Excel workbook.

    if nargin < 1 || isempty(root_dir)
        root_dir = pwd;
    end
    if nargin < 2 || isempty(start_date)
        error('start_date is required (yyyy-MM-dd).');
    end
    if nargin < 3 || isempty(end_date)
        error('end_date is required (yyyy-MM-dd).');
    end
    if nargin < 4 || isempty(cfg)
        cfg = load_config();
    end

    wim = get_wim_cfg(cfg);
    pipeline = get_field_default(wim, 'pipeline', 'direct');
    vendor = resolve_vendor(wim);
    bridge = get_field_default(wim, 'bridge', get_field_default(cfg, 'vendor', 'bridge'));
    yyyymm = datestr(datetime(start_date, 'InputFormat', 'yyyy-MM-dd'), 'yyyymm');

    proj_root = fileparts(fileparts(mfilename('fullpath')));
    output_root = get_field_default(wim, 'output_root', fullfile(proj_root, 'data', 'output'));
    output_root = resolve_path(proj_root, output_root);
    out_dir = fullfile(output_root, bridge, yyyymm);
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end

    if strcmpi(pipeline, 'database')
        run_wim_database_pipeline(root_dir, start_date, end_date, wim, cfg);
        return;
    end

    % Initialize accumulators (direct pipeline)
    acc = init_accumulators(wim, start_date, end_date);

    switch lower(vendor)
        case 'zhichen'
            input_cfg = get_vendor_input(wim, 'zhichen');
            [fmt_path, bcp_path] = resolve_zhichen_paths(input_cfg, proj_root, yyyymm);
            acc = process_zhichen_bcp(fmt_path, bcp_path, acc, wim);
        case 'jiulongjiang'
            input_cfg = get_vendor_input(wim, 'jiulongjiang');
            files = resolve_jiulongjiang_files(input_cfg, proj_root);
            acc = process_jiulongjiang_excel(files, acc, wim);
        otherwise
            error('Unsupported wim.vendor: %s', vendor);
    end

    % Build report tables
    reports = build_report_tables(acc, wim);

    % Write CSVs
    csv_paths = write_report_csvs(reports, out_dir, yyyymm);

    % Merge to Excel
    excel_name = get_field_default(wim, 'excel_name', 'WIM_Report_{bridge}_{yyyymm}.xlsx');
    excel_name = strrep(excel_name, '{bridge}', bridge);
    excel_name = strrep(excel_name, '{yyyymm}', yyyymm);
    excel_path = fullfile(out_dir, excel_name);
    write_excel_from_csvs(csv_paths, excel_path);

    fprintf('WIM reports done: %s\n', excel_path);
end

% =========================
% Config helpers
% =========================
function wim = get_wim_cfg(cfg)
    wim = struct();
    if isfield(cfg, 'wim') && isstruct(cfg.wim)
        wim = cfg.wim;
    end
    wim = fill_default(wim, 'vendor', 'auto');
    wim = fill_default(wim, 'bridge', 'bridge');
    wim = fill_default(wim, 'pipeline', 'direct');
    wim = fill_default(wim, 'design_total_kg', 55000);
    wim = fill_default(wim, 'design_axle_kg', 28000);
    wim = fill_default(wim, 'overload_factors', [1.5, 2.0]);
    wim = fill_default(wim, 'topn', 10);
    wim = fill_default(wim, 'lanes', 1:8);
    wim = fill_default(wim, 'up_lanes', 1:4);
    wim = fill_default(wim, 'speed_bins', [0, 30, 50, 70, 9999]);
    wim = fill_default(wim, 'gross_bins', [0, 10000, 30000, 50000, 999999]);
    wim = fill_default(wim, 'hour_bins', [0,2,4,6,8,10,12,14,16,18,20,22,24]);
    wim = fill_default(wim, 'custom_weights', [30000, 50000]);
    wim = fill_default(wim, 'critical_lanes', 1:8);
    wim = fill_default(wim, 'hourly_critical_weight_kg', 50000);
    wim = fill_default(wim, 'excel_name', 'WIM_Report_{bridge}_{yyyymm}.xlsx');
end

function vendor = resolve_vendor(wim)
    vendor = get_field_default(wim, 'vendor', 'auto');
    if isempty(vendor) || strcmpi(vendor, 'auto')
        vendors = {};
        if isfield(wim, 'input') && isstruct(wim.input)
            if isfield(wim.input, 'zhichen'), vendors{end+1} = 'zhichen'; end %#ok<AGROW>
            if isfield(wim.input, 'jiulongjiang'), vendors{end+1} = 'jiulongjiang'; end %#ok<AGROW>
        end
        if numel(vendors) == 1
            vendor = vendors{1};
        else
            error('wim.vendor is required when multiple vendors are configured.');
        end
    end
end

function input_cfg = get_vendor_input(wim, name)
    input_cfg = struct();
    if isfield(wim, 'input') && isstruct(wim.input) && isfield(wim.input, name)
        input_cfg = wim.input.(name);
    end
end

function p = resolve_path(base, p)
    if isempty(p), return; end
    if isstring(p), p = char(p); end
    if ~ischar(p), return; end
    if ~(numel(p) >= 2 && p(2) == ':') && ~startsWith(p, filesep)
        p = fullfile(base, p);
    end
end

function v = get_field_default(s, field, defaultVal)
    if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
        v = s.(field);
    else
        v = defaultVal;
    end
end

function s = fill_default(s, field, defaultVal)
    if ~isfield(s, field) || isempty(s.(field))
        s.(field) = defaultVal;
    end
end

% =========================
% Input resolvers
% =========================
function [fmt_path, bcp_path] = resolve_zhichen_paths(input_cfg, base, yyyymm)
    fmt_name = get_field_default(input_cfg, 'fmt', ['HS_Data_' yyyymm '.fmt']);
    bcp_name = get_field_default(input_cfg, 'bcp', ['HS_Data_' yyyymm '.bcp']);
    fmt_name = strrep(fmt_name, '{yyyymm}', yyyymm);
    bcp_name = strrep(bcp_name, '{yyyymm}', yyyymm);
    input_dir = get_field_default(input_cfg, 'dir', '');
    input_dir = resolve_path(base, input_dir);
    fmt_path = fullfile(input_dir, fmt_name);
    bcp_path = fullfile(input_dir, bcp_name);
    if ~exist(fmt_path, 'file')
        error('Fmt file not found: %s', fmt_path);
    end
    if ~exist(bcp_path, 'file')
        error('BCP file not found: %s', bcp_path);
    end
end

function files = resolve_jiulongjiang_files(input_cfg, base)
    files = {};
    if isfield(input_cfg, 'files') && ~isempty(input_cfg.files)
        if ischar(input_cfg.files) || isstring(input_cfg.files)
            files = cellstr(input_cfg.files);
        elseif iscell(input_cfg.files)
            files = input_cfg.files;
        end
    end
    for i = 1:numel(files)
        files{i} = resolve_path(base, files{i});
    end
    if isempty(files)
        error('No jiulongjiang input files configured (wim.input.jiulongjiang.files).');
    end
end

% =========================
% Accumulators
% =========================
function acc = init_accumulators(wim, start_date, end_date)
    t0 = datenum(start_date, 'yyyy-mm-dd');
    t1 = datenum(end_date, 'yyyy-mm-dd') + 1;
    day_vec = (datetime(start_date):days(1):datetime(end_date)).';
    nDays = numel(day_vec);

    lanes = double(wim.lanes(:))';
    up_lanes = double(wim.up_lanes(:))';
    speed_edges = double(wim.speed_bins(:))';
    gross_edges = double(wim.gross_bins(:))';
    hour_edges = double(wim.hour_bins(:))';
    custom_weights = double(wim.custom_weights(:))';
    critical_lanes = double(wim.critical_lanes(:))';

    acc = struct();
    acc.t0 = t0;
    acc.t1 = t1;
    acc.days = day_vec;
    acc.daily_up = zeros(nDays,1);
    acc.daily_down = zeros(nDays,1);
    acc.daily_total = zeros(nDays,1);

    acc.lanes = lanes;
    acc.lane_counts = zeros(numel(lanes),1);
    acc.lane_map = containers.Map(num2cell(lanes), num2cell(1:numel(lanes)));
    acc.up_lane_set = containers.Map(num2cell(up_lanes), num2cell(true(size(up_lanes))));

    acc.speed_edges = speed_edges;
    acc.speed_counts = zeros(numel(speed_edges)-1,1);
    acc.gross_edges = gross_edges;
    acc.gross_counts = zeros(numel(gross_edges)-1,1);

    acc.hour_edges = hour_edges;
    acc.hour_counts = zeros(numel(hour_edges)-1,1);
    acc.hour_speed_sum = zeros(numel(hour_edges)-1,1);
    acc.hour_speed_cnt = zeros(numel(hour_edges)-1,1);
    acc.hour_over_cnt = zeros(numel(hour_edges)-1,1);
    acc.hour_critical_weight = double(wim.hourly_critical_weight_kg);

    acc.custom_weights = custom_weights;
    acc.custom_overall = zeros(numel(custom_weights),1);
    acc.critical_lanes = critical_lanes;
    acc.custom_per_lane = zeros(numel(critical_lanes), numel(custom_weights));

    acc.topn = init_topn(double(wim.topn));
    acc.topn_max_axle = init_topn(double(wim.topn));
    acc.topn_raw_headers = {};

    acc.overload_factors = double(wim.overload_factors(:))';
    acc.design_total = double(wim.design_total_kg);
    acc.design_axle = double(wim.design_axle_kg);
    acc.overload_counts = zeros(2, numel(acc.overload_factors)); % row1: total, row2: axle
end

function topn = init_topn(n)
    topn.n = n;
    topn.values = -inf(n,1);
    topn.times = inf(n,1);
    topn.std_rows = cell(n, 1);
    topn.raw_rows = cell(n, 1);
end

% =========================
% Vendor processors
% =========================
function acc = process_zhichen_bcp(fmt_path, bcp_path, acc, wim)
    fmt = parse_bcp_fmt(fmt_path);
    encoding = get_field_default(get_vendor_input(wim, 'zhichen'), 'encoding', 'gbk');

    idx = index_map(fmt);
    required = required_columns();
    check_required(idx, required);

    fid = fopen(bcp_path, 'r', 'ieee-le');
    if fid < 0
        error('Cannot open bcp: %s', bcp_path);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

    while true
        [row_bytes, ok] = read_bcp_row(fid, fmt);
        if ~ok, break; end

        % Decode needed columns for stats
        t_dn = decode_datetime(row_bytes{idx.HSData_DT});
        if isempty(t_dn) || ~isfinite(t_dn), continue; end
        if t_dn < acc.t0 || t_dn >= acc.t1, continue; end

        lane = decode_int(row_bytes{idx.Lane_Id});
        axle_num = decode_int(row_bytes{idx.Axle_Num});
        gross = decode_int(row_bytes{idx.Gross_Load});
        speed = decode_int(row_bytes{idx.Speed});

        axle_w = zeros(1,8);
        for k = 1:8
            lw = decode_int(row_bytes{idx.(['LWheel_' num2str(k) '_W'])});
            rw = decode_int(row_bytes{idx.(['RWheel_' num2str(k) '_W'])});
            axle_w(k) = nansum([lw rw]);
        end
        axle_d = zeros(1,7);
        for k = 1:7
            axle_d(k) = decode_int(row_bytes{idx.(['AxleDis' num2str(k)])});
        end

        plate = decode_string(row_bytes{idx.License_Plate}, 'utf-16le');

        acc = update_accumulators(acc, t_dn, lane, gross, speed, axle_w, axle_num);
        acc = update_overload(acc, gross, axle_w);

        std_row = build_std_row(lane, t_dn, axle_num, gross, speed, plate, axle_w, axle_d);

        acc.topn = update_topn(acc.topn, gross, t_dn, std_row, []);
        [max_axle, ~] = max(axle_w, [], 'omitnan');
        raw_vals = [];
        if qualifies_for_topn(acc.topn_max_axle, max_axle, t_dn)
            raw_vals = decode_all_row(fmt, row_bytes, encoding);
            acc.topn_raw_headers = {fmt.name};
        end
        acc.topn_max_axle = update_topn(acc.topn_max_axle, max_axle, t_dn, std_row, raw_vals);
    end
end

function acc = process_jiulongjiang_excel(files, acc, wim)
    for fi = 1:numel(files)
        tbl = readtable(files{fi}, 'VariableNamingRule','preserve');
        if isempty(tbl), continue; end

        cols = resolve_jiulongjiang_columns(tbl);
        t_dn = get_time_column(tbl, cols.time);
        lane = resolve_lane(tbl, cols);
        gross = get_numeric_column(tbl, cols.gross, height(tbl));
        speed = get_numeric_column(tbl, cols.speed, height(tbl));
        axle_num = get_numeric_column(tbl, cols.axle_num, height(tbl));
        axle_w = resolve_axle_weights(tbl, cols.axle_weights);
        axle_d = resolve_axle_dists(tbl, cols.axle_dists);
        plate = resolve_plate(tbl, cols);

        for i = 1:numel(t_dn)
            if ~isfinite(t_dn(i)), continue; end
            if t_dn(i) < acc.t0 || t_dn(i) >= acc.t1, continue; end

            acc = update_accumulators(acc, t_dn(i), lane(i), gross(i), speed(i), axle_w(i,:), axle_num(i));
            acc = update_overload(acc, gross(i), axle_w(i,:));

            std_row = build_std_row(lane(i), t_dn(i), axle_num(i), gross(i), speed(i), plate{i}, axle_w(i,:), axle_d(i,:));
            acc.topn = update_topn(acc.topn, gross(i), t_dn(i), std_row, []);

            [max_axle, ~] = max(axle_w(i,:), [], 'omitnan');
            raw_row = [];
            if qualifies_for_topn(acc.topn_max_axle, max_axle, t_dn(i))
                raw_row = table2cell(tbl(i,:));
                acc.topn_raw_headers = tbl.Properties.VariableNames;
            end
            acc.topn_max_axle = update_topn(acc.topn_max_axle, max_axle, t_dn(i), std_row, raw_row);
        end
    end
end

% =========================
% Reports
% =========================
function reports = build_report_tables(acc, wim)
    reports = struct();
    % Daily traffic
    T = table(acc.days, acc.daily_up, acc.daily_down, acc.daily_total, ...
        'VariableNames', {'date','up_cnt','down_cnt','total'});
    reports.DailyTraffic = T;

    % Lane / Speed / Gross (LaneSpeedWeight)
    reports.LaneSpeedWeight_Lane = table(acc.lanes(:), acc.lane_counts(:), ...
        'VariableNames', {'lane','count'});
    [labels, counts] = bin_table(acc.speed_edges, acc.speed_counts);
    reports.LaneSpeedWeight_Speed = table((1:numel(counts)).', labels, counts, ...
        'VariableNames', {'bin_id','label','count'});
    [labels, counts] = bin_table(acc.gross_edges, acc.gross_counts);
    reports.LaneSpeedWeight_Gross = table((1:numel(counts)).', labels, counts, ...
        'VariableNames', {'bin_id','label','count'});

    % Hourly
    [labels, counts] = bin_table(acc.hour_edges, acc.hour_counts);
    avg_speed = acc.hour_speed_sum ./ acc.hour_speed_cnt;
    avg_speed(acc.hour_speed_cnt==0) = NaN;
    reports.Hourly_Count = table((1:numel(counts)).', labels, counts, ...
        'VariableNames', {'bin_id','label','count'});
    reports.Hourly_AvgSpeed = table((1:numel(counts)).', labels, avg_speed, ...
        'VariableNames', {'bin_id','label','avg_speed'});
    reports.Hourly_Over = table((1:numel(counts)).', labels, acc.hour_over_cnt, ...
        'VariableNames', {'bin_id','label','over_cnt'});

    % Custom thresholds
    reports.CustomThresholds_Overall = table(acc.custom_weights(:), acc.custom_overall(:), ...
        'VariableNames', {'weight_threshold','over_cnt'});
    [lane_grid, weight_grid] = ndgrid(acc.critical_lanes, acc.custom_weights);
    per_lane = reshape(acc.custom_per_lane, numel(acc.critical_lanes)*numel(acc.custom_weights), 1);
    reports.CustomThresholds_PerLane = table(lane_grid(:), weight_grid(:), per_lane, ...
        'VariableNames', {'lane','weight_threshold','over_cnt'});

    % TopN (gross)
    reports.TopN = build_topn_table(acc.topn);
    reports.TopN_MaxAxle = build_topn_table(acc.topn_max_axle);

    % Raw topn max axle
    if ~isempty(acc.topn_raw_headers) && ~isempty(acc.topn_max_axle.raw_rows)
        raw_rows = acc.topn_max_axle.raw_rows;
        raw_rows = raw_rows(~cellfun('isempty', raw_rows));
        if isempty(raw_rows)
            reports.TopN_MaxAxle_Raw = table();
        else
            headers = acc.topn_raw_headers;
            ncol = numel(headers);
            for i = 1:numel(raw_rows)
                r = raw_rows{i};
                if numel(r) < ncol
                    r = [r, repmat({[]}, 1, ncol - numel(r))];
                elseif numel(r) > ncol
                    r = r(1:ncol);
                end
                raw_rows{i} = r;
            end
            headers = normalize_headers(headers);
            mat = vertcat(raw_rows{:});
            reports.TopN_MaxAxle_Raw = cell2table(mat, 'VariableNames', headers);
        end
    else
        reports.TopN_MaxAxle_Raw = table();
    end

    % Overload summary
    factors = acc.overload_factors(:);
    total_thr = acc.design_total * factors;
    axle_thr = acc.design_axle * factors;
    reports.Overload_Summary = table( ...
        [repmat({'total'}, numel(factors),1); repmat({'axle'}, numel(factors),1)], ...
        [total_thr; axle_thr], ...
        [acc.overload_counts(1,:).'; acc.overload_counts(2,:).'], ...
        'VariableNames', {'type','threshold_kg','count'});
end

function [labels, counts] = bin_table(edges, counts)
    n = numel(edges)-1;
    labels = strings(n,1);
    for i = 1:n
        lo = edges(i);
        hi = edges(i+1);
        if i == n
            labels(i) = sprintf('>=%.0f', lo);
        else
            labels(i) = sprintf('%.0f-%.0f', lo, hi-1);
        end
    end
end

function headers = normalize_headers(headers)
    if ischar(headers) || isstring(headers)
        headers = cellstr(headers);
    end
    for i = 1:numel(headers)
        if isempty(headers{i})
            headers{i} = sprintf('Var%d', i);
        end
    end
end

function T = build_topn_table(topn)
    rows = topn.std_rows;
    rows = rows(~cellfun('isempty', rows));
    if isempty(rows)
        T = table();
        return;
    end
    cols = {'lane','time','axle_num','gross_kg','speed_kmh','plate', ...
        'axle1','axle2','axle3','axle4','axle5','axle6','axle7','axle8', ...
        'axledis1','axledis2','axledis3','axledis4','axledis5','axledis6','axledis7'};
    % normalize row width and stack to matrix
    ncol = numel(cols);
    for i = 1:numel(rows)
        r = rows{i};
        if numel(r) < ncol
            r = [r, repmat({[]}, 1, ncol - numel(r))];
        elseif numel(r) > ncol
            r = r(1:ncol);
        end
        rows{i} = r;
    end
    mat = vertcat(rows{:});
    T = cell2table(mat, 'VariableNames', cols);
    if ismember('plate', T.Properties.VariableNames)
        if iscell(T.plate)
            T.plate = string(cellfun(@to_string_scalar, T.plate, 'UniformOutput', false));
        else
            T.plate = string(T.plate);
        end
    end
    T = addvars(T, (1:height(T)).', 'Before', 1, 'NewVariableNames','rank');
end

function s = to_string_scalar(x)
    if isstring(x)
        if numel(x) > 1
            s = strjoin(x(:).', '');
        else
            s = x;
        end
    elseif ischar(x)
        if size(x,1) > 1
            s = strjoin(cellstr(x), '');
        else
            s = string(x);
        end
    elseif isnumeric(x)
        s = string(x);
        if numel(s) > 1
            s = strjoin(s(:).', '');
        end
    else
        try
            s = string(x);
            if numel(s) > 1
                s = strjoin(s(:).', '');
            end
        catch
            s = "";
        end
    end
end

% =========================
% CSV / Excel output
% =========================
function csv_paths = write_report_csvs(reports, out_dir, yyyymm)
    csv_paths = struct();
    names = fieldnames(reports);
    for i = 1:numel(names)
        name = names{i};
        T = reports.(name);
        csv_name = sprintf('%s_%s.csv', yyyymm, name);
        csv_path = fullfile(out_dir, csv_name);
        if istable(T)
            writetable(T, csv_path, 'Encoding','UTF-8');
        else
            writecell(T, csv_path, 'Encoding','UTF-8');
        end
        csv_paths.(name) = csv_path;
    end
end

function write_excel_from_csvs(csv_paths, excel_path)
    names = fieldnames(csv_paths);
    if exist(excel_path, 'file')
        delete(excel_path);
    end
    for i = 1:numel(names)
        name = names{i};
        csv_path = csv_paths.(name);
        if ~exist(csv_path,'file'), continue; end
        enc = detect_file_encoding(csv_path);
        try
            T = readtable(csv_path, 'TextType','string', 'Encoding', enc);
            writetable(T, excel_path, 'Sheet', safe_sheet_name(name));
        catch
            C = readcell(csv_path, 'Encoding', enc);
            writecell(C, excel_path, 'Sheet', safe_sheet_name(name));
        end
    end
end

function s = safe_sheet_name(name)
    s = regexprep(name, '[:\\/\?\*\[\]]', '_');
    if numel(s) > 31, s = s(1:31); end
end

% =========================
% Accumulator updates
% =========================
function acc = update_accumulators(acc, t_dn, lane, gross, speed, axle_w, axle_num)
    day_idx = floor(t_dn) - floor(acc.t0) + 1;
    if day_idx >= 1 && day_idx <= numel(acc.daily_total)
        acc.daily_total(day_idx) = acc.daily_total(day_idx) + 1;
        if isfinite(lane) && isKey(acc.up_lane_set, lane)
            acc.daily_up(day_idx) = acc.daily_up(day_idx) + 1;
        else
            acc.daily_down(day_idx) = acc.daily_down(day_idx) + 1;
        end
    end

    if isfinite(lane) && isKey(acc.lane_map, lane)
        li = acc.lane_map(lane);
        acc.lane_counts(li) = acc.lane_counts(li) + 1;
    end

    if isfinite(speed)
        bi = find_bin(speed, acc.speed_edges);
        if bi > 0, acc.speed_counts(bi) = acc.speed_counts(bi) + 1; end
    end

    if isfinite(gross)
        bi = find_bin(gross, acc.gross_edges);
        if bi > 0, acc.gross_counts(bi) = acc.gross_counts(bi) + 1; end
    end

    hh = floor(mod(t_dn, 1) * 24);
    bi = find_bin(hh, acc.hour_edges);
    if bi > 0
        acc.hour_counts(bi) = acc.hour_counts(bi) + 1;
        if isfinite(speed)
            acc.hour_speed_sum(bi) = acc.hour_speed_sum(bi) + speed;
            acc.hour_speed_cnt(bi) = acc.hour_speed_cnt(bi) + 1;
        end
        if isfinite(gross) && gross >= acc.hour_critical_weight
            acc.hour_over_cnt(bi) = acc.hour_over_cnt(bi) + 1;
        end
    end

    if isfinite(gross)
        for i = 1:numel(acc.custom_weights)
            if gross >= acc.custom_weights(i)
                acc.custom_overall(i) = acc.custom_overall(i) + 1;
            end
        end
        for li = 1:numel(acc.critical_lanes)
            if isfinite(lane) && lane == acc.critical_lanes(li)
                for i = 1:numel(acc.custom_weights)
                    if gross >= acc.custom_weights(i)
                        acc.custom_per_lane(li,i) = acc.custom_per_lane(li,i) + 1;
                    end
                end
                break;
            end
        end
    end
end

function acc = update_overload(acc, gross, axle_w)
    if ~isfinite(gross), return; end
    for i = 1:numel(acc.overload_factors)
        if gross >= acc.design_total * acc.overload_factors(i)
            acc.overload_counts(1,i) = acc.overload_counts(1,i) + 1;
        end
    end
    max_axle = max(axle_w, [], 'omitnan');
    if isfinite(max_axle)
        for i = 1:numel(acc.overload_factors)
            if max_axle >= acc.design_axle * acc.overload_factors(i)
                acc.overload_counts(2,i) = acc.overload_counts(2,i) + 1;
            end
        end
    end
end

function idx = find_bin(val, edges)
    if ~isfinite(val), idx = 0; return; end
    n = numel(edges) - 1;
    for i = 1:n
        lo = edges(i);
        hi = edges(i+1);
        if i == n
            if val >= lo
                idx = i; return;
            end
        else
            if val >= lo && val < hi
                idx = i; return;
            end
        end
    end
    idx = 0;
end

% =========================
% TopN helpers
% =========================
function ok = qualifies_for_topn(topn, key, t_dn)
    ok = false;
    if ~isfinite(key), return; end
    min_val = topn.values(end);
    if key > min_val
        ok = true;
    elseif key == min_val && t_dn < topn.times(end)
        ok = true;
    end
end

function topn = update_topn(topn, key, t_dn, std_row, raw_row)
    if ~isfinite(key), return; end
    idx = find_insert_index(topn, key, t_dn);
    if isempty(idx), return; end
    if idx < topn.n
        topn.values(idx+1:end) = topn.values(idx:end-1);
        topn.times(idx+1:end) = topn.times(idx:end-1);
        topn.std_rows(idx+1:end) = topn.std_rows(idx:end-1);
        topn.raw_rows(idx+1:end) = topn.raw_rows(idx:end-1);
    end
    topn.values(idx) = key;
    topn.times(idx) = t_dn;
    topn.std_rows{idx} = std_row;
    topn.raw_rows{idx} = raw_row;
end

function idx = find_insert_index(topn, key, t_dn)
    idx = [];
    for i = 1:topn.n
        if key > topn.values(i)
            idx = i; return;
        elseif key == topn.values(i) && t_dn < topn.times(i)
            idx = i; return;
        end
    end
end

function row = build_std_row(lane, t_dn, axle_num, gross, speed, plate, axle_w, axle_d)
    t_str = datestr(t_dn, 'yyyy-mm-dd HH:MM:SS');
    row = [{lane, t_str, axle_num, gross, speed, plate}, num2cell(axle_w), num2cell(axle_d)];
end

% =========================
% BCP parsing
% =========================
function fmt = parse_bcp_fmt(fmt_path)
    lines = readlines(fmt_path, 'WhitespaceRule','preserve');
    if numel(lines) < 3
        error('Invalid fmt file: %s', fmt_path);
    end
    ncols = str2double(strtrim(lines(2)));
    fmt = repmat(struct('name','','type','','prefix',0,'len',0), ncols, 1);
    for i = 1:ncols
        line = strtrim(lines(i+2));
        if line == "", continue; end
        tokens = regexp(line, '\s+', 'split');
        % tokens: id type prefix len term order name [collation]
        if numel(tokens) < 7
            error('Fmt line parse error: %s', line);
        end
        fmt(i).type = tokens{2};
        fmt(i).prefix = str2double(tokens{3});
        fmt(i).len = str2double(tokens{4});
        fmt(i).name = tokens{7};
    end
end

function idx = index_map(fmt)
    idx = struct();
    for i = 1:numel(fmt)
        idx.(fmt(i).name) = i;
    end
end

function required = required_columns()
    required = {'HSData_DT','Lane_Id','Axle_Num','Gross_Load','Speed','License_Plate'};
    for k = 1:8
        required{end+1} = sprintf('LWheel_%d_W', k); %#ok<AGROW>
        required{end+1} = sprintf('RWheel_%d_W', k); %#ok<AGROW>
    end
    for k = 1:7
        required{end+1} = sprintf('AxleDis%d', k); %#ok<AGROW>
    end
end

function check_required(idx, required)
    for i = 1:numel(required)
        if ~isfield(idx, required{i})
            error('Missing column in fmt: %s', required{i});
        end
    end
end

function [row_bytes, ok] = read_bcp_row(fid, fmt)
    n = numel(fmt);
    row_bytes = cell(1, n);
    ok = true;
    for i = 1:n
        [bytes, ok] = read_field_bytes(fid, fmt(i));
        if ~ok
            row_bytes = {};
            return;
        end
        row_bytes{i} = bytes;
    end
end

function [bytes, ok] = read_field_bytes(fid, spec)
    ok = true;
    if spec.prefix > 0
        len = read_prefix_len(fid, spec.prefix);
        if isempty(len)
            ok = false; bytes = []; return;
        end
        if len == 0
            bytes = [];
            return;
        end
        bytes = fread(fid, len, 'uint8=>uint8');
        if numel(bytes) < len
            ok = false;
        end
    else
        bytes = fread(fid, spec.len, 'uint8=>uint8');
        if numel(bytes) < spec.len
            ok = false;
        end
    end
end

function len = read_prefix_len(fid, prefix_len)
    switch prefix_len
        case 1
            len = fread(fid, 1, 'uint8=>double');
        case 2
            len = fread(fid, 1, 'uint16=>double');
        case 4
            len = fread(fid, 1, 'uint32=>double');
        case 8
            len = fread(fid, 1, 'uint64=>double');
        otherwise
            len = fread(fid, 1, 'uint32=>double');
    end
end

function dt = decode_datetime(bytes)
    if isempty(bytes) || numel(bytes) < 8
        dt = NaN; return;
    end
    days = typecast(uint8(bytes(1:4)), 'int32');
    ticks = typecast(uint8(bytes(5:8)), 'int32');
    dt = datenum('1900-01-01') + double(days) + double(ticks) / 300 / 86400;
end

function v = decode_int(bytes)
    if isempty(bytes), v = NaN; return; end
    n = numel(bytes);
    if n == 1
        v = double(typecast(uint8(bytes), 'uint8'));
    elseif n == 2
        v = double(typecast(uint8(bytes), 'int16'));
    elseif n == 4
        v = double(typecast(uint8(bytes), 'int32'));
    else
        v = double(bytes(1));
    end
end

function s = decode_string(bytes, encoding)
    if isempty(bytes)
        s = '';
        return;
    end
    try
        if strcmpi(encoding, 'utf-16le')
            s = native2unicode(uint8(bytes), 'UTF-16LE');
        else
            s = native2unicode(uint8(bytes), encoding);
        end
    catch
        s = native2unicode(uint8(bytes), 'UTF-8');
    end
    s = strtrim(s);
end

function vals = decode_all_row(fmt, row_bytes, encoding)
    vals = cell(1, numel(fmt));
    for i = 1:numel(fmt)
        vals{i} = decode_by_type(fmt(i).type, row_bytes{i}, encoding);
    end
end

function v = decode_by_type(type_name, bytes, encoding)
    if isempty(bytes)
        v = '';
        return;
    end
    switch upper(type_name)
        case 'SQLINT'
            v = double(typecast(uint8(bytes), 'int32'));
        case 'SQLTINYINT'
            v = double(typecast(uint8(bytes), 'uint8'));
        case 'SQLSMALLINT'
            v = double(typecast(uint8(bytes), 'int16'));
        case 'SQLBIGINT'
            v = double(typecast(uint8(bytes), 'int64'));
        case 'SQLDATETIME'
            dt = decode_datetime(bytes);
            if isfinite(dt)
                v = datestr(dt, 'yyyy-mm-dd HH:MM:SS');
            else
                v = '';
            end
        case 'SQLCHAR'
            v = decode_string(bytes, encoding);
        case 'SQLNCHAR'
            v = decode_string(bytes, 'utf-16le');
        case 'SQLNUMERIC'
            v = decode_numeric(bytes);
        case 'SQLFLT4'
            v = double(typecast(uint8(bytes), 'single'));
        case 'SQLFLT8'
            v = double(typecast(uint8(bytes), 'double'));
        otherwise
            v = decode_string(bytes, encoding);
    end
end

function v = decode_numeric(bytes)
    if isempty(bytes)
        v = NaN; return;
    end
    sign_byte = bytes(1);
    mag = 0;
    if numel(bytes) > 1
        for i = 2:numel(bytes)
            mag = mag + double(bytes(i)) * 256^(i-2);
        end
    end
    if sign_byte == 0
        v = -mag;
    else
        v = mag;
    end
end

% =========================
% Jiulongjiang helpers
% =========================
function cols = resolve_jiulongjiang_columns(tbl)
    names = tbl.Properties.VariableNames;
    cols = struct();
    cols.time = find_col(names, {'采集时间','时间','日期'});
    cols.lane_id = find_col(names, {'车道号','车道编号'});
    cols.lane_text = find_col(names, {'车道'});
    cols.speed = find_col(names, {'车速','车速(Km/h)','车速(km/h)'});
    cols.gross = find_col(names, {'总重','总重(kg)'});
    cols.axle_num = find_col(names, {'轴数','轴数(个)'});
    cols.plate = find_col(names, {'车牌号'});
    cols.axle_weights = find_series_cols(names, '轴重', 8);
    cols.axle_dists = find_series_cols(names, '轴距', 7);
end

function idx = find_col(names, candidates)
    idx = [];
    for i = 1:numel(candidates)
        c = candidates{i};
        hit = find(strcmp(names, c), 1);
        if ~isempty(hit)
            idx = hit; return;
        end
    end
    for i = 1:numel(candidates)
        c = candidates{i};
        hit = find(contains(names, c), 1);
        if ~isempty(hit)
            idx = hit; return;
        end
    end
end

function idxs = find_series_cols(names, prefix, nmax)
    idxs = zeros(1, nmax);
    for k = 1:nmax
        pat = sprintf('%s%d', prefix, k);
        hit = find(contains(names, pat), 1);
        if ~isempty(hit), idxs(k) = hit; end
    end
end

function t_dn = excel_datetime_to_datenum(col)
    if isdatetime(col)
        t_dn = datenum(col);
    else
        try
            t_dn = datenum(col);
        catch
            t_dn = datenum(datetime(col, 'InputFormat','yyyy-MM-dd HH:mm:ss.SSS'));
        end
    end
end

function t_dn = get_time_column(tbl, idx)
    if isempty(idx)
        t_dn = NaN(height(tbl),1);
        return;
    end
    t_dn = excel_datetime_to_datenum(tbl{:, idx});
end

function v = get_numeric_column(tbl, idx, n)
    if isempty(idx)
        v = NaN(n,1);
        return;
    end
    v = to_double(tbl{:, idx});
end

function lane = resolve_lane(tbl, cols)
    n = height(tbl);
    lane = NaN(n,1);
    % Prefer text lane column (e.g., "车道2") when present
    if ~isempty(cols.lane_text)
        lane = parse_lane_text(tbl{:, cols.lane_text});
        if any(isfinite(lane))
            return;
        end
    end
    % Fallback to numeric lane id column
    if ~isempty(cols.lane_id)
        lane = to_double(tbl{:, cols.lane_id});
    end
end

function lane = parse_lane_text(col)
    n = numel(col);
    lane = NaN(n,1);
    for i = 1:n
        s = string(col(i));
        d = regexp(s, '\d+', 'match');
        if ~isempty(d)
            lane(i) = str2double(d{1});
        end
    end
end

function plate = resolve_plate(tbl, cols)
    n = height(tbl);
    plate = repmat({''}, n, 1);
    if ~isempty(cols.plate)
        raw = tbl{:, cols.plate};
        for i = 1:n
            plate{i} = char(string(raw(i)));
        end
    end
end

function v = to_double(x)
    v = NaN(size(x));
    if iscell(x)
        for i = 1:numel(x)
            v(i) = str2double(string(x{i}));
        end
    elseif isstring(x) || ischar(x)
        v = str2double(string(x));
    else
        v = double(x);
    end
end

function axle_w = resolve_axle_weights(tbl, idxs)
    n = height(tbl);
    axle_w = zeros(n, numel(idxs));
    for k = 1:numel(idxs)
        if idxs(k) > 0
            axle_w(:,k) = to_double(tbl{:, idxs(k)});
        end
    end
end

function axle_d = resolve_axle_dists(tbl, idxs)
    n = height(tbl);
    axle_d = zeros(n, numel(idxs));
    for k = 1:numel(idxs)
        if idxs(k) > 0
            axle_d(:,k) = to_double(tbl{:, idxs(k)});
        end
    end
end

% =========================
% Database pipeline
% =========================
function run_wim_database_pipeline(root_dir, start_date, end_date, wim, cfg)
    proj_root = fileparts(fileparts(mfilename('fullpath')));
    db = get_wim_db_cfg(wim, cfg, proj_root);

    vendor = resolve_vendor(wim);
    bridge = get_field_default(wim, 'bridge', get_field_default(cfg, 'vendor', 'bridge'));
    yyyymm = datestr(datetime(start_date, 'InputFormat', 'yyyy-MM-dd'), 'yyyymm');

    output_root = get_field_default(wim, 'output_root', fullfile(proj_root, 'data', 'output'));
    output_root = resolve_path(proj_root, output_root);
    out_dir = fullfile(output_root, bridge, yyyymm);
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end

    start_dt = datetime(start_date, 'InputFormat', 'yyyy-MM-dd');
    finish_dt = datetime(end_date, 'InputFormat', 'yyyy-MM-dd') + days(1);
    start_str = datestr(start_dt, 'yyyy-mm-dd HH:MM:SS');
    finish_str = datestr(finish_dt, 'yyyy-mm-dd HH:MM:SS');

    src_table = qualify_table(db, [db.table_prefix yyyymm]);
    raw_table = qualify_table(db, [db.raw_table_prefix yyyymm]);

    raw_meta = struct();

    switch lower(vendor)
        case 'zhichen'
            input_cfg = get_vendor_input(wim, 'zhichen');
            [fmt_path, bcp_path] = resolve_zhichen_paths(input_cfg, proj_root, yyyymm);
            ensure_zhichen_table(db, src_table, fmt_path);
            if should_import(db, src_table)
                import_bcp_with_fmt(db, src_table, bcp_path, fmt_path);
            end
            fmt = parse_bcp_fmt(fmt_path);
            raw_meta.mode = 'zhichen';
            raw_meta.headers = {fmt.name};
            raw_meta.raw_table = src_table;
            raw_meta.time_col = 'HSData_DT';
            raw_meta.axle_cols = {};
        case 'jiulongjiang'
            input_cfg = get_vendor_input(wim, 'jiulongjiang');
            files = resolve_jiulongjiang_files(input_cfg, proj_root);
            stage_dir = fullfile(out_dir, '_db_stage');
            if ~exist(stage_dir, 'dir'), mkdir(stage_dir); end
            [norm_csv, raw_csv, raw_meta] = build_jiulongjiang_stage(files, stage_dir);
            ensure_normalized_table(db, src_table);
            ensure_raw_table(db, raw_table, raw_meta.headers);
            if should_import(db, src_table)
                bulk_insert_csv(db, src_table, norm_csv);
            end
            if should_import(db, raw_table)
                bulk_insert_csv(db, raw_table, raw_csv);
            end
            raw_meta.mode = 'jiulongjiang';
            raw_meta.raw_table = raw_table;
        otherwise
            error('Unsupported wim.vendor: %s', vendor);
    end

    csv_paths = run_wim_sql_reports(db, wim, out_dir, yyyymm, src_table, start_str, finish_str, raw_meta);

    excel_name = get_field_default(wim, 'excel_name', 'WIM_Report_{bridge}_{yyyymm}.xlsx');
    excel_name = strrep(excel_name, '{bridge}', bridge);
    excel_name = strrep(excel_name, '{yyyymm}', yyyymm);
    excel_path = fullfile(out_dir, excel_name);
    write_excel_from_csvs(csv_paths, excel_path);
    fprintf('WIM reports done (database): %s\n', excel_path);
end

function db = get_wim_db_cfg(wim, cfg, proj_root)
    db = struct();
    if isfield(cfg, 'wim_db') && isstruct(cfg.wim_db)
        db = cfg.wim_db;
    end
    if isfield(wim, 'db') && isstruct(wim.db)
        db = merge_struct(db, wim.db);
    end
    db = fill_default(db, 'server', '.\\SQLEXPRESS');
    db = fill_default(db, 'database', 'HighSpeed_PROC');
    db = fill_default(db, 'schema', 'dbo');
    db = fill_default(db, 'table_prefix', 'HS_Data_');
    db = fill_default(db, 'raw_table_prefix', 'WIM_Raw_');
    db = fill_default(db, 'import_mode', 'truncate');
    db = fill_default(db, 'scripts_dir', fullfile('scripts', 'wim_sql'));
    db = fill_default(db, 'auth', 'windows');
    db = fill_default(db, 'sqlcmd_utf8', true);
    db = fill_default(db, 'trust_server_cert', true);
    db.scripts_dir = resolve_path(proj_root, db.scripts_dir);
end

function out = merge_struct(a, b)
    out = a;
    if ~isstruct(b), return; end
    f = fieldnames(b);
    for i = 1:numel(f)
        out.(f{i}) = b.(f{i});
    end
end

function ok = should_import(db, table_name)
    mode = lower(get_field_default(db, 'import_mode', 'truncate'));
    switch mode
        case 'skip_if_exists'
            if sql_table_exists(db, table_name)
                if sql_table_has_rows(db, table_name)
                    ok = false;
                    return;
                end
            end
            ok = true;
        otherwise
            ok = true;
    end
end

function ensure_zhichen_table(db, table_name, fmt_path)
    if ~sql_table_exists(db, table_name)
        sql = create_table_sql_from_fmt(table_name, fmt_path, db);
        run_sqlcmd_query(db, sql);
    elseif strcmpi(get_field_default(db, 'import_mode', 'truncate'), 'truncate')
        run_sqlcmd_query(db, sprintf('TRUNCATE TABLE %s;', quote_table_name(table_name)));
    end
end

function ensure_normalized_table(db, table_name)
    if ~sql_table_exists(db, table_name)
        sql = create_normalized_table_sql(table_name);
        run_sqlcmd_query(db, sql);
    elseif strcmpi(get_field_default(db, 'import_mode', 'truncate'), 'truncate')
        run_sqlcmd_query(db, sprintf('TRUNCATE TABLE %s;', quote_table_name(table_name)));
    end
end

function ensure_raw_table(db, table_name, raw_headers)
    if ~sql_table_exists(db, table_name)
        sql = create_raw_table_sql(table_name, raw_headers);
        run_sqlcmd_query(db, sql);
    elseif strcmpi(get_field_default(db, 'import_mode', 'truncate'), 'truncate')
        run_sqlcmd_query(db, sprintf('TRUNCATE TABLE %s;', quote_table_name(table_name)));
    end
end

function import_bcp_with_fmt(db, table_name, bcp_path, fmt_path)
    bcp_path = escape_sql_literal(bcp_path);
    fmt_path = escape_sql_literal(fmt_path);
    sql = sprintf(['BULK INSERT %s FROM ''%s'' WITH (' ...
        'FORMATFILE = ''%s'', TABLOCK, BATCHSIZE = 50000, KEEPIDENTITY);'], ...
        quote_table_name(table_name), bcp_path, fmt_path);
    run_sqlcmd_query(db, sql);
end

function bulk_insert_csv(db, table_name, csv_path)
    csv_path = escape_sql_literal(csv_path);
    sql = sprintf(['BULK INSERT %s FROM ''%s'' WITH (' ...
        'FIRSTROW = 2, FIELDTERMINATOR = ''\\t'', ROWTERMINATOR = ''0x0d0a'', ' ...
        'CODEPAGE = ''65001'', TABLOCK, BATCHSIZE = 50000);'], ...
        quote_table_name(table_name), csv_path);
    run_sqlcmd_query(db, sql);
end

function [norm_csv, raw_csv, meta] = build_jiulongjiang_stage(files, stage_dir)
    norm_csv = fullfile(stage_dir, 'jiulongjiang_norm.tsv');
    raw_csv = fullfile(stage_dir, 'jiulongjiang_raw.tsv');
    if exist(norm_csv, 'file'), delete(norm_csv); end
    if exist(raw_csv, 'file'), delete(raw_csv); end

    meta = struct();
    meta.headers = {};
    meta.axle_cols = {};
    meta.time_col = '';

    row_id = 0;
    for fi = 1:numel(files)
        tbl = readtable(files{fi}, 'VariableNamingRule', 'preserve');
        if isempty(tbl), continue; end

        if isempty(meta.headers)
            meta.headers = tbl.Properties.VariableNames;
        end

        cols = resolve_jiulongjiang_columns(tbl);
        if isempty(meta.time_col) && ~isempty(cols.time)
            meta.time_col = tbl.Properties.VariableNames{cols.time};
        end
        if isempty(meta.axle_cols)
            idxs = cols.axle_weights;
            idxs = idxs(idxs > 0);
            if ~isempty(idxs)
                meta.axle_cols = tbl.Properties.VariableNames(idxs);
            end
        end

        n = height(tbl);
        ids = (1:n).' + row_id;
        row_id = row_id + n;

        t_dn = get_time_column(tbl, cols.time);
        dt = datetime(t_dn, 'ConvertFrom', 'datenum');
        dt.Format = 'yyyy-MM-dd HH:mm:ss.SSS';

        lane = resolve_lane(tbl, cols);
        gross = get_numeric_column(tbl, cols.gross, n);
        speed = get_numeric_column(tbl, cols.speed, n);
        axle_num = get_numeric_column(tbl, cols.axle_num, n);
        axle_w = resolve_axle_weights(tbl, cols.axle_weights);
        axle_d = resolve_axle_dists(tbl, cols.axle_dists);
        plate = resolve_plate(tbl, cols);

        L = axle_w;
        R = zeros(size(axle_w));

        Tnorm = table(ids, lane, dt, axle_num, gross, speed, plate, ...
            L(:,1), L(:,2), L(:,3), L(:,4), L(:,5), L(:,6), L(:,7), L(:,8), ...
            R(:,1), R(:,2), R(:,3), R(:,4), R(:,5), R(:,6), R(:,7), R(:,8), ...
            axle_d(:,1), axle_d(:,2), axle_d(:,3), axle_d(:,4), axle_d(:,5), axle_d(:,6), axle_d(:,7), ...
            'VariableNames', {'HSData_Id','Lane_Id','HSData_DT','Axle_Num','Gross_Load','Speed','License_Plate', ...
            'LWheel_1_W','LWheel_2_W','LWheel_3_W','LWheel_4_W','LWheel_5_W','LWheel_6_W','LWheel_7_W','LWheel_8_W', ...
            'RWheel_1_W','RWheel_2_W','RWheel_3_W','RWheel_4_W','RWheel_5_W','RWheel_6_W','RWheel_7_W','RWheel_8_W', ...
            'AxleDis1','AxleDis2','AxleDis3','AxleDis4','AxleDis5','AxleDis6','AxleDis7'});

        write_tsv(raw_csv, tbl, fi == 1);
        write_tsv(norm_csv, Tnorm, fi == 1);
    end
end

function write_tsv(path, T, write_header)
    if nargin < 3, write_header = true; end
    if write_header
        writetable(T, path, 'Delimiter', '\t', 'Encoding', 'UTF-8');
    else
        writetable(T, path, 'Delimiter', '\t', 'Encoding', 'UTF-8', 'WriteMode', 'append', 'WriteVariableNames', false);
    end
end

function sql = create_normalized_table_sql(table_name)
    sql = sprintf(['IF OBJECT_ID(''%s'', ''U'') IS NULL BEGIN ' ...
        'CREATE TABLE %s (' ...
        '[HSData_Id] INT NULL,' ...
        '[Lane_Id] INT NULL,' ...
        '[HSData_DT] DATETIME NULL,' ...
        '[Axle_Num] INT NULL,' ...
        '[Gross_Load] INT NULL,' ...
        '[Speed] INT NULL,' ...
        '[License_Plate] NVARCHAR(50) NULL,' ...
        '[LWheel_1_W] INT NULL,[LWheel_2_W] INT NULL,[LWheel_3_W] INT NULL,[LWheel_4_W] INT NULL,' ...
        '[LWheel_5_W] INT NULL,[LWheel_6_W] INT NULL,[LWheel_7_W] INT NULL,[LWheel_8_W] INT NULL,' ...
        '[RWheel_1_W] INT NULL,[RWheel_2_W] INT NULL,[RWheel_3_W] INT NULL,[RWheel_4_W] INT NULL,' ...
        '[RWheel_5_W] INT NULL,[RWheel_6_W] INT NULL,[RWheel_7_W] INT NULL,[RWheel_8_W] INT NULL,' ...
        '[AxleDis1] INT NULL,[AxleDis2] INT NULL,[AxleDis3] INT NULL,[AxleDis4] INT NULL,' ...
        '[AxleDis5] INT NULL,[AxleDis6] INT NULL,[AxleDis7] INT NULL' ...
        '); END;'], object_id_name(table_name), quote_table_name(table_name));
end

function sql = create_raw_table_sql(table_name, headers)
    cols = cell(1, numel(headers));
    for i = 1:numel(headers)
        name = headers{i};
        if isempty(name)
            name = sprintf('Var%d', i);
        end
        cols{i} = sprintf('%s NVARCHAR(255) NULL', quote_identifier(name));
    end
    col_sql = strjoin(cols, ',');
    sql = sprintf('IF OBJECT_ID(''%s'', ''U'') IS NULL BEGIN CREATE TABLE %s (%s); END;', ...
        object_id_name(table_name), quote_table_name(table_name), col_sql);
end

function sql = create_table_sql_from_fmt(table_name, fmt_path, db)
    fmt = parse_bcp_fmt(fmt_path);
    cols = cell(1, numel(fmt));
    for i = 1:numel(fmt)
        cols{i} = sprintf('%s %s NULL', quote_identifier(fmt(i).name), map_fmt_type(fmt(i)));
    end
    col_sql = strjoin(cols, ',');
    sql = sprintf('IF OBJECT_ID(''%s'', ''U'') IS NULL BEGIN CREATE TABLE %s (%s); END;', ...
        object_id_name(table_name), quote_table_name(table_name), col_sql);
end

function t = map_fmt_type(spec)
    switch upper(spec.type)
        case 'SQLINT'
            t = 'INT';
        case 'SQLTINYINT'
            t = 'TINYINT';
        case 'SQLSMALLINT'
            t = 'SMALLINT';
        case 'SQLBIGINT'
            t = 'BIGINT';
        case 'SQLDATETIME'
            t = 'DATETIME';
        case 'SQLCHAR'
            t = sprintf('VARCHAR(%d)', spec.len);
        case 'SQLNCHAR'
            t = sprintf('NVARCHAR(%d)', spec.len);
        case 'SQLNUMERIC'
            t = sprintf('NUMERIC(%d,0)', max(1, min(38, spec.len)));
        case 'SQLFLT4'
            t = 'REAL';
        case 'SQLFLT8'
            t = 'FLOAT';
        otherwise
            t = 'NVARCHAR(255)';
    end
end

function csv_paths = run_wim_sql_reports(db, wim, out_dir, yyyymm, src_table, start_str, finish_str, raw_meta)
    vars = struct();
    vars.SrcTable = src_table;
    vars.Start = start_str;
    vars.Finish = finish_str;
    vars.LaneText = join_num_list(wim.lanes);
    vars.UpLanes = join_num_list(wim.up_lanes);
    vars.SpeedBins = join_num_list(wim.speed_bins);
    vars.GrossBins = join_num_list(wim.gross_bins);
    vars.HourBins = join_num_list(wim.hour_bins);
    vars.CustomWeights = join_num_list(wim.custom_weights);
    vars.CriticalLanes = join_num_list(wim.critical_lanes);
    vars.HourlyCriticalWeight = double(wim.hourly_critical_weight_kg);
    vars.TopN = double(wim.topn);
    vars.DesignTotal = double(wim.design_total_kg);
    vars.DesignAxle = double(wim.design_axle_kg);
    vars.OverloadFactors = join_num_list(wim.overload_factors);

    script_dir = db.scripts_dir;
    csv_paths = struct();

    csv_paths.DailyTraffic = run_sql_report(db, fullfile(script_dir, 'report_daily_traffic.sql'), ...
        fullfile(out_dir, sprintf('%s_DailyTraffic.csv', yyyymm)), vars, ...
        {'date','up_cnt','down_cnt','total'});

    csv_paths.LaneSpeedWeight_Lane = run_sql_report(db, fullfile(script_dir, 'report_lane_distribution.sql'), ...
        fullfile(out_dir, sprintf('%s_LaneSpeedWeight_Lane.csv', yyyymm)), vars, ...
        {'lane','count'});

    csv_paths.LaneSpeedWeight_Speed = run_sql_report(db, fullfile(script_dir, 'report_speed_bins.sql'), ...
        fullfile(out_dir, sprintf('%s_LaneSpeedWeight_Speed.csv', yyyymm)), vars, ...
        {'bin_id','label','count'});

    csv_paths.LaneSpeedWeight_Gross = run_sql_report(db, fullfile(script_dir, 'report_gross_bins.sql'), ...
        fullfile(out_dir, sprintf('%s_LaneSpeedWeight_Gross.csv', yyyymm)), vars, ...
        {'bin_id','label','count'});

    csv_paths.Hourly_Count = run_sql_report(db, fullfile(script_dir, 'report_hourly_count.sql'), ...
        fullfile(out_dir, sprintf('%s_Hourly_Count.csv', yyyymm)), vars, ...
        {'bin_id','label','count'});

    csv_paths.Hourly_AvgSpeed = run_sql_report(db, fullfile(script_dir, 'report_hourly_avgspeed.sql'), ...
        fullfile(out_dir, sprintf('%s_Hourly_AvgSpeed.csv', yyyymm)), vars, ...
        {'bin_id','label','avg_speed'});

    csv_paths.Hourly_Over = run_sql_report(db, fullfile(script_dir, 'report_hourly_over.sql'), ...
        fullfile(out_dir, sprintf('%s_Hourly_Over.csv', yyyymm)), vars, ...
        {'bin_id','label','over_cnt'});

    csv_paths.CustomThresholds_Overall = run_sql_report(db, fullfile(script_dir, 'report_custom_overall.sql'), ...
        fullfile(out_dir, sprintf('%s_CustomThresholds_Overall.csv', yyyymm)), vars, ...
        {'weight_threshold','over_cnt'});

    csv_paths.CustomThresholds_PerLane = run_sql_report(db, fullfile(script_dir, 'report_custom_per_lane.sql'), ...
        fullfile(out_dir, sprintf('%s_CustomThresholds_PerLane.csv', yyyymm)), vars, ...
        {'lane','weight_threshold','over_cnt'});

    csv_paths.TopN = run_sql_report(db, fullfile(script_dir, 'report_topn_gross.sql'), ...
        fullfile(out_dir, sprintf('%s_TopN.csv', yyyymm)), vars, ...
        topn_headers());

    csv_paths.TopN_MaxAxle = run_sql_report(db, fullfile(script_dir, 'report_topn_max_axle.sql'), ...
        fullfile(out_dir, sprintf('%s_TopN_MaxAxle.csv', yyyymm)), vars, ...
        topn_headers());

    csv_paths.Overload_Summary = run_sql_report(db, fullfile(script_dir, 'report_overload_summary.sql'), ...
        fullfile(out_dir, sprintf('%s_Overload_Summary.csv', yyyymm)), vars, ...
        {'type','threshold_kg','count'});

    csv_paths.TopN_MaxAxle_Raw = write_topn_max_axle_raw(db, out_dir, yyyymm, src_table, vars, raw_meta);
end

function headers = topn_headers()
    headers = {'rank','lane','time','axle_num','gross_kg','speed_kmh','plate', ...
        'axle1','axle2','axle3','axle4','axle5','axle6','axle7','axle8', ...
        'axledis1','axledis2','axledis3','axledis4','axledis5','axledis6','axledis7'};
end

function csv_path = write_topn_max_axle_raw(db, out_dir, yyyymm, src_table, vars, raw_meta)
    csv_path = fullfile(out_dir, sprintf('%s_TopN_MaxAxle_Raw.csv', yyyymm));
    tmp_path = [csv_path '.tmp'];
    if strcmpi(raw_meta.mode, 'zhichen')
        script = fullfile(db.scripts_dir, 'report_topn_max_axle_raw.sql');
        run_sqlcmd_file(db, script, tmp_path, vars);
        prepend_csv_header(raw_meta.headers, tmp_path, csv_path);
        return;
    end
    if ~isfield(raw_meta, 'raw_table') || isempty(raw_meta.raw_table) || isempty(raw_meta.headers)
        if exist(tmp_path, 'file'), delete(tmp_path); end
        writecell({}, csv_path, 'Encoding','UTF-8');
        return;
    end
    time_col = raw_meta.time_col;
    axle_cols = raw_meta.axle_cols;
    if isempty(time_col) || isempty(axle_cols)
        writecell({}, csv_path, 'Encoding','UTF-8');
        return;
    end
    select_cols = cellfun(@quote_identifier, raw_meta.headers, 'UniformOutput', false);
    select_sql = strjoin(select_cols, ',');
    axle_vals = cellfun(@(c) sprintf('(TRY_CONVERT(float,%s))', quote_identifier(c)), axle_cols, 'UniformOutput', false);
    axle_sql = strjoin(axle_vals, ',');
    sql = sprintf(['SELECT TOP (%d) %s FROM %s AS r ' ...
        'CROSS APPLY (SELECT MAX(v) AS max_axle FROM (VALUES %s) AS A(v)) AS mx ' ...
        'WHERE TRY_CONVERT(datetime2,%s) >= ''%s'' AND TRY_CONVERT(datetime2,%s) < ''%s'' ' ...
        'ORDER BY mx.max_axle DESC, TRY_CONVERT(datetime2,%s) ASC;'], ...
        vars.TopN, select_sql, quote_table_name(raw_meta.raw_table), axle_sql, ...
        quote_identifier(time_col), vars.Start, quote_identifier(time_col), vars.Finish, ...
        quote_identifier(time_col));
    run_sqlcmd_query_to_file(db, sql, tmp_path);
    prepend_csv_header(raw_meta.headers, tmp_path, csv_path);
end

function csv_path = run_sql_report(db, script_path, out_path, vars, header)
    tmp_path = [out_path '.tmp'];
    run_sqlcmd_file(db, script_path, tmp_path, vars);
    prepend_csv_header(header, tmp_path, out_path);
    csv_path = out_path;
end

function run_sqlcmd_file(db, script_path, out_path, vars)
    if ~exist(script_path, 'file')
        error('SQL script not found: %s', script_path);
    end
    args = sprintf('-i \"%s\" -o \"%s\" -s , -W -h -1 -w 65535', script_path, out_path);
    [status, out] = run_sqlcmd_system(db, args, vars);
    if status ~= 0
        error('sqlcmd failed: %s', out);
    end
end

function run_sqlcmd_query(db, sql)
    [status, out] = run_sqlcmd_system(db, sprintf('-Q \"%s\" -h -1 -W', escape_cmd_sql(sql)), struct());
    if status ~= 0
        error('sqlcmd failed: %s', out);
    end
end

function run_sqlcmd_query_to_file(db, sql, out_path)
    [status, out] = run_sqlcmd_system(db, sprintf('-Q \"%s\" -o \"%s\" -s , -W -h -1 -w 65535', ...
        escape_cmd_sql(sql), out_path), struct());
    if status ~= 0
        error('sqlcmd failed: %s', out);
    end
end

function cmd = build_sqlcmd_cmd(db, extra_args, vars, use_utf8)
    exe = find_sqlcmd();
    cmd = sprintf('\"%s\" -S \"%s\" -d \"%s\" -E -b', exe, db.server, db.database);
    if isfield(db, 'trust_server_cert') && db.trust_server_cert
        cmd = sprintf('%s -C', cmd);
    end
    if use_utf8
        cmd = sprintf('%s -f 65001', cmd);
    end
    if ~isempty(extra_args)
        cmd = sprintf('%s %s', cmd, extra_args);
    end
    if nargin >= 3 && ~isempty(vars)
        cmd = sprintf('%s %s', cmd, build_sqlcmd_vars(vars));
    end
end

function args = build_sqlcmd_vars(vars)
    args = '';
    if isempty(vars), return; end
    keys = fieldnames(vars);
    for i = 1:numel(keys)
        k = keys{i};
        v = vars.(k);
        if isnumeric(v)
            vstr = num2str(v);
            args = sprintf('%s -v %s=%s', args, k, vstr);
        else
            vstr = char(v);
            vstr = strrep(vstr, '"', '""');
            args = sprintf('%s -v %s=\"%s\"', args, k, vstr);
        end
    end
end

function exe = find_sqlcmd()
    candidates = { ...
        'sqlcmd', ...
        fullfile(getenv('ProgramFiles'), 'Microsoft SQL Server', 'Client SDK', 'ODBC', '190', 'Tools', 'Binn', 'sqlcmd.exe'), ...
        fullfile(getenv('ProgramFiles'), 'Microsoft SQL Server', 'Client SDK', 'ODBC', '180', 'Tools', 'Binn', 'sqlcmd.exe'), ...
        fullfile(getenv('ProgramFiles'), 'Microsoft SQL Server', 'Client SDK', 'ODBC', '170', 'Tools', 'Binn', 'sqlcmd.exe'), ...
        fullfile(getenv('ProgramFiles'), 'Microsoft SQL Server', 'Client SDK', 'ODBC', '130', 'Tools', 'Binn', 'sqlcmd.exe'), ...
        fullfile(getenv('ProgramFiles(x86)'), 'Microsoft SQL Server', 'Client SDK', 'ODBC', '170', 'Tools', 'Binn', 'sqlcmd.exe'), ...
        fullfile(getenv('ProgramFiles(x86)'), 'Microsoft SQL Server', 'Client SDK', 'ODBC', '130', 'Tools', 'Binn', 'sqlcmd.exe')};
    exe = '';
    for i = 1:numel(candidates)
        if exist(candidates{i}, 'file')
            exe = candidates{i};
            return;
        end
    end
    if isempty(exe)
        error('sqlcmd not found. Please install SQL Server command line utilities or add sqlcmd to PATH.');
    end
end

function out = join_num_list(v)
    if isempty(v)
        out = '';
        return;
    end
    if isstring(v) || ischar(v)
        out = char(v);
        return;
    end
    out = strjoin(arrayfun(@(x) num2str(x), v(:).', 'UniformOutput', false), ',');
end

function ok = sql_table_exists(db, table_name)
    sql = sprintf('SET NOCOUNT ON; IF OBJECT_ID(''%s'',''U'') IS NULL SELECT 0 ELSE SELECT 1;', ...
        object_id_name(table_name));
    out = run_sqlcmd_capture(db, sql);
    ok = str2double(strtrim(out)) == 1;
end

function ok = sql_table_has_rows(db, table_name)
    sql = sprintf('SET NOCOUNT ON; SELECT COUNT(1) FROM %s;', quote_table_name(table_name));
    out = run_sqlcmd_capture(db, sql);
    ok = str2double(strtrim(out)) > 0;
end

function out = run_sqlcmd_capture(db, sql)
    [status, out] = run_sqlcmd_system(db, sprintf('-Q \"%s\" -h -1 -W', escape_cmd_sql(sql)), struct());
    if status ~= 0
        error('sqlcmd failed: %s', out);
    end
    out = strtrim(out);
    % sqlcmd may include localized "(x rows affected)" lines; keep first numeric token.
    tokens = regexp(out, '[-+]?\d+(\.\d+)?', 'match');
    if ~isempty(tokens)
        out = tokens{1};
    end
end

function [status, out] = run_sqlcmd_system(db, args, vars)
    cmd = build_sqlcmd_cmd(db, args, vars, db.sqlcmd_utf8);
    [status, out] = system(cmd);
    if status ~= 0 && db.sqlcmd_utf8
        cmd = build_sqlcmd_cmd(db, args, vars, false);
        [status, out] = system(cmd);
    end
end

function name = qualify_table(db, table_name)
    name = sprintf('%s.%s.%s', db.database, db.schema, table_name);
end

function q = quote_table_name(table_name)
    parts = strsplit(table_name, '.');
    parts = cellfun(@quote_identifier, parts, 'UniformOutput', false);
    q = strjoin(parts, '.');
end

function q = quote_identifier(name)
    name = char(name);
    name = strrep(name, ']', ']]');
    q = ['[' name ']'];
end

function name = object_id_name(table_name)
    parts = strsplit(table_name, '.');
    if numel(parts) >= 2
        name = sprintf('%s.%s', parts{end-1}, parts{end});
    else
        name = table_name;
    end
end

function s = escape_sql_literal(s)
    s = char(s);
    s = strrep(s, '''', '''''');
end

function s = escape_cmd_sql(s)
    s = strrep(s, '"', '""');
end

function prepend_csv_header(header, tmp_path, out_path)
    if isempty(header)
        movefile(tmp_path, out_path, 'f');
        return;
    end
    enc = detect_file_encoding(tmp_path);
    [fid_in, msg] = fopen(tmp_path, 'rb');
    if fid_in < 0
        error('Cannot open tmp file: %s', msg);
    end
    bytes = fread(fid_in, inf, 'uint8=>uint8');
    fclose(fid_in);

    % Strip BOM if present in tmp
    if numel(bytes) >= 3 && bytes(1)==239 && bytes(2)==187 && bytes(3)==191
        bytes = bytes(4:end);
    elseif numel(bytes) >= 2 && bytes(1)==255 && bytes(2)==254
        bytes = bytes(3:end);
    end

    [fid_out, msg] = fopen(out_path, 'wb');
    if fid_out < 0
        error('Cannot write csv: %s', msg);
    end

    if strcmpi(enc, 'UTF-16LE')
        fwrite(fid_out, uint8([255 254]), 'uint8');
        header_line = strjoin(header, ',');
        fwrite(fid_out, unicode2native([header_line newline], 'UTF-16LE'), 'uint8');
        fwrite(fid_out, bytes, 'uint8');
    else
        fwrite(fid_out, uint8([239 187 191]), 'uint8');
        header_line = strjoin(header, ',');
        fwrite(fid_out, unicode2native([header_line newline], 'UTF-8'), 'uint8');
        fwrite(fid_out, bytes, 'uint8');
    end
    fclose(fid_out);
    delete(tmp_path);
end

function enc = detect_file_encoding(path)
    enc = 'UTF-8';
    fid = fopen(path, 'rb');
    if fid < 0, return; end
    bytes = fread(fid, 3, 'uint8=>uint8');
    fclose(fid);
    if numel(bytes) >= 2 && bytes(1)==255 && bytes(2)==254
        enc = 'UTF-16LE';
    elseif numel(bytes) >= 3 && bytes(1)==239 && bytes(2)==187 && bytes(3)==191
        enc = 'UTF-8';
    end
end
