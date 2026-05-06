classdef TiltAnalyzer < bms.analyzer.BaseAnalyzer
    %TILTANALYZER OOP adapter for the legacy tilt analysis.

    methods
        function obj = TiltAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.BaseAnalyzer('tilt', root, startDate, endDate, statsFile, subfolder, cfg, {});
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_tilt_points(obj.Root, obj.StartDate, obj.EndDate, obj.StatsFile, obj.Subfolder, obj.Config);
        end
    end
end
