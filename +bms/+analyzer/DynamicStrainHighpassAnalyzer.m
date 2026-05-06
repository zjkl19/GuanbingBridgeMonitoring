classdef DynamicStrainHighpassAnalyzer < bms.analyzer.BaseAnalyzer
    %DYNAMICSTRAINHIGHPASSANALYZER OOP adapter for highpass dynamic strain.

    properties
        OutputDir char = ''
        Fs double = 20
        Fc double = 0.1
        Whisker double = 300
    end

    methods
        function obj = DynamicStrainHighpassAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.BaseAnalyzer('dynamic_strain_highpass', root, startDate, endDate, statsFile, subfolder, cfg, {});
            obj.OutputDir = char(bms.config.ConfigReader.get(cfg, 'dynamic_strain.output_dir', ...
                bms.app.LegacyStepFunctions.dynamicHighpassOutputDir()));
            obj.Fs = bms.config.ConfigReader.getNumeric(cfg, 'dynamic_strain.fs', 20);
            obj.Fc = bms.config.ConfigReader.getNumeric(cfg, 'dynamic_strain.fc', 0.1);
            obj.Whisker = bms.config.ConfigReader.getNumeric(cfg, 'dynamic_strain.whisker', 300);
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_dynamic_strain_boxplot(obj.Root, obj.StartDate, obj.EndDate, ...
                'Cfg', obj.Config, 'Subfolder', obj.Subfolder, 'OutputDir', obj.OutputDir, ...
                'Fs', obj.Fs, 'Fc', obj.Fc, 'Whisker', obj.Whisker, ...
                'ShowOutliers', false, 'YLimManual', true, 'YLimRange', [-30 30], ...
                'LowerBound', -150, 'UpperBound', 30, 'EdgeTrimSec', 5);
        end
    end
end
