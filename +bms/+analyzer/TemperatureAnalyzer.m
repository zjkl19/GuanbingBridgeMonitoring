classdef TemperatureAnalyzer < bms.analyzer.BaseAnalyzer
    %TEMPERATUREANALYZER OOP adapter for temperature analysis.

    methods
        function obj = TemperatureAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, points)
            obj@bms.analyzer.BaseAnalyzer('temperature', root, startDate, endDate, statsFile, subfolder, cfg, points);
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_temperature_points(obj.Root, obj.Points, obj.StartDate, obj.EndDate, obj.StatsFile, obj.Subfolder, obj.Config);
        end
    end
end
