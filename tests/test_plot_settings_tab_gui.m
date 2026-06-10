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

        function spectrumTableWritesPointPeakOrders(tc)
            cfg = test_plot_settings_tab_gui.sampleSpectrumCfg();
            tab = uitab(uitabgroup(tc.Fig), 'Title', 'plot');
            cfgEdit = uieditfield(tc.Fig, 'text', 'Value', fullfile(tc.TempDir, 'config.json'));

            ps = build_plot_settings_tab(tab, tc.Fig, cfg, cfgEdit.Value, cfgEdit, @(~) [], [0 0.3 0.7]);
            ps.moduleDrop.Value = 'accel_spectrum';
            ps.moduleDrop.ValueChangedFcn(ps.moduleDrop, []);

            tc.verifyEqual(size(ps.peakTable.Data, 2), numel(bms.gui.SpectrumPeakOrderEditorService.columnNames()));

            rows = ps.peakTable.Data;
            rows(end+1, :) = {'point', 'AZ-2', 1, 'AZ-2 first', 0.600, 0.500, 0.700, true, 'AZ-2 theory', 'new'};
            ps.peakTable.Data = rows;

            cfgOut = ps.applyToCfg(cfg);

            tc.verifyTrue(isfield(cfgOut.per_point.accel_spectrum.AZ_2, 'peak_orders'));
            tc.verifyEqual(cfgOut.per_point.accel_spectrum.AZ_2.peak_orders.search_center_hz, 0.600, 'AbsTol', 1e-12);
            tc.verifyEqual(cfgOut.per_point.accel_spectrum.AZ_2.peak_orders.search_half_width_hz, 0.100, 'AbsTol', 1e-12);
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

        function cfg = sampleSpectrumCfg()
            cfg = struct();
            cfg.points.acceleration = {'AZ-1', 'AZ-2'};
            cfg.accel_spectrum_params.peak_orders = struct( ...
                'order', 1, ...
                'label', 'default first', ...
                'theoretical_hz', 0.593, ...
                'search_center_hz', 0.640, ...
                'search_half_width_hz', 0.200);
        end
    end
end
