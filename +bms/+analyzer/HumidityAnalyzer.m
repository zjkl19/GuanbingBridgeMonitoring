classdef HumidityAnalyzer < bms.analyzer.BaseAnalyzer
    %HUMIDITYANALYZER OOP adapter for humidity analysis.

    methods
        function obj = HumidityAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, points)
            obj@bms.analyzer.BaseAnalyzer('humidity', root, startDate, endDate, statsFile, subfolder, cfg, points);
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_humidity_points(obj.Root, obj.Points, obj.StartDate, obj.EndDate, obj.StatsFile, obj.Subfolder, obj.Config);
        end
    end
end
