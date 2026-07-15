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

        function twoSidedThresholdUsesStrictComparisons(tc)
            values = [-1.1; -1; 0; 1; 1.1];
            times = datetime(2026, 1, 1) + seconds(0:4)';
            rules = bms.data.CleaningPipeline.emptyRules();
            rules.thresholds = struct('min', -1, 'max', 1);

            [cleaned, log] = bms.data.CleaningPipeline.apply( ...
                values, times, rules, struct());

            tc.verifyTrue(isnan(cleaned(1)), ...
                'Only a value strictly below min should be removed.');
            tc.verifyEqual(cleaned(2:4), [-1; 0; 1], ...
                'Samples equal to min or max must be retained.');
            tc.verifyTrue(isnan(cleaned(5)), ...
                'Only a value strictly above max should be removed.');
            tc.verifyEqual(log.threshold_removed_count, 2);
        end

        function jsonOneSidedThresholdsUseStrictComparisons(tc)
            lowerCfg = jsondecode( ...
                '{"defaults":{"temperature":{"thresholds":{"min":-1}}}}');
            upperCfg = jsondecode( ...
                '{"defaults":{"temperature":{"thresholds":{"max":1}}}}');
            lowerRules = bms.data.CleaningPipeline.resolveRules( ...
                lowerCfg, 'temperature', 'T-1');
            upperRules = bms.data.CleaningPipeline.resolveRules( ...
                upperCfg, 'temperature', 'T-1');
            values = [-2; -1; 0; 1; 2];
            times = datetime(2026, 1, 1) + seconds(0:4)';

            lowerCleaned = bms.data.CleaningPipeline.applyThresholds( ...
                values, times, lowerRules.thresholds);
            tc.verifyTrue(isnan(lowerCleaned(1)));
            tc.verifyEqual(lowerCleaned(2:5), [-1; 0; 1; 2], ...
                'A min-only JSON rule must retain the sample equal to min.');

            upperCleaned = bms.data.CleaningPipeline.applyThresholds( ...
                values, times, upperRules.thresholds);
            tc.verifyEqual(upperCleaned(1:4), [-2; -1; 0; 1], ...
                'A max-only JSON rule must retain the sample equal to max.');
            tc.verifyTrue(isnan(upperCleaned(5)));
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
