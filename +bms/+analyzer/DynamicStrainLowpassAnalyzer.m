classdef DynamicStrainLowpassAnalyzer < bms.analyzer.BaseAnalyzer
    %DYNAMICSTRAINLOWPASSANALYZER OOP adapter for lowpass dynamic strain.

    methods
        function obj = DynamicStrainLowpassAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.BaseAnalyzer('dynamic_strain_lowpass', root, startDate, endDate, statsFile, subfolder, cfg, {});
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_dynamic_strain_lowpass_boxplot(obj.Root, obj.StartDate, obj.EndDate, ...
                'Cfg', obj.Config, 'Subfolder', obj.Subfolder);
        end
    end
end
