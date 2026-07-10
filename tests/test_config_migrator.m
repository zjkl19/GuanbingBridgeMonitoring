classdef test_config_migrator < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'config'), fullfile(proj, 'pipeline'), fullfile(proj, 'analysis'));
        end
    end

    methods (Test)
        function migratesSparseConfigInMemory(tc)
            cfg = bms.config.ConfigMigrator.migrate(struct());

            tc.verifyEqual(cfg.config_schema_version, bms.config.ConfigMigrator.TargetVersion);
            tc.verifyTrue(isstruct(cfg.defaults));
            tc.verifyTrue(isstruct(cfg.per_point));
            tc.verifyFalse(cfg.plot_common.append_timestamp);
            tc.verifyEqual(cfg.plot_common.gap_mode, 'connect');
            tc.verifyEqual(cfg.plot_common.gap_break_factor, 5);
            tc.verifyEqual(cfg.plot_common.dynamic_raw_sampling_mode, 'capped');
            tc.verifyFalse(cfg.gui.show_warnings);
        end

        function preservesExistingValues(tc)
            input = struct('plot_common', struct('gap_mode', 'connect', 'fig_max_points', 123), ...
                'gui', struct('show_warnings', true));
            cfg = bms.config.ConfigMigrator.migrate(input);

            tc.verifyEqual(cfg.plot_common.gap_mode, 'connect');
            tc.verifyEqual(cfg.plot_common.fig_max_points, 123);
            tc.verifyTrue(cfg.gui.show_warnings);
        end

        function normalizesDynamicRawSamplingMode(tc)
            input = struct('plot_common', struct('dynamic_raw_sampling_mode', ' FULL '));
            cfg = bms.config.ConfigMigrator.migrate(input);
            tc.verifyEqual(cfg.plot_common.dynamic_raw_sampling_mode, 'full');

            input.plot_common.dynamic_raw_sampling_mode = 'unexpected';
            cfg = bms.config.ConfigMigrator.migrate(input);
            tc.verifyEqual(cfg.plot_common.dynamic_raw_sampling_mode, 'capped');
        end

        function plotCommonExtractionCarriesSamplingMode(tc)
            cfg = struct('plot_common', struct('dynamic_raw_sampling_mode', 'full'));

            common = bms.app.LegacyStepFunctions.extractPlotCommon(cfg);

            tc.verifyEqual(common.dynamic_raw_sampling_mode, 'full');
        end
    end
end
