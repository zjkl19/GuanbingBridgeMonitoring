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

        function liveConfigTabStatesIncludesGroupConfig(tc)
            th = struct('applyToCfg', @(cfg) setfield(cfg, 'threshold_marker', true));
            pf = struct('applyToCfg', @(cfg) setfield(cfg, 'post_filter_marker', true));
            oc = struct('applyToCfg', @(cfg) setfield(cfg, 'offset_marker', true));
            gc = struct('applyToCfg', @(cfg) setfield(cfg, 'group_marker', true));
            pp = struct('applyToCfg', @(cfg) setfield(cfg, 'plot_marker', true));
            ignored = struct('onShow', @() []);

            states = bms.gui.GuiRunController.liveConfigTabStates(th, pf, oc, gc, pp, ignored);
            cfg2 = bms.gui.GuiConfigBinder.applyLiveTabs(struct(), states);

            tc.verifyEqual(numel(states), 5);
            tc.verifyTrue(cfg2.threshold_marker);
            tc.verifyTrue(cfg2.post_filter_marker);
            tc.verifyTrue(cfg2.offset_marker);
            tc.verifyTrue(cfg2.group_marker);
            tc.verifyTrue(cfg2.plot_marker);
        end

        function resultSummaryIncludesErrorDetails(tc)
            rec = [struct('key','offset_correction_report', 'label','offset_correction_report', ...
                'category','postprocess', 'status','ok', 'elapsed_sec', NaN, ...
                'stats_path','', 'error_type','', 'message','', 'artifacts', []), ...
                struct('key','temp', 'label','温度分析', 'category','analysis', 'status','fail', ...
                'elapsed_sec', 1.25, 'stats_path', fullfile(tc.TempDir, 'missing.xlsx'), ...
                'error_type', 'read_failed', 'message', '无法读取输入文件', ...
                'artifacts', struct('kind','figure','path','x.jpg'))]';
            manifest = struct('status','failed', 'module_results', rec, ...
                'module_status_counts', struct('ok',0,'fail',1,'skip',0,'missing',0,'other',0), ...
                'artifact_count', 1, ...
                'missing_expected_stats', {{'missing.xlsx'}}, ...
                'run_preflight', struct('warnings', {{'warn'}}, ...
                    'result_artifact_preflight', struct('status','possible_stale')));
            ctx = struct('available', true, 'path', 'manifest.json', 'status', 'failed', ...
                'manifest', manifest, 'artifact_count', 1);

            summary = bms.gui.GuiResultSummary.fromManifestContext(ctx);

            tc.verifyGreaterThanOrEqual(size(summary.module_rows, 1), 5);
            tc.verifyEqual(summary.module_rows{1, 1}, '汇总');
            tc.verifyTrue(any(strcmp(summary.module_rows(:, 1), '预检')));
            tc.verifyTrue(any(strcmp(summary.module_rows(:, 1), '缺失统计表')));
            tc.verifyTrue(any(strcmp(summary.module_rows(:, 6), '读取失败')));
            tc.verifyTrue(any(strcmp(summary.module_rows(:, 6), '缺失统计表')));
            tc.verifyEqual(summary.preflight_warning_count, 1);
            tc.verifyEqual(summary.preflight_error_count, 0);
            tc.verifyEqual(summary.missing_stats_count, 1);
            tc.verifyEqual(summary.possible_stale_count, 1);
        end

        function resultSummaryHandlesNonScalarModuleFields(tc)
            rec = struct('key','temp', 'label','温度分析', 'category','analysis', ...
                'status','ok', 'elapsed_sec', [1 2], 'stats_path', '', ...
                'stats_exists', [true false], 'error_type', '', 'message', '', ...
                'artifacts', []);
            manifest = struct('status','ok', 'module_results', rec, ...
                'module_status_counts', struct('ok',1,'fail',0,'skip',0,'missing',0,'other',0), ...
                'artifact_count', 0);
            ctx = struct('available', true, 'path', 'manifest.json', 'status', 'ok', ...
                'manifest', manifest, 'artifact_count', 0);

            summary = bms.gui.GuiResultSummary.fromManifestContext(ctx);

            tc.verifyEqual(summary.status, 'ok');
            tc.verifyTrue(any(strcmp(summary.module_rows(:, 1), '温度分析')));
            tempRow = summary.module_rows(strcmp(summary.module_rows(:, 1), '温度分析'), :);
            tc.verifyEqual(tempRow{1, 3}, '');
        end

        function layoutUsesTallerScreenAwareWindow(tc)
            pos = bms.gui.GuiLayout.mainWindowPosition([1 1 1600 1000]);
            tc.verifyEqual(pos(3), 1380);
            tc.verifyEqual(pos(4), 860);

            heights = bms.gui.GuiLayout.runPageRowHeights();
            tc.verifyEqual(numel(heights), 19);
            tc.verifyEqual(heights{19}, '1x');
        end

        function statusPanelBuildsPendingRows(tc)
            opts = struct('doTemp', true, 'doAccel', false, 'doCrack', true);
            rows = bms.gui.GuiStatusPanel.pendingRowsFromOptions(opts);

            tc.verifySize(rows, [2 7]);
            tc.verifyEqual(rows{1, 2}, '待运行');
            tc.verifyTrue(any(strcmp(rows(:, 1), '温度分析')));
            tc.verifyTrue(any(strcmp(rows(:, 1), '裂缝分析')));
        end
    end
end
