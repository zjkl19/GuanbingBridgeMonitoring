classdef test_cable_force_service < matlab.unittest.TestCase
    methods (Test)
        function computeUsesFrequencyRhoAndLength(tc)
            force = bms.analyzer.CableForceService.compute([1; 2], 50, 10, 1);

            tc.verifyEqual(force, [20; 80]);
        end

        function paramsAndYLimPreferPerPointConfig(tc)
            cfg = struct();
            cfg.per_point.cable_accel.CABLE_01 = struct( ...
                'rho', 60, ...
                'L', 12, ...
                'force_decimals', 3, ...
                'force_ylim', [10 100]);
            style = struct('force_ylim', [0 50]);

            [rho, spanLength, decimals, hasParams] = bms.analyzer.CableForceService.params(cfg, 'CABLE-01');
            ylimValue = bms.analyzer.CableForceService.resolveYLim(cfg, 'CABLE-01', style);

            tc.verifyEqual(rho, 60);
            tc.verifyEqual(spanLength, 12);
            tc.verifyEqual(decimals, 3);
            tc.verifyTrue(hasParams);
            tc.verifyEqual(ylimValue, [10 100]);
        end

        function warnLinesUseNumericLevelsAndLabels(tc)
            style = struct('force_alarm_colors', [1 1 0; 1 0 0]);

            warnLines = bms.analyzer.CableForceService.normalizeWarnLines([10 20], style, 'S1');

            tc.verifyEqual(numel(warnLines), 2);
            tc.verifyEqual(warnLines{1}.y, 10);
            tc.verifyEqual(warnLines{1}.label, 'S1 黄色预警');
            tc.verifyEqual(warnLines{2}.color, [1 0 0]);
        end

        function warnLinesPreferPerPointBounds(tc)
            cfg = struct();
            cfg.per_point.cable_accel.CABLE_01 = struct( ...
                'force_alarm_bounds', struct('level2', [20 10], 'level3', [30 40]));
            style = struct('force_warn_lines', [1 2], 'force_alarm_colors', [1 1 0; 1 0 0]);

            warnLines = bms.analyzer.CableForceService.warnLines(cfg, 'CABLE-01', style, 'C1');

            tc.verifyEqual(numel(warnLines), 4);
            tc.verifyEqual(warnLines{1}.y, 10);
            tc.verifyEqual(warnLines{2}.y, 20);
            tc.verifyEqual(warnLines{3}.label, 'C1 三级下限');
            tc.verifyEqual(warnLines{4}.color, [1 0 0]);
        end
    end
end
