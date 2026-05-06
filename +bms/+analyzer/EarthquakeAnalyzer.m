classdef EarthquakeAnalyzer < bms.analyzer.BaseAnalyzer
    %EARTHQUAKEANALYZER OOP adapter for earthquake acceleration analysis.

    methods
        function obj = EarthquakeAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.BaseAnalyzer('earthquake', root, startDate, endDate, statsFile, subfolder, cfg, {});
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_eq_points(obj.Root, obj.StartDate, obj.EndDate, obj.Subfolder, obj.Config);
        end
    end
end
