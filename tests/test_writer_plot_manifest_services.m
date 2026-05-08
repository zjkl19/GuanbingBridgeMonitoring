classdef test_writer_plot_manifest_services < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'pipeline'));
        end
    end

    methods (Test)
        function statsWriterRoundsNumericColumns(tc)
            T = table([1.234; NaN], {'a'; ''}, 'VariableNames', {'Value','Name'});
            T2 = bms.io.StatsWriter.roundNumericColumns(T, 1, 'Value');
            tc.verifyEqual(T2.Value(1), 1.2);
            T3 = bms.io.StatsWriter.normalizeForReport(T, 1, '/');
            tc.verifyTrue(iscell(T3.Value));
            tc.verifyEqual(T3.Value{2}, '/');
        end

        function plotRuntimeOptionsReadConfig(tc)
            cfg = struct();
            cfg.plot_common = struct('save_fig', false, 'lightweight_fig', true, ...
                'fig_max_points', 1234, 'append_timestamp', false, 'gap_mode', 'break', 'gap_break_factor', 7);
            opts = bms.plot.PlotService.runtimeOptionsFromConfig(cfg);
            tc.verifyFalse(opts.save_fig);
            tc.verifyEqual(opts.fig_max_points, 1234);
            tc.verifyEqual(opts.gap_mode, 'break');
            tc.verifyEqual(opts.gap_break_factor, 7);
            merged = bms.plot.PlotService.mergeOptions(opts, struct('save_emf', false));
            tc.verifyFalse(merged.save_emf);
            tc.verifyEqual(merged.gap_mode, 'break');
        end

        function plotServiceModuleBundleUsesRuntimeOptions(tc)
            tmp = tempname;
            mkdir(tmp);
            cleanup = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>

            fig = figure('Visible', 'off');
            plot(1:3, [1 4 9]);
            cfg.plot_common = struct('save_fig', false, 'append_timestamp', false);
            paths = bms.plot.PlotService.saveModuleBundle(fig, tmp, ...
                'Unit_20260101_20260102_20260506_123456', cfg, ...
                struct('save_emf', false));

            expected = fullfile(tmp, 'Unit_20260101_20260102.jpg');
            tc.verifyTrue(isfile(expected));
            tc.verifyEqual(paths, {expected});
            tc.verifyFalse(isfile(fullfile(tmp, 'Unit_20260101_20260102.emf')));
            tc.verifyFalse(isfile(fullfile(tmp, 'Unit_20260101_20260102.fig')));
        end

        function errorClassifierReturnsStableTypes(tc)
            tc.verifyEqual(bms.app.ErrorClassifier.classifyText('unrecognized field ylim_auto'), 'config_invalid');
            tc.verifyEqual(bms.app.ErrorClassifier.classifyText('writetable failed for stats.xlsx'), 'stats_write_failed');
            tc.verifyEqual(bms.app.ErrorClassifier.classifyText('Failed to save .fig file'), 'plot_save_failed');
            tc.verifyEqual(bms.app.ErrorClassifier.classifyText('sqlcmd ODBC login failed'), 'sql_error');
        end

        function manifestStatusCountsSummarizeRecords(tc)
            records = {struct('status','ok'), struct('status','fail'), struct('status','skip'), struct('status','missing'), struct('status','weird')};
            counts = bms.app.ManifestWriter.statusCounts(records);
            tc.verifyEqual(counts.ok, 1);
            tc.verifyEqual(counts.fail, 1);
            tc.verifyEqual(counts.skip, 1);
            tc.verifyEqual(counts.missing, 1);
            tc.verifyEqual(counts.other, 1);
        end

        function manifestNormalizesModuleRecordSchema(tc)
            statsPath = fullfile(tempdir, 'missing_unit_stats.xlsx');
            artifact = struct('kind','figure','role','time_history','path','D:/x.jpg');
            records = bms.app.ManifestWriter.normalizeModuleRecords( ...
                {struct('key','deflection','status','fail','message','not found','stats_path',statsPath,'artifacts',{{artifact}})}, tempdir);
            tc.verifyEqual(numel(records), 1);
            rec = records{1};
            tc.verifyEqual(rec.error_type, 'input_missing');
            tc.verifyFalse(rec.stats_exists);
            tc.verifyEqual(rec.artifact_count, 1);
            tc.verifyEqual(rec.figure_count, 1);
            tc.verifyEqual(rec.figure_paths, {'D:/x.jpg'});
        end

        function guiResultSummaryBuildsLines(tc)
            ctx = struct();
            ctx.available = true;
            ctx.path = 'D:/run_logs/analysis_manifest_1.json';
            ctx.status = 'failed';
            ctx.manifest = struct('module_status_counts', struct('ok', 2, 'fail', 1, 'skip', 0, 'missing', 1, 'other', 0));
            summary = bms.gui.GuiResultSummary.fromManifestContext(ctx);
            tc.verifyEqual(summary.counts.ok, 2);
            tc.verifyTrue(any(contains(summary.lines, 'fail=1')));
        end

        function guiResultSummaryBuildsModuleRows(tc)
            ctx = struct();
            ctx.available = true;
            ctx.path = 'D:/run_logs/analysis_manifest_1.json';
            ctx.status = 'ok';
            artifact = struct('kind','figure','role','time_history','path','D:/x.jpg');
            ctx.manifest = struct('module_results', {{struct('key','deflection','label','挠度分析', ...
                'status','ok','elapsed_sec',1.25,'stats_path','', 'artifacts', {{artifact}})}});
            summary = bms.gui.GuiResultSummary.fromManifestContext(ctx);
            tc.verifyEqual(size(summary.module_rows, 1), 2);
            tc.verifyEqual(summary.module_rows{1, 1}, 'Summary');
            tc.verifyNotEqual(summary.module_rows{2, 1}, 'Summary');
            tc.verifyEqual(summary.module_rows{2, 5}, 1);
        end
    end
end
