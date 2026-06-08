classdef test_group_config_service < matlab.unittest.TestCase
    methods (Test)
        function readsGroupsAndLabels(tc)
            cfg = test_group_config_service.sampleCfg();

            groups = bms.gui.GroupConfigService.readGroups(cfg, 'deflection');
            labels = bms.gui.GroupConfigService.readGroupLabels(cfg, 'deflection');

            tc.verifyEqual(groups.G1(:).', {'DX-1', 'DX-2'});
            tc.verifyEqual(labels.G1, '梁端位移组1');
        end

        function lowpassFallsBackToHighpassGroups(tc)
            cfg = test_group_config_service.sampleCfg();
            cfg.groups = rmfield(cfg.groups, 'dynamic_strain_lowpass');

            groups = bms.gui.GroupConfigService.readGroups(cfg, 'dynamic_strain_lowpass');

            tc.verifyEqual(groups.DYN1(:).', {'DS-1', 'DS-2'});
        end

        function validatesGroupKeysClearly(tc)
            cfg = test_group_config_service.sampleCfg();

            report = bms.gui.GroupConfigService.validateGroupRows( ...
                cfg, 'deflection', {'A-中文'}, {{'DX-1'}}, {''});

            tc.verifyFalse(report.ok);
            tc.verifyTrue(contains(report.errors{1}, '只能使用英文字母、数字、下划线'));
        end

        function rejectsDuplicateAndUnknownPoints(tc)
            cfg = test_group_config_service.sampleCfg();
            groups = struct();
            groups.G1 = {'DX-1', 'DX-1'};
            groups.G2 = {'DX-404'};

            report = bms.gui.GroupConfigService.validateGroups(cfg, 'deflection', groups, struct());

            tc.verifyFalse(report.ok);
            tc.verifyTrue(any(contains(report.errors, '重复测点')));
            tc.verifyTrue(any(contains(report.errors, '未知测点')));
        end

        function setGroupsCleansOrphanLabels(tc)
            cfg = test_group_config_service.sampleCfg();
            groups = struct();
            groups.New_1 = {'DX-3', 'DX-4'};
            labels = struct('New_1', '新组', 'Old_Orphan', '旧孤儿');

            cfg = bms.gui.GroupConfigService.setGroups(cfg, 'deflection', groups, labels);

            tc.verifyEqual(cfg.groups.deflection.New_1(:).', {'DX-3', 'DX-4'});
            tc.verifyEqual(cfg.plot_styles.deflection.group_labels.New_1, '新组');
            tc.verifyFalse(isfield(cfg.plot_styles.deflection.group_labels, 'Old_Orphan'));
        end

        function availablePointsUsePerPointOriginalNames(tc)
            cfg = test_group_config_service.sampleCfg();
            cfg.points = rmfield(cfg.points, 'deflection');
            cfg.name_map_global = struct('DX_5', 'DX-5');
            cfg.per_point.deflection.DX_5 = struct();

            points = bms.gui.GroupConfigService.availablePoints(cfg, 'deflection');

            tc.verifyTrue(any(strcmp(points, 'DX-5')));
        end

        function editableModuleKeysExposeGroupModules(tc)
            cfg = test_group_config_service.sampleCfg();

            keys = bms.gui.ConfigEditorService.editableModuleKeys(cfg, 'groups');

            tc.verifyTrue(any(strcmp(keys, 'deflection')));
            tc.verifyTrue(any(strcmp(keys, 'dynamic_strain')));
            tc.verifyFalse(any(strcmp(keys, 'accel_spectrum')));
        end
    end

    methods (Static, Access = private)
        function cfg = sampleCfg()
            cfg = struct();
            cfg.points = struct();
            cfg.points.deflection = {'DX-1', 'DX-2', 'DX-3', 'DX-4'};
            cfg.points.strain = {'DS-1', 'DS-2', 'DS-3'};
            cfg.groups = struct();
            cfg.groups.deflection = struct('G1', {{'DX-1', 'DX-2'}});
            cfg.groups.dynamic_strain = struct('DYN1', {{'DS-1', 'DS-2'}});
            cfg.groups.dynamic_strain_lowpass = struct('DYNLP1', {{'DS-2', 'DS-3'}});
            cfg.plot_styles = struct();
            cfg.plot_styles.deflection = struct('group_labels', struct('G1', '梁端位移组1'));
            cfg.plot_styles.dynamic_strain = struct('group_labels', struct('DYN1', '高通组1'));
            cfg.plot_styles.dynamic_strain_lowpass = struct('group_labels', struct('DYNLP1', '低通组1'));
        end
    end
end
