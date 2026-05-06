classdef AnalyzerResult
    %ANALYZERRESULT Normalized result returned by OOP analysis adapters.

    properties
        Key char = ''
        Status char = 'unknown'
        Message char = ''
        ErrorType char = ''
        StatsPath char = ''
        StatsExists logical = false
        FigurePaths cell = {}
        Artifacts cell = {}
        ArtifactCount double = 0
        FigureCount double = 0
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
            obj.StatsExists = ~isempty(obj.StatsPath) && isfile(obj.StatsPath);
            obj.FigurePaths = bms.analyzer.AnalyzerResult.figurePathsFromArtifacts(obj.Artifacts);
            obj.ArtifactCount = numel(obj.Artifacts);
            obj.FigureCount = numel(obj.FigurePaths);
            if strcmpi(obj.Status, 'fail')
                obj.ErrorType = bms.app.ErrorClassifier.classifyText(obj.Message);
            end
        end

        function s = toStruct(obj)
            s = struct();
            s.key = obj.Key;
            s.status = obj.Status;
            s.message = obj.Message;
            s.error_type = obj.ErrorType;
            s.stats_path = obj.StatsPath;
            s.stats_exists = obj.StatsExists;
            s.figure_paths = obj.FigurePaths;
            s.artifacts = obj.Artifacts;
            s.artifact_count = obj.ArtifactCount;
            s.figure_count = obj.FigureCount;
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

        function obj = fail(key, message, statsPath, startedAt, endedAt, errorType)
            if nargin < 3, statsPath = ''; end
            if nargin < 6 || isempty(errorType)
                errorType = bms.app.ErrorClassifier.classifyText(message);
            end
            obj = bms.analyzer.AnalyzerResult(key, 'fail', message, statsPath, {}, {}, startedAt, endedAt);
            obj.ErrorType = char(errorType);
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

        function paths = figurePathsFromArtifacts(artifacts)
            paths = {};
            artifacts = bms.analyzer.AnalyzerResult.toCell(artifacts);
            for i = 1:numel(artifacts)
                item = artifacts{i};
                if ~isstruct(item)
                    continue;
                end
                kind = '';
                if isfield(item, 'kind') && ~isempty(item.kind)
                    kind = char(string(item.kind));
                end
                if ~strcmpi(kind, 'figure')
                    continue;
                end
                if isfield(item, 'path') && ~isempty(item.path)
                    paths{end+1} = char(string(item.path)); %#ok<AGROW>
                end
            end
        end
    end
end
