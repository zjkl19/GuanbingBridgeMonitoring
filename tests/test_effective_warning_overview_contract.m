classdef test_effective_warning_overview_contract < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addProjectRoot(~)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(projectRoot);
        end
    end

    methods (Test)
        function guanbingLegacyWarningSourcesMatchRuntimeConsumers(tc)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            cfg = jsondecode(fileread(fullfile(projectRoot, 'config', 'default_config.json')));

            % The narrow alarm_bounds editor is correctly empty for Guanbing.
            spec = struct('value', 'deflection', 'per_point_key', 'deflection', ...
                'point_key', 'deflection');
            tc.verifyEmpty(bms.gui.AlarmBoundsEditorService.rows(cfg, spec));

            % The runtime nevertheless consumes these effective warning sources.
            wind = bms.analyzer.WindSeriesService.params(cfg, '');
            tc.verifyEqual(wind.alarm_levels, [25, 29.92, 37.4], 'AbsTol', 1e-12);

            deflection = bms.analyzer.StructuralPlotConfigService.resolveWarnLines( ...
                cfg.plot_styles.deflection, cfg, 'deflection', '');
            deflection = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(deflection);
            tc.verifyEqual(cellfun(@(item) double(item.y), deflection).', ...
                [-21, 33.4, -26.3, 41.7], 'AbsTol', 1e-12);

            tilt = bms.analyzer.StructuralPlotConfigService.resolveWarnLines( ...
                cfg.plot_styles.tilt, cfg, 'tilt', '');
            tilt = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(tilt);
            tc.verifyEqual(cellfun(@(item) double(item.y), tilt).', ...
                [-0.126, 0.126, -0.155, 0.155], 'AbsTol', 1e-12);
        end
    end
end
