classdef test_wim_zhichen_bcp_source < matlab.unittest.TestCase
    properties
        ProjectRoot
        SampleDir
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
            tc.SampleDir = fullfile(tc.ProjectRoot, 'data', '_samples', 'wim', 'zhichen', '202512');
            addpath(tc.ProjectRoot);
        end
    end

    methods (Test)
        function parseFmtReadsNativeBcpSchema(tc)
            fmtPath = fullfile(tc.SampleDir, 'HS_Data_202512_sample_300.fmt');

            spec = bms.analyzer.WimZhichenBcpSource.loadSpec(fmtPath);

            tc.verifyEqual(numel(spec.fmt), 42);
            tc.verifyEqual(spec.fmt(2).name, 'Lane_Id');
            tc.verifyEqual(spec.fmt(2).type, 'SQLTINYINT');
            tc.verifyEqual(spec.fmt(38).name, 'License_Plate');
            tc.verifyEqual(spec.fmt(38).type, 'SQLNCHAR');
            tc.verifyEqual(spec.fmt(38).prefix, 2);
            tc.verifyEqual(spec.fmt(38).len, 24);
            tc.verifyEqual(spec.index.Gross_Load, 7);
            tc.verifyEqual(spec.index.Temp, 42);
        end

        function decodeFirstSampleRecordMatchesCsvExport(tc)
            fmtPath = fullfile(tc.SampleDir, 'HS_Data_202512_sample_300.fmt');
            bcpPath = fullfile(tc.SampleDir, 'HS_Data_202512_sample_300.bcp');
            spec = bms.analyzer.WimZhichenBcpSource.loadSpec(fmtPath);

            fid = fopen(bcpPath, 'r', 'ieee-le');
            tc.assertGreaterThan(fid, 0);
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

            [rowBytes, ok] = bms.analyzer.WimZhichenBcpSource.readRowBytes(fid, spec.fmt);
            tc.assertTrue(ok);

            row = bms.analyzer.WimZhichenBcpSource.decodeRecord(spec.fmt, spec.index, rowBytes, 'gbk');

            tc.verifyEqual(datestr(row.time_datenum, 'yyyy-mm-dd HH:MM:SS'), '2025-12-01 00:00:00');
            tc.verifyEqual(row.lane, 7);
            tc.verifyEqual(row.axle_num, 2);
            tc.verifyEqual(row.gross, 2240);
            tc.verifyEqual(row.speed, 74);
            tc.verifyEqual(row.axle_weights(1:4), [1380 860 0 0]);
            tc.verifyEqual(row.axle_distances(1:4), [3638 0 0 0]);
            tc.verifyNotEmpty(row.plate);

            raw = bms.analyzer.WimZhichenBcpSource.decodeAllRow(spec.fmt, rowBytes, 'gbk');
            tc.verifyEqual(numel(raw), 42);
            tc.verifyEqual(raw{2}, 7);
            tc.verifyEqual(raw{3}, '2025-12-01 00:00:00');
            tc.verifyEqual(raw{7}, 2240);
            tc.verifyEqual(raw{34}, 74);
        end

        function sqlTypeMapsFmtTypes(tc)
            tc.verifyEqual(bms.analyzer.WimZhichenBcpSource.sqlType(struct('type', 'SQLINT', 'len', 4)), 'INT');
            tc.verifyEqual(bms.analyzer.WimZhichenBcpSource.sqlType(struct('type', 'SQLNCHAR', 'len', 24)), 'NVARCHAR(24)');
            tc.verifyEqual(bms.analyzer.WimZhichenBcpSource.sqlType(struct('type', 'SQLNUMERIC', 'len', 50)), 'NUMERIC(38,0)');
            tc.verifyEqual(bms.analyzer.WimZhichenBcpSource.sqlType(struct('type', 'UNKNOWN', 'len', 4)), 'NVARCHAR(255)');
        end

        function validateRequiredReportsMissingColumns(tc)
            idx = struct('HSData_DT', 1);

            try
                bms.analyzer.WimZhichenBcpSource.validateRequired(idx, {'HSData_DT', 'Lane_Id'});
                tc.verifyFail('Expected missing-column validation to throw.');
            catch ME
                tc.verifyTrue(contains(ME.message, 'Missing column in fmt: Lane_Id'));
            end
        end
    end
end
