classdef test_wim_plot_labels < matlab.unittest.TestCase
    methods (Test)
        function legacyWrapperUsesServiceLabels(testCase)
            xlabels = ["Lane1","Lane2"];
            yvals = [100, 200];
            labels = wim_build_xtick_labels(xlabels, yvals, true, true);
            testCase.verifyEqual(numel(labels), 2);
            testCase.verifyTrue(contains(string(labels{1}), "Lane1"));
            testCase.verifyTrue(contains(string(labels{1}), "%"));
            parts = split(string(labels{1}), newline);
            testCase.verifyEqual(numel(parts), 2);
        end

        function serviceLabelsIncludeInlinePercent(testCase)
            xlabels = ["A","B"];
            yvals = [1, 3];
            labels = bms.analyzer.WimPlotService.buildXTickLabels(xlabels, yvals, true, false);
            testCase.verifyEqual(labels{1}, 'A (25.00%)');
            testCase.verifyEqual(labels{2}, 'B (75.00%)');
        end
    end
end
