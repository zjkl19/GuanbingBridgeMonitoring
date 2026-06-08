classdef test_group_config_tab_gui < matlab.unittest.TestCase
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
            tc.Fig = uifigure('Visible', 'off', 'Position', [100 100 900 520]);
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
        function tabBuildsAndShowsGroupKeyRule(tc)
            cfg = test_group_config_tab_gui.sampleCfg();
            tab = uitab(uitabgroup(tc.Fig), 'Title', '组图配置');
            cfgEdit = uieditfield(tc.Fig, 'text', 'Value', fullfile(tc.TempDir, 'config.json'));

            gc = build_group_config_tab(tab, tc.Fig, cfg, cfgEdit.Value, cfgEdit, @(~) [], [0 0.3 0.7]);

            tc.verifyTrue(contains(gc.ruleLabel.Text, 'group_key'));
            tc.verifyTrue(contains(gc.ruleLabel.Text, '英文字母、数字、下划线'));
            tc.verifyTrue(any(strcmp(gc.moduleDrop.ItemsData, 'deflection')));
            tc.verifyEqual(gc.groupTable.Data{1, 1}, 'G1');
            tc.verifyTrue(any(strcmp(gc.availableTable.Data(:, 1), 'DX-3')));
        end

        function applyToCfgWritesGroupsAndLabels(tc)
            cfg = test_group_config_tab_gui.sampleCfg();
            tab = uitab(uitabgroup(tc.Fig), 'Title', '组图配置');
            cfgEdit = uieditfield(tc.Fig, 'text', 'Value', fullfile(tc.TempDir, 'config.json'));
            gc = build_group_config_tab(tab, tc.Fig, cfg, cfgEdit.Value, cfgEdit, @(~) [], [0 0.3 0.7]);

            gc.groupTable.Data = {'New_1', '新分组', 2};
            gc.pointTable.Data = {'DX-3'; 'DX-4'};

            cfgOut = gc.applyToCfg(cfg);

            tc.verifyEqual(cfgOut.groups.deflection.New_1(:).', {'DX-3', 'DX-4'});
            tc.verifyEqual(cfgOut.plot_styles.deflection.group_labels.New_1, '新分组');
        end

        function applyToCfgRejectsInvalidGroupKey(tc)
            cfg = test_group_config_tab_gui.sampleCfg();
            tab = uitab(uitabgroup(tc.Fig), 'Title', '组图配置');
            cfgEdit = uieditfield(tc.Fig, 'text', 'Value', fullfile(tc.TempDir, 'config.json'));
            gc = build_group_config_tab(tab, tc.Fig, cfg, cfgEdit.Value, cfgEdit, @(~) [], [0 0.3 0.7]);

            gc.groupTable.Data = {'A-中文', '非法分组', 1};
            gc.pointTable.Data = {'DX-1'};

            tc.verifyError(@() gc.applyToCfg(cfg), 'build_group_config_tab:InvalidGroups');
        end
    end

    methods (Static, Access = private)
        function cfg = sampleCfg()
            cfg = struct();
            cfg.points = struct('deflection', {{'DX-1', 'DX-2', 'DX-3', 'DX-4'}});
            cfg.groups = struct('deflection', struct('G1', {{'DX-1', 'DX-2'}}));
            cfg.plot_styles = struct('deflection', struct('group_labels', struct('G1', '原分组')));
        end
    end
end
