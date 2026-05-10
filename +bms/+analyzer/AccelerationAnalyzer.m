classdef AccelerationAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %ACCELERATIONANALYZER OOP adapter for the legacy acceleration analysis.

    properties
        SaveFigures logical = true
    end

    methods
        function obj = AccelerationAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, saveFigures)
            if nargin < 7 || isempty(saveFigures)
                saveFigures = true;
            end
            obj@bms.analyzer.LegacyFunctionAnalyzer('acceleration', root, startDate, endDate, statsFile, subfolder, cfg, {}, ...
                @(self) bms.analyzer.DynamicAccelerationPipeline.run('acceleration', ...
                    self.Root, self.StartDate, self.EndDate, self.StatsFile, self.Subfolder, self.SaveFigures, self.Config));
            obj.SaveFigures = logical(saveFigures);
        end
    end
end
