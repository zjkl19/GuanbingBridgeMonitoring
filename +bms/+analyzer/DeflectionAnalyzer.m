classdef DeflectionAnalyzer < bms.analyzer.BaseAnalyzer
    %DEFLECTIONANALYZER OOP adapter for the legacy deflection analysis.

    methods
        function obj = DeflectionAnalyzer(varargin)
            obj@bms.analyzer.BaseAnalyzer(varargin{:});
        end

        function run(obj)
            analyze_deflection_points(obj.Root, obj.StartDate, obj.EndDate, obj.StatsFile, obj.Subfolder, obj.Config);
        end
    end
end
