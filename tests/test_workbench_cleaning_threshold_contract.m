classdef test_workbench_cleaning_threshold_contract < matlab.unittest.TestCase
    methods (Test)
        function jsonContractResolvesThroughCleaningPipeline(tc)
            root = fileparts(fileparts(mfilename('fullpath')));
            path = fullfile(root, 'tests', 'fixtures', ...
                'workbench_cleaning_threshold_contract.json');
            cfg = bms.core.ConfigStore.load(path);

            defaultRules = bms.data.CleaningPipeline.resolveRules( ...
                cfg, 'deflection', 'UNCONFIGURED');
            tc.verifyNumElements(defaultRules.thresholds, 1);
            tc.verifyEqual(defaultRules.thresholds.min, -5);
            tc.verifyEqual(defaultRules.thresholds.max, 5);
            tc.verifyTrue(defaultRules.zero_to_nan);
            tc.verifyEqual(defaultRules.outlier_window_sec, 15);
            tc.verifyEqual(defaultRules.outlier_threshold_factor, 3);

            pointRules = bms.data.CleaningPipeline.resolveRules( ...
                cfg, 'deflection', 'PT-1');
            tc.verifyNumElements(pointRules.thresholds, 2);
            tc.verifyEqual(pointRules.thresholds(2).min, -10);
            tc.verifyEqual(pointRules.thresholds(2).max, 10);
            tc.verifyFalse(pointRules.zero_to_nan);
            tc.verifyEqual(pointRules.offset_correction, 12);
            tc.verifyNumElements(pointRules.exclude_ranges, 1);
            tc.verifyEqual(pointRules.exclude_ranges.start_time, ...
                '2026-01-10 00:00:00');
            tc.verifyEqual(pointRules.exclude_ranges.end_time, ...
                '2026-01-10 23:59:59');
            tc.verifyEqual(pointRules.exclude_ranges.reason, ...
                '测试夹具中的明确整段排除规则');
        end

        function oneSidedThresholdRemainsSupported(tc)
            root = fileparts(fileparts(mfilename('fullpath')));
            path = fullfile(root, 'tests', 'fixtures', ...
                'workbench_cleaning_threshold_contract.json');
            cfg = bms.core.ConfigStore.load(path);
            rules = bms.data.CleaningPipeline.resolveRules( ...
                cfg, 'temperature', 'T-1');
            values = [49 50 51];
            times = datetime(2026, 1, 1) + seconds(0:2);
            [cleaned, ~] = bms.data.CleaningPipeline.apply( ...
                values, times, rules, struct());
            tc.verifyEqual(cleaned(1:2), [49 50]);
            tc.verifyTrue(isnan(cleaned(3)));
        end

        function postFilterContractSupportsOneSidedTimedRule(tc)
            root = fileparts(fileparts(mfilename('fullpath')));
            addpath(fullfile(root, 'pipeline'), '-begin');
            path = fullfile(root, 'tests', 'fixtures', ...
                'workbench_cleaning_threshold_contract.json');
            cfg = bms.core.ConfigStore.load(path);
            rules = resolve_post_filter_thresholds(cfg, 'deflection', 'PT-1');
            tc.verifyNumElements(rules, 1);
            tc.verifyEmpty(rules.min);
            tc.verifyEqual(rules.max, 4);
            tc.verifyEqual(rules.t_range_start, '2026-01-01 00:00:00');
            tc.verifyEqual(rules.t_range_end, '2026-01-31 23:59:59');
        end
    end
end
