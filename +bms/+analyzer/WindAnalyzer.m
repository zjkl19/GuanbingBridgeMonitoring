classdef WindAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %WINDANALYZER OOP adapter for wind speed and direction analysis.

    methods
        function obj = WindAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.LegacyFunctionAnalyzer('wind', root, startDate, endDate, statsFile, subfolder, cfg, {}, ...
                @(self) analyze_wind_points(self.Root, self.StartDate, self.EndDate, self.Subfolder, self.Config));
        end
    end
end
