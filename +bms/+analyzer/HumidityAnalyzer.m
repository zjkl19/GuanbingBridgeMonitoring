classdef HumidityAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %HUMIDITYANALYZER OOP adapter for humidity analysis.

    methods
        function obj = HumidityAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, points)
            obj@bms.analyzer.LegacyFunctionAnalyzer('humidity', root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                @(self) bms.analyzer.ScalarSeriesPipeline.run('humidity', self.Root, self.Points, self.StartDate, self.EndDate, self.StatsFile, self.Subfolder, self.Config));
        end
    end
end
