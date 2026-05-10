classdef RainfallAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %RAINFALLANALYZER OOP adapter for rainfall analysis.

    methods
        function obj = RainfallAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, points)
            obj@bms.analyzer.LegacyFunctionAnalyzer('rainfall', root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                @(self) analyze_rainfall_points(self.Root, self.Points, self.StartDate, self.EndDate, self.StatsFile, self.Subfolder, self.Config));
        end
    end
end
