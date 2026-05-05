classdef CrackAnalyzer < bms.analyzer.BaseAnalyzer
    %CRACKANALYZER OOP adapter for the legacy crack analysis.

    methods
        function obj = CrackAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.BaseAnalyzer('crack', root, startDate, endDate, statsFile, subfolder, cfg, {});
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_crack_points(obj.Root, obj.StartDate, obj.EndDate, obj.StatsFile, obj.Subfolder, obj.Config);
        end
    end
end
