classdef StepExecutor
    %STEPEXECUTOR Executes a step and returns structured timing/status data.

    methods (Static)
        function result = execute(step, fcn, shouldStopFcn)
            if nargin < 3 || isempty(shouldStopFcn)
                shouldStopFcn = @() false;
            end
            if ~isa(step, 'bms.app.StepDefinition')
                step = bms.app.StepDefinition.fromLabel(char(step));
            end
            started = datetime('now');
            try
                if shouldStopFcn()
                    result = bms.app.StepResult.skip(step, 'User requested stop', started, datetime('now'));
                    return;
                end
                fcn();
                result = bms.app.StepResult.ok(step, started, datetime('now'));
            catch ME
                result = bms.app.StepResult.fail(step, ME, started, datetime('now'));
                warning('%s failed: %s', step.Label, ME.message);
            end
        end

        function result = skip(step, message)
            if nargin < 2, message = ''; end
            if ~isa(step, 'bms.app.StepDefinition')
                step = bms.app.StepDefinition.fromLabel(char(step));
            end
            nowTime = datetime('now');
            result = bms.app.StepResult.skip(step, message, nowTime, nowTime);
        end
    end
end
