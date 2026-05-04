classdef test_config_store < matlab.unittest.TestCase
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
        function guardedSavePreservesOffset(tc)
            target = fullfile(tc.TempDir, 'cfg.json');
            cfg = makeCfg();
            write_json(target, cfg);
            cfg2 = cfg;
            cfg2.per_point.strain.PT_1.thresholds = struct('min', -2, 'max', 2);
            bms.core.ConfigStore.saveGuarded(cfg2, target, true);
            out = jsondecode(fileread(target));
            tc.verifyEqual(out.per_point.strain.PT_1.offset_correction, 12);
        end

        function guardedSaveRejectsOffsetDrop(tc)
            target = fullfile(tc.TempDir, 'cfg.json');
            cfg = makeCfg();
            write_json(target, cfg);
            cfg2 = cfg;
            cfg2.per_point.strain.PT_1 = rmfield(cfg2.per_point.strain.PT_1, 'offset_correction');
            tc.verifyError(@() bms.core.ConfigStore.saveGuarded(cfg2, target, false), 'BMS:Config:ProtectedFieldDropped');
        end
    end
end

function cfg = makeCfg()
    cfg = struct();
    cfg.defaults = struct('header_marker', '[time]');
    cfg.subfolders = struct();
    cfg.file_patterns = struct();
    cfg.groups = struct();
    cfg.plot_styles = struct();
    cfg.per_point = struct();
    cfg.per_point.strain = struct();
    cfg.per_point.strain.PT_1 = struct('thresholds', struct('min', -1, 'max', 1), 'offset_correction', 12);
end

function write_json(path, cfg)
    txt = jsonencode(cfg, 'PrettyPrint', true);
    fid = fopen(path, 'wt', 'n', 'UTF-8');
    fwrite(fid, txt, 'char');
    fclose(fid);
end
