classdef StepPlan
    %STEPPLAN Ordered list of executable or skipped analysis steps.

    properties
        Steps cell = {}
    end

    methods
        function obj = addRun(obj, def, fcn)
            obj.Steps{end+1} = struct('mode', 'run', 'def', def, 'fcn', fcn, 'message', '');
        end

        function obj = addSkip(obj, def, message)
            if nargin < 3, message = ''; end
            obj.Steps{end+1} = struct('mode', 'skip', 'def', def, 'fcn', [], 'message', char(message));
        end

        function [results, finalProgress] = execute(obj, shouldStopFcn, progressFcn)
            if nargin < 2 || isempty(shouldStopFcn)
                shouldStopFcn = @() false;
            end
            if nargin < 3
                progressFcn = [];
            end
            results = {};
            bms.app.RunProgressReporter.configure(obj.Steps, progressFcn);
            progressCleanup = onCleanup(@() bms.app.RunProgressReporter.clear()); %#ok<NASGU>
            memoryErrorSource = '';
            for i = 1:numel(obj.Steps)
                bms.app.StepPlan.pumpUiEvents();
                item = obj.Steps{i};
                bms.app.RunProgressReporter.startModule(i);
                if ~isempty(memoryErrorSource) && strcmp(item.mode, 'run') && ...
                        bms.app.StepPlan.isHighMemoryAnalysis(item.def)
                    message = sprintf('Skipped after memory error in %s', memoryErrorSource);
                    results{end+1} = bms.app.StepExecutor.skip(item.def, message); %#ok<AGROW>
                else
                    switch item.mode
                        case 'run'
                            results{end+1} = bms.app.StepExecutor.execute(item.def, item.fcn, shouldStopFcn); %#ok<AGROW>
                        case 'skip'
                            results{end+1} = bms.app.StepExecutor.skip(item.def, item.message); %#ok<AGROW>
                    end
                end
                if isa(results{end}, 'bms.app.StepResult')
                    results{end} = results{end}.withProgress(bms.app.RunProgressReporter.currentStep());
                end
                bms.app.RunProgressReporter.completeModule(i, results{end}, 'module_complete');
                if bms.app.StepPlan.isMemoryErrorResult(results{end})
                    memoryErrorSource = results{end}.Key;
                    if isempty(memoryErrorSource)
                        memoryErrorSource = results{end}.Label;
                    end
                end
                if bms.app.StepPlan.isStoppedResult(results{end})
                    for j = i+1:numel(obj.Steps)
                        nextItem = obj.Steps{j};
                        results{end+1} = bms.app.StepExecutor.skip(nextItem.def, 'Skipped after stop request'); %#ok<AGROW>
                        bms.app.RunProgressReporter.completeModule( ...
                            j, results{end}, 'module_skipped_after_stop');
                    end
                    finalProgress = bms.app.RunProgressReporter.snapshot();
                    return;
                end
            end
            finalProgress = bms.app.RunProgressReporter.snapshot();
        end

        function defs = definitions(obj)
            defs = bms.app.StepDefinition.empty();
            for i = 1:numel(obj.Steps)
                defs(end+1) = obj.Steps{i}.def; %#ok<AGROW>
            end
        end
    end

    methods (Static)
        function pumpUiEvents()
            try
                drawnow limitrate;
            catch
            end
        end

        function emitProgress(progressFcn, payload)
            if isempty(progressFcn)
                return;
            end
            try
                progressFcn(payload);
            catch ME
                warning('StepPlan:ProgressCallbackFailed', 'Progress callback failed: %s', ME.message);
            end
        end

        function payload = progressPayload(eventName, item, result, index, total, completed, elapsedSec)
            if nargin < 3
                result = [];
            end
            if nargin < 7
                elapsedSec = NaN;
            end
            payload = struct();
            payload.event = char(string(eventName));
            payload.status = 'running';
            payload.module_index = index;
            payload.module_total = total;
            payload.completed_modules = completed;
            payload.progress_fraction = min(0.99, max(0, double(completed) / max(1, double(total))));
            payload.elapsed_sec = double(elapsedSec);
            payload.estimated_remaining_sec = bms.app.StepPlan.estimateRemaining(elapsedSec, completed, total);
            payload.current_module_key = '';
            payload.current_module_label = '';
            payload.current_module_status = '';
            payload.message = '';
            if isstruct(item) && isfield(item, 'def') && isa(item.def, 'bms.app.StepDefinition')
                payload.current_module_key = item.def.Key;
                payload.current_module_label = item.def.Label;
            end
            if isa(result, 'bms.app.StepResult')
                payload.current_module_status = result.Status;
                payload.message = result.Message;
                if strcmpi(result.Status, 'stopped')
                    payload.status = 'stopping';
                end
            elseif strcmp(payload.event, 'module_start')
                payload.current_module_status = 'running';
                payload.completed_modules = max(0, index - 1);
                payload.progress_fraction = min(0.99, max(0, double(index - 1) / max(1, double(total))));
                payload.estimated_remaining_sec = bms.app.StepPlan.estimateRemaining(elapsedSec, index - 1, total);
            end
        end

        function secondsLeft = estimateRemaining(elapsedSec, completed, total)
            secondsLeft = NaN;
            if completed <= 0 || total <= completed || ~isfinite(elapsedSec)
                return;
            end
            avg = double(elapsedSec) / double(completed);
            secondsLeft = max(0, avg * double(total - completed));
        end

        function tf = isStoppedResult(result)
            tf = isa(result, 'bms.app.StepResult') && strcmpi(result.Status, 'stopped');
        end

        function tf = isMemoryErrorResult(result)
            tf = isa(result, 'bms.app.StepResult') && ...
                strcmpi(result.Status, 'fail') && ...
                strcmpi(result.ErrorType, 'memory_error');
        end

        function tf = isHighMemoryAnalysis(def)
            tf = false;
            if ~isa(def, 'bms.app.StepDefinition') || isempty(def.Key)
                return;
            end
            spec = bms.module.ModuleRegistry.fromKey(def.Key);
            tf = spec.HighMemoryRisk && strcmpi(spec.Category, 'analysis');
        end
    end
end
