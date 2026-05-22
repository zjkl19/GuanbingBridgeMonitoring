classdef test_structural_plot_config_service < matlab.unittest.TestCase
    methods (Test)
        function resolvesPerPointAlarmBounds(tc)
            style = struct('alarm_colors', [1 1 0; 1 0 0], 'ylabel', '应变 (με)');
            cfg.per_point.strain.P_1.alarm_bounds = struct('level2', [-2 2], 'level3', [-3 3]);

            lines = bms.analyzer.StructuralPlotConfigService.resolveWarnLines(style, cfg, 'strain', 'P-1');

            tc.verifyEqual(numel(lines), 4);
            tc.verifyEqual(lines{1}.y, -2);
            tc.verifyEqual(lines{4}.y, 3);
            tc.verifyEqual(lines{1}.color, [1 1 0]);
            tc.verifyEqual(lines{3}.color, [1 0 0]);
            tc.verifyEqual(bms.analyzer.StructuralPlotConfigService.warnLabel(lines{1}), '二级预警值 -2με');
            tc.verifyEqual(bms.analyzer.StructuralPlotConfigService.warnLabel(lines{4}), '三级预警值 3με');
        end

        function explicitEmptyWarnLinesClearGlobal(tc)
            style.warn_lines = [1 2];
            cfg.per_point.tilt.P_1.warn_lines = [];

            lines = bms.analyzer.StructuralPlotConfigService.resolveWarnLines(style, cfg, 'tilt', 'P-1');

            tc.verifyEmpty(lines);
        end

        function groupColorsExpandWhenNeeded(tc)
            style.colors_6 = [1 0 0; 0 1 0];

            colors = bms.analyzer.StructuralPlotConfigService.groupColors(style, 5);

            tc.verifySize(colors, [5 3]);
        end

        function distinctColorsReturnRequestedCategoricalPalette(tc)
            colors = bms.analyzer.StructuralPlotConfigService.distinctColors(16);

            tc.verifySize(colors, [16 3]);
            tc.verifyEqual(size(unique(round(colors, 6), 'rows'), 1), 16);
        end

        function warnLabelNormalizesLegacyTerms(tc)
            wl = struct('y', 100, 'label', '一级阈值100cm/s²');

            label = bms.analyzer.StructuralPlotConfigService.warnLabel(wl);

            tc.verifyEqual(label, '一级预警值 100cm/s²');
        end

        function warnLabelAppendsValueWhenLegacyBoundHasNoNumber(tc)
            wl = struct('y', -36, 'label', '二级下限', 'unit', 'με');

            label = bms.analyzer.StructuralPlotConfigService.warnLabel(wl);

            tc.verifyEqual(label, '二级预警值 -36με');
        end

        function pointFallbackFlattensGroups(tc)
            cfg = struct();
            groups = {{'A', 'B'}, {'B', 'C'}};

            pts = bms.analyzer.StructuralPlotConfigService.getPointsOrFlattenFallback(cfg, 'deflection', groups);

            tc.verifyEqual(pts, {'A'; 'B'; 'C'});
        end
    end
end
