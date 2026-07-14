classdef test_main_gui_smoke < matlab.unittest.TestCase
    properties
        Fig
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.assumeTrue(usejava('jvm'), 'MATLAB GUI smoke tests require JVM support.');
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'ui'), fullfile(proj, 'config'), ...
                fullfile(proj, 'pipeline'), fullfile(proj, 'analysis'));
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if ~isempty(tc.Fig) && isvalid(tc.Fig)
                delete(tc.Fig);
            end
        end
    end

    methods (Test)
        function hiddenMainWindowExposesStableTestHandles(tc)
            tc.Fig = run_gui('Visible', 'off');

            tc.verifyEqual(char(tc.Fig.Visible), 'off');
            tc.verifyNotEmpty(tc.Fig.KeyPressFcn);
            ud = tc.Fig.UserData;
            tc.verifyEqual(ud.app, 'guanbing_main_gui');
            tc.verifyEqual(ud.version, 'v1.8.0');
            tc.verifyTrue(isfield(ud, 'controls'));
            tc.verifyNotEmpty(ud.controls.rootEdit.Value);
            tc.verifyTrue(contains(ud.controls.runBtn.Text, 'Ctrl+R'));
            tc.verifyTrue(contains(ud.controls.clearBtn.Text, 'Ctrl+K'));
            tc.verifyEqual(char(ud.controls.stopBtn.Enable), 'off');
            tc.verifyTrue(isfield(ud.controls, 'lowfreqSync'));
            tc.verifyTrue(isfield(ud.controls, 'dynamicRawSamplingMode'));
            tc.verifyTrue(any(strcmp(char(string(ud.controls.dynamicRawSamplingMode.Value)), ...
                {'capped', 'full'})));
            tc.verifyTrue(isfield(ud.controls, 'pathProfileNote'));
            tc.verifyTrue(contains(ud.controls.pathProfileNote.Text, 'Path profile'));
            tc.verifyTrue(isfield(ud.controls, 'progressLabel'));
            tc.verifyTrue(contains(ud.controls.progressLabel.Text, '运行进度'));
        end

        function ctrlKShortcutClearsRunLog(tc)
            tc.Fig = run_gui('Visible', 'off');
            ud = tc.Fig.UserData;
            ud.controls.logArea.Value = {'line to clear'};

            cb = tc.Fig.KeyPressFcn;
            cb(tc.Fig, struct('Modifier', {{'control'}}, 'Key', 'k'));

            value = ud.controls.logArea.Value;
            if iscell(value)
                tc.verifyTrue(all(cellfun(@isempty, value)));
            else
                tc.verifyEmpty(char(value));
            end
        end

        function ctrlRShortcutFailsPreflightWithoutLaunchingAsyncRun(tc)
            tc.Fig = run_gui('Visible', 'off');
            ud = tc.Fig.UserData;
            tmpRoot = fullfile(tempdir, ['guanbing_gui_preflight_' char(java.util.UUID.randomUUID)]);
            cleanupObj = onCleanup(@() cleanupTempRoot(tmpRoot)); %#ok<NASGU>

            ud.controls.rootEdit.Value = tmpRoot;
            ud.controls.startPicker.Value = datetime(2026, 5, 26);
            ud.controls.endPicker.Value = datetime(2026, 5, 28);

            cb = tc.Fig.KeyPressFcn;
            cb(tc.Fig, struct('Modifier', {{'control'}}, 'Key', 'r'));

            tc.verifyEqual(char(ud.controls.runBtn.Enable), 'on');
            tc.verifyEqual(char(ud.controls.stopBtn.Enable), 'off');
            tc.verifyTrue(contains(ud.controls.progressLabel.Text, '失败') || ...
                contains(ud.controls.progressLabel.Text, '澶辫触'));
            tc.verifyFalse(exist(fullfile(tmpRoot, 'run_logs', 'async_status.json'), 'file') == 2);
        end

        function hiddenGuiPreparedRunIndexesMatOnlyHongtangSource(tc)
            tc.Fig = run_gui('Visible', 'off');
            ud = tc.Fig.UserData;
            tmpRoot = fullfile(tempdir, ['guanbing_gui_mat_only_' char(java.util.UUID.randomUUID)]);
            cleanupObj = onCleanup(@() cleanupTempRoot(tmpRoot)); %#ok<NASGU>
            mkdir(tmpRoot);

            cfg = localHongtangMatOnlyWindFixture(tmpRoot);
            cfgPath = fullfile(tmpRoot, 'hongtang_mat_only.json');
            cfg.source = cfgPath;
            bms.core.Logger.writeJson(cfgPath, cfg);

            ud.controls.rootEdit.Value = tmpRoot;
            ud.controls.startPicker.Value = datetime(2026, 1, 1);
            ud.controls.endPicker.Value = datetime(2026, 1, 1);
            ud.controls.cfgEdit.Value = cfgPath;

            state = bms.gui.GuiState.fromValues( ...
                ud.controls.rootEdit.Value, ...
                datestr(ud.controls.startPicker.Value, 'yyyy-mm-dd'), ...
                datestr(ud.controls.endPicker.Value, 'yyyy-mm-dd'), ...
                ud.controls.cfgEdit.Value, ...
                fullfile(tmpRoot, 'run_logs'), false, struct(), struct('wind', true));

            [request, preflight, logLines] = bms.gui.GuiRunController.prepareRun(state, cfg);

            tc.verifyEqual(request.DataRoot, tmpRoot);
            tc.verifyTrue(request.Options.doWind);
            tc.verifyNotEqual(preflight.status, 'failed', strjoin(preflight.errors, newline));
            tc.verifyFalse(any(contains(preflight.warnings, 'no input directory found for subfolder')));
            tc.verifyNotEmpty(logLines);
            tc.verifyEqual(preflight.data_index.summary.found_point_count, 1);
            index = bms.data.DataIndex.load(preflight.data_index_path);
            pointRows = bms.data.DataIndex.pointRows(index);
            windRow = pointRows(strcmp(pointRows.module_key, 'wind') & strcmp(pointRows.point_id, 'W1'), :);
            tc.verifyEqual(height(windRow), 1);
            tc.verifyEqual(windRow.status{1}, 'found');
            tc.verifyTrue(endsWith(windRow.first_file{1}, fullfile('cache', 'SPEED.mat')));
        end
    end
end

function cleanupTempRoot(path)
if exist(path, 'dir')
    rmdir(path, 's');
end
end

function cfg = localHongtangMatOnlyWindFixture(root)
waveDir = fullfile(root, '2026-01-01', 'wave');
cacheDir = fullfile(waveDir, 'cache');
mkdir(cacheDir);

times = datetime(2026, 1, 1, 0, 0, 0) + seconds((0:9)');
vals = (1:10)';
save(fullfile(cacheDir, 'SPEED.mat'), 'times', 'vals');
vals = (91:100)';
save(fullfile(cacheDir, 'DIR.mat'), 'times', 'vals');

cfg = struct();
cfg.vendor = 'hongtang';
cfg.defaults = struct('header_marker', '[missing marker]');
cfg.subfolders = struct('wind_raw', 'wave');
cfg.points = struct('wind', {{'W1'}});
cfg.file_patterns = struct();
cfg.file_patterns.wind_speed = struct('default', '{file_id}.csv');
cfg.file_patterns.wind_direction = struct('default', '{file_id}.csv');
cfg.per_point = struct();
cfg.per_point.wind = struct();
cfg.per_point.wind.W1 = struct('speed_point_id', 'SPEED', 'dir_point_id', 'DIR');
cfg.data_index = struct('enabled', true);
cfg.data_adapter = struct();
cfg.data_adapter.time_series = struct( ...
    'source_mode', 'auto', ...
    'cache_version', 'csv_timeseries_v2', ...
    'require_metadata', false);
end
