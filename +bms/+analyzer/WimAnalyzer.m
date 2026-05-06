classdef WimAnalyzer < bms.analyzer.BaseAnalyzer
    %WIMANALYZER OOP adapter for WIM report analysis.

    methods
        function obj = WimAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.BaseAnalyzer('wim', root, startDate, endDate, statsFile, subfolder, cfg, {});
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_wim_reports(obj.Root, obj.StartDate, obj.EndDate, obj.Config);
        end
    end
end
