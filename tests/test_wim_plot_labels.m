classdef test_wim_plot_labels < matlab.unittest.TestCase
    methods (Test)
        function testPercentLabelsSingleTick(testCase)
            xlabels = ["车道1","车道2"];
            yvals = [100, 200];
            labels = wim_build_xtick_labels(xlabels, yvals, true, true);
            testCase.verifyEqual(numel(labels), 2);
            testCase.verifyTrue(contains(string(labels{1}), "车道1"));
            testCase.verifyTrue(contains(string(labels{1}), "%"));
            parts = split(string(labels{1}), newline);
            testCase.verifyEqual(numel(parts), 2);
        end
    end
end
