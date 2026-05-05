classdef test_gui_state_services < matlab.unittest.TestCase
    properties
        TempDir
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'config'), fullfile(proj, 'pipeline'), fullfile(proj, 'analysis'), fullfile(proj, 'ui'));
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if exist(tc.TempDir, 'dir'), rmdir(tc.TempDir, 's'); end
        end
    end

    methods (Test)
        function stateRoundTripsThroughPresetStore(tc)
            state = bms.gui.GuiState.fromValues( ...
                tc.TempDir, '2026-03-01', '2026-03-31', 'config/default_config.json', ...
                fullfile(tc.TempDir, 'run_logs'), true, ...
                struct('unzip', true), struct('temp', true, 'accel', false));
            path = fullfile(tc.TempDir, 'preset.json');

            bms.gui.GuiPresetStore.save(path, state);
            loaded = bms.gui.GuiPresetStore.load(path);

            tc.verifyEqual(loaded.Root, tc.TempDir);
            tc.verifyEqual(loaded.StartDate, '2026-03-01');
            tc.verifyTrue(loaded.ShowWarnings);
            tc.verifyTrue(loaded.Preproc.unzip);
            tc.verifyTrue(loaded.Modules.temp);
        end

        function presetFromControlsUsesModuleRegistry(tc)
            controls = struct();
            controls.doUnzip = struct('Value', true);
            controls.doTemp = struct('Value', true);
            controls.doAccel = struct('Value', false);

            preproc = bms.gui.GuiRunController.presetFromControls(controls, 'preprocess');
            modules = bms.gui.GuiRunController.presetFromControls(controls, 'analysis');
            state = bms.gui.GuiState.fromValues(tc.TempDir, '2026-01-01', '2026-01-02', '', '', false, preproc, modules);
            opts = state.toOptions();

            tc.verifyTrue(preproc.unzip);
            tc.verifyTrue(modules.temp);
            tc.verifyFalse(modules.accel);
            tc.verifyTrue(opts.doUnzip);
            tc.verifyTrue(opts.doTemp);
            tc.verifyFalse(opts.doAccel);
        end

        function configBinderLoadsDefaultAndAppliesTabs(tc)
            defaultPath = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'config', 'default_config.json');
            [cfg, actualPath] = bms.gui.GuiConfigBinder.loadConfig('', defaultPath);

            tc.verifyEqual(actualPath, defaultPath);
            tc.verifyTrue(isfield(cfg, 'plot_common'));

            tabState = struct('applyToCfg', @(c) bms.config.ConfigPatch.setPath(c, 'plot_common.gap_mode', 'connect'));
            cfg2 = bms.gui.GuiConfigBinder.applyLiveTabs(cfg, {tabState});
            tc.verifyEqual(cfg2.plot_common.gap_mode, 'connect');
        end

        function resultSummaryIncludesErrorDetails(tc)
            rec = struct('key','temp', 'label','温度分析', 'status','fail', ...
                'elapsed_sec', 1.25, 'stats_path', fullfile(tc.TempDir, 'missing.xlsx'), ...
                'error_type', 'read_failed', 'message', '无法读取输入文件', ...
                'artifacts', struct('kind','figure','path','x.jpg'));
            manifest = struct('status','failed', 'module_results', rec, ...
                'module_status_counts', struct('ok',0,'fail',1,'skip',0,'missing',0,'other',0), ...
                'artifact_count', 1, ...
                'missing_expected_stats', {{'missing.xlsx'}}, ...
                'run_preflight', struct('warnings', {{'warn'}}, ...
                    'result_artifact_preflight', struct('status','possible_stale')));
            ctx = struct('available', true, 'path', 'manifest.json', 'status', 'failed', ...
                'manifest', manifest, 'artifact_count', 1);

            summary = bms.gui.GuiResultSummary.fromManifestContext(ctx);

            tc.verifySize(summary.module_rows, [1 7]);
            tc.verifyEqual(summary.module_rows{1, 1}, '温度分析');
            tc.verifyEqual(summary.module_rows{1, 6}, 'read_failed');
            tc.verifyEqual(summary.module_rows{1, 7}, '无法读取输入文件');
            tc.verifyEqual(summary.preflight_warning_count, 1);
            tc.verifyEqual(summary.missing_stats_count, 1);
            tc.verifyEqual(summary.possible_stale_count, 1);
        end
    end
end
