classdef CrackAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %CRACKANALYZER OOP adapter for the legacy crack analysis.

    methods
        function obj = CrackAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.LegacyFunctionAnalyzer('crack', root, startDate, endDate, statsFile, subfolder, cfg, {}, ...
                @(self) bms.analyzer.CrackAnalysisPipeline.run(self.Root, self.StartDate, self.EndDate, self.StatsFile, self.Subfolder, self.Config));
        end
    end
end
