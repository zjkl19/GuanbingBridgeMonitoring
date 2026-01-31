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
    vendor = resolve_vendor(wim);
    bridge = get_field_default(wim, 'bridge', get_field_default(cfg, 'vendor', 'bridge'));
    yyyymm = datestr(datetime(start_date, 'InputFormat', 'yyyy-MM-dd'), 'yyyymm');

    proj_root = fileparts(fileparts(mfilename('fullpath')));
    output_root = get_field_default(wim, 'output_root', fullfile(proj_root, 'data', 'output'));
    output_root = resolve_path(proj_root, output_root);
    out_dir = fullfile(output_root, bridge, yyyymm);
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end

    % Initialize accumulators
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
    T = addvars(T, (1:height(T)).', 'Before', 1, 'NewVariableNames','rank');
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
        try
            T = readtable(csv_path, 'TextType','string', 'Encoding','UTF-8');
            writetable(T, excel_path, 'Sheet', safe_sheet_name(name));
        catch
            C = readcell(csv_path, 'Encoding','UTF-8');
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
