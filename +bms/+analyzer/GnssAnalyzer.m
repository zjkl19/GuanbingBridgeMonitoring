classdef GnssAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %GNSSANALYZER OOP adapter for the legacy GNSS analysis.

    methods
        function obj = GnssAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, points)
            if nargin < 7
                points = {};
            end
            obj@bms.analyzer.LegacyFunctionAnalyzer('gnss', root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                @(self) bms.analyzer.GnssAnalysisPipeline.run(self.Root, self.Points, self.StartDate, self.EndDate, self.StatsFile, self.Subfolder, self.Config));
        end
    end
end
