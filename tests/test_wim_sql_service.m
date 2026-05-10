classdef test_wim_sql_service < matlab.unittest.TestCase
    properties
        TempDir
        ProjectRoot
    end

    methods (TestMethodSetup)
        function setupTempDir(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            tc.ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(tc.ProjectRoot);
        end
    end

    methods (TestMethodTeardown)
        function cleanupTempDir(tc)
            if exist(tc.TempDir, 'dir')
                rmdir(tc.TempDir, 's');
            end
        end
    end

    methods (Test)
        function quotesNamesAndEscapesSqlText(tc)
            tc.verifyEqual(bms.analyzer.WimSqlService.quoteIdentifier('a]b'), '[a]]b]');
            tc.verifyEqual(bms.analyzer.WimSqlService.quoteTableName('DB.dbo.WIM'), '[DB].[dbo].[WIM]');
            tc.verifyEqual(bms.analyzer.WimSqlService.objectIdName('DB.dbo.WIM'), 'dbo.WIM');
            tc.verifyEqual(bms.analyzer.WimSqlService.escapeSqlLiteral("C:\a'b"), 'C:\a''''b');
            tc.verifyEqual(bms.analyzer.WimSqlService.escapeCmdSql('select "x"'), 'select ""x""');
        end

        function buildsSqlReportVariables(tc)
            wim = struct();
            wim.lanes = 1:3;
            wim.up_lanes = [1 2];
            wim.speed_bins = [0 30 50];
            wim.gross_bins = [0 10000 999999];
            wim.hour_bins = [0 12 24];
            wim.custom_weights = [30000 50000];
            wim.critical_lanes = [2 3];
            wim.hourly_critical_weight_kg = 50000;
            wim.topn = 10;
            wim.design_total_kg = 55000;
            wim.design_axle_kg = 28000;
            wim.overload_factors = [1.5 2.0];

            vars = bms.analyzer.WimSqlService.reportVars(wim, 'DB.dbo.T', '2026-01-01', '2026-02-01');

            tc.verifyEqual(vars.SrcTable, 'DB.dbo.T');
            tc.verifyEqual(vars.LaneText, '1,2,3');
            tc.verifyEqual(vars.UpLanes, '1,2');
            tc.verifyEqual(vars.OverloadFactors, '1.5,2');
            tc.verifyEqual(vars.TopN, 10);
        end

        function createsTableSqlFromNativeFmt(tc)
            fmtPath = fullfile(tc.ProjectRoot, 'data', '_samples', 'wim', 'zhichen', '202512', 'HS_Data_202512_sample_300.fmt');

            sql = bms.analyzer.WimSqlService.createTableSqlFromFmt('HighSpeed_PROC.dbo.HS_Data_202512', fmtPath);

            tc.verifyTrue(contains(sql, 'OBJECT_ID(''dbo.HS_Data_202512'', ''U'')'));
            tc.verifyTrue(contains(sql, 'CREATE TABLE [HighSpeed_PROC].[dbo].[HS_Data_202512]'));
            tc.verifyTrue(contains(sql, '[Lane_Id] TINYINT NULL'));
            tc.verifyTrue(contains(sql, '[License_Plate] NVARCHAR(24) NULL'));
            tc.verifyTrue(contains(sql, '[Acceleration] NUMERIC(19,0) NULL'));
        end

        function createsRawTableSqlNormalizesHeaders(tc)
            sql = bms.analyzer.WimSqlService.createRawTableSql('DB.dbo.Raw', {'time', '', 'a]b'});

            tc.verifyTrue(contains(sql, '[time] NVARCHAR(255) NULL'));
            tc.verifyTrue(contains(sql, '[Var2] NVARCHAR(255) NULL'));
            tc.verifyTrue(contains(sql, '[a]]b] NVARCHAR(255) NULL'));
        end

        function classifiesSqlcmdErrors(tc)
            db = struct('server', '.\SQLEXPRESS', 'database', 'HighSpeed_PROC', 'service_name', 'MSSQLSERVER');

            [errId, msg] = bms.analyzer.WimSqlService.classifySqlcmdError(db, 'Cannot open database "HighSpeed_PROC"', 'query');
            tc.verifyEqual(errId, 'WIM:SQL:DatabaseMissing');
            tc.verifyTrue(contains(msg, 'HighSpeed_PROC'));

            [errId, ~] = bms.analyzer.WimSqlService.classifySqlcmdError(db, 'Login failed for user X', 'query');
            tc.verifyEqual(errId, 'WIM:SQL:Permission');

            [errId, ~] = bms.analyzer.WimSqlService.classifySqlcmdError(db, 'Named Pipes Provider, error: 40', 'query');
            tc.verifyEqual(errId, 'WIM:SQL:Instance');
        end

        function prependsUtf8CsvHeader(tc)
            tmpPath = fullfile(tc.TempDir, 'utf8.tmp');
            outPath = fullfile(tc.TempDir, 'utf8.csv');
            fid = fopen(tmpPath, 'wb');
            fwrite(fid, uint8([239 187 191]), 'uint8');
            fwrite(fid, unicode2native(['1,2' newline], 'UTF-8'), 'uint8');
            fclose(fid);

            bms.analyzer.WimSqlService.prependCsvHeader({'a', 'b'}, tmpPath, outPath);

            tc.verifyFalse(isfile(tmpPath));
            tc.verifyEqual(bms.analyzer.WimSqlService.detectFileEncoding(outPath), 'UTF-8');
            fid = fopen(outPath, 'rb');
            bytes = fread(fid, inf, 'uint8=>uint8');
            fclose(fid);
            tc.verifyEqual(bytes(1:3).', uint8([239 187 191]));
            text = native2unicode(bytes(4:end).', 'UTF-8');
            tc.verifyTrue(startsWith(string(text), "a,b"));
            tc.verifyTrue(contains(string(text), "1,2"));
        end

        function prependsUtf16CsvHeader(tc)
            tmpPath = fullfile(tc.TempDir, 'utf16.tmp');
            outPath = fullfile(tc.TempDir, 'utf16.csv');
            fid = fopen(tmpPath, 'wb');
            fwrite(fid, uint8([255 254]), 'uint8');
            fwrite(fid, unicode2native(['1,2' newline], 'UTF-16LE'), 'uint8');
            fclose(fid);

            bms.analyzer.WimSqlService.prependCsvHeader({'a', 'b'}, tmpPath, outPath);

            tc.verifyEqual(bms.analyzer.WimSqlService.detectFileEncoding(outPath), 'UTF-16LE');
            fid = fopen(outPath, 'rb');
            bytes = fread(fid, inf, 'uint8=>uint8');
            fclose(fid);
            tc.verifyEqual(bytes(1:2).', uint8([255 254]));
            text = native2unicode(bytes(3:end).', 'UTF-16LE');
            tc.verifyTrue(startsWith(string(text), "a,b"));
            tc.verifyTrue(contains(string(text), "1,2"));
        end
    end
end
