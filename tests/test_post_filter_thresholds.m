classdef test_post_filter_thresholds < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(fullfile(proj, 'pipeline'));
            addpath(fullfile(proj, 'scripts'));
        end
    end

    methods (Test)
        function mergeDefaultAndPerPointRules(tc)
            cfg = struct();
            cfg.defaults = struct();
            cfg.defaults.deflection = struct( ...
                'post_filter_thresholds', struct( ...
                    'min', -10, 'max', 10, ...
                    't_range_start', '', 't_range_end', ''));
            cfg.per_point = struct();
            cfg.per_point.deflection = struct();
            cfg.per_point.deflection.GB_DIS_G05_001_01Y = struct( ...
                'post_filter_thresholds', struct( ...
                    'min', -5, 'max', 5, ...
                    't_range_start', '2025-01-01 00:00:00', ...
                    't_range_end',   '2025-01-01 01:00:00'));

            ths = resolve_post_filter_thresholds(cfg, 'deflection', 'GB-DIS-G05-001-01Y');
            tc.verifyEqual(numel(ths), 2);
            tc.verifyEqual(ths(1).min, -10);
            tc.verifyEqual(ths(2).max, 5);
        end

        function applyTimeWindowThresholdRules(tc)
            times = datetime(2025,1,1,0,0,0) + minutes(0:3);
            vals = [1; 20; 3; 40];
            ths = [ ...
                struct('min', 0, 'max', 50, 't_range_start', '', 't_range_end', ''), ...
                struct('min', 0, 'max', 10, 't_range_start', '2025-01-01 00:01:00', 't_range_end', '2025-01-01 00:02:00')];

            out = apply_threshold_rules(vals, times, ths);
            tc.verifyEqual(out(1), 1);
            tc.verifyTrue(isnan(out(2)));
            tc.verifyEqual(out(3), 3);
            tc.verifyEqual(out(4), 40);
        end

        function validateConfigAcceptsPostFilterThresholds(tc)
            cfg = struct();
            cfg.defaults = struct();
            cfg.defaults.header_marker = '[绝对时间]';
            cfg.defaults.deflection = struct( ...
                'thresholds', [], ...
                'zero_to_nan', false, ...
                'outlier', [], ...
                'post_filter_thresholds', struct( ...
                    'min', -1, 'max', 1, ...
                    't_range_start', '', 't_range_end', ''));
            cfg.per_point = struct();
            warns = validate_config(cfg, false);
            tc.verifyEmpty(warns);
        end
    end
end
