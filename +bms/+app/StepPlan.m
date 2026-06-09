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

        function results = execute(obj, shouldStopFcn)
            if nargin < 2 || isempty(shouldStopFcn)
                shouldStopFcn = @() false;
            end
            results = {};
            for i = 1:numel(obj.Steps)
                bms.app.StepPlan.pumpUiEvents();
                item = obj.Steps{i};
                switch item.mode
                    case 'run'
                        results{end+1} = bms.app.StepExecutor.execute(item.def, item.fcn, shouldStopFcn); %#ok<AGROW>
                    case 'skip'
                        results{end+1} = bms.app.StepExecutor.skip(item.def, item.message); %#ok<AGROW>
                end
            end
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
    end
end
