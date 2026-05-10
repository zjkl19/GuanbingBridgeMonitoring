classdef DynamicStrainHighpassAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %DYNAMICSTRAINHIGHPASSANALYZER OOP adapter for highpass dynamic strain.

    properties
        OutputDir char = ''
        Fs double = 20
        Fc double = 0.1
        Whisker double = 300
    end

    methods
        function obj = DynamicStrainHighpassAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.LegacyFunctionAnalyzer('dynamic_strain_highpass', root, startDate, endDate, statsFile, subfolder, cfg, {}, ...
                @(self) analyze_dynamic_strain_boxplot(self.Root, self.StartDate, self.EndDate, ...
                    'Cfg', self.Config, 'Subfolder', self.Subfolder, 'OutputDir', self.OutputDir, ...
                    'Fs', self.Fs, 'Fc', self.Fc, 'Whisker', self.Whisker, ...
                    'ShowOutliers', false, 'YLimManual', true, 'YLimRange', [-30 30], ...
                    'LowerBound', -150, 'UpperBound', 30, 'EdgeTrimSec', 5));
            obj.OutputDir = char(bms.config.ConfigReader.get(cfg, 'dynamic_strain.output_dir', ...
                bms.app.LegacyStepFunctions.dynamicHighpassOutputDir()));
            obj.Fs = bms.config.ConfigReader.getNumeric(cfg, 'dynamic_strain.fs', 20);
            obj.Fc = bms.config.ConfigReader.getNumeric(cfg, 'dynamic_strain.fc', 0.1);
            obj.Whisker = bms.config.ConfigReader.getNumeric(cfg, 'dynamic_strain.whisker', 300);
        end
    end
end
