classdef CableAccelerationSpectrumAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %CABLEACCELERATIONSPECTRUMANALYZER OOP adapter for cable spectrum.

    properties
        Frequencies = []
        Tolerance = []
    end

    methods
        function obj = CableAccelerationSpectrumAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, points, freqs, tol)
            if nargin < 7
                points = {};
            end
            if nargin < 8
                freqs = [];
            end
            if nargin < 9
                tol = [];
            end
            obj@bms.analyzer.LegacyFunctionAnalyzer('cable_accel_spectrum', root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                @(self) bms.analyzer.SpectrumAnalysisPipeline.run('cable_accel_spectrum', self.Root, self.StartDate, self.EndDate, self.Points, ...
                    self.StatsFile, self.Subfolder, self.Frequencies, self.Tolerance, false, self.Config));
            obj.Frequencies = freqs;
            obj.Tolerance = tol;
        end
    end
end
