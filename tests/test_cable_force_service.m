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
            style = struct('force_alarm_colors', [1 1 0; 1 0 0], 'force_ylabel', '索力 (kN)');

            warnLines = bms.analyzer.CableForceService.normalizeWarnLines([10 20], style, 'S1');

            tc.verifyEqual(numel(warnLines), 2);
            tc.verifyEqual(warnLines{1}.y, 10);
            tc.verifyEqual(bms.analyzer.CableForceService.warnLabel(warnLines{1}), 'S1 一级预警值 10kN');
            tc.verifyEqual(warnLines{2}.color, [1 0 0]);
        end

        function warnLinesPreferPerPointBounds(tc)
            cfg = struct();
            cfg.per_point.cable_accel.CABLE_01 = struct( ...
                'force_alarm_bounds', struct('level2', [20 10], 'level3', [30 40]));
            style = struct('force_warn_lines', [1 2], 'force_alarm_colors', [1 1 0; 1 0 0], ...
                'force_ylabel', '索力 (kN)');

            warnLines = bms.analyzer.CableForceService.warnLines(cfg, 'CABLE-01', style, 'C1');

            tc.verifyEqual(numel(warnLines), 4);
            tc.verifyEqual(warnLines{1}.y, 10);
            tc.verifyEqual(warnLines{2}.y, 20);
            tc.verifyEqual(bms.analyzer.CableForceService.warnLabel(warnLines{3}), 'C1 三级预警值 30kN');
            tc.verifyEqual(warnLines{4}.color, [1 0 0]);
        end

        function forceFrequenciesCanUseReferenceTarget(tc)
            cfg.per_point.cable_accel.CABLE_01 = struct( ...
                'target_freqs', 1.4665, ...
                'force_reference_from_target', true);
            freqDay = [1.1; NaN; 1.9];

            freqs = bms.analyzer.CableForceService.forceFrequencies(cfg, 'CABLE-01', freqDay);

            tc.verifyEqual(freqs, [1.4665; NaN; 1.4665]);
        end

        function forceTimeseriesDrawsSinglePointWarnLines(tc)
            rootDir = tempname;
            mkdir(rootDir);
            tc.addTeardown(@() rmdir(rootDir, 's'));
            cfg.plot_common = struct('save_fig', true, 'append_timestamp', false, 'lightweight_fig', false);
            style = struct( ...
                'force_ylabel', 'Cable force (kN)', ...
                'force_title_prefix', 'Cable force', ...
                'force_color', [0 0.447 0.741], ...
                'force_alarm_colors', [1 1 0; 1 0 0], ...
                'colors', {{[0 0.447 0.741]}});
            warnLines = bms.analyzer.CableForceService.normalizeAlarmBounds( ...
                struct('level2', [97 103], 'level3', [95 105]), style, '');
            datesAll = (datetime(2026, 3, 1):days(1):datetime(2026, 3, 2)).';

            bms.analyzer.SpectrumPlotService.plotForceTimeseries( ...
                {datesAll}, {[100; 101]}, {'C1'}, 'C1', rootDir, style, [], {warnLines}, cfg);

            files = dir(fullfile(rootDir, 'CableForce_C1_*.fig'));
            tc.verifyEqual(numel(files), 1);
            values = local_constant_line_values(fullfile(files(1).folder, files(1).name));
            tc.verifyEqual(values(:), [95; 97; 103; 105]);
        end
    end
end

function values = local_constant_line_values(figPath)
    fig = openfig(figPath, 'invisible');
    cleaner = onCleanup(@() close(fig)); %#ok<NASGU>
    lines = findall(fig, '-isa', 'matlab.graphics.chart.decoration.ConstantLine');
    if isempty(lines)
        values = [];
        return;
    end
    values = sort(arrayfun(@(h) h.Value, lines));
end
