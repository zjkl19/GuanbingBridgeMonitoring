classdef test_structural_plot_config_service < matlab.unittest.TestCase
    methods (Test)
        function resolvesPerPointAlarmBounds(tc)
            style = struct('alarm_colors', [1 1 0; 1 0 0]);
            cfg.per_point.strain.P_1.alarm_bounds = struct('level2', [-2 2], 'level3', [-3 3]);

            lines = bms.analyzer.StructuralPlotConfigService.resolveWarnLines(style, cfg, 'strain', 'P-1');

            tc.verifyEqual(numel(lines), 4);
            tc.verifyEqual(lines{1}.y, -2);
            tc.verifyEqual(lines{4}.y, 3);
            tc.verifyEqual(lines{1}.color, [1 1 0]);
            tc.verifyEqual(lines{3}.color, [1 0 0]);
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

        function pointFallbackFlattensGroups(tc)
            cfg = struct();
            groups = {{'A', 'B'}, {'B', 'C'}};

            pts = bms.analyzer.StructuralPlotConfigService.getPointsOrFlattenFallback(cfg, 'deflection', groups);

            tc.verifyEqual(pts, {'A'; 'B'; 'C'});
        end
    end
end
