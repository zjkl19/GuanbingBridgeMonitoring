classdef StrainAnalyzer < bms.analyzer.BaseAnalyzer
    %STRAINANALYZER OOP adapter for the legacy strain analysis.

    methods
        function obj = StrainAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.BaseAnalyzer('strain', root, startDate, endDate, statsFile, subfolder, cfg, {});
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_strain_points(obj.Root, obj.StartDate, obj.EndDate, obj.StatsFile, obj.Subfolder, obj.Config);
        end
    end
end
