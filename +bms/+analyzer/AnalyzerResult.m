classdef AnalyzerResult
    %ANALYZERRESULT Normalized result returned by OOP analysis adapters.

    properties
        Key char = ''
        Status char = 'unknown'
        Message char = ''
        StatsPath char = ''
        FigurePaths cell = {}
        Artifacts cell = {}
        Warnings cell = {}
        StartedAt datetime = NaT
        EndedAt datetime = NaT
        ElapsedSec double = 0
    end

    methods
        function obj = AnalyzerResult(key, status, message, statsPath, artifacts, warnings, startedAt, endedAt)
            if nargin >= 1, obj.Key = char(key); end
            if nargin >= 2, obj.Status = char(status); end
            if nargin >= 3, obj.Message = char(message); end
            if nargin >= 4, obj.StatsPath = char(statsPath); end
            if nargin >= 5 && ~isempty(artifacts), obj.Artifacts = bms.analyzer.AnalyzerResult.toCell(artifacts); end
            if nargin >= 6 && ~isempty(warnings), obj.Warnings = bms.analyzer.AnalyzerResult.toCell(warnings); end
            if nargin < 7 || isempty(startedAt), startedAt = datetime('now'); end
            if nargin < 8 || isempty(endedAt), endedAt = datetime('now'); end
            obj.StartedAt = startedAt;
            obj.EndedAt = endedAt;
            obj.ElapsedSec = max(0, seconds(endedAt - startedAt));
        end

        function s = toStruct(obj)
            s = struct();
            s.key = obj.Key;
            s.status = obj.Status;
            s.message = obj.Message;
            s.stats_path = obj.StatsPath;
            s.figure_paths = obj.FigurePaths;
            s.artifacts = obj.Artifacts;
            s.warnings = obj.Warnings;
            s.started_at = bms.app.StepResult.formatTime(obj.StartedAt);
            s.ended_at = bms.app.StepResult.formatTime(obj.EndedAt);
            s.elapsed_sec = obj.ElapsedSec;
        end
    end

    methods (Static)
        function obj = ok(key, statsPath, artifacts, warnings, startedAt, endedAt, message)
            if nargin < 7, message = ''; end
            obj = bms.analyzer.AnalyzerResult(key, 'ok', message, statsPath, artifacts, warnings, startedAt, endedAt);
        end

        function obj = fail(key, message, statsPath, startedAt, endedAt)
            if nargin < 3, statsPath = ''; end
            obj = bms.analyzer.AnalyzerResult(key, 'fail', message, statsPath, {}, {}, startedAt, endedAt);
        end

        function c = toCell(value)
            if isempty(value)
                c = {};
            elseif iscell(value)
                c = value;
            elseif ischar(value)
                c = {value};
            elseif isstring(value)
                c = cellstr(value);
            else
                c = {value};
            end
        end
    end
end
