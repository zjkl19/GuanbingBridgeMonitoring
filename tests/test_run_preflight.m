classdef test_run_preflight < matlab.unittest.TestCase
    properties
        TempDir
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj);
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if exist(tc.TempDir, 'dir'), rmdir(tc.TempDir, 's'); end
        end
    end

    methods (Test)
        function validRootProducesProfileAndLayout(tc)
            cfg = struct('source', 'config/jiulongjiang_config.json');
            opts = struct('doTemp', true, 'doWIM', false);
            result = bms.app.RunPreflight.check(tc.TempDir, '2026-03-01', '2026-03-02', opts, cfg);

            tc.verifyNotEqual(result.status, 'failed');
            tc.verifyEqual(result.profile.bridge_id, 'jiulongjiang');
            tc.verifyEqual(result.data_layout.exists, true);
            tc.verifyTrue(ismember('temperature', result.enabled_modules));
            tc.verifyFalse(isempty(bms.app.RunPreflight.toLogLines(result)));
        end

        function invalidDateRangeFails(tc)
            result = bms.app.RunPreflight.check(tc.TempDir, '2026-03-10', '2026-03-01', struct(), struct());

            tc.verifyEqual(result.status, 'failed');
            tc.verifyTrue(any(contains(result.errors, 'date range invalid')));
        end

        function missingRootFails(tc)
            missingRoot = fullfile(tc.TempDir, 'missing');
            result = bms.app.RunPreflight.check(missingRoot, '2026-03-01', '2026-03-02', struct(), struct());

            tc.verifyEqual(result.status, 'failed');
            tc.verifyTrue(any(contains(result.errors, 'data root does not exist')));
        end

        function wimMissingFilesWarns(tc)
            opts = struct('doWIM', true);
            result = bms.app.RunPreflight.check(tc.TempDir, '2026-01-01', '2026-02-01', opts, struct());

            tc.verifyEqual(result.status, 'warning');
            tc.verifyEqual(numel(result.wim_month_files), 2);
            tc.verifyTrue(any(contains(result.warnings, 'WIM input missing for 202601')));
        end
    end
end
