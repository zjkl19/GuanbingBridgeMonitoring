classdef WimReportPipeline
    %WIMREPORTPIPELINE Orchestrates WIM report generation workflows.

    methods (Static)
        function run(rootDir, startDate, endDate, cfg)
            if nargin < 1 || isempty(rootDir)
                rootDir = pwd;
            end
            if nargin < 2 || isempty(startDate)
                error('start_date is required (yyyy-MM-dd).');
            end
            if nargin < 3 || isempty(endDate)
                error('end_date is required (yyyy-MM-dd).');
            end
            if nargin < 4 || isempty(cfg)
                cfg = load_config();
            end

            [monthStartDates, monthEndDates] = bms.analyzer.WimConfigService.splitMonthRanges(startDate, endDate);
            for i = 1:numel(monthStartDates)
                bms.app.StopController.throwIfRequested('Stop requested before next WIM month');
                monthStart = datestr(monthStartDates(i), 'yyyy-mm-dd');
                monthEnd = datestr(monthEndDates(i), 'yyyy-mm-dd');
                fprintf('[WIM] Processing %s to %s\n', monthStart, monthEnd);
                bms.analyzer.WimReportPipeline.runSingleMonth(rootDir, monthStart, monthEnd, cfg);
            end
        end

        function runSingleMonth(rootDir, startDate, endDate, cfg)
            wim = bms.analyzer.WimConfigService.getWimConfig(cfg);
            pipeline = bms.analyzer.WimConfigService.fieldDefault(wim, 'pipeline', 'direct');
            vendor = bms.analyzer.WimConfigService.resolveVendor(wim);
            bridge = bms.analyzer.WimReportPipeline.resolveBridge(wim, cfg);
            yyyymm = datestr(datetime(startDate, 'InputFormat', 'yyyy-MM-dd'), 'yyyymm');

            projRoot = bms.analyzer.WimReportPipeline.projectRoot();
            outputRoot = bms.analyzer.WimConfigService.resolveOutputRoot(rootDir, wim, projRoot);
            outDir = fullfile(outputRoot, bridge, yyyymm);
            if ~exist(outDir, 'dir'), mkdir(outDir); end

            if strcmpi(pipeline, 'database')
                bms.analyzer.WimReportPipeline.runDatabasePipeline(rootDir, startDate, endDate, wim, cfg);
                return;
            end

            bms.analyzer.WimReportPipeline.runDirectPipeline(rootDir, startDate, endDate, wim, cfg, vendor, bridge, yyyymm, projRoot, outDir);
        end

        function runDirectPipeline(rootDir, startDate, endDate, wim, cfg, vendor, bridge, yyyymm, projRoot, outDir) %#ok<INUSD>
            acc = bms.analyzer.WimTrafficAggregationService.initAccumulators(wim, startDate, endDate);
            switch lower(vendor)
                case 'zhichen'
                    inputCfg = bms.analyzer.WimConfigService.getVendorInput(wim, 'zhichen');
                    [fmtPath, bcpPath] = bms.analyzer.WimConfigService.resolveZhichenPaths(inputCfg, projRoot, yyyymm, rootDir);
                    acc = bms.analyzer.WimReportPipeline.processZhichenBcp(fmtPath, bcpPath, acc, wim);
                case 'jiulongjiang'
                    inputCfg = bms.analyzer.WimConfigService.getVendorInput(wim, 'jiulongjiang');
                    files = bms.analyzer.WimConfigService.resolveJiulongjiangFiles(inputCfg, projRoot);
                    acc = bms.analyzer.WimReportPipeline.processJiulongjiangExcel(files, acc);
                otherwise
                    error('Unsupported wim.vendor: %s', vendor);
            end

            reports = bms.analyzer.WimTrafficAggregationService.buildReportTables(acc);
            csvPaths = bms.analyzer.WimReportWriterService.writeCsvs(reports, outDir, yyyymm);
            excelPath = bms.analyzer.WimReportPipeline.excelPath(wim, outDir, bridge, yyyymm);
            bms.analyzer.WimReportWriterService.writeExcelFromCsvs(csvPaths, excelPath, bridge);

            fprintf('WIM reports done: %s\n', excelPath);
            bms.analyzer.WimPlotService.generate(csvPaths, outDir, wim, cfg, bridge, yyyymm);
        end

        function acc = processZhichenBcp(fmtPath, bcpPath, acc, wim)
            spec = bms.analyzer.WimZhichenBcpSource.loadSpec(fmtPath);
            fmt = spec.fmt;
            idx = spec.index;
            encoding = bms.analyzer.WimConfigService.fieldDefault( ...
                bms.analyzer.WimConfigService.getVendorInput(wim, 'zhichen'), 'encoding', 'gbk');

            fid = fopen(bcpPath, 'r', 'ieee-le');
            if fid < 0
                error('Cannot open bcp: %s', bcpPath);
            end
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

            rowCounter = 0;
            while true
                rowCounter = rowCounter + 1;
                if rowCounter == 1 || mod(rowCounter, 1000) == 0
                    bms.app.StopController.throwIfRequested('Stop requested before next WIM BCP row batch');
                end
                [rowBytes, ok] = bms.analyzer.WimZhichenBcpSource.readRowBytes(fid, fmt);
                if ~ok, break; end

                row = bms.analyzer.WimZhichenBcpSource.decodeRecord(fmt, idx, rowBytes, encoding);
                timeDatenum = row.time_datenum;
                if ~bms.analyzer.WimTrafficAggregationService.isInRange(acc, timeDatenum), continue; end

                rawVals = [];
                rawHeaders = {};
                if bms.analyzer.WimTrafficAggregationService.qualifiesForMaxAxleTopN(acc, row.axle_weights, timeDatenum)
                    rawVals = bms.analyzer.WimZhichenBcpSource.decodeAllRow(fmt, rowBytes, encoding);
                    rawHeaders = {fmt.name};
                end
                acc = bms.analyzer.WimTrafficAggregationService.addRecord(acc, ...
                    timeDatenum, row.lane, row.gross, row.speed, row.axle_weights, row.axle_num, ...
                    row.plate, row.axle_distances, rawVals, rawHeaders);
            end
        end

        function acc = processJiulongjiangExcel(files, acc)
            for fi = 1:numel(files)
                bms.app.StopController.throwIfRequested('Stop requested before next WIM Excel file');
                [rows, tbl] = bms.analyzer.WimJiulongjiangExcelSource.readRecords(files{fi});
                if isempty(tbl), continue; end

                for i = 1:numel(rows.time_datenum)
                    if i == 1 || mod(i, 1000) == 0
                        bms.app.StopController.throwIfRequested('Stop requested before next WIM Excel row batch');
                    end
                    timeDatenum = rows.time_datenum(i);
                    if ~bms.analyzer.WimTrafficAggregationService.isInRange(acc, timeDatenum), continue; end

                    rawRow = [];
                    rawHeaders = {};
                    if bms.analyzer.WimTrafficAggregationService.qualifiesForMaxAxleTopN(acc, rows.axle_weights(i,:), timeDatenum)
                        rawRow = table2cell(tbl(i,:));
                        rawHeaders = tbl.Properties.VariableNames;
                    end

                    acc = bms.analyzer.WimTrafficAggregationService.addRecord(acc, ...
                        timeDatenum, rows.lane(i), rows.gross(i), rows.speed(i), rows.axle_weights(i,:), ...
                        rows.axle_num(i), rows.plate{i}, rows.axle_distances(i,:), rawRow, rawHeaders);
                end
            end
        end

        function runDatabasePipeline(rootDir, startDate, endDate, wim, cfg)
            projRoot = bms.analyzer.WimReportPipeline.projectRoot();
            db = bms.analyzer.WimConfigService.getDbConfig(wim, cfg, projRoot);
            bms.analyzer.WimSqlService.ensureServiceRunning(db);

            vendor = bms.analyzer.WimConfigService.resolveVendor(wim);
            bridge = bms.analyzer.WimReportPipeline.resolveBridge(wim, cfg);
            yyyymm = datestr(datetime(startDate, 'InputFormat', 'yyyy-MM-dd'), 'yyyymm');

            outputRoot = bms.analyzer.WimConfigService.resolveOutputRoot(rootDir, wim, projRoot);
            outDir = fullfile(outputRoot, bridge, yyyymm);
            if ~exist(outDir, 'dir'), mkdir(outDir); end

            startDt = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
            finishDt = datetime(endDate, 'InputFormat', 'yyyy-MM-dd') + days(1);
            startStr = datestr(startDt, 'yyyy-mm-dd HH:MM:SS');
            finishStr = datestr(finishDt, 'yyyy-mm-dd HH:MM:SS');

            srcTable = bms.analyzer.WimSqlService.qualifyTable(db, [db.table_prefix yyyymm]);
            rawTable = bms.analyzer.WimSqlService.qualifyTable(db, [db.raw_table_prefix yyyymm]);
            rawMeta = struct();

            switch lower(vendor)
                case 'zhichen'
                    inputCfg = bms.analyzer.WimConfigService.getVendorInput(wim, 'zhichen');
                    [fmtPath, bcpPath] = bms.analyzer.WimConfigService.resolveZhichenPaths(inputCfg, projRoot, yyyymm, rootDir);
                    bms.analyzer.WimSqlService.ensureZhichenTable(db, srcTable, fmtPath);
                    if bms.analyzer.WimSqlService.shouldImport(db, srcTable)
                        bms.analyzer.WimSqlService.importBcpWithFmt(db, srcTable, bcpPath, fmtPath);
                    end
                    fmt = bms.analyzer.WimZhichenBcpSource.parseFmt(fmtPath);
                    rawMeta.mode = 'zhichen';
                    rawMeta.headers = {fmt.name};
                    rawMeta.raw_table = srcTable;
                    rawMeta.time_col = 'HSData_DT';
                    rawMeta.axle_cols = {};
                case 'jiulongjiang'
                    inputCfg = bms.analyzer.WimConfigService.getVendorInput(wim, 'jiulongjiang');
                    files = bms.analyzer.WimConfigService.resolveJiulongjiangFiles(inputCfg, projRoot);
                    stageDir = fullfile(outDir, '_db_stage');
                    if ~exist(stageDir, 'dir'), mkdir(stageDir); end
                    [normCsv, rawCsv, rawMeta] = bms.analyzer.WimJiulongjiangExcelSource.buildStage(files, stageDir);
                    bms.analyzer.WimSqlService.ensureNormalizedTable(db, srcTable);
                    bms.analyzer.WimSqlService.ensureRawTable(db, rawTable, rawMeta.headers);
                    if bms.analyzer.WimSqlService.shouldImport(db, srcTable)
                        bms.analyzer.WimSqlService.bulkInsertCsv(db, srcTable, normCsv);
                    end
                    if bms.analyzer.WimSqlService.shouldImport(db, rawTable)
                        bms.analyzer.WimSqlService.bulkInsertCsv(db, rawTable, rawCsv);
                    end
                    rawMeta.mode = 'jiulongjiang';
                    rawMeta.raw_table = rawTable;
                otherwise
                    error('Unsupported wim.vendor: %s', vendor);
            end

            csvPaths = bms.analyzer.WimSqlService.runReports(db, wim, outDir, yyyymm, srcTable, startStr, finishStr, rawMeta);
            excelPath = bms.analyzer.WimReportPipeline.excelPath(wim, outDir, bridge, yyyymm);
            bms.analyzer.WimReportWriterService.writeExcelFromCsvs(csvPaths, excelPath, bridge);
            fprintf('WIM reports done (database): %s\n', excelPath);

            bms.analyzer.WimPlotService.generate(csvPaths, outDir, wim, cfg, bridge, yyyymm);
        end

        function path = excelPath(wim, outDir, bridge, yyyymm)
            excelName = bms.analyzer.WimConfigService.fieldDefault(wim, 'excel_name', 'WIM_Report_{bridge}_{yyyymm}.xlsx');
            excelName = strrep(excelName, '{bridge}', bridge);
            excelName = strrep(excelName, '{yyyymm}', yyyymm);
            path = fullfile(outDir, excelName);
        end

        function bridge = resolveBridge(wim, cfg)
            bridge = bms.analyzer.WimConfigService.fieldDefault(wim, 'bridge', ...
                bms.analyzer.WimConfigService.fieldDefault(cfg, 'vendor', 'bridge'));
        end

        function root = projectRoot()
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
        end
    end
end
