classdef AccelerationSpectrumAnalyzer < bms.analyzer.BaseAnalyzer
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
            obj@bms.analyzer.BaseAnalyzer('accel_spectrum', root, startDate, endDate, statsFile, subfolder, cfg, points);
            obj.Frequencies = freqs;
            obj.Tolerance = tol;
        end
    end

    methods (Access = protected)
        function executeLegacy(obj)
            analyze_accel_spectrum_points(obj.Root, obj.StartDate, obj.EndDate, obj.Points, ...
                obj.StatsFile, obj.Subfolder, obj.Frequencies, obj.Tolerance, false, obj.Config);
        end
    end
end
