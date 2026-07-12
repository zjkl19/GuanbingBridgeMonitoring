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
            tc.verifyEqual(pointRules.thresholds(2).min, 1000);
            tc.verifyEqual(pointRules.thresholds(2).max, -1000);
            tc.verifyFalse(pointRules.zero_to_nan);
            tc.verifyEqual(pointRules.offset_correction, 12);
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
    end
end
