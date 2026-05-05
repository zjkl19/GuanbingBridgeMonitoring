classdef test_config_patch < matlab.unittest.TestCase
    properties
        TempDir
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'config'), fullfile(proj, 'scripts'));
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if exist(tc.TempDir, 'dir'), rmdir(tc.TempDir, 's'); end
        end
    end

    methods (Test)
        function applySetAndRemoveOnlyTouchesRequestedPath(tc)
            cfg = struct();
            cfg.plot_common.gap_mode = 'break';
            cfg.plot_common.append_timestamp = true;
            cfg.per_point.strain.PT_1.offset_correction = 12;

            ops = { ...
                bms.config.ConfigPatch.setOp('plot_common.gap_mode', 'connect'), ...
                bms.config.ConfigPatch.removeOp('plot_common.append_timestamp') ...
            };
            out = bms.config.ConfigPatch.apply(cfg, ops);

            tc.verifyEqual(out.plot_common.gap_mode, 'connect');
            tc.verifyFalse(isfield(out.plot_common, 'append_timestamp'));
            tc.verifyEqual(out.per_point.strain.PT_1.offset_correction, 12);
        end

        function patchFileKeepsProtectedConfigFields(tc)
            target = fullfile(tc.TempDir, 'cfg.json');
            cfg = makeCfg();
            write_json(target, cfg);
            bms.core.ConfigStore.patchFile(target, {bms.config.ConfigPatch.setOp('plot_common.gap_mode', 'connect')}, false);
            out = jsondecode(fileread(target));
            tc.verifyEqual(out.plot_common.gap_mode, 'connect');
            tc.verifyEqual(out.per_point.strain.PT_1.offset_correction, 12);
        end

        function schemaValidatorDetailedReturnsStatus(tc)
            cfg = makeCfg();
            cfg.per_point.strain.PT_1.thresholds = struct('min', 5, 'max', -5);
            result = bms.config.SchemaValidator.validateDetailed(cfg);
            tc.verifyEqual(result.status, 'warning');
            tc.verifyTrue(any(contains(result.warnings, 'min > max')));
        end
    end
end

function cfg = makeCfg()
    cfg = struct();
    cfg.defaults = struct('header_marker', '[time]');
    cfg.subfolders = struct('strain', 'strain');
    cfg.file_patterns = struct('strain', struct('default', '*.csv'));
    cfg.points = struct('strain', {{'PT-1'}});
    cfg.plot_styles = struct();
    cfg.plot_common = struct('gap_mode', 'break', 'append_timestamp', true);
    cfg.per_point.strain.PT_1 = struct('thresholds', struct('min', -1, 'max', 1), 'offset_correction', 12);
end

function write_json(path, cfg)
    txt = jsonencode(cfg, 'PrettyPrint', true);
    fid = fopen(path, 'wt', 'n', 'UTF-8');
    fwrite(fid, txt, 'char');
    fclose(fid);
end
