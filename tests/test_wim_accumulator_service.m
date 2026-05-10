classdef test_wim_accumulator_service < matlab.unittest.TestCase
    methods (Test)
        function findBinUsesOpenUpperAndClosedLastBin(tc)
            edges = [0 10 20];

            tc.verifyEqual(bms.analyzer.WimAccumulatorService.findBin(-1, edges), 0);
            tc.verifyEqual(bms.analyzer.WimAccumulatorService.findBin(0, edges), 1);
            tc.verifyEqual(bms.analyzer.WimAccumulatorService.findBin(9.99, edges), 1);
            tc.verifyEqual(bms.analyzer.WimAccumulatorService.findBin(10, edges), 2);
            tc.verifyEqual(bms.analyzer.WimAccumulatorService.findBin(100, edges), 2);
        end

        function updateTopNSortsDescendingAndBreaksTiesByEarlierTime(tc)
            topn = bms.analyzer.WimAccumulatorService.initTopN(3);
            t0 = datenum('2026-01-01 00:00:00');

            topn = bms.analyzer.WimAccumulatorService.updateTopN(topn, 100, t0 + 2, {'late'}, {'raw-late'});
            topn = bms.analyzer.WimAccumulatorService.updateTopN(topn, 200, t0 + 3, {'high'}, {'raw-high'});
            topn = bms.analyzer.WimAccumulatorService.updateTopN(topn, 100, t0 + 1, {'early'}, {'raw-early'});
            topn = bms.analyzer.WimAccumulatorService.updateTopN(topn, 50, t0 + 4, {'low'}, {'raw-low'});

            tc.verifyEqual(topn.values, [200; 100; 100]);
            tc.verifyEqual(topn.std_rows{1}, {'high'});
            tc.verifyEqual(topn.std_rows{2}, {'early'});
            tc.verifyEqual(topn.std_rows{3}, {'late'});
            tc.verifyFalse(bms.analyzer.WimAccumulatorService.qualifiesForTopN(topn, 50, t0));
            tc.verifyTrue(bms.analyzer.WimAccumulatorService.qualifiesForTopN(topn, 100, t0));
        end

        function standardRowKeepsWimTopNColumnShape(tc)
            t = datenum('2026-01-01 01:02:03');

            row = bms.analyzer.WimAccumulatorService.standardRow(1, t, 2, 30000, 70, '闽A12345', [100 200], [1000 2000]);

            tc.verifyEqual(row(1:6), {1, '2026-01-01 01:02:03', 2, 30000, 70, '闽A12345'});
            tc.verifyEqual(row(7:8), {100, 200});
            tc.verifyEqual(row(9:10), {1000, 2000});
        end
    end
end
