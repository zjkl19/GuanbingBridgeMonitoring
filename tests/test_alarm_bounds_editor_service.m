classdef test_alarm_bounds_editor_service < matlab.unittest.TestCase
    methods (Test)
        function rowsExpandEveryConfiguredPoint(tc)
            cfg.points.strain = {'SX-1', 'SX-2'};
            cfg.per_point.strain.SX_1.alarm_bounds = struct('level2', [-283, 414]);
            cfg.per_point.strain.SX_2.alarm_bounds = struct('level2', [-218, 298], 'level3', [-300, 380]);
            spec = struct('value', 'strain', 'per_point_key', 'strain', 'point_key', 'strain');

            rows = bms.gui.AlarmBoundsEditorService.rows(cfg, spec);

            tc.verifyEqual(size(rows, 1), 3);
            tc.verifyEqual(rows(:, 1).', {'SX-1', 'SX-2', 'SX-2'});
            tc.verifyEqual(rows(:, 2).', {'level2', 'level2', 'level3'});
            tc.verifyEqual(cell2mat(rows(:, 3)).', [-283, -218, -300]);
            tc.verifyEqual(cell2mat(rows(:, 4)).', [414, 298, 380]);
        end

        function defaultsExpandForConfiguredPoints(tc)
            cfg.points.deflection = {'D-1', 'D-2'};
            cfg.defaults.deflection.alarm_bounds = struct('level2', [-80, 80]);
            spec = struct('value', 'deflection', 'per_point_key', 'deflection', 'point_key', 'deflection');

            rows = bms.gui.AlarmBoundsEditorService.rows(cfg, spec);

            tc.verifyEqual(size(rows, 1), 2);
            tc.verifyEqual(rows(:, 1).', {'D-1', 'D-2'});
            tc.verifyTrue(all(strcmp(rows(:, 5), 'defaults')));
        end

        function applyRowsWritesPointAlarmBounds(tc)
            cfg.points.strain = {'SX-1', 'SX-2'};
            cfg.per_point.strain.SX_1.offset_correction = struct('enabled', true);
            rows = {
                'SX-1', 'level2', -200, 400, 'per_point'
                'SX-2', 'level2', '-218', '298', 'per_point'
                };
            spec = struct('value', 'strain', 'per_point_key', 'strain', 'point_key', 'strain');

            cfgOut = bms.gui.AlarmBoundsEditorService.applyRows(cfg, spec, rows);

            tc.verifyEqual(cfgOut.per_point.strain.SX_1.alarm_bounds.level2, [-200, 400]);
            tc.verifyEqual(cfgOut.per_point.strain.SX_2.alarm_bounds.level2, [-218, 298]);
            tc.verifyTrue(cfgOut.per_point.strain.SX_1.offset_correction.enabled);
            tc.verifyEqual(cfgOut.name_map_global.SX_1, 'SX-1');
        end

        function applyRowsRemovesDeletedExplicitBounds(tc)
            cfg.points.strain = {'SX-1', 'SX-2'};
            cfg.per_point.strain.SX_1.alarm_bounds = struct('level2', [-1, 1]);
            cfg.per_point.strain.SX_2.alarm_bounds = struct('level2', [-2, 2]);
            rows = {'SX-2', 'level2', -5, 5, 'per_point'};
            spec = struct('value', 'strain', 'per_point_key', 'strain', 'point_key', 'strain');

            cfgOut = bms.gui.AlarmBoundsEditorService.applyRows(cfg, spec, rows);

            tc.verifyFalse(isfield(cfgOut.per_point.strain, 'SX_1'));
            tc.verifyEqual(cfgOut.per_point.strain.SX_2.alarm_bounds.level2, [-5, 5]);
        end

        function duplicatePointLevelRejected(tc)
            cfg.points.strain = {'SX-1'};
            rows = {
                'SX-1', 'level2', -1, 1, ''
                'SX-1', 'level2', -2, 2, ''
                };
            spec = struct('value', 'strain', 'per_point_key', 'strain', 'point_key', 'strain');

            tc.verifyError(@() bms.gui.AlarmBoundsEditorService.applyRows(cfg, spec, rows), ...
                'bms:gui:AlarmBoundsEditorService:DuplicateLevel');
        end

        function invalidLevelRejected(tc)
            cfg.points.strain = {'SX-1'};
            rows = {'SX-1', '二级', -1, 1, ''};
            spec = struct('value', 'strain', 'per_point_key', 'strain', 'point_key', 'strain');

            tc.verifyError(@() bms.gui.AlarmBoundsEditorService.applyRows(cfg, spec, rows), ...
                'bms:gui:AlarmBoundsEditorService:InvalidLevel');
        end
    end
end
