classdef (Abstract) BaseAnalyzer < handle
    %BASEANALYZER Minimal adapter base for legacy analysis functions.

    properties
        Root char
        StartDate char
        EndDate char
        StatsFile char
        Subfolder char
        Config struct = struct()
    end

    methods
        function obj = BaseAnalyzer(root, startDate, endDate, statsFile, subfolder, cfg)
            if nargin >= 1, obj.Root = char(root); end
            if nargin >= 2, obj.StartDate = char(startDate); end
            if nargin >= 3, obj.EndDate = char(endDate); end
            if nargin >= 4, obj.StatsFile = char(statsFile); end
            if nargin >= 5, obj.Subfolder = char(subfolder); end
            if nargin >= 6 && isstruct(cfg), obj.Config = cfg; end
        end

        function p = statsPath(obj)
            p = obj.StatsFile;
        end
    end

    methods (Abstract)
        run(obj)
    end
end
