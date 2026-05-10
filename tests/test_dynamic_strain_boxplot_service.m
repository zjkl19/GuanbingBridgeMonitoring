classdef test_dynamic_strain_boxplot_service < matlab.unittest.TestCase
    methods (Test)
        function sampleBoxplotMatrixDropsNonFiniteAndCapsRows(tc)
            data = [1 10; NaN 11; 2 Inf; 3 12; 4 13];

            plotMat = bms.analyzer.DynamicStrainBoxplotService.sampleBoxplotMatrix(data, 1000);

            tc.verifyEqual(size(plotMat, 2), 2);
            tc.verifyEqual(plotMat(:, 1), [1; 2; 3; 4]);
            tc.verifyEqual(plotMat(1:4, 2), [10; 11; 12; 13]);
        end

        function statsTableMatchesDynamicStrainOutputShape(tc)
            data = [1 10; 2 NaN; 3 14; NaN 18];

            T = bms.analyzer.DynamicStrainBoxplotService.statsTable(data, {'S1', 'S2'});

            tc.verifyEqual(T.Properties.VariableNames, ...
                {'PointID', 'Min', 'Q1', 'Median', 'Q3', 'Max', 'Mean', 'Std', 'Count'});
            tc.verifyEqual(T.PointID{1}, 'S1');
            tc.verifyEqual(T.Min(1), 1);
            tc.verifyEqual(T.Max(1), 3);
            tc.verifyEqual(T.Median(1), 2);
            tc.verifyEqual(T.Count(1), 3);
            tc.verifyEqual(T.PointID{2}, 'S2');
            tc.verifyEqual(T.Min(2), 10);
            tc.verifyEqual(T.Max(2), 18);
            tc.verifyEqual(T.Count(2), 3);
        end
    end
end
