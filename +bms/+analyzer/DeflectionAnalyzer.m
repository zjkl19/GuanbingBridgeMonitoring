classdef DeflectionAnalyzer < bms.analyzer.BaseAnalyzer
    %DEFLECTIONANALYZER OOP adapter for the legacy deflection analysis.

    methods
        function obj = DeflectionAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.BaseAnalyzer('deflection', root, startDate, endDate, statsFile, subfolder, cfg, {});
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_deflection_points(obj.Root, obj.StartDate, obj.EndDate, obj.StatsFile, obj.Subfolder, obj.Config);
        end
    end
end
