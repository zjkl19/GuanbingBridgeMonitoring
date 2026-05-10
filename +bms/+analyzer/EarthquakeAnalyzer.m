classdef EarthquakeAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %EARTHQUAKEANALYZER OOP adapter for earthquake acceleration analysis.

    methods
        function obj = EarthquakeAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.LegacyFunctionAnalyzer('earthquake', root, startDate, endDate, statsFile, subfolder, cfg, {}, ...
                @(self) analyze_eq_points(self.Root, self.StartDate, self.EndDate, self.Subfolder, self.Config));
        end
    end
end
