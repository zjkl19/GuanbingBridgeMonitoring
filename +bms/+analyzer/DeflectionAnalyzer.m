classdef DeflectionAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %DEFLECTIONANALYZER OOP adapter for the legacy deflection analysis.

    methods
        function obj = DeflectionAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.LegacyFunctionAnalyzer('deflection', root, startDate, endDate, statsFile, subfolder, cfg, {}, ...
                @(self) analyze_deflection_points(self.Root, self.StartDate, self.EndDate, self.StatsFile, self.Subfolder, self.Config));
        end
    end
end
