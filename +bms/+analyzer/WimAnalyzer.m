classdef WimAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %WIMANALYZER OOP adapter for WIM report analysis.

    methods
        function obj = WimAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            obj@bms.analyzer.LegacyFunctionAnalyzer('wim', root, startDate, endDate, statsFile, subfolder, cfg, {}, ...
                @(self) analyze_wim_reports(self.Root, self.StartDate, self.EndDate, self.Config));
        end
    end
end
