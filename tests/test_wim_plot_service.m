classdef test_wim_plot_service < matlab.unittest.TestCase
    properties
        TempDir
    end

    methods (TestMethodSetup)
        function setupTempDir(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
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
        function plotConfigMergesDefaultsAndOverrides(tc)
            cfg = struct('wim_plot', struct('enabled', true, 'fig_size_px', [800 500]));
            wim = struct('plot', struct('format', 'jpg', 'output_dir', 'wim_plots'));

            plotCfg = bms.analyzer.WimPlotService.getPlotConfig(cfg, wim);

            tc.verifyTrue(plotCfg.enabled);
            tc.verifyEqual(plotCfg.fig_size_px, [800 500]);
            tc.verifyEqual(plotCfg.format, 'jpg');
            tc.verifyEqual(plotCfg.output_dir, 'wim_plots');
            tc.verifyEqual(plotCfg.y_decimals, 0);
        end

        function resolvePlotDataReadsExpectedCsv(tc)
            csvPath = fullfile(tc.TempDir, 'lane.csv');
            T = table([1; 2], [3; 4], 'VariableNames', {'lane','count'});
            writetable(T, csvPath, 'Encoding', 'UTF-8');
            csvPaths = struct('LaneSpeedWeight_Lane', csvPath);
            plotCfg = bms.analyzer.WimPlotService.getPlotConfig(struct(), struct());

            [xlabels, yvals, ylabel, titleText] = bms.analyzer.WimPlotService.resolvePlotData("不同车道车辆数", csvPaths, struct(), plotCfg);

            tc.verifyEqual(xlabels, ["车道1"; "车道2"]);
            tc.verifyEqual(yvals, [3; 4]);
            tc.verifyEqual(ylabel, "数量");
            tc.verifyEqual(titleText, "不同车道车辆数");
        end

        function safeNameAndFieldKeyAreStable(tc)
            tc.verifyEqual(bms.analyzer.WimPlotService.safeName("A B/C"), "A_B_C");
            tc.verifyEqual(bms.analyzer.WimPlotService.makeFieldKey("A B/C"), 'A_B_C');
        end
    end
end
