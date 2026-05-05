classdef RainfallAnalyzer < bms.analyzer.BaseAnalyzer
    %RAINFALLANALYZER OOP adapter for rainfall analysis.

    methods
        function obj = RainfallAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, points)
            obj@bms.analyzer.BaseAnalyzer('rainfall', root, startDate, endDate, statsFile, subfolder, cfg, points);
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_rainfall_points(obj.Root, obj.Points, obj.StartDate, obj.EndDate, obj.StatsFile, obj.Subfolder, obj.Config);
        end
    end
end
