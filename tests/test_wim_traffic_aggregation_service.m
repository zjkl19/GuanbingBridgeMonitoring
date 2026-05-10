classdef test_wim_traffic_aggregation_service < matlab.unittest.TestCase
    methods (Test)
        function aggregatesDirectTrafficRecords(tc)
            wim = test_wim_traffic_aggregation_service.sampleWimConfig();
            acc = bms.analyzer.WimTrafficAggregationService.initAccumulators(wim, '2026-01-01', '2026-01-02');
            t1 = datenum('2026-01-01 01:00:00');
            t2 = datenum('2026-01-02 13:00:00');

            tc.verifyTrue(bms.analyzer.WimTrafficAggregationService.isInRange(acc, t1));
            tc.verifyFalse(bms.analyzer.WimTrafficAggregationService.isInRange(acc, datenum('2026-01-03 00:00:00')));

            acc = bms.analyzer.WimTrafficAggregationService.addRecord(acc, ...
                t1, 1, 12000, 40, [1000 2000 0 0 0 0 0 0], 2, 'A', [1000 0 0 0 0 0 0], {'raw1'}, {'H1'});
            acc = bms.analyzer.WimTrafficAggregationService.addRecord(acc, ...
                t2, 3, 60000, 80, [50000 1000 0 0 0 0 0 0], 2, 'B', [2000 0 0 0 0 0 0], {'raw2'}, {'H1'});

            reports = bms.analyzer.WimTrafficAggregationService.buildReportTables(acc);

            tc.verifyEqual(reports.DailyTraffic.total, [1; 1]);
            tc.verifyEqual(reports.DailyTraffic.up_cnt, [1; 0]);
            tc.verifyEqual(reports.DailyTraffic.down_cnt, [0; 1]);
            tc.verifyEqual(sum(reports.LaneSpeedWeight_Lane.count), 2);
            tc.verifyEqual(sum(reports.LaneSpeedWeight_Speed.count), 2);
            tc.verifyEqual(sum(reports.LaneSpeedWeight_Gross.count), 2);
            tc.verifyEqual(sum(reports.Hourly_Count.count), 2);
            tc.verifyEqual(reports.CustomThresholds_Overall.over_cnt, [1; 1]);
            tc.verifyEqual(height(reports.TopN), 2);
            tc.verifyEqual(reports.TopN.gross_kg(1), 60000);
            tc.verifyEqual(height(reports.TopN_MaxAxle), 2);
            tc.verifyEqual(reports.Overload_Summary.count(1), 1);
            tc.verifyEqual(reports.Overload_Summary.count(3), 1);
        end

        function maxAxleTopNQualificationUsesCurrentAccumulator(tc)
            wim = test_wim_traffic_aggregation_service.sampleWimConfig();
            wim.topn = 1;
            acc = bms.analyzer.WimTrafficAggregationService.initAccumulators(wim, '2026-01-01', '2026-01-01');
            t = datenum('2026-01-01 00:00:00');

            tc.verifyTrue(bms.analyzer.WimTrafficAggregationService.qualifiesForMaxAxleTopN(acc, [10 20], t));
            acc = bms.analyzer.WimTrafficAggregationService.addRecord(acc, t, 1, 1000, 40, [10 20], 2, 'A', zeros(1,7), {'raw'}, {'H'});

            tc.verifyFalse(bms.analyzer.WimTrafficAggregationService.qualifiesForMaxAxleTopN(acc, [5 6], t + 1));
            tc.verifyTrue(bms.analyzer.WimTrafficAggregationService.qualifiesForMaxAxleTopN(acc, [20 0], t - 1));
        end
    end

    methods (Static, Access = private)
        function wim = sampleWimConfig()
            wim = struct();
            wim.lanes = 1:4;
            wim.up_lanes = 1:2;
            wim.speed_bins = [0 50 100];
            wim.gross_bins = [0 30000 999999];
            wim.hour_bins = [0 12 24];
            wim.custom_weights = [30000 50000];
            wim.critical_lanes = 1:4;
            wim.hourly_critical_weight_kg = 50000;
            wim.topn = 3;
            wim.overload_factors = [1.0 2.0];
            wim.design_total_kg = 55000;
            wim.design_axle_kg = 28000;
        end
    end
end
