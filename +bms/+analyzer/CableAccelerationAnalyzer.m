classdef CableAccelerationAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %CABLEACCELERATIONANALYZER OOP adapter for cable acceleration analysis.

    properties
        SaveFigures logical = true
    end

    methods
        function obj = CableAccelerationAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, saveFigures)
            if nargin < 7 || isempty(saveFigures)
                saveFigures = true;
            end
            obj@bms.analyzer.LegacyFunctionAnalyzer('cable_accel', root, startDate, endDate, statsFile, subfolder, cfg, {}, ...
                @(self) bms.analyzer.DynamicAccelerationPipeline.run('cable_accel', ...
                    self.Root, self.StartDate, self.EndDate, self.StatsFile, self.Subfolder, self.SaveFigures, self.Config));
            obj.SaveFigures = logical(saveFigures);
        end
    end
end
