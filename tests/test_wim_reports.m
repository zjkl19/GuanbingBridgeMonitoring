classdef test_wim_reports < matlab.unittest.TestCase
    methods (Test)
        function testDirectSample(testCase)
            proj_root = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj_root, fullfile(proj_root,'analysis'), fullfile(proj_root,'config'));
            cfg = load_config(fullfile(proj_root,'config','hongtang_config.json'));
            sample_dir = fullfile(proj_root, 'data', '_samples', 'wim', 'zhichen', '202512');

            cfg.wim.vendor = 'zhichen';
            cfg.wim.bridge = 'hongtang';
            cfg.wim.pipeline = 'direct';
            cfg.wim.input.zhichen.dir = sample_dir;
            cfg.wim.input.zhichen.bcp = 'HS_Data_202512_sample_1000.bcp';
            cfg.wim.input.zhichen.fmt = 'HS_Data_202512_sample_1000.fmt';
            cfg.wim.output_root = tempname;

            analyze_wim_reports(proj_root, '2025-12-01', '2025-12-31', cfg);
            out_dir = fullfile(cfg.wim.output_root, cfg.wim.bridge, '202512');
            testCase.verifyTrue(isfile(fullfile(out_dir, '202512_DailyTraffic.csv')));
            testCase.verifyTrue(isfile(fullfile(out_dir, 'WIM_Report_hongtang_202512.xlsx')));
        end

        function testDatabaseSample(testCase)
            proj_root = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj_root, fullfile(proj_root,'analysis'), fullfile(proj_root,'config'));
            sqlcmd = fullfile(getenv('ProgramFiles'), 'Microsoft SQL Server', 'Client SDK', 'ODBC', '180', 'Tools', 'Binn', 'sqlcmd.exe');
            if ~exist(sqlcmd, 'file')
                testCase.assumeTrue(false, 'sqlcmd not found');
            end

            cfg = load_config(fullfile(proj_root,'config','hongtang_config.json'));
            sample_dir = fullfile(proj_root, 'data', '_samples', 'wim', 'zhichen', '202512');

            cfg.wim.vendor = 'zhichen';
            cfg.wim.bridge = 'hongtang';
            cfg.wim.pipeline = 'database';
            cfg.wim.input.zhichen.dir = sample_dir;
            cfg.wim.input.zhichen.bcp = 'HS_Data_202512_sample_1000.bcp';
            cfg.wim.input.zhichen.fmt = 'HS_Data_202512_sample_1000.fmt';
            cfg.wim.output_root = tempname;
            cfg.wim_db.server = '.';
            cfg.wim_db.database = 'HighSpeed_PROC';
            cfg.wim_db.trust_server_cert = true;
            cfg.wim_db.table_prefix = 'HS_Data_Sample_';
            cfg.wim_db.raw_table_prefix = 'WIM_Raw_Sample_';

            analyze_wim_reports(proj_root, '2025-12-01', '2025-12-31', cfg);
            out_dir = fullfile(cfg.wim.output_root, cfg.wim.bridge, '202512');
            testCase.verifyTrue(isfile(fullfile(out_dir, '202512_DailyTraffic.csv')));
            testCase.verifyTrue(isfile(fullfile(out_dir, 'WIM_Report_hongtang_202512.xlsx')));
        end
    end
end
