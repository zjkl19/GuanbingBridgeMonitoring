classdef test_analyzer_pilot < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'analysis'));
        end
    end

    methods (Test)
        function deflectionAnalyzerCarriesLegacyArguments(tc)
            stats = fullfile(tempdir, 'deflection_stats.xlsx');
            a = bms.analyzer.DeflectionAnalyzer('D:/data', '2026-01-01', '2026-01-02', stats, '时程曲线_挠度', struct());
            tc.verifyClass(a, 'bms.analyzer.DeflectionAnalyzer');
            tc.verifyEqual(a.Root, 'D:/data');
            tc.verifyEqual(a.statsPath(), stats);
        end

        function crackAnalyzerCarriesLegacyArguments(tc)
            stats = fullfile(tempdir, 'crack_stats.xlsx');
            a = bms.analyzer.CrackAnalyzer('D:/data', '2026-01-01', '2026-01-02', stats, '时程曲线_裂缝', struct());
            tc.verifyClass(a, 'bms.analyzer.CrackAnalyzer');
            tc.verifyEqual(a.StatsFile, stats);
        end
    end
end
