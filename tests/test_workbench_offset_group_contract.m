classdef test_workbench_offset_group_contract < matlab.unittest.TestCase
    properties
        Root
        Fixture
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.Root = fileparts(fileparts(mfilename('fullpath')));
            addpath(tc.Root, '-begin');
            addpath(fullfile(tc.Root, 'pipeline'), '-begin');
            addpath(fullfile(tc.Root, 'analysis'), '-begin');
            addpath(fullfile(tc.Root, 'config'), '-begin');
            addpath(fullfile(tc.Root, 'ui'), '-begin');
            tc.Fixture = fullfile(tc.Root, 'tests', 'fixtures', ...
                'workbench_offset_group_contract.json');
        end
    end

    methods (Test)
        function structuredOffsetsResolveThroughCleaningPipeline(tc)
            cfg = bms.core.ConfigStore.load(tc.Fixture);
            rules = bms.data.CleaningPipeline.resolveRules(cfg, 'cable_accel', 'CF-5');
            tc.verifyEqual(rules.offset_correction.mode, 'segmented');
            tc.verifyEqual(numel(rules.offset_correction.segments), 2);
            tc.verifyEqual(rules.offset_correction.segments(1).value, 10);
            tc.verifyEqual(rules.offset_correction.segments(2).mode, 'hourly_median');
            tc.verifyEqual(cfg.per_point.cable_accel.CF_5.alarm_bounds.level1(:).', [-1000 1000]);
        end

        function historicalListGroupsAndLabelsRemainReadable(tc)
            cfg = bms.core.ConfigStore.load(tc.Fixture);
            groups = bms.gui.GroupConfigService.readGroups(cfg, 'deflection');
            tc.verifyEqual(groups.G1(:).', {'D-1', 'D-2'});
            tc.verifyEqual(groups.G2(:).', {'D-3'});
            labels = bms.gui.GroupConfigService.readGroupLabels(cfg, 'strain');
            tc.verifyEqual(labels.BOX, '箱线组');
            tc.verifyEqual(labels.TS, '时程组');
        end

        function strainEditorWriteReadsBackAndPreservesUnrelatedFields(tc)
            cfg = bms.core.ConfigStore.load(tc.Fixture);
            groups = struct('NEW_TS', {{'S-2', 'S-3'}});
            labels = struct('NEW_TS', '新时程组');
            out = bms.gui.GroupConfigService.setGroups(cfg, 'strain', groups, labels);
            resolved = bms.gui.GroupConfigService.readGroups(out, 'strain');
            tc.verifyEqual(resolved.NEW_TS(:).', {'S-2', 'S-3'});
            tc.verifyEqual(out.groups.strain.BOX(:).', {'S-1', 'S-2'});
            tc.verifyTrue(out.unrelated_marker.keep);
            tc.verifyEqual(out.plot_styles.strain.line_width, 1);
        end
    end
end
