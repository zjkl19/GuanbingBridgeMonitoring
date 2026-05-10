classdef StrainAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %STRAINANALYZER OOP adapter for the legacy strain analysis.

    methods
        function obj = StrainAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.LegacyFunctionAnalyzer('strain', root, startDate, endDate, statsFile, subfolder, cfg, {}, ...
                @(self) analyze_strain_points(self.Root, self.StartDate, self.EndDate, self.StatsFile, self.Subfolder, self.Config));
        end
    end
end
