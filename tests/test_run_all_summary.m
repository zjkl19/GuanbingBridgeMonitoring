classdef test_run_all_summary < matlab.unittest.TestCase
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
        function emptyRunReturnsStructuredSummary(tc)
            opts = emptyOpts();
            cfg = struct('source', fullfile(tc.TempDir, 'unit_config.json'), 'plot_common', struct('append_timestamp', false));
            summary = run_all(tc.TempDir, '2025-01-01', '2025-01-01', opts, cfg);
            tc.verifyEqual(summary.status, 'ok');
            tc.verifyTrue(isfile(summary.log_file));
            tc.verifyTrue(isfield(summary, 'module_logs'));
            tc.verifyTrue(isfield(summary, 'module_catalog'));
            tc.verifyTrue(isfield(summary, 'module_preflight'));
            tc.verifyTrue(isfield(summary, 'run_preflight'));
            tc.verifyTrue(isfield(summary, 'offset_report'));
            tc.verifyEqual(summary.offset_report.status, 'ok');
            tc.verifyTrue(isfield(summary, 'analysis_manifest'));
            tc.verifyTrue(isfile(summary.analysis_manifest));
            manifest = jsondecode(fileread(summary.analysis_manifest));
            tc.verifyEqual(manifest.manifest_type, 'analysis_run');
            tc.verifyTrue(isfield(manifest, 'bridge_profile'));
            tc.verifyTrue(isfield(manifest, 'run_preflight'));
            tc.verifyTrue(isfield(manifest, 'module_results'));
            tc.verifyGreaterThanOrEqual(summary.elapsed_sec, 0);
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
