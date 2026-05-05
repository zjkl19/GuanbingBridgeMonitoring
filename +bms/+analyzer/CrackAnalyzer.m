classdef CrackAnalyzer < bms.analyzer.BaseAnalyzer
    %CRACKANALYZER OOP adapter for the legacy crack analysis.

    methods
        function obj = CrackAnalyzer(varargin)
            obj@bms.analyzer.BaseAnalyzer(varargin{:});
        end

        function run(obj)
            analyze_crack_points(obj.Root, obj.StartDate, obj.EndDate, obj.StatsFile, obj.Subfolder, obj.Config);
        end
    end
end
