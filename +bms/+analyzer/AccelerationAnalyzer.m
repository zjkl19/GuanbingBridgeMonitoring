classdef AccelerationAnalyzer < bms.analyzer.BaseAnalyzer
    %ACCELERATIONANALYZER OOP adapter for the legacy acceleration analysis.

    properties
        SaveFigures logical = true
    end

    methods
        function obj = AccelerationAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, saveFigures)
            if nargin < 7 || isempty(saveFigures)
                saveFigures = true;
            end
            obj@bms.analyzer.BaseAnalyzer('acceleration', root, startDate, endDate, statsFile, subfolder, cfg, {});
            obj.SaveFigures = logical(saveFigures);
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_acceleration_points(obj.Root, obj.StartDate, obj.EndDate, obj.StatsFile, obj.Subfolder, obj.SaveFigures, obj.Config);
        end
    end
end
