classdef TiltAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %TILTANALYZER OOP adapter for the legacy tilt analysis.

    methods
        function obj = TiltAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.LegacyFunctionAnalyzer('tilt', root, startDate, endDate, statsFile, subfolder, cfg, {}, ...
                @(self) bms.analyzer.StructuralFilteredSeriesPipeline.run('tilt', self.Root, self.StartDate, self.EndDate, self.StatsFile, self.Subfolder, self.Config));
        end
    end
end
