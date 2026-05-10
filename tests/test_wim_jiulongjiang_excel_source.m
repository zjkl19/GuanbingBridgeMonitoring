classdef test_wim_jiulongjiang_excel_source < matlab.unittest.TestCase
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
        function parseTableResolvesJiulongjiangColumns(tc)
            T = table( ...
                datetime(["2025-04-04 01:02:03.123"; "2025-04-04 02:03:04.567"], 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS'), ...
                ["车道2"; "车道10"], ...
                ["80"; "65"], ...
                [30000; 50000], ...
                [2; 3], ...
                ["闽E12345"; "闽E54321"], ...
                [10000; 12000], ...
                [11000; 13000], ...
                [2500; 2600], ...
                'VariableNames', {'采集时间','车道','车速(Km/h)','总重(kg)','轴数(个)','车牌号','轴重1','轴重2','轴距1'});

            rows = bms.analyzer.WimJiulongjiangExcelSource.parseTable(T);

            tc.verifyEqual(rows.lane, [2; 10]);
            tc.verifyEqual(rows.speed, [80; 65]);
            tc.verifyEqual(rows.gross, [30000; 50000]);
            tc.verifyEqual(rows.axle_num, [2; 3]);
            tc.verifyEqual(rows.plate, {'闽E12345'; '闽E54321'});
            tc.verifySize(rows.axle_weights, [2 8]);
            tc.verifyEqual(rows.axle_weights(:, 1:2), [10000 11000; 12000 13000]);
            tc.verifyEqual(rows.axle_weights(:, 3), [0; 0]);
            tc.verifySize(rows.axle_distances, [2 7]);
            tc.verifyEqual(rows.axle_distances(:, 1), [2500; 2600]);
        end

        function parseTableFallsBackToNumericLaneId(tc)
            T = table( ...
                ["2025-04-04 01:02:03.123"; "2025-04-04 02:03:04.567"], ...
                ["3"; "4"], ...
                [30000; 50000], ...
                'VariableNames', {'时间','车道号','总重'});

            rows = bms.analyzer.WimJiulongjiangExcelSource.parseTable(T);

            tc.verifyEqual(rows.lane, [3; 4]);
            tc.verifyEqual(rows.gross, [30000; 50000]);
            tc.verifyTrue(all(isnan(rows.speed)));
            tc.verifyTrue(all(isnan(rows.axle_num)));
        end

        function normalizedTableMatchesSqlStageShape(tc)
            T = table( ...
                datetime("2025-04-04 01:02:03.123", 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS'), ...
                "车道2", ...
                80, ...
                30000, ...
                2, ...
                "闽E12345", ...
                10000, ...
                11000, ...
                2500, ...
                'VariableNames', {'采集时间','车道','车速','总重','轴数','车牌号','轴重1','轴重2','轴距1'});

            rows = bms.analyzer.WimJiulongjiangExcelSource.parseTable(T);
            Tnorm = bms.analyzer.WimJiulongjiangExcelSource.normalizedTable(rows, 10);

            expected = {'HSData_Id','Lane_Id','HSData_DT','Axle_Num','Gross_Load','Speed','License_Plate', ...
                'LWheel_1_W','LWheel_2_W','LWheel_3_W','LWheel_4_W','LWheel_5_W','LWheel_6_W','LWheel_7_W','LWheel_8_W', ...
                'RWheel_1_W','RWheel_2_W','RWheel_3_W','RWheel_4_W','RWheel_5_W','RWheel_6_W','RWheel_7_W','RWheel_8_W', ...
                'AxleDis1','AxleDis2','AxleDis3','AxleDis4','AxleDis5','AxleDis6','AxleDis7'};

            tc.verifyEqual(Tnorm.Properties.VariableNames, expected);
            tc.verifyEqual(Tnorm.HSData_Id, 11);
            tc.verifyEqual(Tnorm.Lane_Id, 2);
            tc.verifyEqual(Tnorm.Gross_Load, 30000);
            tc.verifyEqual(Tnorm.LWheel_1_W, 10000);
            tc.verifyEqual(Tnorm.LWheel_2_W, 11000);
            tc.verifyEqual(Tnorm.LWheel_3_W, 0);
            tc.verifyEqual(Tnorm.RWheel_1_W, 0);
            tc.verifyEqual(Tnorm.AxleDis1, 2500);
        end

        function buildStageWritesRawAndNormalizedTsv(tc)
            T = table( ...
                datetime(["2025-04-04 01:02:03.123"; "2025-04-04 02:03:04.567"], 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS'), ...
                ["车道2"; "车道3"], ...
                [80; 65], ...
                [30000; 50000], ...
                [2; 3], ...
                ["闽E12345"; "闽E54321"], ...
                [10000; 12000], ...
                [11000; 13000], ...
                [2500; 2600], ...
                'VariableNames', {'采集时间','车道','车速','总重','轴数','车牌号','轴重1','轴重2','轴距1'});
            sourceFile = fullfile(tc.TempDir, 'jiulongjiang.xlsx');
            writetable(T, sourceFile);

            [normCsv, rawCsv, meta] = bms.analyzer.WimJiulongjiangExcelSource.buildStage({sourceFile}, tc.TempDir);

            tc.verifyTrue(isfile(normCsv));
            tc.verifyTrue(isfile(rawCsv));
            tc.verifyEqual(meta.time_col, '采集时间');
            tc.verifyEqual(meta.axle_cols(1:2), {'轴重1','轴重2'});

            Tnorm = readtable(normCsv, 'FileType', 'text', 'Delimiter', '\t', 'VariableNamingRule', 'preserve');
            tc.verifyEqual(height(Tnorm), 2);
            tc.verifyEqual(Tnorm.HSData_Id, [1; 2]);
            tc.verifyEqual(Tnorm.Lane_Id, [2; 3]);
            tc.verifyEqual(Tnorm.LWheel_1_W, [10000; 12000]);
            tc.verifyEqual(Tnorm.RWheel_1_W, [0; 0]);
        end
    end
end
