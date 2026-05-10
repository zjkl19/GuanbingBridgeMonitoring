function analyze_wim_reports(root_dir, start_date, end_date, cfg)
% analyze_wim_reports  Process WIM data and generate CSV/Excel/plot outputs.

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

    [month_start_dates, month_end_dates] = bms.analyzer.WimConfigService.splitMonthRanges(start_date, end_date);
    for i = 1:numel(month_start_dates)
        month_start = datestr(month_start_dates(i), 'yyyy-mm-dd');
        month_end = datestr(month_end_dates(i), 'yyyy-mm-dd');
        fprintf('[WIM] Processing %s to %s\n', month_start, month_end);
        analyze_wim_reports_single_month(root_dir, month_start, month_end, cfg);
    end
end

function analyze_wim_reports_single_month(root_dir, start_date, end_date, cfg)
    wim = bms.analyzer.WimConfigService.getWimConfig(cfg);
    pipeline = bms.analyzer.WimConfigService.fieldDefault(wim, 'pipeline', 'direct');
    vendor = bms.analyzer.WimConfigService.resolveVendor(wim);
    bridge = bms.analyzer.WimConfigService.fieldDefault(wim, 'bridge', ...
        bms.analyzer.WimConfigService.fieldDefault(cfg, 'vendor', 'bridge'));
    yyyymm = datestr(datetime(start_date, 'InputFormat', 'yyyy-MM-dd'), 'yyyymm');

    proj_root = fileparts(fileparts(mfilename('fullpath')));
    output_root = bms.analyzer.WimConfigService.resolveOutputRoot(root_dir, wim, proj_root);
    out_dir = fullfile(output_root, bridge, yyyymm);
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end

    if strcmpi(pipeline, 'database')
        run_wim_database_pipeline(root_dir, start_date, end_date, wim, cfg);
        return;
    end

    acc = bms.analyzer.WimTrafficAggregationService.initAccumulators(wim, start_date, end_date);
    switch lower(vendor)
        case 'zhichen'
            input_cfg = bms.analyzer.WimConfigService.getVendorInput(wim, 'zhichen');
            [fmt_path, bcp_path] = bms.analyzer.WimConfigService.resolveZhichenPaths(input_cfg, proj_root, yyyymm, root_dir);
            acc = process_zhichen_bcp(fmt_path, bcp_path, acc, wim);
        case 'jiulongjiang'
            input_cfg = bms.analyzer.WimConfigService.getVendorInput(wim, 'jiulongjiang');
            files = bms.analyzer.WimConfigService.resolveJiulongjiangFiles(input_cfg, proj_root);
            acc = process_jiulongjiang_excel(files, acc);
        otherwise
            error('Unsupported wim.vendor: %s', vendor);
    end

    reports = bms.analyzer.WimTrafficAggregationService.buildReportTables(acc);
    csv_paths = bms.analyzer.WimReportWriterService.writeCsvs(reports, out_dir, yyyymm);

    excel_name = bms.analyzer.WimConfigService.fieldDefault(wim, 'excel_name', 'WIM_Report_{bridge}_{yyyymm}.xlsx');
    excel_name = strrep(excel_name, '{bridge}', bridge);
    excel_name = strrep(excel_name, '{yyyymm}', yyyymm);
    excel_path = fullfile(out_dir, excel_name);
    bms.analyzer.WimReportWriterService.writeExcelFromCsvs(csv_paths, excel_path, bridge);

    fprintf('WIM reports done: %s\n', excel_path);
    bms.analyzer.WimPlotService.generate(csv_paths, out_dir, wim, cfg, bridge, yyyymm);
end

function acc = process_zhichen_bcp(fmt_path, bcp_path, acc, wim)
    spec = bms.analyzer.WimZhichenBcpSource.loadSpec(fmt_path);
    fmt = spec.fmt;
    idx = spec.index;
    encoding = bms.analyzer.WimConfigService.fieldDefault( ...
        bms.analyzer.WimConfigService.getVendorInput(wim, 'zhichen'), 'encoding', 'gbk');

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
        if ~bms.analyzer.WimTrafficAggregationService.isInRange(acc, t_dn), continue; end

        raw_vals = [];
        raw_headers = {};
        if bms.analyzer.WimTrafficAggregationService.qualifiesForMaxAxleTopN(acc, row.axle_weights, t_dn)
            raw_vals = bms.analyzer.WimZhichenBcpSource.decodeAllRow(fmt, row_bytes, encoding);
            raw_headers = {fmt.name};
        end
        acc = bms.analyzer.WimTrafficAggregationService.addRecord(acc, ...
            t_dn, row.lane, row.gross, row.speed, row.axle_weights, row.axle_num, ...
            row.plate, row.axle_distances, raw_vals, raw_headers);
    end
end

function acc = process_jiulongjiang_excel(files, acc)
    for fi = 1:numel(files)
        [rows, tbl] = bms.analyzer.WimJiulongjiangExcelSource.readRecords(files{fi});
        if isempty(tbl), continue; end

        for i = 1:numel(rows.time_datenum)
            t_dn = rows.time_datenum(i);
            if ~bms.analyzer.WimTrafficAggregationService.isInRange(acc, t_dn), continue; end

            raw_row = [];
            raw_headers = {};
            if bms.analyzer.WimTrafficAggregationService.qualifiesForMaxAxleTopN(acc, rows.axle_weights(i,:), t_dn)
                raw_row = table2cell(tbl(i,:));
                raw_headers = tbl.Properties.VariableNames;
            end

            acc = bms.analyzer.WimTrafficAggregationService.addRecord(acc, ...
                t_dn, rows.lane(i), rows.gross(i), rows.speed(i), rows.axle_weights(i,:), ...
                rows.axle_num(i), rows.plate{i}, rows.axle_distances(i,:), raw_row, raw_headers);
        end
    end
end

function run_wim_database_pipeline(root_dir, start_date, end_date, wim, cfg)
    proj_root = fileparts(fileparts(mfilename('fullpath')));
    db = bms.analyzer.WimConfigService.getDbConfig(wim, cfg, proj_root);
    bms.analyzer.WimSqlService.ensureServiceRunning(db);

    vendor = bms.analyzer.WimConfigService.resolveVendor(wim);
    bridge = bms.analyzer.WimConfigService.fieldDefault(wim, 'bridge', ...
        bms.analyzer.WimConfigService.fieldDefault(cfg, 'vendor', 'bridge'));
    yyyymm = datestr(datetime(start_date, 'InputFormat', 'yyyy-MM-dd'), 'yyyymm');

    output_root = bms.analyzer.WimConfigService.resolveOutputRoot(root_dir, wim, proj_root);
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
            input_cfg = bms.analyzer.WimConfigService.getVendorInput(wim, 'zhichen');
            [fmt_path, bcp_path] = bms.analyzer.WimConfigService.resolveZhichenPaths(input_cfg, proj_root, yyyymm, root_dir);
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
            input_cfg = bms.analyzer.WimConfigService.getVendorInput(wim, 'jiulongjiang');
            files = bms.analyzer.WimConfigService.resolveJiulongjiangFiles(input_cfg, proj_root);
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

    excel_name = bms.analyzer.WimConfigService.fieldDefault(wim, 'excel_name', 'WIM_Report_{bridge}_{yyyymm}.xlsx');
    excel_name = strrep(excel_name, '{bridge}', bridge);
    excel_name = strrep(excel_name, '{yyyymm}', yyyymm);
    excel_path = fullfile(out_dir, excel_name);
    bms.analyzer.WimReportWriterService.writeExcelFromCsvs(csv_paths, excel_path, bridge);
    fprintf('WIM reports done (database): %s\n', excel_path);

    bms.analyzer.WimPlotService.generate(csv_paths, out_dir, wim, cfg, bridge, yyyymm);
end
