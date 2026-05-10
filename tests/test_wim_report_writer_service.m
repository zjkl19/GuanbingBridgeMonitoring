classdef test_wim_report_writer_service < matlab.unittest.TestCase
    properties
        TempDir
    end

    methods (TestMethodSetup)
        function setupTempDir(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
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
        function writesCsvAndExcelWithHongtangMetricSheets(tc)
            reports = struct();
            reports.TopN = table(1, "2026-01-01 00:00:00", 30000, 1000, ...
                'VariableNames', {'lane','time','gross_kg','axledis1'});
            reports.TopN_MaxAxle = table(2, "2026-01-01 00:01:00", 25000, 2500, ...
                'VariableNames', {'lane','time','gross_kg','axledis1'});
            reports.DailyTraffic = table(datetime("2026-01-01"), 1, 2, 3, ...
                'VariableNames', {'date','up_cnt','down_cnt','total'});

            csvPaths = bms.analyzer.WimReportWriterService.writeCsvs(reports, tc.TempDir, '202601');
            excelPath = fullfile(tc.TempDir, 'WIM_Report.xlsx');
            bms.analyzer.WimReportWriterService.writeExcelFromCsvs(csvPaths, excelPath, 'hongtang');

            tc.verifyTrue(isfile(csvPaths.TopN));
            tc.verifyTrue(isfile(csvPaths.DailyTraffic));
            tc.verifyTrue(isfile(excelPath));

            sheets = sheetnames(excelPath);
            tc.verifyTrue(ismember("TopN", sheets));
            tc.verifyTrue(ismember("TopN_m", sheets));
            Tm = readtable(excelPath, 'Sheet', 'TopN_m');
            tc.verifyEqual(Tm.axledis1, 1);
        end

        function safeSheetNameSanitizesAndTruncates(tc)
            name = 'a:b/c?d*e[f]012345678901234567890123456789';
            out = bms.analyzer.WimReportWriterService.safeSheetName(name);

            tc.verifyLessThanOrEqual(numel(out), 31);
            tc.verifyFalse(contains(out, ':'));
            tc.verifyFalse(contains(out, '/'));
            tc.verifyFalse(contains(out, '['));
        end
    end
end
