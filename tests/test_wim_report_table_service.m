classdef test_wim_report_table_service < matlab.unittest.TestCase
    methods (Test)
        function binTableBuildsClosedLastBinLabels(tc)
            [labels, counts] = bms.analyzer.WimReportTableService.binTable([0 10 20], [3; 4]);

            tc.verifyEqual(labels, ["0-9"; ">=10"]);
            tc.verifyEqual(counts, [3; 4]);
        end

        function buildTopNTableNormalizesRowsAndPlate(tc)
            topn = struct();
            topn.std_rows = cell(3, 1);
            topn.std_rows{1} = {1, '2026-01-01 00:00:00', 2, 30000, 70, ['A'; 'B'], 1000};
            topn.std_rows{2} = [];
            topn.std_rows{3} = {2, '2026-01-01 00:01:00', 3, 28000, 65, "闽A12345", 900, 800, 700, 600, 500, 400, 300, 200, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 'extra'};

            T = bms.analyzer.WimReportTableService.buildTopNTable(topn);

            tc.verifyEqual(height(T), 2);
            tc.verifyEqual(T.rank, [1; 2]);
            tc.verifyEqual(T.Properties.VariableNames(1), {'rank'});
            tc.verifyEqual(T.plate(1), "AB");
            tc.verifyEqual(T.plate(2), "闽A12345");
            tc.verifyEqual(T.axle1(1), 1000);
            tc.verifyEqual(T.axledis7{2}, 7000);
        end

        function buildRawTopNTableNormalizesHeadersAndRows(tc)
            headers = {'time', '', 'gross'};
            rawRows = {
                {'t1', 1};
                {};
                {'t2', 2, 30000, 'ignored'}
            };

            T = bms.analyzer.WimReportTableService.buildRawTopNTable(headers, rawRows);

            tc.verifyEqual(T.Properties.VariableNames, {'time', 'Var2', 'gross'});
            tc.verifyEqual(height(T), 2);
            tc.verifyEqual(T.time{1}, 't1');
            tc.verifyEqual(T.gross{1}, []);
            tc.verifyEqual(T.gross{2}, 30000);
        end

        function convertAxleDistancesMmToMOnlyChangesAxledisColumns(tc)
            T = table([1000; 2500], [10; 20], ["3000"; "4500"], ...
                'VariableNames', {'axledis1', 'gross_kg', 'AxleDis2'});

            out = bms.analyzer.WimReportTableService.convertAxleDistancesMmToM(T);

            tc.verifyEqual(out.axledis1, [1; 2.5]);
            tc.verifyEqual(out.gross_kg, [10; 20]);
            tc.verifyEqual(out.AxleDis2, [3; 4.5]);
        end
    end
end
