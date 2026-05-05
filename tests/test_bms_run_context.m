classdef test_bms_run_context < matlab.unittest.TestCase
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
        function wrapperWritesManifest(tc)
            opts = emptyOpts();
            cfg = struct('source', fullfile(tc.TempDir, 'unit_config.json'), 'plot_common', struct('append_timestamp', false));
            manifestPath = bms_run_context(tc.TempDir, '2025-01-01', '2025-01-01', opts, cfg);
            tc.verifyTrue(isfile(manifestPath));
            manifest = jsondecode(fileread(manifestPath));
            tc.verifyEqual(manifest.status, 'ok');
            tc.verifyEqual(manifest.schema_version, 2);
            tc.verifyEqual(manifest.manifest_type, 'analysis_run');
            tc.verifyEqual(manifest.data_root, tc.TempDir);
            tc.verifyTrue(isfile(manifest.latest_log));
            tc.verifyTrue(isfield(manifest, 'module_logs'));
            tc.verifyTrue(isfield(manifest, 'module_catalog'));
            tc.verifyTrue(isfield(manifest, 'module_preflight'));
            tc.verifyTrue(isfield(manifest, 'run_preflight'));
            tc.verifyTrue(isfield(manifest, 'run_request'));
            tc.verifyTrue(isfield(manifest, 'offset_report'));
            tc.verifyEqual(manifest.offset_report.status, 'ok');
        end

        function legacyWrapperStillWorks(tc)
            opts = emptyOpts();
            cfg = struct('source', fullfile(tc.TempDir, 'legacy_config.json'), 'plot_common', struct('append_timestamp', false));
            manifestPath = gbm_run_context(tc.TempDir, '2025-01-01', '2025-01-01', opts, cfg);
            tc.verifyTrue(isfile(manifestPath));
            manifest = jsondecode(fileread(manifestPath));
            tc.verifyEqual(manifest.status, 'ok');
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
