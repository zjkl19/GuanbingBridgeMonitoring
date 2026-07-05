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
            tc.verifyClass(r, 'bms.app.StepResult');
            rec = r.toStruct(tempdir);
            tc.verifyEqual(rec.status, 'fail');
            tc.verifyEqual(rec.key, 'temperature');
            tc.verifyNotEmpty(rec.message);
            tc.verifyEqual(rec.error_type, 'runtime_error');
            tc.verifyGreaterThanOrEqual(rec.elapsed_sec, 0);
        end

        function adapterAddsStatsPath(tc)
            logs = {struct('label',bms.app.StepDefinition.fromKey('acceleration').Label,'status','ok','message','','elapsed_sec',0.1)};
            summary = bms.app.LegacyRunAllAdapter.buildSummary(tempdir, '2026-01-01', '2026-01-01', ...
                struct('doAccel', true), struct(), datetime('now'), 0.1, logs, '', [], fullfile(tempdir, 'stats'), fullfile(tempdir, 'run_logs'));
            tc.verifyEqual(summary.enabled_modules, {'acceleration'});
            tc.verifyEqual(summary.module_logs{1}.key, 'acceleration');
            tc.verifyTrue(endsWith(summary.module_logs{1}.stats_path, fullfile('stats', 'accel_stats.xlsx')));
        end

        function moduleResultAcceptsStepResult(tc)
            step = bms.app.StepDefinition.fromKey('crack');
            rec = bms.app.StepResult.ok(step, datetime('now'), datetime('now'));
            mod = bms.module.ModuleResult.fromStepStruct(rec);
            tc.verifyEqual(mod.Spec.Key, 'crack');
            tc.verifyEqual(mod.Status, 'ok');
        end

        function stepPlanReportsProgressAndStops(tc)
            global RUN_STOP_FLAG;
            RUN_STOP_FLAG = false;
            bms.app.StopController.clear();
            cleanup = onCleanup(@() reset_stop()); %#ok<NASGU>

            plan = bms.app.StepPlan();
            plan = plan.addRun(bms.app.StepDefinition.fromKey('temperature'), @() request_stop_now());
            plan = plan.addRun(bms.app.StepDefinition.fromKey('humidity'), @() error('unit:shouldNotRun', 'should not run'));
            payloads = {};

            results = plan.execute(@() bms.app.StopController.isStopRequested(), @(payload) collect_payload(payload));

            tc.verifyEqual(results{1}.Status, 'stopped');
            tc.verifyEqual(results{2}.Status, 'skip');
            tc.verifyGreaterThanOrEqual(numel(payloads), 2);
            tc.verifyTrue(any(cellfun(@(p) isfield(p, 'progress_fraction'), payloads)));
            tc.verifyTrue(any(cellfun(@(p) isfield(p, 'current_module_label'), payloads)));

            function collect_payload(payload)
                payloads{end+1} = payload; %#ok<AGROW>
            end
        end
    end
end

function request_stop_now()
    bms.app.StopController.requestStop();
    bms.app.StopController.throwIfRequested('unit stop');
end

function reset_stop()
    global RUN_STOP_FLAG;
    RUN_STOP_FLAG = false;
    bms.app.StopController.clear();
end
