classdef GnssAnalyzer < bms.analyzer.BaseAnalyzer
    %GNSSANALYZER OOP adapter for the legacy GNSS analysis.

    methods
        function obj = GnssAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, points)
            if nargin < 7
                points = {};
            end
            obj@bms.analyzer.BaseAnalyzer('gnss', root, startDate, endDate, statsFile, subfolder, cfg, points);
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_gnss_points(obj.Root, obj.Points, obj.StartDate, obj.EndDate, obj.StatsFile, obj.Subfolder, obj.Config);
        end
    end
end
