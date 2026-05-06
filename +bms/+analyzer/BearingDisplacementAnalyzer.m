classdef BearingDisplacementAnalyzer < bms.analyzer.BaseAnalyzer
    %BEARINGDISPLACEMENTANALYZER OOP adapter for bearing displacement.

    methods
        function obj = BearingDisplacementAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.BaseAnalyzer('bearing_displacement', root, startDate, endDate, statsFile, subfolder, cfg, {});
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_bearing_displacement_points(obj.Root, obj.StartDate, obj.EndDate, obj.StatsFile, obj.Subfolder, obj.Config);
        end
    end
end
