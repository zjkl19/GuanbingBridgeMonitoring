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
            tc.verifyEqual(size(summary.module_rows, 1), 1);
            tc.verifyEqual(summary.module_rows{1, 1}, '挠度分析');
            tc.verifyEqual(summary.module_rows{1, 5}, 1);
        end
    end
end
