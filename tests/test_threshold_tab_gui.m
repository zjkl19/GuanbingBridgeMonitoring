classdef test_threshold_tab_gui < matlab.unittest.TestCase
    properties
        Root
        TempDir
        Fig
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.assumeTrue(usejava('jvm'), 'MATLAB GUI tests require JVM support.');
            tc.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(tc.Root, fullfile(tc.Root, 'ui'), fullfile(tc.Root, 'config'), ...
                fullfile(tc.Root, 'pipeline'), fullfile(tc.Root, 'analysis'));
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            tc.Fig = uifigure('Visible', 'off', 'Position', [100 100 1100 620]);
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
        function applyToCfgPreservesDefaultAndPointOneSidedThresholds(tc)
            cfg = test_threshold_tab_gui.sampleCfg();
            tab = uitab(uitabgroup(tc.Fig), 'Title', '清洗阈值');
            cfgPath = fullfile(tc.TempDir, 'config.json');
            cfgEdit = uieditfield(tc.Fig, 'text', 'Value', cfgPath);

            th = build_threshold_tab( ...
                tab, tc.Fig, cfg, cfgPath, cfgEdit, @(~) [], [0 0.3 0.7]);

            tc.verifyEqual(th.sensorDrop.Value, 'temperature');
            tc.verifyEqual(size(th.defaultsTable.Data, 1), 1);
            tc.verifyEmpty(th.defaultsTable.Data{1, 1});
            tc.verifyEqual(th.defaultsTable.Data{1, 2}, 50);
            tc.verifyEqual(size(th.perTable.Data, 1), 1);
            tc.verifyEqual(th.perTable.Data{1, 1}, 'T-1');
            tc.verifyEqual(th.perTable.Data{1, 2}, 0);
            tc.verifyEmpty(th.perTable.Data{1, 3});

            cfgOut = th.applyToCfg(cfg);

            tc.verifyNumElements(cfgOut.defaults.temperature.thresholds, 1);
            tc.verifyEmpty(cfgOut.defaults.temperature.thresholds.min);
            tc.verifyEqual(cfgOut.defaults.temperature.thresholds.max, 50);
            tc.verifyNumElements(cfgOut.per_point.temperature.T_1.thresholds, 1);
            tc.verifyEqual(cfgOut.per_point.temperature.T_1.thresholds.min, 0);
            tc.verifyEmpty(cfgOut.per_point.temperature.T_1.thresholds.max);
        end

        function applyToCfgAcceptsNewTimedUpperOnlyRule(tc)
            cfg = test_threshold_tab_gui.sampleCfg();
            tab = uitab(uitabgroup(tc.Fig), 'Title', '清洗阈值');
            cfgPath = fullfile(tc.TempDir, 'config.json');
            cfgEdit = uieditfield(tc.Fig, 'text', 'Value', cfgPath);
            th = build_threshold_tab( ...
                tab, tc.Fig, cfg, cfgPath, cfgEdit, @(~) [], [0 0.3 0.7]);
            th.perTable.Data = {
                'T-1', [], 42.25, '2026-05-01 00:00:00', ...
                '2026-05-02 00:00:00', false, [], []};

            cfgOut = th.applyToCfg(cfg);
            rule = cfgOut.per_point.temperature.T_1.thresholds;

            tc.verifyEmpty(rule.min);
            tc.verifyEqual(rule.max, 42.25);
            tc.verifyEqual(rule.t_range_start, '2026-05-01 00:00:00');
            tc.verifyEqual(rule.t_range_end, '2026-05-02 00:00:00');
        end
    end

    methods (Static, Access = private)
        function cfg = sampleCfg()
            cfg = struct();
            cfg.defaults = struct();
            cfg.defaults.temperature = struct( ...
                'thresholds', struct('min', [], 'max', 50, ...
                    't_range_start', '', 't_range_end', ''), ...
                'zero_to_nan', false, 'outlier', []);
            cfg.per_point = struct();
            cfg.per_point.temperature = struct();
            cfg.per_point.temperature.T_1 = struct( ...
                'thresholds', struct('min', 0, 'max', [], ...
                    't_range_start', '', 't_range_end', ''), ...
                'zero_to_nan', false, 'outlier', []);
            cfg.points = struct('temperature', {{'T-1'}});
            cfg.name_map_global = struct('T_1', 'T-1');
        end
    end
end
