classdef LegacyFunctionAnalyzer < bms.analyzer.BaseAnalyzer
    %LEGACYFUNCTIONANALYZER Adapter for analysis modules not yet OOP-native.

    properties
        FunctionHandle = []
    end

    methods
        function obj = LegacyFunctionAnalyzer(key, root, startDate, endDate, statsFile, subfolder, cfg, points, fcn)
            obj@bms.analyzer.BaseAnalyzer(key, root, startDate, endDate, statsFile, subfolder, cfg, points);
            if nargin >= 9
                obj.FunctionHandle = fcn;
            end
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            if isempty(obj.FunctionHandle)
                executeLegacy@bms.analyzer.BaseAnalyzer(obj);
                return;
            end
            if nargin(obj.FunctionHandle) == 0
                obj.FunctionHandle();
            else
                obj.FunctionHandle(obj);
            end
        end
    end
end
