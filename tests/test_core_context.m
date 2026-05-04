classdef test_core_context < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'config'), fullfile(proj, 'pipeline'), fullfile(proj, 'analysis'), fullfile(proj, 'scripts'));
        end
    end

    methods (Test)
        function contextBuildsExpectedPaths(tc)
            opts = struct('doTemp', true, 'doAccel', false);
            cfg = struct('source', 'config/default_config.json');
            ctx = bms.core.AnalysisContext('X:/data/root', '2026-01-01', '2026-01-31', opts, cfg, 'RunId', 'unit');
            tc.verifyEqual(ctx.StatsDir, fullfile('X:/data/root', 'stats'));
            tc.verifyEqual(ctx.LogDir, fullfile('X:/data/root', 'run_logs'));
            tc.verifyEqual(ctx.enabledModules(), {'temperature'});
            s = ctx.toStruct();
            tc.verifyEqual(s.run_id, 'unit');
        end

        function pathResolverFindsLatest(tc)
            tmp = tempname;
            mkdir(tmp);
            cleanup = onCleanup(@() rmdir(tmp, 's'));
            fid = fopen(fullfile(tmp, 'a.txt'), 'wt'); fprintf(fid, 'a'); fclose(fid);
            fid = fopen(fullfile(tmp, 'b.txt'), 'wt'); fprintf(fid, 'b'); fclose(fid);
            latest = bms.core.PathResolver.latestFile(tmp, '*.txt');
            tc.verifyTrue(isfile(latest));
            clear cleanup;
        end
    end
end
