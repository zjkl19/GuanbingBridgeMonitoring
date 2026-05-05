classdef StepResult
    %STEPRESULT Standard result object for one analysis step.

    properties
        Key char = ''
        OptField char = ''
        Label char = ''
        Category char = 'analysis'
        StatsFile char = ''
        StatsPath char = ''
        Status char = 'unknown'
        Message char = ''
        ErrorType char = ''
        StartedAt datetime = NaT
        EndedAt datetime = NaT
        ElapsedSec double = 0
        Artifacts cell = {}
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
            s.stats_file = obj.StatsFile;
            s.stats_path = obj.StatsPath;
            if isempty(s.stats_path) && ~isempty(statsDir) && ~isempty(obj.StatsFile)
                s.stats_path = fullfile(statsDir, obj.StatsFile);
            end
            s.artifacts = obj.Artifacts;
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

        function obj = fail(step, ME, startedAt, endedAt)
            obj = bms.app.StepResult(step, 'fail', ME.message, startedAt, endedAt, bms.app.ErrorClassifier.classifyException(ME));
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
