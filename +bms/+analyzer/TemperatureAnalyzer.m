classdef TemperatureAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %TEMPERATUREANALYZER OOP adapter for temperature analysis.

    methods
        function obj = TemperatureAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, points)
            obj@bms.analyzer.LegacyFunctionAnalyzer('temperature', root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                @(self) analyze_temperature_points(self.Root, self.Points, self.StartDate, self.EndDate, self.StatsFile, self.Subfolder, self.Config));
        end
    end
end
