classdef BaseAnalyzer < handle
    %BASEANALYZER Common lifecycle wrapper for analysis modules.

    properties
        Key char = ''
        Root char
        StartDate char
        EndDate char
        StatsFile char
        Subfolder char
        Config struct = struct()
        Points cell = {}
        Artifacts cell = {}
        Warnings cell = {}
    end

    methods
        function obj = BaseAnalyzer(key, root, startDate, endDate, statsFile, subfolder, cfg, points)
            if nargin >= 1, obj.Key = char(key); end
            if nargin >= 2, obj.Root = char(root); end
            if nargin >= 3, obj.StartDate = char(startDate); end
            if nargin >= 4, obj.EndDate = char(endDate); end
            if nargin >= 5, obj.StatsFile = char(statsFile); end
            if nargin >= 6, obj.Subfolder = char(subfolder); end
            if nargin >= 7 && isstruct(cfg), obj.Config = cfg; end
            if nargin >= 8 && ~isempty(points), obj.Points = cellstr(string(points)); end
        end

        function p = statsPath(obj)
            p = obj.StatsFile;
        end

        function result = run(obj)
            started = datetime('now');
            obj.resolveInputs();
            obj.loadData();
            obj.cleanData();
            obj.computeStats();
            obj.plot();
            obj.executeLegacy();
            obj.writeStats();
            ended = datetime('now');
            result = bms.analyzer.AnalyzerResult.ok(obj.Key, obj.StatsFile, obj.Artifacts, obj.Warnings, started, ended);
        end
    end

    methods (Access = protected)
        function resolveInputs(~)
        end

        function loadData(~)
        end

        function cleanData(~)
        end

        function computeStats(~)
        end

        function plot(~)
        end

        function writeStats(~)
        end

        function executeLegacy(obj)
            error('BaseAnalyzer:NotImplemented', 'Analyzer "%s" does not implement executeLegacy.', obj.Key);
        end
    end
end
