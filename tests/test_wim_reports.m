classdef test_wim_reports < matlab.unittest.TestCase
    methods (Test)
        function testDirectSample(testCase)
            proj_root = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj_root, fullfile(proj_root,'analysis'), fullfile(proj_root,'config'));
            cfg = load_config(fullfile(proj_root,'config','hongtang_config.json'));
            temp_root = tempname;
            mkdir(temp_root);
            cleanup = onCleanup(@() rmdir(temp_root, 's')); %#ok<NASGU>
            sample_dir = fullfile(temp_root, 'synthetic_zhichen');
            fixture = create_synthetic_zhichen_fixture(sample_dir);

            cfg.wim.vendor = 'zhichen';
            cfg.wim.bridge = 'hongtang';
            cfg.wim.pipeline = 'direct';
            cfg.wim.input.zhichen.dir = sample_dir;
            cfg.wim.input.zhichen.bcp = fixture.bcpName;
            cfg.wim.input.zhichen.fmt = fixture.fmtName;
            cfg.wim.output_root = fullfile(temp_root, 'output');
            if isfield(cfg, 'wim_plot'), cfg.wim_plot.enabled = false; end

            analyze_wim_reports(proj_root, '2025-12-01', '2025-12-31', cfg);
            out_dir = fullfile(cfg.wim.output_root, cfg.wim.bridge, '202512');
            testCase.verifyTrue(isfile(fullfile(out_dir, '202512_DailyTraffic.csv')));
            testCase.verifyTrue(isfile(fullfile(out_dir, 'WIM_Report_hongtang_202512.xlsx')));
        end

        function testDatabaseSample(testCase)
            proj_root = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj_root, fullfile(proj_root,'analysis'), fullfile(proj_root,'config'));
            test_wim_reports.assumeSqlcmdAvailable(testCase);

            cfg = load_config(fullfile(proj_root,'config','hongtang_config.json'));
            temp_root = tempname;
            mkdir(temp_root);
            cleanup = onCleanup(@() rmdir(temp_root, 's')); %#ok<NASGU>
            sample_dir = fullfile(temp_root, 'synthetic_zhichen');
            fixture = create_synthetic_zhichen_fixture(sample_dir);

            cfg.wim.vendor = 'zhichen';
            cfg.wim.bridge = 'hongtang';
            cfg.wim.pipeline = 'database';
            cfg.wim.input.zhichen.dir = sample_dir;
            cfg.wim.input.zhichen.bcp = fixture.bcpName;
            cfg.wim.input.zhichen.fmt = fixture.fmtName;
            cfg.wim.output_root = fullfile(temp_root, 'output');
            if isfield(cfg, 'wim_plot'), cfg.wim_plot.enabled = false; end
            cfg.wim_db.server = '.';
            cfg.wim_db.database = 'HighSpeed_PROC';
            cfg.wim_db.trust_server_cert = true;
            cfg.wim_db.table_prefix = 'HS_Data_Sample_';
            cfg.wim_db.raw_table_prefix = 'WIM_Raw_Sample_';
            test_wim_reports.assumeSqlServerRunning(testCase, cfg.wim_db);

            analyze_wim_reports(proj_root, '2025-12-01', '2025-12-31', cfg);
            out_dir = fullfile(cfg.wim.output_root, cfg.wim.bridge, '202512');
            testCase.verifyTrue(isfile(fullfile(out_dir, '202512_DailyTraffic.csv')));
            testCase.verifyTrue(isfile(fullfile(out_dir, 'WIM_Report_hongtang_202512.xlsx')));
        end
    end

    methods (Static, Access = private)
        function assumeSqlcmdAvailable(testCase)
            try
                bms.analyzer.WimSqlService.findSqlcmd();
            catch ME
                testCase.assumeTrue(false, ['sqlcmd not available: ' ME.message]);
            end
        end

        function assumeSqlServerRunning(testCase, db)
            try
                svc = bms.analyzer.WimSqlService.resolveServiceName(db);
                status = bms.analyzer.WimSqlService.serviceStatus(svc);
            catch ME
                testCase.assumeTrue(false, ['SQL Server service cannot be resolved: ' ME.message]);
                return;
            end
            testCase.assumeTrue(strcmpi(status, 'Running'), ...
                sprintf('SQL Server service %s is %s; skipping database integration test.', svc, status));
        end
    end
end
