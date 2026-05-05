classdef ModuleResult
    %MODULERESULT Normalized status record for a module execution.

    properties
        Spec bms.module.ModuleSpec = bms.module.ModuleSpec()
        Status char = 'unknown'
        Message char = ''
        ErrorType char = ''
        StartedAt datetime = NaT
        EndedAt datetime = NaT
        ElapsedSec double = 0
    end

    methods
        function obj = ModuleResult(spec, status, message, startedAt, endedAt, errorType)
            if nargin >= 1 && isa(spec, 'bms.module.ModuleSpec')
                obj.Spec = spec;
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
            s = obj.Spec.toStruct(statsDir);
            s.status = obj.Status;
            s.message = obj.Message;
            s.error_type = obj.ErrorType;
            s.started_at = bms.module.ModuleResult.formatTime(obj.StartedAt);
            s.ended_at = bms.module.ModuleResult.formatTime(obj.EndedAt);
            s.elapsed_sec = obj.ElapsedSec;
        end
    end

    methods (Static)
        function obj = fromStepStruct(rec)
            if isa(rec, 'bms.app.StepResult')
                rec = rec.toStruct();
            end
            spec = bms.module.ModuleRegistry.fromKey(bms.module.ModuleResult.getText(rec, 'key'));
            if isempty(spec.Key)
                spec = bms.module.ModuleRegistry.fromLabel(bms.module.ModuleResult.getText(rec, 'label'));
            end
            obj = bms.module.ModuleResult(spec, ...
                bms.module.ModuleResult.getText(rec, 'status'), ...
                bms.module.ModuleResult.getText(rec, 'message'), ...
                datetime('now'), datetime('now'), ...
                bms.module.ModuleResult.getText(rec, 'error_type'));
        end

        function txt = formatTime(t)
            if isempty(t) || isnat(t)
                txt = '';
            else
                txt = datestr(t, 'yyyy-mm-dd HH:MM:ss');
            end
        end

        function txt = getText(s, field)
            txt = '';
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                txt = char(string(s.(field)));
            end
        end
    end
end
