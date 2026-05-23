classdef test_plot_warning_line_resolver < matlab.unittest.TestCase
    methods (Test)
        function explicitWarnLinesStayEditable(tc)
            style.warn_lines = struct('y', 10, 'label', '二级阈值10mm', 'color', [1 0 0]);
            spec = struct('value', 'deflection', 'style_key', 'deflection');

            preview = bms.analyzer.PlotWarningLineResolver.tablePreview(struct(), spec, style, 'warn_lines');

            tc.verifyFalse(preview.is_preview);
            tc.verifyEqual(size(preview.rows, 1), 1);
            tc.verifyEqual(preview.rows{1, 1}, 10);
            tc.verifyEqual(preview.source, 'explicit');
        end

        function groupMapWarnLinesAreReadOnlyPreview(tc)
            style.group_warn_lines.G1 = struct('y', -80, 'label', '二级预警值 -80mm', 'color', [0.72 0.5 0]);
            spec = struct('value', 'bearing_displacement', 'style_key', 'bearing_displacement');

            preview = bms.analyzer.PlotWarningLineResolver.tablePreview(struct(), spec, style, 'group_warn_lines');

            tc.verifyTrue(preview.is_preview);
            tc.verifyEqual(size(preview.rows, 1), 1);
            tc.verifyTrue(contains(preview.rows{1, 2}, 'G1'));
            tc.verifyEqual(preview.source, 'explicit_map');
        end

        function derivesPointAlarmBounds(tc)
            cfg.points.deflection = {'P-1'};
            cfg.per_point.deflection.P_1.alarm_bounds = struct('level2', [-2 2]);
            style = struct('ylabel', '位移 (mm)');
            spec = struct('value', 'deflection', 'style_key', 'deflection');

            preview = bms.analyzer.PlotWarningLineResolver.tablePreview(cfg, spec, style, 'warn_lines');
            values = cell2mat(preview.rows(:, 1));

            tc.verifyTrue(preview.is_preview);
            tc.verifyEqual(sort(values(:)), [-2; 2]);
            tc.verifyTrue(contains(preview.hint, 'per_point.deflection'));
        end

        function derivesCommonGroupAlarmBounds(tc)
            cfg.groups.strain_timeseries.GDDYB = {'S-1', 'S-2'};
            cfg.per_point.strain.S_1.alarm_bounds = struct('level2', [-264 264]);
            cfg.per_point.strain.S_2.alarm_bounds = struct('level2', [-264 264]);
            style = struct('ylabel', '应变 (με)');
            spec = struct('value', 'strain', 'style_key', 'strain');

            preview = bms.analyzer.PlotWarningLineResolver.tablePreview(cfg, spec, style, 'group_warn_lines');
            values = cell2mat(preview.rows(:, 1));

            tc.verifyTrue(preview.is_preview);
            tc.verifyEqual(sort(values(:)), [-264; 264]);
            tc.verifyTrue(all(contains(preview.rows(:, 2), 'GDDYB')));
        end

        function derivesEarthquakeAlarmLevels(tc)
            cfg.points.eq = {'EQ-X', 'EQ-Y'};
            cfg.eq_params.alarm_levels = [1.5 2.55];
            style = struct('ylabel', '地震动加速度 (m/s^2)');
            spec = struct('value', 'earthquake', 'style_key', 'eq');

            preview = bms.analyzer.PlotWarningLineResolver.tablePreview(cfg, spec, style, 'warn_lines');
            values = cell2mat(preview.rows(:, 1));

            tc.verifyTrue(preview.is_preview);
            tc.verifyEqual(sort(values(:)), [1.5; 2.55]);
            tc.verifyTrue(contains(preview.hint, 'alarm_levels'));
        end
    end
end
