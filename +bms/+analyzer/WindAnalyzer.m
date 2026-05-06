classdef WindAnalyzer < bms.analyzer.BaseAnalyzer
    %WINDANALYZER OOP adapter for wind speed and direction analysis.

    methods
        function obj = WindAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.BaseAnalyzer('wind', root, startDate, endDate, statsFile, subfolder, cfg, {});
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_wind_points(obj.Root, obj.StartDate, obj.EndDate, obj.Subfolder, obj.Config);
        end
    end
end
