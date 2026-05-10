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

    [month_start_dates, month_end_dates] = split_month_ranges(start_date, end_date);
    for i = 1:numel(month_start_dates)
        month_start = datestr(month_start_dates(i), 'yyyy-mm-dd');
        month_end = datestr(month_end_dates(i), 'yyyy-mm-dd');
        fprintf('[WIM] Processing %s to %s\n', month_start, month_end);
        analyze_wim_reports_single_month(root_dir, month_start, month_end, cfg);
    end
end

function analyze_wim_reports_single_month(root_dir, start_date, end_date, cfg)
    wim = get_wim_cfg(cfg);
    pipeline = get_field_default(wim, 'pipeline', 'direct');
    vendor = resolve_vendor(wim);
    bridge = get_field_default(wim, 'bridge', get_field_default(cfg, 'vendor', 'bridge'));
    yyyymm = datestr(datetime(start_date, 'InputFormat', 'yyyy-MM-dd'), 'yyyymm');

    proj_root = fileparts(fileparts(mfilename('fullpath')));
    output_root = resolve_wim_output_root(root_dir, wim, proj_root);
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
            [fmt_path, bcp_path] = resolve_zhichen_paths(input_cfg, proj_root, yyyymm, root_dir);
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
    write_excel_from_csvs(csv_paths, excel_path, bridge);

    fprintf('WIM reports done: %s\n', excel_path);
    maybe_generate_wim_plots(csv_paths, out_dir, wim, cfg, bridge, yyyymm);
end

function [month_starts, month_ends] = split_month_ranges(start_date, end_date)
    start_dt = datetime(start_date, 'InputFormat', 'yyyy-MM-dd');
    end_dt = datetime(end_date, 'InputFormat', 'yyyy-MM-dd');
    if end_dt < start_dt
        error('end_date must be on or after start_date.');
    end

    cursor = dateshift(start_dt, 'start', 'month');
    last_month = dateshift(end_dt, 'start', 'month');
    month_starts = datetime.empty(0, 1);
    month_ends = datetime.empty(0, 1);
    while cursor <= last_month
        seg_start = max(cursor, start_dt);
        seg_end = min(dateshift(cursor, 'end', 'month'), end_dt);
        month_starts(end+1, 1) = seg_start; %#ok<AGROW>
        month_ends(end+1, 1) = seg_end; %#ok<AGROW>
        cursor = cursor + calmonths(1);
    end
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
    if ~is_absolute_path_local(p)
        p = fullfile(base, p);
    end
end

function tf = is_absolute_path_local(p)
    tf = false;
    if isempty(p)
        return;
    end
    if isstring(p), p = char(p); end
    if ~ischar(p)
        return;
    end
    tf = (numel(p) >= 2 && p(2) == ':') || startsWith(p, filesep) || startsWith(p, '\\');
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
function [fmt_path, bcp_path] = resolve_zhichen_paths(input_cfg, base, yyyymm, root_dir)
    fmt_name = get_field_default(input_cfg, 'fmt', ['HS_Data_' yyyymm '.fmt']);
    bcp_name = get_field_default(input_cfg, 'bcp', ['HS_Data_' yyyymm '.bcp']);
    fmt_name = strrep(fmt_name, '{yyyymm}', yyyymm);
    bcp_name = strrep(bcp_name, '{yyyymm}', yyyymm);
    candidate_dirs = {};
    input_dir = get_field_default(input_cfg, 'dir', '');
    if ~isempty(input_dir)
        if is_absolute_path_local(input_dir)
            candidate_dirs{end+1} = input_dir; %#ok<AGROW>
        elseif nargin >= 4 && ~isempty(root_dir)
            candidate_dirs{end+1} = resolve_path(root_dir, input_dir); %#ok<AGROW>
        else
            candidate_dirs{end+1} = resolve_path(base, input_dir); %#ok<AGROW>
        end
    end
    if nargin >= 4 && ~isempty(root_dir)
        candidate_dirs{end+1} = fullfile(root_dir, 'WIM'); %#ok<AGROW>
    end
    candidate_dirs = unique(candidate_dirs, 'stable');

    fmt_path = '';
    bcp_path = '';
    fmt_candidates = {};
    bcp_candidates = {};
    for i = 1:numel(candidate_dirs)
        fmt_i = fullfile(candidate_dirs{i}, fmt_name);
        bcp_i = fullfile(candidate_dirs{i}, bcp_name);
        fmt_candidates{end+1} = fmt_i; %#ok<AGROW>
        bcp_candidates{end+1} = bcp_i; %#ok<AGROW>
        if exist(fmt_i, 'file') && exist(bcp_i, 'file')
            fmt_path = fmt_i;
            bcp_path = bcp_i;
            return;
        end
    end

    for i = 1:numel(fmt_candidates)
        if exist(fmt_candidates{i}, 'file')
            error('WIM:Input:MissingBcp', ...
                'WIM input file missing for %s: bcp file not found: %s', yyyymm, bcp_candidates{i});
        end
    end

    for i = 1:numel(bcp_candidates)
        if exist(bcp_candidates{i}, 'file')
            error('WIM:Input:MissingFmt', ...
                'WIM input file missing for %s: fmt file not found: %s', yyyymm, fmt_candidates{i});
        end
    end

    if isempty(fmt_candidates)
        error('WIM:Input:MissingFmt', ...
            'WIM input file missing for %s: no candidate input directory resolved.', yyyymm);
    end

    error('WIM:Input:MissingFmt', ...
        'WIM input file missing for %s: fmt file not found. Searched: %s', ...
        yyyymm, strjoin(fmt_candidates, '; '));
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
    acc.lane_gross_counts = zeros(numel(lanes), numel(gross_edges)-1);

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

    acc.topn = bms.analyzer.WimAccumulatorService.initTopN(double(wim.topn));
    acc.topn_max_axle = bms.analyzer.WimAccumulatorService.initTopN(double(wim.topn));
    acc.topn_raw_headers = {};

    acc.overload_factors = double(wim.overload_factors(:))';
    acc.design_total = double(wim.design_total_kg);
    acc.design_axle = double(wim.design_axle_kg);
    acc.overload_counts = zeros(2, numel(acc.overload_factors)); % row1: total, row2: axle
end

% =========================
% Vendor processors
% =========================
function acc = process_zhichen_bcp(fmt_path, bcp_path, acc, wim)
    spec = bms.analyzer.WimZhichenBcpSource.loadSpec(fmt_path);
    fmt = spec.fmt;
    idx = spec.index;
    encoding = get_field_default(get_vendor_input(wim, 'zhichen'), 'encoding', 'gbk');

    fid = fopen(bcp_path, 'r', 'ieee-le');
    if fid < 0
        error('Cannot open bcp: %s', bcp_path);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

    while true
        [row_bytes, ok] = bms.analyzer.WimZhichenBcpSource.readRowBytes(fid, fmt);
        if ~ok, break; end

        row = bms.analyzer.WimZhichenBcpSource.decodeRecord(fmt, idx, row_bytes, encoding);
        t_dn = row.time_datenum;
        if isempty(t_dn) || ~isfinite(t_dn), continue; end
        if t_dn < acc.t0 || t_dn >= acc.t1, continue; end

        acc = update_accumulators(acc, t_dn, row.lane, row.gross, row.speed, row.axle_weights, row.axle_num);
        acc = update_overload(acc, row.gross, row.axle_weights);

        std_row = bms.analyzer.WimAccumulatorService.standardRow( ...
            row.lane, t_dn, row.axle_num, row.gross, row.speed, row.plate, row.axle_weights, row.axle_distances);

        acc.topn = bms.analyzer.WimAccumulatorService.updateTopN(acc.topn, row.gross, t_dn, std_row, []);
        [max_axle, ~] = max(row.axle_weights, [], 'omitnan');
        raw_vals = [];
        if bms.analyzer.WimAccumulatorService.qualifiesForTopN(acc.topn_max_axle, max_axle, t_dn)
            raw_vals = bms.analyzer.WimZhichenBcpSource.decodeAllRow(fmt, row_bytes, encoding);
            acc.topn_raw_headers = {fmt.name};
        end
        acc.topn_max_axle = bms.analyzer.WimAccumulatorService.updateTopN(acc.topn_max_axle, max_axle, t_dn, std_row, raw_vals);
    end
end

function acc = process_jiulongjiang_excel(files, acc, wim)
    for fi = 1:numel(files)
        [rows, tbl] = bms.analyzer.WimJiulongjiangExcelSource.readRecords(files{fi});
        if isempty(tbl), continue; end

        t_dn = rows.time_datenum;
        lane = rows.lane;
        gross = rows.gross;
        speed = rows.speed;
        axle_num = rows.axle_num;
        axle_w = rows.axle_weights;
        axle_d = rows.axle_distances;
        plate = rows.plate;

        for i = 1:numel(t_dn)
            if ~isfinite(t_dn(i)), continue; end
            if t_dn(i) < acc.t0 || t_dn(i) >= acc.t1, continue; end

            acc = update_accumulators(acc, t_dn(i), lane(i), gross(i), speed(i), axle_w(i,:), axle_num(i));
            acc = update_overload(acc, gross(i), axle_w(i,:));

            std_row = bms.analyzer.WimAccumulatorService.standardRow(lane(i), t_dn(i), axle_num(i), gross(i), speed(i), plate{i}, axle_w(i,:), axle_d(i,:));
            acc.topn = bms.analyzer.WimAccumulatorService.updateTopN(acc.topn, gross(i), t_dn(i), std_row, []);

            [max_axle, ~] = max(axle_w(i,:), [], 'omitnan');
            raw_row = [];
            if bms.analyzer.WimAccumulatorService.qualifiesForTopN(acc.topn_max_axle, max_axle, t_dn(i))
                raw_row = table2cell(tbl(i,:));
                acc.topn_raw_headers = tbl.Properties.VariableNames;
            end
            acc.topn_max_axle = bms.analyzer.WimAccumulatorService.updateTopN(acc.topn_max_axle, max_axle, t_dn(i), std_row, raw_row);
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
    [labels, counts] = bms.analyzer.WimReportTableService.binTable(acc.speed_edges, acc.speed_counts);
    reports.LaneSpeedWeight_Speed = table((1:numel(counts)).', labels, counts, ...
        'VariableNames', {'bin_id','label','count'});
    [labels, counts] = bms.analyzer.WimReportTableService.binTable(acc.gross_edges, acc.gross_counts);
    reports.LaneSpeedWeight_Gross = table((1:numel(counts)).', labels, counts, ...
        'VariableNames', {'bin_id','label','count'});
    % Per-lane gross bins
    [labels2, ~] = bms.analyzer.WimReportTableService.binTable(acc.gross_edges, acc.gross_counts);
    [lane_grid, bin_grid] = ndgrid(acc.lanes(:), 1:numel(labels2));
    label_grid = repmat(labels2(:).', numel(acc.lanes), 1);
    reports.LaneSpeedWeight_GrossPerLane = table( ...
        lane_grid(:), bin_grid(:), label_grid(:), acc.lane_gross_counts(:), ...
        'VariableNames', {'lane','bin_id','label','count'});

    % Hourly
    [labels, counts] = bms.analyzer.WimReportTableService.binTable(acc.hour_edges, acc.hour_counts);
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
    reports.TopN = bms.analyzer.WimReportTableService.buildTopNTable(acc.topn);
    reports.TopN_MaxAxle = bms.analyzer.WimReportTableService.buildTopNTable(acc.topn_max_axle);

    % Raw topn max axle
    if ~isempty(acc.topn_raw_headers) && ~isempty(acc.topn_max_axle.raw_rows)
        reports.TopN_MaxAxle_Raw = bms.analyzer.WimReportTableService.buildRawTopNTable( ...
            acc.topn_raw_headers, acc.topn_max_axle.raw_rows);
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

function write_excel_from_csvs(csv_paths, excel_path, bridge)
    if nargin < 3, bridge = ''; end
    names = fieldnames(csv_paths);
    if exist(excel_path, 'file')
        delete(excel_path);
    end
    for i = 1:numel(names)
        name = names{i};
        csv_path = csv_paths.(name);
        if ~exist(csv_path,'file'), continue; end
        enc = bms.analyzer.WimSqlService.detectFileEncoding(csv_path);
        try
            T = readtable(csv_path, 'TextType','string', 'Encoding', enc);
            writetable(T, excel_path, 'Sheet', safe_sheet_name(name));
        catch
            C = readcell(csv_path, 'Encoding', enc);
            writecell(C, excel_path, 'Sheet', safe_sheet_name(name));
        end
    end

    if should_write_topn_metric_sheets(bridge)
        write_topn_metric_sheet(csv_paths, excel_path, 'TopN', 'TopN_m');
        write_topn_metric_sheet(csv_paths, excel_path, 'TopN_MaxAxle', 'TopN_MaxAxle_m');
    end
end

function s = safe_sheet_name(name)
    s = regexprep(name, '[:\\/\?\*\[\]]', '_');
    if numel(s) > 31, s = s(1:31); end
end

function tf = should_write_topn_metric_sheets(bridge)
    if isstring(bridge), bridge = char(bridge); end
    tf = ischar(bridge) && strcmpi(strtrim(bridge), 'hongtang');
end

function write_topn_metric_sheet(csv_paths, excel_path, src_name, dst_name)
    if ~isfield(csv_paths, src_name), return; end
    csv_path = csv_paths.(src_name);
    if ~exist(csv_path, 'file'), return; end

    enc = bms.analyzer.WimSqlService.detectFileEncoding(csv_path);
    try
        T = readtable(csv_path, 'TextType', 'string', 'Encoding', enc);
    catch
        return;
    end

    Tm = bms.analyzer.WimReportTableService.convertAxleDistancesMmToM(T);
    writetable(Tm, excel_path, 'Sheet', safe_sheet_name(dst_name));
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
        bi = bms.analyzer.WimAccumulatorService.findBin(speed, acc.speed_edges);
        if bi > 0, acc.speed_counts(bi) = acc.speed_counts(bi) + 1; end
    end

    if isfinite(gross)
        bi = bms.analyzer.WimAccumulatorService.findBin(gross, acc.gross_edges);
        if bi > 0
            acc.gross_counts(bi) = acc.gross_counts(bi) + 1;
            if isfinite(lane) && isKey(acc.lane_map, lane)
                li = acc.lane_map(lane);
                acc.lane_gross_counts(li, bi) = acc.lane_gross_counts(li, bi) + 1;
            end
        end
    end

    hh = floor(mod(t_dn, 1) * 24);
    bi = bms.analyzer.WimAccumulatorService.findBin(hh, acc.hour_edges);
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

% =========================
% Database pipeline
% =========================
function run_wim_database_pipeline(root_dir, start_date, end_date, wim, cfg)
    proj_root = fileparts(fileparts(mfilename('fullpath')));
    db = get_wim_db_cfg(wim, cfg, proj_root);
    bms.analyzer.WimSqlService.ensureServiceRunning(db);

    vendor = resolve_vendor(wim);
    bridge = get_field_default(wim, 'bridge', get_field_default(cfg, 'vendor', 'bridge'));
    yyyymm = datestr(datetime(start_date, 'InputFormat', 'yyyy-MM-dd'), 'yyyymm');

    output_root = resolve_wim_output_root(root_dir, wim, proj_root);
    out_dir = fullfile(output_root, bridge, yyyymm);
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end

    start_dt = datetime(start_date, 'InputFormat', 'yyyy-MM-dd');
    finish_dt = datetime(end_date, 'InputFormat', 'yyyy-MM-dd') + days(1);
    start_str = datestr(start_dt, 'yyyy-mm-dd HH:MM:SS');
    finish_str = datestr(finish_dt, 'yyyy-mm-dd HH:MM:SS');

    src_table = bms.analyzer.WimSqlService.qualifyTable(db, [db.table_prefix yyyymm]);
    raw_table = bms.analyzer.WimSqlService.qualifyTable(db, [db.raw_table_prefix yyyymm]);

    raw_meta = struct();

    switch lower(vendor)
        case 'zhichen'
            input_cfg = get_vendor_input(wim, 'zhichen');
            [fmt_path, bcp_path] = resolve_zhichen_paths(input_cfg, proj_root, yyyymm, root_dir);
            bms.analyzer.WimSqlService.ensureZhichenTable(db, src_table, fmt_path);
            if bms.analyzer.WimSqlService.shouldImport(db, src_table)
                bms.analyzer.WimSqlService.importBcpWithFmt(db, src_table, bcp_path, fmt_path);
            end
            fmt = bms.analyzer.WimZhichenBcpSource.parseFmt(fmt_path);
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
            [norm_csv, raw_csv, raw_meta] = bms.analyzer.WimJiulongjiangExcelSource.buildStage(files, stage_dir);
            bms.analyzer.WimSqlService.ensureNormalizedTable(db, src_table);
            bms.analyzer.WimSqlService.ensureRawTable(db, raw_table, raw_meta.headers);
            if bms.analyzer.WimSqlService.shouldImport(db, src_table)
                bms.analyzer.WimSqlService.bulkInsertCsv(db, src_table, norm_csv);
            end
            if bms.analyzer.WimSqlService.shouldImport(db, raw_table)
                bms.analyzer.WimSqlService.bulkInsertCsv(db, raw_table, raw_csv);
            end
            raw_meta.mode = 'jiulongjiang';
            raw_meta.raw_table = raw_table;
        otherwise
            error('Unsupported wim.vendor: %s', vendor);
    end

    csv_paths = bms.analyzer.WimSqlService.runReports(db, wim, out_dir, yyyymm, src_table, start_str, finish_str, raw_meta);

    excel_name = get_field_default(wim, 'excel_name', 'WIM_Report_{bridge}_{yyyymm}.xlsx');
    excel_name = strrep(excel_name, '{bridge}', bridge);
    excel_name = strrep(excel_name, '{yyyymm}', yyyymm);
    excel_path = fullfile(out_dir, excel_name);
    write_excel_from_csvs(csv_paths, excel_path, bridge);
    fprintf('WIM reports done (database): %s\n', excel_path);

    maybe_generate_wim_plots(csv_paths, out_dir, wim, cfg, bridge, yyyymm);
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
    db = fill_default(db, 'service_name', 'MSSQLSERVER');
    db = fill_default(db, 'auth', 'windows');
    db = fill_default(db, 'sqlcmd_utf8', true);
    db = fill_default(db, 'trust_server_cert', true);
    db.scripts_dir = resolve_path(proj_root, db.scripts_dir);
end

function output_root = resolve_wim_output_root(root_dir, wim, proj_root)
    configured = get_field_default(wim, 'output_root', '');
    if isempty(configured)
        output_root = fullfile(root_dir, 'WIM', 'results');
        return;
    end
    if is_absolute_path_local(configured)
        output_root = configured;
        return;
    end
    output_root = resolve_path(root_dir, configured);
    if strcmp(output_root, configured)
        output_root = resolve_path(proj_root, configured);
    end
end

function out = merge_struct(a, b)
    out = a;
    if ~isstruct(b), return; end
    f = fieldnames(b);
    for i = 1:numel(f)
        out.(f{i}) = b.(f{i});
    end
end

% =========================
% Plotting (WIM)
% =========================
function maybe_generate_wim_plots(csv_paths, out_dir, wim, cfg, bridge, yyyymm)
    plot_cfg = get_wim_plot_cfg(cfg, wim);
    if ~plot_cfg.enabled
        return;
    end

    plot_dir = fullfile(out_dir, plot_cfg.output_dir);
    if ~exist(plot_dir, 'dir'), mkdir(plot_dir); end

    defs = load_wim_plot_defs(plot_cfg.excel_path, plot_cfg.sheet);
    if isempty(defs)
        fprintf('[WIM] No plot defs found: %s\n', plot_cfg.excel_path);
        return;
    end

    summary_path = fullfile(plot_dir, sprintf('WIM_Plot_Summary_%s_%s.txt', bridge, yyyymm));
    fid = fopen(summary_path, 'w', 'n', 'UTF-8');
    if fid < 0
        fprintf('[WIM] Cannot write summary: %s\n', summary_path);
        fid = [];
    end

    lane_template = [];
    for i = 1:numel(defs)
        if contains(defs(i).name, "车道") && contains(defs(i).name, "不同车重区间车辆数")
            lane_template = defs(i);
            break;
        end
    end

    for i = 1:numel(defs)
        def = defs(i);
        if contains(def.name, "车道") && contains(def.name, "不同车重区间车辆数")
            continue; % handled by template
        end
        [xlabels, yvals, ylabel, title] = resolve_plot_data(def.name, csv_paths, wim, plot_cfg);
        if isempty(yvals)
            continue;
        end
        fig_px = plot_cfg.fig_size_px;
        if isfield(plot_cfg, 'fig_size_per_plot') && isstruct(plot_cfg.fig_size_per_plot)
            key = make_field_key(def.name);
            if isfield(plot_cfg.fig_size_per_plot, key)
                fig_px = plot_cfg.fig_size_per_plot.(key);
            end
        end
        if isfield(plot_cfg, 'fig_size_list') && ~isempty(plot_cfg.fig_size_list)
            sz = lookup_figsize_list(plot_cfg.fig_size_list, def.name);
            if ~isempty(sz)
                fig_px = sz;
            end
        end
        out_name = sprintf('WIM_%s_%s_%s.%s', safe_name(def.name), bridge, yyyymm, plot_cfg.format);
        out_path = fullfile(plot_dir, out_name);
        plot_bar_chart(out_path, title, ylabel, xlabels, yvals, def.show_pct, def.dtype, plot_cfg, fig_px);
        write_plot_summary(fid, title, xlabels, yvals, def.dtype, def.show_pct, plot_cfg);
    end

    if ~isempty(lane_template)
        if isfield(csv_paths, 'LaneSpeedWeight_GrossPerLane') && exist(csv_paths.LaneSpeedWeight_GrossPerLane, 'file')
            T = readtable(csv_paths.LaneSpeedWeight_GrossPerLane, 'TextType','string', 'Encoding','UTF-8');
            lanes = unique(T.lane);
            labels = string(T.label);
            for li = 1:numel(lanes)
                lane = lanes(li);
                mask = T.lane == lane;
                [~, order] = sort(T.bin_id(mask));
                yvals = T.count(mask);
                yvals = yvals(order);
                xlabels = labels(mask);
                xlabels = xlabels(order);
                title = regexprep(lane_template.name, "车道\d+", sprintf("车道%d", lane));
                fig_px = plot_cfg.fig_size_px;
                if isfield(plot_cfg, 'fig_size_per_plot') && isstruct(plot_cfg.fig_size_per_plot)
                    key = make_field_key(title);
                    if isfield(plot_cfg.fig_size_per_plot, key)
                        fig_px = plot_cfg.fig_size_per_plot.(key);
                    end
                end
                if isfield(plot_cfg, 'fig_size_list') && ~isempty(plot_cfg.fig_size_list)
                    sz = lookup_figsize_list(plot_cfg.fig_size_list, title);
                    if ~isempty(sz)
                        fig_px = sz;
                    end
                end
                out_name = sprintf('WIM_%s_%s_%s.%s', safe_name(title), bridge, yyyymm, plot_cfg.format);
                out_path = fullfile(plot_dir, out_name);
                plot_bar_chart(out_path, title, lane_template.ylabel, xlabels, yvals, lane_template.show_pct, lane_template.dtype, plot_cfg, fig_px);
                write_plot_summary(fid, title, xlabels, yvals, lane_template.dtype, lane_template.show_pct, plot_cfg);
            end
        end
    end

    if ~isempty(fid)
        fclose(fid);
    end
end

function plot_cfg = get_wim_plot_cfg(cfg, wim)
    plot_cfg = struct();
    if isfield(cfg, 'wim_plot') && isstruct(cfg.wim_plot)
        plot_cfg = cfg.wim_plot;
    end
    if isfield(wim, 'plot') && isstruct(wim.plot)
        plot_cfg = merge_struct(plot_cfg, wim.plot);
    end
    plot_cfg = fill_default(plot_cfg, 'enabled', false);
    plot_cfg = fill_default(plot_cfg, 'output_dir', 'plots');
    plot_cfg = fill_default(plot_cfg, 'format', 'png');
    plot_cfg = fill_default(plot_cfg, 'excel_path', fullfile('data','python','动态称重.xlsx'));
    plot_cfg = fill_default(plot_cfg, 'sheet', 'Sheet1');
    plot_cfg = fill_default(plot_cfg, 'fig_size_px', [900, 600]);
    plot_cfg = fill_default(plot_cfg, 'y_decimals', 0);
    plot_cfg = fill_default(plot_cfg, 'value_label', true);
    plot_cfg = fill_default(plot_cfg, 'percent_on_newline', true);
    plot_cfg = fill_default(plot_cfg, 'font_tick', 11);
    plot_cfg = fill_default(plot_cfg, 'font_xlabel', 12);
    plot_cfg = fill_default(plot_cfg, 'font_ylabel', 12);
    plot_cfg = fill_default(plot_cfg, 'font_title', 14);
    plot_cfg = fill_default(plot_cfg, 'font_value_label', 11);
    plot_cfg = fill_default(plot_cfg, 'x_label_rotation', 0);
    plot_cfg = fill_default(plot_cfg, 'save_fig', true);
    plot_cfg = fill_default(plot_cfg, 'force_exponent_label', true);
    plot_cfg = fill_default(plot_cfg, 'xlabels_list', []);
    plot_cfg = fill_default(plot_cfg, 'ylabels_list', []);
    plot_cfg = fill_default(plot_cfg, 'fig_size_list', []);
end

function defs = load_wim_plot_defs(excel_path, sheet)
    defs = struct('name', {}, 'dtype', {}, 'ylabel', {}, 'show_pct', {});
    if ~exist(excel_path, 'file')
        fprintf('[WIM] Plot config not found: %s\n', excel_path);
        return;
    end
    T = readtable(excel_path, 'Sheet', sheet, 'VariableNamingRule','preserve');
    n = height(T);
    for i = 1:n
        name = string(T{i,2});
        if strlength(strtrim(name)) == 0
            break;
        end
        dtype = lower(string(T{i,4}));
        ylabel = string(T{i,6});
        pct = string(T{i,7});
        defs(end+1) = struct( ... %#ok<AGROW>
            'name', strtrim(name), ...
            'dtype', strtrim(dtype), ...
            'ylabel', strtrim(ylabel), ...
            'show_pct', strcmp(strtrim(pct), "是"));
    end
end

function [xlabels, yvals, ylabel, title] = resolve_plot_data(name, csv_paths, wim, plot_cfg)
    xlabels = strings(0,1);
    yvals = [];
    ylabel = "";
    title = name;

    if contains(name, "不同车道车辆数") && isfield(csv_paths, 'LaneSpeedWeight_Lane')
        T = readtable(csv_paths.LaneSpeedWeight_Lane, 'TextType','string', 'Encoding','UTF-8');
        xlabels = "车道" + string(T.lane);
        yvals = T.count;
        ylabel = "数量";
        [xlabels, ylabel] = apply_plot_overrides(name, xlabels, ylabel, plot_cfg);
        return;
    end
    if contains(name, "不同车速区间车辆数") && isfield(csv_paths, 'LaneSpeedWeight_Speed')
        T = readtable(csv_paths.LaneSpeedWeight_Speed, 'TextType','string', 'Encoding','UTF-8');
        xlabels = string(T.label);
        yvals = T.count;
        ylabel = "数量";
        [xlabels, ylabel] = apply_plot_overrides(name, xlabels, ylabel, plot_cfg);
        return;
    end
    if contains(name, "不同车重区间车辆数") && isfield(csv_paths, 'LaneSpeedWeight_Gross')
        T = readtable(csv_paths.LaneSpeedWeight_Gross, 'TextType','string', 'Encoding','UTF-8');
        xlabels = string(T.label);
        yvals = T.count;
        ylabel = "数量";
        [xlabels, ylabel] = apply_plot_overrides(name, xlabels, ylabel, plot_cfg);
        return;
    end
    if contains(name, "不同小时区间车辆数") && isfield(csv_paths, 'Hourly_Count')
        T = readtable(csv_paths.Hourly_Count, 'TextType','string', 'Encoding','UTF-8');
        xlabels = string(T.label);
        yvals = T.count;
        ylabel = "数量";
        [xlabels, ylabel] = apply_plot_overrides(name, xlabels, ylabel, plot_cfg);
        return;
    end
    if contains(name, "不同小时区间平均车速") && isfield(csv_paths, 'Hourly_AvgSpeed')
        T = readtable(csv_paths.Hourly_AvgSpeed, 'TextType','string', 'Encoding','UTF-8');
        xlabels = string(T.label);
        yvals = T.avg_speed;
        ylabel = "km/h";
        [xlabels, ylabel] = apply_plot_overrides(name, xlabels, ylabel, plot_cfg);
        return;
    end
    if contains(name, "车辆时间分布") && isfield(csv_paths, 'Hourly_Over')
        T = readtable(csv_paths.Hourly_Over, 'TextType','string', 'Encoding','UTF-8');
        xlabels = string(T.label);
        yvals = T.over_cnt;
        ylabel = "数量";
        thr = double(wim.hourly_critical_weight_kg) / 1000;
        title = regexprep(name, "\\d+\\s*t", sprintf('%.0ft', thr));
        [xlabels, ylabel] = apply_plot_overrides(name, xlabels, ylabel, plot_cfg);
        return;
    end
end

function plot_bar_chart(out_path, plot_title, y_label, xlabels, yvals, show_pct, dtype, plot_cfg, fig_px)
    if isempty(yvals)
        return;
    end
    f = figure('Visible','off', 'Units','pixels', 'Position',[100 100 fig_px(1) fig_px(2)]);
    bars = bar(yvals, 'FaceColor', [0 0.447 0.741]);
    grid on;
    if ~isempty(plot_title)
        title(char(plot_title), 'Interpreter','none', 'FontSize', plot_cfg.font_title);
    end
    if ~isempty(y_label)
        ylabel(char(y_label), 'Interpreter','none', 'FontSize', plot_cfg.font_ylabel);
    end
    xlabel('', 'FontSize', plot_cfg.font_xlabel);
    xticklabels(cellstr(xlabels));
    ax = gca;
    ax.FontSize = plot_cfg.font_tick;
    ax.TickLabelInterpreter = 'none';
    labels = wim_build_xtick_labels(xlabels, yvals, show_pct, plot_cfg.percent_on_newline);
    ax.XTick = 1:numel(labels);
    ax.XTickLabel = labels;
    if show_pct
        % Use manual text labels to avoid MATLAB splitting multi-line tick labels
        ax.XTickLabel = [];
        ax.XTick = 1:numel(labels);
        pos = ax.Position;
        pad_frac = 0.10;
        pos(2) = pos(2) + pad_frac;
        pos(4) = max(0.1, pos(4) - pad_frac);
        ax.Position = pos;
        y = ax.YLim(1) - diff(ax.YLim) * 0.12;
        for i = 1:numel(labels)
            text(ax.XTick(i), y, labels{i}, ...
                'HorizontalAlignment','center', ...
                'VerticalAlignment','top', ...
                'FontSize', plot_cfg.font_tick, ...
                'Clipping', 'off');
        end
    else
        ax.XTickLabelRotation = plot_cfg.x_label_rotation;
    end
    ax.YAxis.TickLabelFormat = sprintf('%%.%df', plot_cfg.y_decimals);
    exp_val = ax.YAxis.Exponent;
    if exp_val ~= 0
        force_exp = true;
        if isfield(plot_cfg, 'force_exponent_label')
            force_exp = logical(plot_cfg.force_exponent_label);
        end
        if force_exp
            text(ax, 0, 1, sprintf('\\times10^{%d}', exp_val), ...
                'Units','normalized', ...
                'HorizontalAlignment','left', ...
                'VerticalAlignment','bottom', ...
                'FontSize', plot_cfg.font_tick, ...
                'Interpreter','tex', ...
                'Clipping','off');
        end
    end
    if plot_cfg.value_label
        add_bar_labels(bars, yvals, plot_cfg.y_decimals, plot_cfg.font_value_label);
    end
    drawnow;
    [p, n, ~] = fileparts(out_path);
    fig_path = fullfile(p, [n '.fig']);
    set(findall(f, 'Visible', 'off'), 'Visible', 'on');
    set(f, 'Visible', 'on');
    drawnow;
    if plot_cfg.save_fig
        savefig(f, fig_path);
    else
        fig_path = fullfile(tempdir, [n '_' char(java.util.UUID.randomUUID) '.fig']);
        savefig(f, fig_path);
    end
    close(f);

    % Re-open fig to export png (avoids tight cropping issues)
    f2 = openfig(fig_path, 'invisible');
    set(f2, 'Units','pixels', 'Position',[100 100 fig_px(1) fig_px(2)]);
    drawnow;
    pad_px = 10;
    if isfield(plot_cfg, 'export_padding_px') && ~isempty(plot_cfg.export_padding_px)
        pad_px = plot_cfg.export_padding_px;
    end
    try
        exportgraphics(f2, out_path, 'Resolution', 100, 'BackgroundColor','white', 'ContentType','image', 'Padding', pad_px);
    catch
        exportgraphics(f2, out_path, 'Resolution', 100, 'BackgroundColor','white', 'ContentType','image');
    end
    close(f2);
    if ~plot_cfg.save_fig
        if exist(fig_path, 'file')
            delete(fig_path);
        end
    end
end

function write_plot_summary(fid, title, xlabels, yvals, dtype, show_pct, plot_cfg)
    if isempty(fid) || isempty(yvals)
        return;
    end
    total = sum(yvals);
    [mx, idx] = max(yvals);
    if isstring(xlabels) || iscellstr(xlabels)
        lab = string(xlabels(idx));
    else
        lab = string(idx);
    end
    fprintf(fid, "[%s]\n", title);
    fmt = sprintf('%%.%df', plot_cfg.y_decimals);
    fprintf(fid, "总量: %s\n", sprintf(fmt, total));
    fprintf(fid, "最大: %s = %s\n", lab, sprintf(fmt, mx));
    if show_pct && total > 0
        fprintf(fid, "占比: %s = %.2f%%\n", lab, mx / total * 100);
    end
    fprintf(fid, "\n");
end

function s = safe_name(s)
    s = regexprep(s, '[\\/:*?\"<>| ]', '_');
end

function key = make_field_key(name)
    key = regexprep(char(name), '\s+', '_');
    key = regexprep(key, '[^A-Za-z0-9_]', '_');
    if isempty(key)
        key = 'plot';
    end
end

function [xlabels, ylabel] = apply_plot_overrides(name, xlabels, ylabel, plot_cfg)
    if isfield(plot_cfg, 'xlabels') && isstruct(plot_cfg.xlabels)
        key = make_field_key(name);
        if isfield(plot_cfg.xlabels, key)
            xl = plot_cfg.xlabels.(key);
            if ischar(xl) || isstring(xl)
                xl = cellstr(xl);
            end
            if numel(xl) == numel(xlabels)
                xlabels = string(xl);
            end
        end
    end
    if isfield(plot_cfg, 'xlabels_list') && ~isempty(plot_cfg.xlabels_list)
        xl = lookup_label_list(plot_cfg.xlabels_list, name);
        if ~isempty(xl)
            if ischar(xl) || isstring(xl)
                xl = cellstr(xl);
            end
            if numel(xl) == numel(xlabels)
                xlabels = string(xl);
            end
        end
    end
    if isfield(plot_cfg, 'ylabels') && isstruct(plot_cfg.ylabels)
        key = make_field_key(name);
        if isfield(plot_cfg.ylabels, key)
            ylabel = string(plot_cfg.ylabels.(key));
        end
    end
    if isfield(plot_cfg, 'ylabels_list') && ~isempty(plot_cfg.ylabels_list)
        yl = lookup_label_list(plot_cfg.ylabels_list, name);
        if ~isempty(yl)
            ylabel = string(yl);
        end
    end
end

function val = lookup_label_list(list, name)
    val = [];
    try
        for i = 1:numel(list)
            item = list(i);
            if isfield(item, 'name') && strcmp(string(item.name), string(name))
                if isfield(item, 'labels')
                    val = item.labels;
                elseif isfield(item, 'ylabel')
                    val = item.ylabel;
                end
                return;
            end
        end
    catch
        % ignore
    end
end

function add_bar_labels(bars, yvals, decimals, font_size)
    fmt = sprintf('%%.%df', decimals);
    if isempty(bars)
        return;
    end
    x = bars(1).XEndPoints;
    y = bars(1).YEndPoints;
    n = min(numel(yvals), numel(x));
    for i = 1:n
        txt = sprintf(fmt, yvals(i));
        text(x(i), y(i), txt, 'HorizontalAlignment','center', 'VerticalAlignment','bottom', ...
            'FontSize', font_size);
    end
end


function sz = lookup_figsize_list(list, name)
    sz = [];
    try
        for i = 1:numel(list)
            item = list(i);
            if isfield(item, 'name') && strcmp(string(item.name), string(name))
                if isfield(item, 'size_px')
                    sz = item.size_px;
                elseif isfield(item, 'fig_size_px')
                    sz = item.fig_size_px;
                end
                return;
            end
        end
    catch
        % ignore
    end
end
