classdef test_run_request < matlab.unittest.TestCase
    properties
        TempDir
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'config'), fullfile(proj, 'pipeline'), fullfile(proj, 'analysis'), fullfile(proj, 'scripts'));
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if exist(tc.TempDir, 'dir'), rmdir(tc.TempDir, 's'); end
        end
    end

    methods (Test)
        function requestNormalizesLegacyInputs(tc)
            opts = struct('doTemp', true, 'doAccel', false);
            cfg = struct('source', 'config/default_config.json');
            req = bms.app.RunRequest.fromLegacy(tc.TempDir, '2026-01-01', '2026-01-31', opts, cfg);

            tc.verifyEqual(req.DataRoot, tc.TempDir);
            tc.verifyEqual(req.StatsDir, fullfile(tc.TempDir, 'stats'));
            tc.verifyEqual(req.LogDir, fullfile(tc.TempDir, 'run_logs'));
            tc.verifyEqual(req.Profile.BridgeId, 'guanbing');
            tc.verifyEqual(req.toStruct().enabled_modules, {'temperature'});
        end

        function requestBuildsContext(tc)
            cfg = struct('source', 'config/jiulongjiang_config.json');
            req = bms.app.RunRequest.fromLegacy(tc.TempDir, '2026-03-23', '2026-03-31', struct('doGNSS', true), cfg);
            ctx = req.toContext();

            tc.verifyEqual(ctx.DataRoot, tc.TempDir);
            tc.verifyEqual(ctx.ConfigPath, 'config/jiulongjiang_config.json');
            tc.verifyEqual(ctx.BridgeProfile.BridgeId, 'jiulongjiang');
            tc.verifyEqual(ctx.enabledModules(), {'gnss'});
        end

        function analysisRunnerAcceptsRunRequest(tc)
            req = bms.app.RunRequest.fromLegacy(tc.TempDir, '2026-01-01', '2026-01-01', emptyOpts(), struct());
            runner = bms.app.AnalysisRunner(req);

            tc.verifyEqual(runner.Context.DataRoot, tc.TempDir);
            tc.verifyEqual(runner.Request.DataRoot, tc.TempDir);
        end
    end
end

function opts = emptyOpts()
    opts = struct();
    keys = {'precheck_zip_count','doUnzip','doRenameCsv','doRemoveHeader','doResample', ...
        'doTemp','doHumidity','doRainfall','doGNSS','doWind','doEq','doWIM', ...
        'doDeflect','doBearingDisplacement','doTilt','doAccel','doAccelSpectrum', ...
        'doCableAccel','doCableAccelSpectrum','doRenameCrk','doCrack','doStrain', ...
        'doDynStrainBoxplot','doDynStrainLowpassBoxplot'};
    for i = 1:numel(keys)
        opts.(keys{i}) = false;
    end
end
