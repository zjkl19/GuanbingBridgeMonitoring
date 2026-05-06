classdef CableAccelerationAnalyzer < bms.analyzer.BaseAnalyzer
    %CABLEACCELERATIONANALYZER OOP adapter for cable acceleration analysis.

    properties
        SaveFigures logical = true
    end

    methods
        function obj = CableAccelerationAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, saveFigures)
            if nargin < 7 || isempty(saveFigures)
                saveFigures = true;
            end
            obj@bms.analyzer.BaseAnalyzer('cable_accel', root, startDate, endDate, statsFile, subfolder, cfg, {});
            obj.SaveFigures = logical(saveFigures);
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_cable_acceleration_points(obj.Root, obj.StartDate, obj.EndDate, obj.StatsFile, obj.Subfolder, obj.SaveFigures, obj.Config);
        end
    end
end
