classdef WimSqlService
    %WIMSQLSERVICE SQL Server helpers for WIM database reporting.

    methods (Static)
        function ensureServiceRunning(db)
            svc = bms.analyzer.WimSqlService.resolveServiceName(db);
            status = bms.analyzer.WimSqlService.serviceStatus(svc);
            if ~strcmpi(status, 'Running')
                fprintf('[WIM] SQL Server service %s is %s. Attempting to start...\n', svc, status);
                [rc, out] = system(bms.analyzer.WimSqlService.powerShellCommand(sprintf("Start-Service -Name '%s'", svc)));
                if rc ~= 0
                    error('SQL Server service %s not running and failed to start. Run MATLAB as Administrator. Details: %s', svc, strtrim(out));
                end
                pause(1.0);
                status = bms.analyzer.WimSqlService.serviceStatus(svc);
                if ~strcmpi(status, 'Running')
                    error('SQL Server service %s not running after start. Run MATLAB as Administrator.', svc);
                end
            end
        end

        function svc = resolveServiceName(db)
            svc = bms.analyzer.WimSqlService.fieldDefault(db, 'service_name', '');
            if ~isempty(svc) && bms.analyzer.WimSqlService.serviceExists(svc)
                return;
            end

            names = bms.analyzer.WimSqlService.listServices();
            if isempty(names)
                error('No SQL Server services found. Install SQL Server or set wim_db.service_name.');
            end
            svc = names{1};
            if numel(names) > 1
                fprintf('[WIM] Multiple SQL Server services detected: %s. Using %s. Set wim_db.service_name to override.\n', strjoin(names, ', '), svc);
            end
        end

        function ok = serviceExists(name)
            if isempty(name)
                ok = false;
                return;
            end
            cmd = sprintf("Get-Service -Name '%s' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name", name);
            [rc, out] = system(bms.analyzer.WimSqlService.powerShellCommand(cmd));
            ok = (rc == 0) && ~isempty(strtrim(out));
        end

        function status = serviceStatus(name)
            cmd = sprintf("Get-Service -Name '%s' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Status", name);
            [rc, out] = system(bms.analyzer.WimSqlService.powerShellCommand(cmd));
            if rc ~= 0
                status = '';
            else
                status = strtrim(out);
            end
        end

        function names = listServices()
            cmd = "Get-Service -Name 'MSSQL*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name";
            [rc, out] = system(bms.analyzer.WimSqlService.powerShellCommand(cmd));
            if rc ~= 0
                names = {};
                return;
            end
            lines = strtrim(splitlines(string(out)));
            lines = lines(lines ~= "");
            names = cellstr(lines);
        end

        function cmd = powerShellCommand(inner)
            cmd = sprintf('powershell -NoProfile -Command \"%s\"', strrep(inner, '"', '\"'));
        end

        function ok = shouldImport(db, tableName)
            mode = lower(bms.analyzer.WimSqlService.fieldDefault(db, 'import_mode', 'truncate'));
            switch mode
                case 'skip_if_exists'
                    if bms.analyzer.WimSqlService.tableExists(db, tableName)
                        if bms.analyzer.WimSqlService.tableHasRows(db, tableName)
                            ok = false;
                            return;
                        end
                    end
                    ok = true;
                otherwise
                    ok = true;
            end
        end

        function ensureZhichenTable(db, tableName, fmtPath)
            if ~bms.analyzer.WimSqlService.tableExists(db, tableName)
                sql = bms.analyzer.WimSqlService.createTableSqlFromFmt(tableName, fmtPath);
                bms.analyzer.WimSqlService.runQuery(db, sql);
            elseif strcmpi(bms.analyzer.WimSqlService.fieldDefault(db, 'import_mode', 'truncate'), 'truncate')
                bms.analyzer.WimSqlService.runQuery(db, sprintf('TRUNCATE TABLE %s;', bms.analyzer.WimSqlService.quoteTableName(tableName)));
            end
        end

        function ensureNormalizedTable(db, tableName)
            if ~bms.analyzer.WimSqlService.tableExists(db, tableName)
                sql = bms.analyzer.WimSqlService.createNormalizedTableSql(tableName);
                bms.analyzer.WimSqlService.runQuery(db, sql);
            elseif strcmpi(bms.analyzer.WimSqlService.fieldDefault(db, 'import_mode', 'truncate'), 'truncate')
                bms.analyzer.WimSqlService.runQuery(db, sprintf('TRUNCATE TABLE %s;', bms.analyzer.WimSqlService.quoteTableName(tableName)));
            end
        end

        function ensureRawTable(db, tableName, rawHeaders)
            if ~bms.analyzer.WimSqlService.tableExists(db, tableName)
                sql = bms.analyzer.WimSqlService.createRawTableSql(tableName, rawHeaders);
                bms.analyzer.WimSqlService.runQuery(db, sql);
            elseif strcmpi(bms.analyzer.WimSqlService.fieldDefault(db, 'import_mode', 'truncate'), 'truncate')
                bms.analyzer.WimSqlService.runQuery(db, sprintf('TRUNCATE TABLE %s;', bms.analyzer.WimSqlService.quoteTableName(tableName)));
            end
        end

        function importBcpWithFmt(db, tableName, bcpPath, fmtPath)
            bcpPath = bms.analyzer.WimSqlService.escapeSqlLiteral(bcpPath);
            fmtPath = bms.analyzer.WimSqlService.escapeSqlLiteral(fmtPath);
            sql = sprintf(['BULK INSERT %s FROM ''%s'' WITH (' ...
                'FORMATFILE = ''%s'', TABLOCK, BATCHSIZE = 50000, KEEPIDENTITY);'], ...
                bms.analyzer.WimSqlService.quoteTableName(tableName), bcpPath, fmtPath);
            bms.analyzer.WimSqlService.runQuery(db, sql);
        end

        function bulkInsertCsv(db, tableName, csvPath)
            csvPath = bms.analyzer.WimSqlService.escapeSqlLiteral(csvPath);
            sql = sprintf(['BULK INSERT %s FROM ''%s'' WITH (' ...
                'FIRSTROW = 2, FIELDTERMINATOR = ''\\t'', ROWTERMINATOR = ''0x0d0a'', ' ...
                'CODEPAGE = ''65001'', TABLOCK, BATCHSIZE = 50000);'], ...
                bms.analyzer.WimSqlService.quoteTableName(tableName), csvPath);
            bms.analyzer.WimSqlService.runQuery(db, sql);
        end

        function sql = createNormalizedTableSql(tableName)
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
                '); END;'], bms.analyzer.WimSqlService.objectIdName(tableName), bms.analyzer.WimSqlService.quoteTableName(tableName));
        end

        function sql = createRawTableSql(tableName, headers)
            cols = cell(1, numel(headers));
            for i = 1:numel(headers)
                name = headers{i};
                if isempty(name)
                    name = sprintf('Var%d', i);
                end
                cols{i} = sprintf('%s NVARCHAR(255) NULL', bms.analyzer.WimSqlService.quoteIdentifier(name));
            end
            colSql = strjoin(cols, ',');
            sql = sprintf('IF OBJECT_ID(''%s'', ''U'') IS NULL BEGIN CREATE TABLE %s (%s); END;', ...
                bms.analyzer.WimSqlService.objectIdName(tableName), bms.analyzer.WimSqlService.quoteTableName(tableName), colSql);
        end

        function sql = createTableSqlFromFmt(tableName, fmtPath)
            fmt = bms.analyzer.WimZhichenBcpSource.parseFmt(fmtPath);
            cols = cell(1, numel(fmt));
            for i = 1:numel(fmt)
                cols{i} = sprintf('%s %s NULL', ...
                    bms.analyzer.WimSqlService.quoteIdentifier(fmt(i).name), ...
                    bms.analyzer.WimZhichenBcpSource.sqlType(fmt(i)));
            end
            colSql = strjoin(cols, ',');
            sql = sprintf('IF OBJECT_ID(''%s'', ''U'') IS NULL BEGIN CREATE TABLE %s (%s); END;', ...
                bms.analyzer.WimSqlService.objectIdName(tableName), bms.analyzer.WimSqlService.quoteTableName(tableName), colSql);
        end

        function csvPaths = runReports(db, wim, outDir, yyyymm, srcTable, startStr, finishStr, rawMeta)
            vars = bms.analyzer.WimSqlService.reportVars(wim, srcTable, startStr, finishStr);
            scriptDir = db.scripts_dir;
            csvPaths = struct();

            csvPaths.DailyTraffic = bms.analyzer.WimSqlService.runReport(db, fullfile(scriptDir, 'report_daily_traffic.sql'), ...
                fullfile(outDir, sprintf('%s_DailyTraffic.csv', yyyymm)), vars, ...
                {'date','up_cnt','down_cnt','total'});
            csvPaths.LaneSpeedWeight_Lane = bms.analyzer.WimSqlService.runReport(db, fullfile(scriptDir, 'report_lane_distribution.sql'), ...
                fullfile(outDir, sprintf('%s_LaneSpeedWeight_Lane.csv', yyyymm)), vars, ...
                {'lane','count'});
            csvPaths.LaneSpeedWeight_Speed = bms.analyzer.WimSqlService.runReport(db, fullfile(scriptDir, 'report_speed_bins.sql'), ...
                fullfile(outDir, sprintf('%s_LaneSpeedWeight_Speed.csv', yyyymm)), vars, ...
                {'bin_id','label','count'});
            csvPaths.LaneSpeedWeight_Gross = bms.analyzer.WimSqlService.runReport(db, fullfile(scriptDir, 'report_gross_bins.sql'), ...
                fullfile(outDir, sprintf('%s_LaneSpeedWeight_Gross.csv', yyyymm)), vars, ...
                {'bin_id','label','count'});
            csvPaths.LaneSpeedWeight_GrossPerLane = bms.analyzer.WimSqlService.runReport(db, fullfile(scriptDir, 'report_lane_gross_bins.sql'), ...
                fullfile(outDir, sprintf('%s_LaneSpeedWeight_GrossPerLane.csv', yyyymm)), vars, ...
                {'lane','bin_id','label','count'});
            csvPaths.Hourly_Count = bms.analyzer.WimSqlService.runReport(db, fullfile(scriptDir, 'report_hourly_count.sql'), ...
                fullfile(outDir, sprintf('%s_Hourly_Count.csv', yyyymm)), vars, ...
                {'bin_id','label','count'});
            csvPaths.Hourly_AvgSpeed = bms.analyzer.WimSqlService.runReport(db, fullfile(scriptDir, 'report_hourly_avgspeed.sql'), ...
                fullfile(outDir, sprintf('%s_Hourly_AvgSpeed.csv', yyyymm)), vars, ...
                {'bin_id','label','avg_speed'});
            csvPaths.Hourly_Over = bms.analyzer.WimSqlService.runReport(db, fullfile(scriptDir, 'report_hourly_over.sql'), ...
                fullfile(outDir, sprintf('%s_Hourly_Over.csv', yyyymm)), vars, ...
                {'bin_id','label','over_cnt'});
            csvPaths.CustomThresholds_Overall = bms.analyzer.WimSqlService.runReport(db, fullfile(scriptDir, 'report_custom_overall.sql'), ...
                fullfile(outDir, sprintf('%s_CustomThresholds_Overall.csv', yyyymm)), vars, ...
                {'weight_threshold','over_cnt'});
            csvPaths.CustomThresholds_PerLane = bms.analyzer.WimSqlService.runReport(db, fullfile(scriptDir, 'report_custom_per_lane.sql'), ...
                fullfile(outDir, sprintf('%s_CustomThresholds_PerLane.csv', yyyymm)), vars, ...
                {'lane','weight_threshold','over_cnt'});
            csvPaths.TopN = bms.analyzer.WimSqlService.runReport(db, fullfile(scriptDir, 'report_topn_gross.sql'), ...
                fullfile(outDir, sprintf('%s_TopN.csv', yyyymm)), vars, ...
                bms.analyzer.WimSqlService.topNHeaders());
            csvPaths.TopN_MaxAxle = bms.analyzer.WimSqlService.runReport(db, fullfile(scriptDir, 'report_topn_max_axle.sql'), ...
                fullfile(outDir, sprintf('%s_TopN_MaxAxle.csv', yyyymm)), vars, ...
                bms.analyzer.WimSqlService.topNHeaders());
            csvPaths.Overload_Summary = bms.analyzer.WimSqlService.runReport(db, fullfile(scriptDir, 'report_overload_summary.sql'), ...
                fullfile(outDir, sprintf('%s_Overload_Summary.csv', yyyymm)), vars, ...
                {'type','threshold_kg','count'});
            csvPaths.TopN_MaxAxle_Raw = bms.analyzer.WimSqlService.writeTopNMaxAxleRaw(db, outDir, yyyymm, vars, rawMeta);
        end

        function vars = reportVars(wim, srcTable, startStr, finishStr)
            vars = struct();
            vars.SrcTable = srcTable;
            vars.Start = startStr;
            vars.Finish = finishStr;
            vars.LaneText = bms.analyzer.WimSqlService.joinNumList(wim.lanes);
            vars.UpLanes = bms.analyzer.WimSqlService.joinNumList(wim.up_lanes);
            vars.SpeedBins = bms.analyzer.WimSqlService.joinNumList(wim.speed_bins);
            vars.GrossBins = bms.analyzer.WimSqlService.joinNumList(wim.gross_bins);
            vars.HourBins = bms.analyzer.WimSqlService.joinNumList(wim.hour_bins);
            vars.CustomWeights = bms.analyzer.WimSqlService.joinNumList(wim.custom_weights);
            vars.CriticalLanes = bms.analyzer.WimSqlService.joinNumList(wim.critical_lanes);
            vars.HourlyCriticalWeight = double(wim.hourly_critical_weight_kg);
            vars.TopN = double(wim.topn);
            vars.DesignTotal = double(wim.design_total_kg);
            vars.DesignAxle = double(wim.design_axle_kg);
            vars.OverloadFactors = bms.analyzer.WimSqlService.joinNumList(wim.overload_factors);
        end

        function headers = topNHeaders()
            headers = {'rank','lane','time','axle_num','gross_kg','speed_kmh','plate', ...
                'axle1','axle2','axle3','axle4','axle5','axle6','axle7','axle8', ...
                'axledis1','axledis2','axledis3','axledis4','axledis5','axledis6','axledis7'};
        end

        function csvPath = writeTopNMaxAxleRaw(db, outDir, yyyymm, vars, rawMeta)
            csvPath = fullfile(outDir, sprintf('%s_TopN_MaxAxle_Raw.csv', yyyymm));
            tmpPath = [csvPath '.tmp'];
            if strcmpi(rawMeta.mode, 'zhichen')
                script = fullfile(db.scripts_dir, 'report_topn_max_axle_raw.sql');
                bms.analyzer.WimSqlService.runSqlcmdFile(db, script, tmpPath, vars);
                bms.analyzer.WimSqlService.prependCsvHeader(rawMeta.headers, tmpPath, csvPath);
                return;
            end
            if ~isfield(rawMeta, 'raw_table') || isempty(rawMeta.raw_table) || isempty(rawMeta.headers)
                if exist(tmpPath, 'file'), delete(tmpPath); end
                writecell({}, csvPath, 'Encoding', 'UTF-8');
                return;
            end
            timeCol = rawMeta.time_col;
            axleCols = rawMeta.axle_cols;
            if isempty(timeCol) || isempty(axleCols)
                writecell({}, csvPath, 'Encoding', 'UTF-8');
                return;
            end
            selectCols = cellfun(@(c) bms.analyzer.WimSqlService.quoteIdentifier(c), rawMeta.headers, 'UniformOutput', false);
            selectSql = strjoin(selectCols, ',');
            axleVals = cellfun(@(c) sprintf('(TRY_CONVERT(float,%s))', ...
                bms.analyzer.WimSqlService.quoteIdentifier(c)), axleCols, 'UniformOutput', false);
            axleSql = strjoin(axleVals, ',');
            sql = sprintf(['SELECT TOP (%d) %s FROM %s AS r ' ...
                'CROSS APPLY (SELECT MAX(v) AS max_axle FROM (VALUES %s) AS A(v)) AS mx ' ...
                'WHERE TRY_CONVERT(datetime2,%s) >= ''%s'' AND TRY_CONVERT(datetime2,%s) < ''%s'' ' ...
                'ORDER BY mx.max_axle DESC, TRY_CONVERT(datetime2,%s) ASC;'], ...
                vars.TopN, selectSql, bms.analyzer.WimSqlService.quoteTableName(rawMeta.raw_table), axleSql, ...
                bms.analyzer.WimSqlService.quoteIdentifier(timeCol), vars.Start, ...
                bms.analyzer.WimSqlService.quoteIdentifier(timeCol), vars.Finish, ...
                bms.analyzer.WimSqlService.quoteIdentifier(timeCol));
            bms.analyzer.WimSqlService.runQueryToFile(db, sql, tmpPath);
            bms.analyzer.WimSqlService.prependCsvHeader(rawMeta.headers, tmpPath, csvPath);
        end

        function csvPath = runReport(db, scriptPath, outPath, vars, header)
            tmpPath = [outPath '.tmp'];
            bms.analyzer.WimSqlService.runSqlcmdFile(db, scriptPath, tmpPath, vars);
            bms.analyzer.WimSqlService.prependCsvHeader(header, tmpPath, outPath);
            csvPath = outPath;
        end

        function runSqlcmdFile(db, scriptPath, outPath, vars)
            if ~exist(scriptPath, 'file')
                error('SQL script not found: %s', scriptPath);
            end
            args = sprintf('-i \"%s\" -o \"%s\" -s , -W -h -1 -w 65535', scriptPath, outPath);
            [status, out] = bms.analyzer.WimSqlService.runSqlcmdSystem(db, args, vars);
            if status ~= 0
                bms.analyzer.WimSqlService.throwSqlcmdError(db, out, sprintf('script %s', scriptPath));
            end
        end

        function runQuery(db, sql)
            [status, out] = bms.analyzer.WimSqlService.runSqlcmdSystem(db, ...
                sprintf('-Q \"%s\" -h -1 -W', bms.analyzer.WimSqlService.escapeCmdSql(sql)), struct());
            if status ~= 0
                bms.analyzer.WimSqlService.throwSqlcmdError(db, out, 'query');
            end
        end

        function runQueryToFile(db, sql, outPath)
            [status, out] = bms.analyzer.WimSqlService.runSqlcmdSystem(db, ...
                sprintf('-Q \"%s\" -o \"%s\" -s , -W -h -1 -w 65535', ...
                bms.analyzer.WimSqlService.escapeCmdSql(sql), outPath), struct());
            if status ~= 0
                bms.analyzer.WimSqlService.throwSqlcmdError(db, out, sprintf('query output %s', outPath));
            end
        end

        function cmd = buildSqlcmdCommand(db, extraArgs, vars, useUtf8)
            exe = bms.analyzer.WimSqlService.findSqlcmd();
            cmd = sprintf('\"%s\" -S \"%s\" -d \"%s\" -E -b', exe, db.server, db.database);
            if isfield(db, 'trust_server_cert') && db.trust_server_cert
                cmd = sprintf('%s -C', cmd);
            end
            if useUtf8
                cmd = sprintf('%s -f 65001', cmd);
            end
            if ~isempty(extraArgs)
                cmd = sprintf('%s %s', cmd, extraArgs);
            end
            if nargin >= 3 && ~isempty(vars)
                cmd = sprintf('%s %s', cmd, bms.analyzer.WimSqlService.buildSqlcmdVars(vars));
            end
        end

        function args = buildSqlcmdVars(vars)
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

        function exe = findSqlcmd()
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

        function out = joinNumList(v)
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

        function ok = tableExists(db, tableName)
            sql = sprintf('SET NOCOUNT ON; IF OBJECT_ID(''%s'',''U'') IS NULL SELECT 0 ELSE SELECT 1;', ...
                bms.analyzer.WimSqlService.objectIdName(tableName));
            out = bms.analyzer.WimSqlService.runCapture(db, sql);
            ok = str2double(strtrim(out)) == 1;
        end

        function ok = tableHasRows(db, tableName)
            sql = sprintf('SET NOCOUNT ON; SELECT COUNT(1) FROM %s;', bms.analyzer.WimSqlService.quoteTableName(tableName));
            out = bms.analyzer.WimSqlService.runCapture(db, sql);
            ok = str2double(strtrim(out)) > 0;
        end

        function out = runCapture(db, sql)
            [status, out] = bms.analyzer.WimSqlService.runSqlcmdSystem(db, ...
                sprintf('-Q \"%s\" -h -1 -W', bms.analyzer.WimSqlService.escapeCmdSql(sql)), struct());
            if status ~= 0
                bms.analyzer.WimSqlService.throwSqlcmdError(db, out, 'scalar query');
            end
            out = strtrim(out);
            tokens = regexp(out, '[-+]?\d+(\.\d+)?', 'match');
            if ~isempty(tokens)
                out = tokens{1};
            end
        end

        function [status, out] = runSqlcmdSystem(db, args, vars)
            cmd = bms.analyzer.WimSqlService.buildSqlcmdCommand(db, args, vars, db.sqlcmd_utf8);
            [status, out] = system(cmd);
            if status ~= 0 && db.sqlcmd_utf8
                cmd = bms.analyzer.WimSqlService.buildSqlcmdCommand(db, args, vars, false);
                [status, out] = system(cmd);
            end
        end

        function throwSqlcmdError(db, out, context)
            [errId, errMsg] = bms.analyzer.WimSqlService.classifySqlcmdError(db, out, context);
            error(errId, '%s\n\nDetails:\n%s', errMsg, strtrim(char(string(out))));
        end

        function [errId, errMsg] = classifySqlcmdError(db, out, context)
            raw = char(string(out));
            rawLower = lower(raw);
            server = bms.analyzer.WimSqlService.fieldDefault(db, 'server', '(unset)');
            database = bms.analyzer.WimSqlService.fieldDefault(db, 'database', '(unset)');
            service = bms.analyzer.WimSqlService.fieldDefault(db, 'service_name', '(auto)');

            if bms.analyzer.WimSqlService.containsAny(raw, {'无法打开登录所请求的数据库', '找不到数据库'}) || ...
                    bms.analyzer.WimSqlService.containsAny(rawLower, {'cannot open database', 'database does not exist'})
                errId = 'WIM:SQL:DatabaseMissing';
                errMsg = sprintf([ ...
                    'WIM SQL database error while running %s. Database "%s" cannot be opened or does not exist. ' ...
                    'Check wim_db.database and create the database before importing WIM data.'], ...
                    context, database);
                return;
            end

            if bms.analyzer.WimSqlService.containsAny(raw, {'登录失败', '没有所需的权限', '拒绝访问', '无法执行 批量加载', '无法执行 BULK LOAD'}) || ...
                    bms.analyzer.WimSqlService.containsAny(rawLower, {'login failed for user', 'permission denied', 'access is denied', ...
                    'you do not have permission', 'bulk load', 'operating system error code 5'})
                errId = 'WIM:SQL:Permission';
                errMsg = sprintf([ ...
                    'WIM SQL permission error while running %s. Current Windows login cannot access server "%s" ' ...
                    'or database "%s". Check SQL Server permissions, bulk import rights, and Windows authentication.'], ...
                    context, server, database);
                return;
            end

            if bms.analyzer.WimSqlService.containsAny(raw, {'未与 SQL Server 建立连接', '与 SQL Server 建立连接时发生了与网络相关的或特定于实例的错误', ...
                    '服务器不存在或拒绝访问', '命名管道提供程序', 'SQL Server 不存在或访问被拒绝'}) || ...
                    bms.analyzer.WimSqlService.containsAny(rawLower, {'network-related or instance-specific error', 'server does not exist or access denied', ...
                    'sql server does not exist or access denied', 'named pipes provider', 'error: 40', ...
                    'login timeout expired', 'server was not found or was not accessible'})
                errId = 'WIM:SQL:Instance';
                errMsg = sprintf([ ...
                    'WIM SQL instance/connectivity error while running %s. Cannot connect to server "%s". ' ...
                    'Check wim_db.server, SQL Server service "%s", and local instance availability.'], ...
                    context, server, service);
                return;
            end

            errId = 'WIM:SQL:CommandFailed';
            errMsg = sprintf([ ...
                'WIM SQL command failed while running %s on server "%s", database "%s". ' ...
                'See sqlcmd details below.'], context, server, database);
        end

        function tf = containsAny(text, patterns)
            tf = false;
            for i = 1:numel(patterns)
                if contains(text, patterns{i})
                    tf = true;
                    return;
                end
            end
        end

        function name = qualifyTable(db, tableName)
            name = sprintf('%s.%s.%s', db.database, db.schema, tableName);
        end

        function q = quoteTableName(tableName)
            parts = strsplit(tableName, '.');
            parts = cellfun(@(c) bms.analyzer.WimSqlService.quoteIdentifier(c), parts, 'UniformOutput', false);
            q = strjoin(parts, '.');
        end

        function q = quoteIdentifier(name)
            name = char(name);
            name = strrep(name, ']', ']]');
            q = ['[' name ']'];
        end

        function name = objectIdName(tableName)
            parts = strsplit(tableName, '.');
            if numel(parts) >= 2
                name = sprintf('%s.%s', parts{end - 1}, parts{end});
            else
                name = tableName;
            end
        end

        function s = escapeSqlLiteral(s)
            s = char(s);
            s = strrep(s, '''', '''''');
        end

        function s = escapeCmdSql(s)
            s = strrep(s, '"', '""');
        end

        function prependCsvHeader(header, tmpPath, outPath)
            if isempty(header)
                movefile(tmpPath, outPath, 'f');
                return;
            end
            enc = bms.analyzer.WimSqlService.detectFileEncoding(tmpPath);
            [fidIn, msg] = fopen(tmpPath, 'rb');
            if fidIn < 0
                error('Cannot open tmp file: %s', msg);
            end
            bytes = fread(fidIn, inf, 'uint8=>uint8');
            fclose(fidIn);

            if numel(bytes) >= 3 && bytes(1) == 239 && bytes(2) == 187 && bytes(3) == 191
                bytes = bytes(4:end);
            elseif numel(bytes) >= 2 && bytes(1) == 255 && bytes(2) == 254
                bytes = bytes(3:end);
            end

            [fidOut, msg] = fopen(outPath, 'wb');
            if fidOut < 0
                error('Cannot write csv: %s', msg);
            end

            if strcmpi(enc, 'UTF-16LE')
                fwrite(fidOut, uint8([255 254]), 'uint8');
                headerLine = strjoin(header, ',');
                fwrite(fidOut, unicode2native([headerLine newline], 'UTF-16LE'), 'uint8');
                fwrite(fidOut, bytes, 'uint8');
            else
                fwrite(fidOut, uint8([239 187 191]), 'uint8');
                headerLine = strjoin(header, ',');
                fwrite(fidOut, unicode2native([headerLine newline], 'UTF-8'), 'uint8');
                fwrite(fidOut, bytes, 'uint8');
            end
            fclose(fidOut);
            delete(tmpPath);
        end

        function enc = detectFileEncoding(path)
            enc = 'UTF-8';
            fid = fopen(path, 'rb');
            if fid < 0
                return;
            end
            bytes = fread(fid, 3, 'uint8=>uint8');
            fclose(fid);
            if numel(bytes) >= 2 && bytes(1) == 255 && bytes(2) == 254
                enc = 'UTF-16LE';
            elseif numel(bytes) >= 3 && bytes(1) == 239 && bytes(2) == 187 && bytes(3) == 191
                enc = 'UTF-8';
            end
        end

        function value = fieldDefault(s, field, defaultValue)
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                value = s.(field);
            else
                value = defaultValue;
            end
        end
    end
end
