classdef AccelerationSpectrumAnalyzer < bms.analyzer.LegacyFunctionAnalyzer
    %ACCELERATIONSPECTRUMANALYZER OOP adapter for acceleration spectrum.

    properties
        Frequencies = []
        Tolerance = []
    end

    methods
        function obj = AccelerationSpectrumAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg, points, freqs, tol)
            if nargin < 7
                points = {};
            end
            if nargin < 8
                freqs = [];
            end
            if nargin < 9
                tol = [];
            end
            obj@bms.analyzer.LegacyFunctionAnalyzer('accel_spectrum', root, startDate, endDate, statsFile, subfolder, cfg, points, ...
                @(self) bms.analyzer.SpectrumAnalysisPipeline.run('accel_spectrum', self.Root, self.StartDate, self.EndDate, self.Points, ...
                    self.StatsFile, self.Subfolder, self.Frequencies, self.Tolerance, false, self.Config));
            obj.Frequencies = freqs;
            obj.Tolerance = tol;
        end
    end
end
