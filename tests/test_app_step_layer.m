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

        function executorCleansOnlyFiguresCreatedByMemoryFailedStep(tc)
            existing = figure('Visible', 'off', 'Name', 'existing-gui-window');
            cleanup = onCleanup(@() cleanup_step_figures(existing));

            r = bms.app.StepExecutor.execute( ...
                bms.app.StepDefinition.fromKey('cable_accel'), ...
                @create_step_figures_then_oom);

            created = getappdata(groot, 'BmsStepExecutorCreatedFigures');
            tc.verifyEqual(r.Status, 'fail');
            tc.verifyEqual(r.ErrorType, 'memory_error');
            tc.verifyTrue(isgraphics(existing, 'figure'), ...
                'A figure that existed before the step must remain open.');
            tc.verifyFalse(any(arrayfun(@(fig) isgraphics(fig, 'figure'), created)), ...
                'Figures created by the OOM-failed step must be deleted.');
        end

        function executorDoesNotTreatMemoryCacheFailureAsOom(tc)
            existing = figure('Visible', 'off', 'Name', 'existing-gui-window');
            cleanup = onCleanup(@() cleanup_step_figures(existing));

            r = bms.app.StepExecutor.execute( ...
                bms.app.StepDefinition.fromKey('cable_accel'), ...
                @create_step_figure_then_memory_cache_error);

            created = getappdata(groot, 'BmsStepExecutorCreatedFigures');
            tc.verifyEqual(r.Status, 'fail');
            tc.verifyNotEqual(r.ErrorType, 'memory_error');
            tc.verifyTrue(isgraphics(existing, 'figure'));
            tc.verifyTrue(all(arrayfun(@(fig) isgraphics(fig, 'figure'), created)), ...
                'A non-OOM error mentioning a memory cache must not trigger OOM figure cleanup.');
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
            finalPayload = payloads{end};
            tc.verifyEqual(finalPayload.progress_schema_version, 2);
            tc.verifyEqual(finalPayload.progress_authority, 'runtime');
            tc.verifyEqual({finalPayload.module_steps.status}, {'stopped', 'skipped'});
            tc.verifyEqual({finalPayload.module_steps.key}, {'temperature', 'humidity'});

            function collect_payload(payload)
                payloads{end+1} = payload; %#ok<AGROW>
            end
        end

        function stepPlanPublishesFullTruthfulModuleContract(tc)
            plan = bms.app.StepPlan();
            plan = plan.addRun(bms.app.StepDefinition.fromKey('temperature'), @report_real_checkpoint);
            plan = plan.addSkip(bms.app.StepDefinition.fromKey('humidity'), 'No humidity points configured');
            payloads = {};

            [results, finalProgress] = plan.execute(@() false, @(payload) collect_payload(payload));

            events = cellfun(@(p) char(string(p.event)), payloads, 'UniformOutput', false);
            progressPayload = payloads{find(strcmp(events, 'module_progress'), 1, 'first')};
            tc.verifyEqual(progressPayload.progress_schema_version, 2);
            tc.verifyEqual(progressPayload.progress_authority, 'runtime');
            tc.verifyEqual(progressPayload.module_total, 2);
            tc.verifyEqual({progressPayload.module_steps.key}, {'temperature', 'humidity'});
            tc.verifyEqual({progressPayload.module_steps.status}, {'running', 'pending'});
            tc.verifyEqual(progressPayload.current_point_id, 'TEMP-01');
            tc.verifyEqual(progressPayload.current_date, '2026-04-03');
            tc.verifyEqual(progressPayload.processed_dates, 3);
            tc.verifyEqual(progressPayload.total_dates, 30);
            tc.verifyEqual(progressPayload.stage, 'load_mat_cache');

            tc.verifyEqual({finalProgress.module_steps.status}, {'completed', 'skipped'});
            tc.verifyEqual(finalProgress.completed_modules, 2);
            tc.verifyEqual(results{1}.CurrentPointId, 'TEMP-01');
            tc.verifyEqual(results{1}.ProcessedDates, 3);
            rec = results{1}.toStruct();
            tc.verifyEqual(rec.current_point_id, 'TEMP-01');
            tc.verifyEqual(rec.total_dates, 30);

            function report_real_checkpoint()
                bms.app.RunProgressReporter.checkpoint( ...
                    'stage', 'load_mat_cache', ...
                    'current_point_id', 'TEMP-01', ...
                    'current_date', '2026-04-03', ...
                    'processed_dates', 3, ...
                    'total_dates', 30, ...
                    'message', 'Loaded verified cache day 3/30');
            end

            function collect_payload(payload)
                payloads{end+1} = payload; %#ok<AGROW>
            end
        end

        function manifestReconciliationKeepsMeasuredIntraModuleState(tc)
            seed = struct('module_steps', struct( ...
                'key', {'temperature','humidity'}, ...
                'label', {'Temperature','Humidity'}, ...
                'index', {1,2}, ...
                'status', {'running','pending'}, ...
                'stage', {'load_data','pending'}, ...
                'current_point_id', {'TEMP-02',''}, ...
                'current_date', {'2026-04-08',''}, ...
                'processed_dates', {8,0}, ...
                'total_dates', {30,0}, ...
                'elapsed_seconds', {12.5,0}, ...
                'message', {'',''}));
            result1 = struct('key','temperature','label','Temperature', ...
                'status','ok','message','','elapsed_sec',15.0);
            result2 = struct('key','humidity','label','Humidity', ...
                'status','skip','message','No configured points','elapsed_sec',0);

            terminal = bms.app.RunProgressReporter.reconcile( ...
                seed, {result1, result2}, 'analysis_manifest');

            tc.verifyEqual(terminal.progress_authority, 'analysis_manifest');
            tc.verifyEqual({terminal.module_steps.status}, {'completed','skipped'});
            tc.verifyEqual(terminal.module_steps(1).current_point_id, 'TEMP-02');
            tc.verifyEqual(terminal.module_steps(1).processed_dates, 8);
            tc.verifyEqual(terminal.module_steps(1).elapsed_seconds, 15.0);
        end

        function stepPlanSkipsOnlyLaterHighMemoryStepsAfterOom(tc)
            lowRiskRuns = 0;
            skippedHighRiskRuns = 0;
            plan = bms.app.StepPlan();
            plan = plan.addRun(bms.app.StepDefinition.fromKey('cable_accel'), ...
                @() error('MATLAB:nomem', 'Out of memory during cable acceleration'));
            plan = plan.addRun(bms.app.StepDefinition.fromKey('temperature'), @run_low_risk);
            plan = plan.addRun(bms.app.StepDefinition.fromKey('accel_spectrum'), @run_high_risk);

            results = plan.execute();

            tc.verifyEqual(cellfun(@(r) r.Status, results, 'UniformOutput', false), ...
                {'fail', 'ok', 'skip'});
            tc.verifyEqual(results{1}.ErrorType, 'memory_error');
            tc.verifySubstring(results{3}.Message, 'cable_accel');
            tc.verifyEqual(lowRiskRuns, 1, 'Low-risk work should continue after an OOM.');
            tc.verifyEqual(skippedHighRiskRuns, 0, 'Later high-memory work must not run.');

            function run_low_risk()
                lowRiskRuns = lowRiskRuns + 1;
            end

            function run_high_risk()
                skippedHighRiskRuns = skippedHighRiskRuns + 1;
            end
        end

        function nonMemoryFailureKeepsExistingContinuationPolicy(tc)
            laterHighRiskRuns = 0;
            plan = bms.app.StepPlan();
            plan = plan.addRun(bms.app.StepDefinition.fromKey('cable_accel'), ...
                @() error('unit:ordinaryFailure', 'ordinary failure'));
            plan = plan.addRun(bms.app.StepDefinition.fromKey('accel_spectrum'), @run_later_high_risk);

            results = plan.execute();

            tc.verifyEqual(cellfun(@(r) r.Status, results, 'UniformOutput', false), ...
                {'fail', 'ok'});
            tc.verifyEqual(results{1}.ErrorType, 'runtime_error');
            tc.verifyEqual(laterHighRiskRuns, 1);

            function run_later_high_risk()
                laterHighRiskRuns = laterHighRiskRuns + 1;
            end
        end


        function memoryCacheFailureDoesNotSkipLaterHighMemoryStep(tc)
            laterHighRiskRuns = 0;
            plan = bms.app.StepPlan();
            plan = plan.addRun(bms.app.StepDefinition.fromKey('cable_accel'), ...
                @() error('unit:memoryCache', 'memory cache metadata is inconsistent'));
            plan = plan.addRun(bms.app.StepDefinition.fromKey('accel_spectrum'), @run_later_high_risk);

            results = plan.execute();

            tc.verifyEqual(cellfun(@(r) r.Status, results, 'UniformOutput', false), ...
                {'fail', 'ok'});
            tc.verifyNotEqual(results{1}.ErrorType, 'memory_error');
            tc.verifyEqual(laterHighRiskRuns, 1);

            function run_later_high_risk()
                laterHighRiskRuns = laterHighRiskRuns + 1;
            end
        end

        function matlabSizeLimitIdentifierIsTreatedAsOom(tc)
            plan = bms.app.StepPlan();
            plan = plan.addRun(bms.app.StepDefinition.fromKey('cable_accel'), ...
                @() error('MATLAB:array:SizeLimitExceeded', 'Requested array exceeds configured limit'));
            plan = plan.addRun(bms.app.StepDefinition.fromKey('accel_spectrum'), ...
                @() error('unit:mustNotRun', 'later high-memory step ran'));

            results = plan.execute();

            tc.verifyEqual(results{1}.ErrorType, 'memory_error');
            tc.verifyEqual(results{2}.Status, 'skip');
        end
    end
end

function create_step_figures_then_oom()
    figures = [figure('Visible', 'off'), figure('Visible', 'off')];
    setappdata(groot, 'BmsStepExecutorCreatedFigures', figures);
    error('MATLAB:nomem', 'Out of memory while plotting');
end

function create_step_figure_then_memory_cache_error()
    figures = figure('Visible', 'off');
    setappdata(groot, 'BmsStepExecutorCreatedFigures', figures);
    error('unit:memoryCache', 'memory cache metadata is inconsistent');
end

function cleanup_step_figures(existing)
    if isappdata(groot, 'BmsStepExecutorCreatedFigures')
        figures = getappdata(groot, 'BmsStepExecutorCreatedFigures');
        for i = 1:numel(figures)
            if isgraphics(figures(i), 'figure')
                delete(figures(i));
            end
        end
        rmappdata(groot, 'BmsStepExecutorCreatedFigures');
    end
    if isgraphics(existing, 'figure')
        delete(existing);
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
