classdef CableAccelerationAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %CABLEACCELERATIONANALYZER OOP adapter for cable acceleration analysis.

    properties
        AutoDetectFs logical = true
    end

    properties (Dependent, SetAccess = private, Hidden)
        % Compatibility inspection only. The current pipeline always writes
        % figures; the seventh constructor argument controls sample-rate
        % detection and has never been a figure-save switch.
        SaveFigures
    end

    methods
        function obj = CableAccelerationAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, autoDetectFs)
            if nargin < 7 || isempty(autoDetectFs)
                autoDetectFs = true;
            end
            obj@bms.analyzer.LegacyFunctionAnalyzer('cable_accel', root, startDate, endDate, statsFile, subfolder, cfg, {}, ...
                @(self) bms.analyzer.DynamicAccelerationPipeline.run('cable_accel', ...
                    self.Root, self.StartDate, self.EndDate, self.StatsFile, self.Subfolder, self.AutoDetectFs, self.Config));
            obj.AutoDetectFs = bms.config.ConfigReader.boolValue(autoDetectFs, true);
        end

        function value = get.SaveFigures(~)
            value = true;
        end
    end
end
