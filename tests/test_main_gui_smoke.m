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
            tc.verifyEqual(ud.version, 'v1.7.13');
            tc.verifyTrue(isfield(ud, 'controls'));
            tc.verifyNotEmpty(ud.controls.rootEdit.Value);
            tc.verifyTrue(contains(ud.controls.runBtn.Text, 'Ctrl+R'));
            tc.verifyTrue(contains(ud.controls.clearBtn.Text, 'Ctrl+K'));
            tc.verifyEqual(char(ud.controls.stopBtn.Enable), 'off');
            tc.verifyTrue(isfield(ud.controls, 'lowfreqSync'));
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
            ud.controls.startDate.Value = datetime(2026, 5, 26);
            ud.controls.endDate.Value = datetime(2026, 5, 28);

            cb = tc.Fig.KeyPressFcn;
            cb(tc.Fig, struct('Modifier', {{'control'}}, 'Key', 'r'));

            tc.verifyEqual(char(ud.controls.runBtn.Enable), 'on');
            tc.verifyEqual(char(ud.controls.stopBtn.Enable), 'off');
            tc.verifyTrue(contains(ud.controls.progressLabel.Text, '失败') || ...
                contains(ud.controls.progressLabel.Text, '澶辫触'));
            tc.verifyFalse(exist(fullfile(tmpRoot, 'run_logs', 'async_status.json'), 'file') == 2);
        end
    end
end

function cleanupTempRoot(path)
if exist(path, 'dir')
    rmdir(path, 's');
end
end
