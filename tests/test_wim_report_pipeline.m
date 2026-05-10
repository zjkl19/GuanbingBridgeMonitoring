classdef test_wim_report_pipeline < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            projRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(projRoot, fullfile(projRoot, 'analysis'), fullfile(projRoot, 'config'));
        end
    end

    methods (Test)
        function projectRootResolvesRepo(tc)
            projRoot = fileparts(fileparts(mfilename('fullpath')));
            tc.verifyEqual(bms.analyzer.WimReportPipeline.projectRoot(), projRoot);
        end

        function directSampleCreatesWorkbook(tc)
            projRoot = fileparts(fileparts(mfilename('fullpath')));
            cfg = load_config(fullfile(projRoot, 'config', 'hongtang_config.json'));
            sampleDir = fullfile(projRoot, 'data', '_samples', 'wim', 'zhichen', '202512');

            cfg.wim.vendor = 'zhichen';
            cfg.wim.bridge = 'hongtang';
            cfg.wim.pipeline = 'direct';
            cfg.wim.input.zhichen.dir = sampleDir;
            cfg.wim.input.zhichen.bcp = 'HS_Data_202512_sample_1000.bcp';
            cfg.wim.input.zhichen.fmt = 'HS_Data_202512_sample_1000.fmt';
            cfg.wim.output_root = tempname;
            if isfield(cfg, 'wim_plot'), cfg.wim_plot.enabled = false; end

            bms.analyzer.WimReportPipeline.run(projRoot, '2025-12-01', '2025-12-31', cfg);
            outDir = fullfile(cfg.wim.output_root, cfg.wim.bridge, '202512');
            tc.verifyTrue(isfile(fullfile(outDir, '202512_DailyTraffic.csv')));
            tc.verifyTrue(isfile(fullfile(outDir, 'WIM_Report_hongtang_202512.xlsx')));
        end
    end
end
