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
            figuresBefore = bms.app.StepExecutor.captureFigures();
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
                if bms.app.StepExecutor.isMemoryErrorResult(result)
                    bms.app.StepExecutor.cleanupNewFigures(figuresBefore);
                end
            catch ME
                if strcmp(ME.identifier, 'BMS:RunStopped')
                    result = bms.app.StepResult.stopped(step, ME.message, started, datetime('now'));
                else
                    if strcmp(bms.app.ErrorClassifier.classifyException(ME), 'memory_error')
                        bms.app.StepExecutor.cleanupNewFigures(figuresBefore);
                    end
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

        function figures = captureFigures()
            % Capture figure identities without changing visibility or focus.
            try
                figures = findall(groot, 'Type', 'figure');
            catch
                figures = [];
            end
        end

        function cleanupNewFigures(figuresBefore)
            % Delete only figures created by the failed step. Existing GUI
            % figures must remain open, so close all/close force are unsafe.
            figuresAfter = bms.app.StepExecutor.captureFigures();
            for i = 1:numel(figuresAfter)
                fig = figuresAfter(i);
                if ~bms.app.StepExecutor.wasPresent(fig, figuresBefore)
                    try
                        if isgraphics(fig, 'figure')
                            delete(fig);
                        end
                    catch
                        % Cleanup must not replace the original OOM result.
                    end
                end
            end
            try
                drawnow;
            catch
                % Graphics event draining is best effort under low memory.
            end
        end

        function tf = wasPresent(fig, figuresBefore)
            tf = false;
            for i = 1:numel(figuresBefore)
                try
                    if isequal(fig, figuresBefore(i))
                        tf = true;
                        return;
                    end
                catch
                    % A figure may have been deleted by the step itself.
                end
            end
        end

        function tf = isMemoryErrorResult(result)
            tf = isa(result, 'bms.app.StepResult') && ...
                strcmpi(result.Status, 'fail') && ...
                strcmpi(result.ErrorType, 'memory_error');
        end
    end
end
