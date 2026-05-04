classdef RunResult
    %RUNRESULT Small value object for one pipeline step result.

    properties
        Label char = ''
        Status char = 'unknown'
        Message char = ''
        StartedAt datetime = NaT
        EndedAt datetime = NaT
    end

    methods
        function obj = RunResult(label, status, message)
            if nargin >= 1, obj.Label = char(label); end
            if nargin >= 2, obj.Status = char(status); end
            if nargin >= 3, obj.Message = char(message); end
            obj.StartedAt = datetime('now');
            obj.EndedAt = obj.StartedAt;
        end

        function s = toStruct(obj)
            s = struct();
            s.label = obj.Label;
            s.status = obj.Status;
            s.message = obj.Message;
            s.started_at = bms.core.RunResult.formatTime(obj.StartedAt);
            s.ended_at = bms.core.RunResult.formatTime(obj.EndedAt);
        end
    end

    methods (Static)
        function obj = ok(label, message)
            if nargin < 2, message = ''; end
            obj = bms.core.RunResult(label, 'ok', message);
        end

        function obj = fail(label, message)
            if nargin < 2, message = ''; end
            obj = bms.core.RunResult(label, 'fail', message);
        end

        function obj = skip(label, message)
            if nargin < 2, message = ''; end
            obj = bms.core.RunResult(label, 'skip', message);
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
