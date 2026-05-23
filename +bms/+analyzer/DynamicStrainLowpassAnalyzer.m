classdef DynamicStrainLowpassAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %DYNAMICSTRAINLOWPASSANALYZER OOP adapter for lowpass dynamic strain.

    methods
        function obj = DynamicStrainLowpassAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.LegacyFunctionAnalyzer('dynamic_strain_lowpass', root, startDate, endDate, statsFile, subfolder, cfg, {}, ...
                @(self) analyze_dynamic_strain_lowpass_boxplot(self.Root, self.StartDate, self.EndDate, ...
                    'Cfg', self.Config, 'Subfolder', self.Subfolder, 'StatsFile', self.StatsFile));
        end
    end
end
