classdef test_wim_config_service < matlab.unittest.TestCase
    properties
        TempDir
        ProjectRoot
    end

    methods (TestMethodSetup)
        function setupTempDir(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            tc.ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(tc.ProjectRoot);
        end
    end

    methods (TestMethodTeardown)
        function cleanupTempDir(tc)
            if exist(tc.TempDir, 'dir')
                rmdir(tc.TempDir, 's');
            end
        end
    end

    methods (Test)
        function wimConfigAppliesDefaults(tc)
            cfg = struct('wim', struct('bridge', 'jiulongjiang'));

            wim = bms.analyzer.WimConfigService.getWimConfig(cfg);

            tc.verifyEqual(wim.bridge, 'jiulongjiang');
            tc.verifyEqual(wim.vendor, 'auto');
            tc.verifyEqual(wim.topn, 10);
            tc.verifyEqual(wim.lanes, 1:8);
            tc.verifyEqual(wim.excel_name, 'WIM_Report_{bridge}_{yyyymm}.xlsx');
        end

        function autoVendorRequiresSingleConfiguredInput(tc)
            wim = struct();
            wim.vendor = 'auto';
            wim.input = struct('jiulongjiang', struct());

            tc.verifyEqual(bms.analyzer.WimConfigService.resolveVendor(wim), 'jiulongjiang');

            wim.input.zhichen = struct();
            try
                bms.analyzer.WimConfigService.resolveVendor(wim);
                tc.verifyFail('Expected multiple auto vendors to require explicit vendor.');
            catch ME
                tc.verifyTrue(contains(ME.message, 'wim.vendor is required'));
            end
        end

        function resolvesZhichenMonthlyPair(tc)
            wimDir = fullfile(tc.TempDir, 'WIM');
            mkdir(wimDir);
            fmtPath = fullfile(wimDir, 'HS_Data_202601.fmt');
            bcpPath = fullfile(wimDir, 'HS_Data_202601.bcp');
            fclose(fopen(fmtPath, 'w'));
            fclose(fopen(bcpPath, 'w'));

            [fmt, bcp] = bms.analyzer.WimConfigService.resolveZhichenPaths(struct(), tc.ProjectRoot, '202601', tc.TempDir);

            tc.verifyEqual(fmt, fmtPath);
            tc.verifyEqual(bcp, bcpPath);
        end

        function reportsMissingZhichenPairMember(tc)
            wimDir = fullfile(tc.TempDir, 'WIM');
            mkdir(wimDir);
            fclose(fopen(fullfile(wimDir, 'HS_Data_202601.fmt'), 'w'));

            tc.verifyError(@() bms.analyzer.WimConfigService.resolveZhichenPaths(struct(), tc.ProjectRoot, '202601', tc.TempDir), ...
                'WIM:Input:MissingBcp');
        end

        function resolvesDbConfigAndOutputRoot(tc)
            cfg = struct();
            cfg.wim_db = struct('database', 'CustomDb', 'scripts_dir', fullfile('scripts', 'wim_sql'));
            wim = struct('db', struct('table_prefix', 'T_', 'sqlcmd_utf8', false), 'output_root', 'WIM/results');

            db = bms.analyzer.WimConfigService.getDbConfig(wim, cfg, tc.ProjectRoot);
            outRoot = bms.analyzer.WimConfigService.resolveOutputRoot(tc.TempDir, wim, tc.ProjectRoot);

            tc.verifyEqual(db.database, 'CustomDb');
            tc.verifyEqual(db.table_prefix, 'T_');
            tc.verifyFalse(db.sqlcmd_utf8);
            tc.verifyTrue(endsWith(db.scripts_dir, fullfile('scripts', 'wim_sql')));
            tc.verifyEqual(outRoot, fullfile(tc.TempDir, 'WIM/results'));
        end
    end
end
