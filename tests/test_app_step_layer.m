classdef test_app_step_layer < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'config'), fullfile(proj, 'pipeline'), fullfile(proj, 'analysis'), fullfile(proj, 'scripts'));
        end
    end

    methods (Test)
        function definitionsMapLabelsAndOptions(tc)
            def = bms.app.StepDefinition.fromLabel(bms.app.StepDefinition.fromKey('acceleration').Label);
            tc.verifyEqual(def.Key, 'acceleration');
            tc.verifyEqual(def.StatsFile, 'accel_stats.xlsx');

            opts = struct('doAccel', true, 'doCrack', false, 'doGNSS', true);
            defs = bms.app.StepDefinition.enabledFromOptions(opts);
            keys = arrayfun(@(d) d.Key, defs, 'UniformOutput', false);
            tc.verifyEqual(keys, {'gnss', 'acceleration'});
        end

        function executorCapturesFailure(tc)
            def = bms.app.StepDefinition.fromKey('temperature');
            r = bms.app.StepExecutor.execute(def, @() error('unit:fail', 'boom'), @() false);
            tc.verifyEqual(r.status, 'fail');
            tc.verifyEqual(r.key, 'temperature');
            tc.verifyNotEmpty(r.message);
            tc.verifyEqual(r.error_type, 'runtime_error');
            tc.verifyGreaterThanOrEqual(r.elapsed_sec, 0);
        end

        function adapterAddsStatsPath(tc)
            logs = {struct('label',bms.app.StepDefinition.fromKey('acceleration').Label,'status','ok','message','','elapsed_sec',0.1)};
            summary = bms.app.LegacyRunAllAdapter.buildSummary(tempdir, '2026-01-01', '2026-01-01', ...
                struct('doAccel', true), struct(), datetime('now'), 0.1, logs, '', [], fullfile(tempdir, 'stats'), fullfile(tempdir, 'run_logs'));
            tc.verifyEqual(summary.enabled_modules, {'acceleration'});
            tc.verifyEqual(summary.module_logs{1}.key, 'acceleration');
            tc.verifyTrue(endsWith(summary.module_logs{1}.stats_path, fullfile('stats', 'accel_stats.xlsx')));
        end
    end
end
