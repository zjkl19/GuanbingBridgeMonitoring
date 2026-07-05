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
                    result = bms.app.StepResult.stopped(step, 'User requested stop', started, datetime('now'));
                    return;
                end
                out = bms.app.StepExecutor.invoke(fcn);
                ended = datetime('now');
                if isa(out, 'bms.analyzer.AnalyzerResult')
                    result = bms.app.StepResult.fromAnalyzerResult(step, out, started, ended);
                else
                    result = bms.app.StepResult.ok(step, started, ended);
                end
            catch ME
                if strcmp(ME.identifier, 'BMS:RunStopped')
                    result = bms.app.StepResult.stopped(step, ME.message, started, datetime('now'));
                else
                    result = bms.app.StepResult.fail(step, ME, started, datetime('now'));
                    warning('%s failed: %s', step.Label, ME.message);
                end
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

        function out = invoke(fcn)
            out = [];
            if nargout(fcn) == 0
                fcn();
                return;
            end
            try
                out = fcn();
            catch ME
                if bms.app.StepExecutor.isTooManyOutputs(ME)
                    fcn();
                else
                    rethrow(ME);
                end
            end
        end

        function tf = isTooManyOutputs(ME)
            tf = strcmp(ME.identifier, 'MATLAB:maxlhs') || ...
                contains(ME.message, 'Too many output arguments') || ...
                contains(ME.message, char([36755 20986 21442 25968 22826]));
        end
    end
end
