classdef test_plot_settings_tab_gui < matlab.unittest.TestCase
    properties
        Root
        TempDir
        Fig
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(tc.Root, fullfile(tc.Root, 'ui'), fullfile(tc.Root, 'config'), ...
                fullfile(tc.Root, 'pipeline'), fullfile(tc.Root, 'analysis'));
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            tc.Fig = uifigure('Visible', 'off', 'Position', [100 100 1100 650]);
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if ~isempty(tc.Fig) && isvalid(tc.Fig)
                delete(tc.Fig);
            end
            if exist(tc.TempDir, 'dir')
                rmdir(tc.TempDir, 's');
            end
        end
    end

    methods (Test)
        function alarmBoundsTableExpandsAndWritesBack(tc)
            cfg = test_plot_settings_tab_gui.sampleCfg();
            tab = uitab(uitabgroup(tc.Fig), 'Title', '绘图参数');
            cfgEdit = uieditfield(tc.Fig, 'text', 'Value', fullfile(tc.TempDir, 'config.json'));

            ps = build_plot_settings_tab(tab, tc.Fig, cfg, cfgEdit.Value, cfgEdit, @(~) [], [0 0.3 0.7]);

            tc.verifyEqual(ps.alarmTable.Data(:, 1).', {'T-1', 'T-2'});
            tc.verifyEqual(ps.alarmTable.Data(:, 2).', {'level2', 'level2'});
            tc.verifyTrue(contains(ps.alarmHint.Text, 'alarm_bounds'));

            edited = ps.alarmTable.Data;
            edited{1, 3} = -8.5;
            edited{1, 4} = 41.5;
            ps.alarmTable.Data = edited;

            cfgOut = ps.applyToCfg(cfg);

            tc.verifyEqual(cfgOut.per_point.temperature.T_1.alarm_bounds.level2, [-8.5, 41.5]);
            tc.verifyEqual(cfgOut.per_point.temperature.T_2.alarm_bounds.level2, [-10, 50]);
        end

        function warnPreviewExpandsPointLabels(tc)
            cfg = test_plot_settings_tab_gui.sampleSameWarnCfg();
            tab = uitab(uitabgroup(tc.Fig), 'Title', 'plot');
            cfgEdit = uieditfield(tc.Fig, 'text', 'Value', fullfile(tc.TempDir, 'config.json'));

            ps = build_plot_settings_tab(tab, tc.Fig, cfg, cfgEdit.Value, cfgEdit, @(~) [], [0 0.3 0.7]);

            tc.verifyEqual(size(ps.warnTable.Data, 1), 2);
            ps.warnExpandCheck.Value = true;
            ps.warnExpandCheck.ValueChangedFcn(ps.warnExpandCheck, []);

            tc.verifyEqual(size(ps.warnTable.Data, 1), 4);
            tc.verifyTrue(any(contains(ps.warnTable.Data(:, 2), 'T-1')));
            tc.verifyTrue(any(contains(ps.warnTable.Data(:, 2), 'T-2')));
        end
    end

    methods (Static, Access = private)
        function cfg = sampleCfg()
            cfg = struct();
            cfg.points.temperature = {'T-1', 'T-2'};
            cfg.per_point.temperature.T_1.alarm_bounds = struct('level2', [-8, 41]);
            cfg.per_point.temperature.T_2.alarm_bounds = struct('level2', [-10, 50]);
            cfg.plot_styles.temperature = struct('ylabel', 'Temperature', 'title_prefix', 'Temperature');
        end

        function cfg = sampleSameWarnCfg()
            cfg = struct();
            cfg.points.temperature = {'T-1', 'T-2'};
            cfg.per_point.temperature.T_1.alarm_bounds = struct('level2', [-8, 41]);
            cfg.per_point.temperature.T_2.alarm_bounds = struct('level2', [-8, 41]);
            cfg.plot_styles.temperature = struct('ylabel', 'Temperature', 'title_prefix', 'Temperature');
        end
    end
end
