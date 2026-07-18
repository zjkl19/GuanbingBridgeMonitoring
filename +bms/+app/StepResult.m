classdef StepResult
    %STEPRESULT Standard result object for one analysis step.

    properties
        Key char = ''
        OptField char = ''
        Label char = ''
        Category char = 'analysis'
        StatsFile char = ''
        StatsPath char = ''
        StatsExists logical = false
        Status char = 'unknown'
        Message char = ''
        ErrorType char = ''
        StartedAt datetime = NaT
        EndedAt datetime = NaT
        ElapsedSec double = 0
        Stage char = ''
        CurrentPointId char = ''
        CurrentDate char = ''
        ProcessedDates double = 0
        TotalDates double = 0
        Artifacts cell = {}
        FigurePaths cell = {}
        ArtifactCount double = 0
        FigureCount double = 0
    end

    methods
        function obj = StepResult(step, status, message, startedAt, endedAt, errorType)
            if nargin >= 1 && isa(step, 'bms.app.StepDefinition')
                obj.Key = step.Key;
                obj.OptField = step.OptField;
                obj.Label = step.Label;
                obj.Category = step.Category;
                obj.StatsFile = step.StatsFile;
            end
            if nargin >= 2, obj.Status = char(status); end
            if nargin >= 3, obj.Message = char(message); end
            if nargin < 4 || isempty(startedAt), startedAt = datetime('now'); end
            if nargin < 5 || isempty(endedAt), endedAt = datetime('now'); end
            if nargin >= 6, obj.ErrorType = char(errorType); end
            obj.StartedAt = startedAt;
            obj.EndedAt = endedAt;
            obj.ElapsedSec = max(0, seconds(endedAt - startedAt));
        end

        function s = toStruct(obj, statsDir)
            if nargin < 2, statsDir = ''; end
            s = struct();
            s.key = obj.Key;
            s.opt_field = obj.OptField;
            s.label = obj.Label;
            s.category = obj.Category;
            s.status = obj.Status;
            s.message = obj.Message;
            s.error_type = obj.ErrorType;
            s.started_at = bms.app.StepResult.formatTime(obj.StartedAt);
            s.ended_at = bms.app.StepResult.formatTime(obj.EndedAt);
            s.elapsed_sec = obj.ElapsedSec;
            s.stage = obj.Stage;
            s.current_point_id = obj.CurrentPointId;
            s.current_date = obj.CurrentDate;
            s.processed_dates = obj.ProcessedDates;
            s.total_dates = obj.TotalDates;
            s.stats_file = obj.StatsFile;
            s.stats_path = obj.StatsPath;
            if isempty(s.stats_path) && ~isempty(statsDir) && ~isempty(obj.StatsFile)
                s.stats_path = fullfile(statsDir, obj.StatsFile);
            end
            if ~isempty(s.stats_path)
                s.stats_exists = isfile(s.stats_path);
            else
                s.stats_exists = obj.StatsExists;
            end
            s.artifacts = obj.Artifacts;
            s.figure_paths = obj.FigurePaths;
            s.artifact_count = obj.ArtifactCount;
            s.figure_count = obj.FigureCount;
        end

        function obj = withProgress(obj, progressStep)
            if ~isstruct(progressStep)
                return;
            end
            if isfield(progressStep, 'stage')
                obj.Stage = char(string(progressStep.stage));
            end
            if isfield(progressStep, 'current_point_id')
                obj.CurrentPointId = char(string(progressStep.current_point_id));
            end
            if isfield(progressStep, 'current_date')
                obj.CurrentDate = char(string(progressStep.current_date));
            end
            if isfield(progressStep, 'processed_dates') && isnumeric(progressStep.processed_dates)
                obj.ProcessedDates = double(progressStep.processed_dates);
            end
            if isfield(progressStep, 'total_dates') && isnumeric(progressStep.total_dates)
                obj.TotalDates = double(progressStep.total_dates);
            end
        end
    end

    methods (Static)
        function obj = ok(step, startedAt, endedAt)
            obj = bms.app.StepResult(step, 'ok', '', startedAt, endedAt, '');
        end

        function obj = skip(step, message, startedAt, endedAt)
            if nargin < 2, message = ''; end
            obj = bms.app.StepResult(step, 'skip', message, startedAt, endedAt, 'skipped');
        end

        function obj = stopped(step, message, startedAt, endedAt)
            if nargin < 2 || isempty(message), message = 'User requested stop'; end
            obj = bms.app.StepResult(step, 'stopped', message, startedAt, endedAt, 'user_stopped');
        end

        function obj = fail(step, ME, startedAt, endedAt)
            obj = bms.app.StepResult(step, 'fail', ME.message, startedAt, endedAt, bms.app.ErrorClassifier.classifyException(ME));
        end

        function obj = fromAnalyzerResult(step, analyzerResult, startedAt, endedAt)
            if nargin < 3 || isempty(startedAt)
                startedAt = analyzerResult.StartedAt;
            end
            if nargin < 4 || isempty(endedAt)
                endedAt = analyzerResult.EndedAt;
            end
            obj = bms.app.StepResult(step, analyzerResult.Status, analyzerResult.Message, startedAt, endedAt, '');
            obj.StatsPath = analyzerResult.StatsPath;
            obj.StatsExists = analyzerResult.StatsExists;
            obj.Artifacts = analyzerResult.Artifacts;
            obj.FigurePaths = analyzerResult.FigurePaths;
            obj.ArtifactCount = analyzerResult.ArtifactCount;
            obj.FigureCount = analyzerResult.FigureCount;
            if isempty(obj.Message) && ~isempty(analyzerResult.Warnings)
                obj.Message = strjoin(cellfun(@char, analyzerResult.Warnings, 'UniformOutput', false), '; ');
            end
            if isprop(analyzerResult, 'ErrorType') && ~isempty(analyzerResult.ErrorType)
                obj.ErrorType = analyzerResult.ErrorType;
            end
            if strcmpi(analyzerResult.Status, 'fail')
                if isempty(obj.ErrorType)
                    obj.ErrorType = bms.app.ErrorClassifier.classifyText(obj.Message);
                end
            end
        end

        function txt = formatTime(t)
            if isempty(t) || isnat(t)
                txt = '';
            else
                txt = datestr(t, 'yyyy-mm-dd HH:MM:ss');
            end
        end
    end
end
