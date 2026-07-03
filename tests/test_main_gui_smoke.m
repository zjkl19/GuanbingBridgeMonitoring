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
    end
end
