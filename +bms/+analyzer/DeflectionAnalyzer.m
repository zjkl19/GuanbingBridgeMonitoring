classdef DeflectionAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %DEFLECTIONANALYZER OOP adapter for the legacy deflection analysis.

    methods
        function obj = DeflectionAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.LegacyFunctionAnalyzer('deflection', root, startDate, endDate, statsFile, subfolder, cfg, {}, ...
                @(self) bms.analyzer.StructuralFilteredSeriesPipeline.run('deflection', self.Root, self.StartDate, self.EndDate, self.StatsFile, self.Subfolder, self.Config));
        end
    end
end
