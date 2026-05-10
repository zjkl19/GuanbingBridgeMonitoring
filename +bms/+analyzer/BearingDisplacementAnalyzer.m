classdef BearingDisplacementAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %BEARINGDISPLACEMENTANALYZER OOP adapter for bearing displacement.

    methods
        function obj = BearingDisplacementAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.LegacyFunctionAnalyzer('bearing_displacement', root, startDate, endDate, statsFile, subfolder, cfg, {}, ...
                @(self) analyze_bearing_displacement_points(self.Root, self.StartDate, self.EndDate, self.StatsFile, self.Subfolder, self.Config));
        end
    end
end
