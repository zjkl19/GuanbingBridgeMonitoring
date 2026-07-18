classdef RunProgressReporter
    %RUNPROGRESSREPORTER Truthful, process-local module progress contract.
    %
    % StepPlan owns the ordered module list and installs one reporter for the
    % duration of execute().  Analyzer code may publish real intra-module
    % checkpoints without knowing anything about the async JSON writer:
    %
    %   bms.app.RunProgressReporter.checkpoint( ...
    %       'stage', 'load_data', ...
    %       'current_point_id', pointId, ...
    %       'current_date', dayText, ...
    %       'processed_dates', dayIndex, ...
    %       'total_dates', totalDays);
    %
    % No timer-derived or guessed point/day progress is generated here.  A
    % field changes only when the running analyzer supplies a real value.

    properties (Constant)
        SchemaVersion = 2
    end

    methods (Static)
        function configure(planSteps, progressFcn)
            if nargin < 1 || isempty(planSteps)
                planSteps = {};
            end
            if nargin < 2
                progressFcn = [];
            end
            state = bms.app.RunProgressReporter.blankState();
            state.enabled = true;
            state.progress_fcn = progressFcn;
            state.plan_timer = tic;
            state.module_steps = bms.app.RunProgressReporter.initialSteps(planSteps);
            bms.app.RunProgressReporter.state('set', state);
            bms.app.RunProgressReporter.emit('plan_initialized');
        end

        function clear()
            bms.app.RunProgressReporter.state('clear');
        end

        function startModule(index)
            state = bms.app.RunProgressReporter.state('get');
            if ~state.enabled || index < 1 || index > numel(state.module_steps)
                return;
            end
            state.current_index = double(index);
            state.current_timer = tic;
            state.module_steps(index).status = 'running';
            state.module_steps(index).stage = 'module_start';
            state.module_steps(index).elapsed_seconds = 0;
            state.module_steps(index).message = '';
            bms.app.RunProgressReporter.state('set', state);
            bms.app.RunProgressReporter.emit('module_start');
        end

        function checkpoint(varargin)
            if bms.app.RunProgressReporter.isParallelWorker()
                return;
            end
            state = bms.app.RunProgressReporter.state('get');
            if ~state.enabled || state.current_index < 1 || ...
                    state.current_index > numel(state.module_steps)
                return;
            end
            details = bms.app.RunProgressReporter.parseCheckpoint(varargin{:});
            index = state.current_index;
            step = state.module_steps(index);
            names = {'stage','current_point_id','current_date','message'};
            for i = 1:numel(names)
                name = names{i};
                if isfield(details, name)
                    step.(name) = char(string(details.(name)));
                end
            end
            numbers = {'processed_dates','total_dates'};
            for i = 1:numel(numbers)
                name = numbers{i};
                if isfield(details, name)
                    value = double(details.(name));
                    if isscalar(value) && isfinite(value) && value >= 0
                        step.(name) = value;
                    end
                end
            end
            if step.total_dates > 0
                step.processed_dates = min(step.processed_dates, step.total_dates);
            end
            step.elapsed_seconds = bms.app.RunProgressReporter.currentElapsed(state);
            state.module_steps(index) = step;
            bms.app.RunProgressReporter.state('set', state);
            bms.app.RunProgressReporter.emit('module_progress');
        end

        function step = currentStep()
            state = bms.app.RunProgressReporter.state('get');
            step = bms.app.RunProgressReporter.emptyStep();
            if state.enabled && state.current_index >= 1 && ...
                    state.current_index <= numel(state.module_steps)
                step = state.module_steps(state.current_index);
                step.elapsed_seconds = bms.app.RunProgressReporter.currentElapsed(state);
            end
        end

        function completeModule(index, result, eventName)
            if nargin < 3 || isempty(eventName)
                eventName = 'module_complete';
            end
            state = bms.app.RunProgressReporter.state('get');
            if ~state.enabled || index < 1 || index > numel(state.module_steps)
                return;
            end
            state.current_index = double(index);
            step = state.module_steps(index);
            step.status = bms.app.RunProgressReporter.canonicalStatus( ...
                bms.app.RunProgressReporter.resultText(result, 'Status', 'status'));
            step.stage = bms.app.RunProgressReporter.terminalStage(step.status);
            step.message = bms.app.RunProgressReporter.resultText(result, 'Message', 'message');
            elapsed = bms.app.RunProgressReporter.resultNumber(result, 'ElapsedSec', 'elapsed_sec', NaN);
            if ~isfinite(elapsed)
                elapsed = bms.app.RunProgressReporter.currentElapsed(state);
            end
            step.elapsed_seconds = max(0, elapsed);
            state.module_steps(index) = step;
            bms.app.RunProgressReporter.state('set', state);
            bms.app.RunProgressReporter.emit(eventName);
        end

        function payload = snapshot()
            state = bms.app.RunProgressReporter.state('get');
            payload = bms.app.RunProgressReporter.payload(state, 'snapshot');
        end

        function payload = reconcile(payload, results, authority)
            if nargin < 1 || ~isstruct(payload)
                payload = struct();
            end
            if nargin < 2 || isempty(results)
                results = {};
            end
            if nargin < 3 || isempty(authority)
                authority = 'analysis_manifest';
            end
            steps = bms.app.RunProgressReporter.stepsFromPayload(payload);
            resultItems = bms.app.RunProgressReporter.asCells(results);
            if isempty(steps)
                steps = repmat(bms.app.RunProgressReporter.emptyStep(), 1, numel(resultItems));
                for i = 1:numel(resultItems)
                    steps(i) = bms.app.RunProgressReporter.stepFromResult(resultItems{i}, i);
                end
            else
                for i = 1:numel(resultItems)
                    result = resultItems{i};
                    index = bms.app.RunProgressReporter.findResultStep(steps, result, i);
                    if index < 1
                        continue;
                    end
                    updated = bms.app.RunProgressReporter.stepFromResult(result, steps(index).index);
                    updated.current_point_id = steps(index).current_point_id;
                    updated.current_date = steps(index).current_date;
                    updated.processed_dates = steps(index).processed_dates;
                    updated.total_dates = steps(index).total_dates;
                    steps(index) = updated;
                end
            end
            payload = bms.app.RunProgressReporter.payloadFromSteps(steps, authority);
        end

        function payload = terminalPayloadFromManifest(manifest, finalStatus)
            if nargin < 1 || ~isstruct(manifest)
                manifest = struct();
            end
            if nargin < 2 || isempty(finalStatus)
                finalStatus = 'completed';
            end
            seed = struct();
            hasExplicitV2Plan = false;
            if isfield(manifest, 'module_steps')
                seed.module_steps = manifest.module_steps;
                if isfield(manifest, 'progress_schema_version')
                    version = double(manifest.progress_schema_version);
                    hasExplicitV2Plan = isscalar(version) && isfinite(version) && ...
                        version >= bms.app.RunProgressReporter.SchemaVersion;
                end
            elseif isfield(manifest, 'analysis_progress') && isstruct(manifest.analysis_progress)
                seed = manifest.analysis_progress;
            end
            if isempty(bms.app.RunProgressReporter.stepsFromPayload(seed))
                expectedSteps = bms.app.RunProgressReporter.expectedStepsFromManifest(manifest);
                if ~isempty(expectedSteps)
                    seed.module_steps = expectedSteps;
                end
            end
            results = {};
            if isfield(manifest, 'module_results')
                results = manifest.module_results;
            end
            if hasExplicitV2Plan && ...
                    isempty(bms.app.RunProgressReporter.stepsFromPayload(seed))
                % An explicit empty v2 plan is authoritative. Runs with no
                % enabled modules may still publish config/postprocess
                % diagnostics, but those are not planned analysis modules.
                results = {};
            end
            payload = bms.app.RunProgressReporter.reconcile(seed, results, 'analysis_manifest');
            steps = payload.module_steps;
            running = find(strcmp({steps.status}, 'running'), 1, 'last');
            if ~isempty(running)
                if strcmpi(finalStatus, 'stopped')
                    steps(running).status = 'stopped';
                    steps(running).stage = 'stopped';
                elseif strcmpi(finalStatus, 'failed')
                    steps(running).status = 'failed';
                    steps(running).stage = 'failed';
                end
                payload = bms.app.RunProgressReporter.payloadFromSteps(steps, 'analysis_manifest');
            end
            unresolved = find(ismember({payload.module_steps.status}, {'pending','running'}));
            if strcmpi(finalStatus, 'completed') && ~isempty(unresolved)
                finalStatus = 'failed';
                payload.missing_module_keys = {payload.module_steps(unresolved).key};
                payload.message = sprintf( ...
                    'Final analysis manifest omitted %d planned module result(s).', ...
                    numel(unresolved));
            else
                payload.missing_module_keys = {};
            end
            payload.status = char(string(finalStatus));
            if strcmpi(finalStatus, 'completed') && payload.module_total > 0
                payload.progress_fraction = 1;
            end
        end
    end

    methods (Static, Access = private)
        function state = blankState()
            state = struct( ...
                'enabled', false, ...
                'progress_fcn', [], ...
                'plan_timer', [], ...
                'current_timer', [], ...
                'current_index', 0, ...
                'module_steps', repmat(bms.app.RunProgressReporter.emptyStep(), 1, 0));
        end

        function out = state(action, value)
            persistent stored;
            if isempty(stored)
                stored = bms.app.RunProgressReporter.blankState();
            end
            switch lower(char(string(action)))
                case 'get'
                    out = stored;
                case 'set'
                    stored = value;
                    out = stored;
                case 'clear'
                    stored = bms.app.RunProgressReporter.blankState();
                    out = stored;
                otherwise
                    error('BMS:RunProgressReporter:InvalidStateAction', ...
                        'Unknown state action: %s', char(string(action)));
            end
        end

        function steps = initialSteps(planSteps)
            if ~iscell(planSteps)
                planSteps = num2cell(planSteps);
            end
            steps = repmat(bms.app.RunProgressReporter.emptyStep(), 1, numel(planSteps));
            for i = 1:numel(planSteps)
                item = planSteps{i};
                step = bms.app.RunProgressReporter.emptyStep();
                step.index = double(i);
                if isstruct(item) && isfield(item, 'def') && isa(item.def, 'bms.app.StepDefinition')
                    step.key = item.def.Key;
                    step.label = item.def.Label;
                elseif isa(item, 'bms.app.StepDefinition')
                    step.key = item.Key;
                    step.label = item.Label;
                end
                steps(i) = step;
            end
        end

        function step = emptyStep()
            step = struct( ...
                'key', '', ...
                'label', '', ...
                'index', 0, ...
                'status', 'pending', ...
                'stage', 'pending', ...
                'current_point_id', '', ...
                'current_date', '', ...
                'processed_dates', 0, ...
                'total_dates', 0, ...
                'elapsed_seconds', 0, ...
                'message', '');
        end

        function details = parseCheckpoint(varargin)
            details = struct();
            if isscalar(varargin) && isstruct(varargin{1})
                details = varargin{1};
                return;
            end
            if mod(numel(varargin), 2) ~= 0
                error('BMS:RunProgressReporter:InvalidCheckpoint', ...
                    'Checkpoint values must be a struct or name-value pairs.');
            end
            for i = 1:2:numel(varargin)
                name = lower(char(string(varargin{i})));
                switch name
                    case {'stage','current_point_id','current_date','processed_dates','total_dates','message'}
                        details.(name) = varargin{i+1};
                    case 'point_id'
                        details.current_point_id = varargin{i+1};
                    case 'date'
                        details.current_date = varargin{i+1};
                    otherwise
                        error('BMS:RunProgressReporter:UnknownCheckpointField', ...
                            'Unknown checkpoint field: %s', name);
                end
            end
        end

        function emit(eventName)
            state = bms.app.RunProgressReporter.state('get');
            if ~state.enabled || isempty(state.progress_fcn)
                return;
            end
            try
                state.progress_fcn(bms.app.RunProgressReporter.payload(state, eventName));
            catch ME
                warning('RunProgressReporter:ProgressCallbackFailed', ...
                    'Progress callback failed: %s', ME.message);
            end
        end

        function payload = payload(state, eventName)
            payload = bms.app.RunProgressReporter.payloadFromSteps(state.module_steps, 'runtime');
            payload.event = char(string(eventName));
            payload.elapsed_sec = bms.app.RunProgressReporter.planElapsed(state);
            payload.estimated_remaining_sec = bms.app.RunProgressReporter.estimateRemaining( ...
                payload.elapsed_sec, payload.completed_modules, payload.module_total);
            if state.current_index >= 1 && state.current_index <= numel(state.module_steps)
                step = state.module_steps(state.current_index);
                step.elapsed_seconds = bms.app.RunProgressReporter.currentElapsed(state);
                payload.module_steps(state.current_index) = step;
                payload = bms.app.RunProgressReporter.applyCurrent(payload, step);
            end
            if strcmp(payload.current_module_status, 'stopped')
                payload.status = 'stopping';
            end
        end

        function payload = payloadFromSteps(steps, authority)
            steps = bms.app.RunProgressReporter.normalizeSteps(steps);
            payload = struct();
            payload.progress_schema_version = bms.app.RunProgressReporter.SchemaVersion;
            payload.progress_authority = char(string(authority));
            payload.event = 'snapshot';
            payload.status = 'running';
            payload.module_index = 0;
            payload.module_total = numel(steps);
            payload.completed_modules = sum(ismember({steps.status}, ...
                {'completed','failed','skipped','stopped'}));
            payload.progress_fraction = min(0.99, max(0, ...
                double(payload.completed_modules) / max(1, double(payload.module_total))));
            payload.elapsed_sec = sum([steps.elapsed_seconds]);
            payload.estimated_remaining_sec = NaN;
            payload.current_module_key = '';
            payload.current_module_label = '';
            payload.current_module_status = '';
            payload.stage = '';
            payload.current_point_id = '';
            payload.current_date = '';
            payload.processed_dates = 0;
            payload.total_dates = 0;
            payload.message = '';
            payload.module_steps = steps;
            if isempty(steps)
                return;
            end
            current = find(strcmp({steps.status}, 'running'), 1, 'last');
            if isempty(current)
                current = find(~strcmp({steps.status}, 'pending'), 1, 'last');
            end
            if isempty(current)
                current = 1;
            end
            payload = bms.app.RunProgressReporter.applyCurrent(payload, steps(current));
        end

        function payload = applyCurrent(payload, step)
            payload.module_index = step.index;
            payload.current_module_key = step.key;
            payload.current_module_label = step.label;
            payload.current_module_status = step.status;
            payload.stage = step.stage;
            payload.current_point_id = step.current_point_id;
            payload.current_date = step.current_date;
            payload.processed_dates = step.processed_dates;
            payload.total_dates = step.total_dates;
            payload.message = step.message;
        end

        function steps = stepsFromPayload(payload)
            steps = repmat(bms.app.RunProgressReporter.emptyStep(), 1, 0);
            if isstruct(payload) && isfield(payload, 'module_steps')
                steps = bms.app.RunProgressReporter.normalizeSteps(payload.module_steps);
            end
        end

        function steps = normalizeSteps(raw)
            items = bms.app.RunProgressReporter.asCells(raw);
            steps = repmat(bms.app.RunProgressReporter.emptyStep(), 1, numel(items));
            for i = 1:numel(items)
                item = items{i};
                step = bms.app.RunProgressReporter.emptyStep();
                if isstruct(item)
                    texts = {'key','label','status','stage','current_point_id','current_date','message'};
                    for j = 1:numel(texts)
                        name = texts{j};
                        if isfield(item, name) && ~isempty(item.(name))
                            step.(name) = char(string(item.(name)));
                        end
                    end
                    numbers = {'index','processed_dates','total_dates','elapsed_seconds'};
                    for j = 1:numel(numbers)
                        name = numbers{j};
                        if isfield(item, name) && isnumeric(item.(name)) && isscalar(item.(name))
                            step.(name) = double(item.(name));
                        end
                    end
                end
                if step.index <= 0
                    step.index = double(i);
                end
                step.status = bms.app.RunProgressReporter.canonicalStatus(step.status);
                steps(i) = step;
            end
        end

        function cells = asCells(value)
            if isempty(value)
                cells = {};
            elseif iscell(value)
                cells = value;
            elseif isstruct(value) || isobject(value)
                cells = num2cell(value);
            else
                cells = {value};
            end
        end

        function step = stepFromResult(result, index)
            step = bms.app.RunProgressReporter.emptyStep();
            step.index = double(index);
            step.key = bms.app.RunProgressReporter.resultText(result, 'Key', 'key');
            step.label = bms.app.RunProgressReporter.resultText(result, 'Label', 'label');
            step.status = bms.app.RunProgressReporter.canonicalStatus( ...
                bms.app.RunProgressReporter.resultText(result, 'Status', 'status'));
            step.stage = bms.app.RunProgressReporter.terminalStage(step.status);
            step.message = bms.app.RunProgressReporter.resultText(result, 'Message', 'message');
            step.elapsed_seconds = max(0, bms.app.RunProgressReporter.resultNumber( ...
                result, 'ElapsedSec', 'elapsed_sec', 0));
            step.current_point_id = bms.app.RunProgressReporter.resultText(result, 'CurrentPointId', 'current_point_id');
            step.current_date = bms.app.RunProgressReporter.resultText(result, 'CurrentDate', 'current_date');
            step.processed_dates = bms.app.RunProgressReporter.resultNumber(result, 'ProcessedDates', 'processed_dates', 0);
            step.total_dates = bms.app.RunProgressReporter.resultNumber(result, 'TotalDates', 'total_dates', 0);
        end

        function index = findResultStep(steps, result, fallbackIndex)
            index = 0;
            key = bms.app.RunProgressReporter.resultText(result, 'Key', 'key');
            if ~isempty(key)
                index = find(strcmp({steps.key}, key), 1, 'first');
                if isempty(index)
                    index = 0;
                end
                return;
            end
            if index < 1
                if fallbackIndex >= 1 && fallbackIndex <= numel(steps)
                    index = fallbackIndex;
                else
                    index = 0;
                end
            end
        end

        function text = resultText(result, propertyName, fieldName)
            text = '';
            try
                if isobject(result) && isprop(result, propertyName)
                    text = char(string(result.(propertyName)));
                elseif isstruct(result) && isfield(result, fieldName) && ~isempty(result.(fieldName))
                    text = char(string(result.(fieldName)));
                end
            catch
                text = '';
            end
        end

        function value = resultNumber(result, propertyName, fieldName, fallback)
            value = fallback;
            try
                if isobject(result) && isprop(result, propertyName)
                    raw = result.(propertyName);
                elseif isstruct(result) && isfield(result, fieldName)
                    raw = result.(fieldName);
                else
                    return;
                end
                if isnumeric(raw) && isscalar(raw) && isfinite(raw)
                    value = double(raw);
                end
            catch
                value = fallback;
            end
        end

        function status = canonicalStatus(raw)
            value = lower(strtrim(char(string(raw))));
            switch value
                case {'ok','pass','passed','complete','completed','success'}
                    status = 'completed';
                case {'fail','failed','error'}
                    status = 'failed';
                case {'skip','skipped','not_applicable','no_data','no_valid_data'}
                    status = 'skipped';
                case {'stop','stopped','stopping'}
                    status = 'stopped';
                case 'running'
                    status = 'running';
                otherwise
                    status = 'pending';
            end
        end

        function stage = terminalStage(status)
            switch status
                case 'completed'
                    stage = 'completed';
                case 'failed'
                    stage = 'failed';
                case 'skipped'
                    stage = 'skipped';
                case 'stopped'
                    stage = 'stopped';
                otherwise
                    stage = char(string(status));
            end
        end

        function elapsed = currentElapsed(state)
            elapsed = 0;
            try
                if ~isempty(state.current_timer)
                    elapsed = max(0, toc(state.current_timer));
                end
            catch
                elapsed = 0;
            end
        end

        function elapsed = planElapsed(state)
            elapsed = sum([state.module_steps.elapsed_seconds]);
            try
                if ~isempty(state.plan_timer)
                    elapsed = max(0, toc(state.plan_timer));
                end
            catch
            end
        end

        function secondsLeft = estimateRemaining(elapsedSec, completed, total)
            secondsLeft = NaN;
            if completed <= 0 || total <= completed || ~isfinite(elapsedSec)
                return;
            end
            secondsLeft = max(0, double(elapsedSec) / double(completed) * double(total - completed));
        end

        function steps = expectedStepsFromManifest(manifest)
            raw = [];
            if isstruct(manifest) && isfield(manifest, 'enabled_module_specs') ...
                    && ~isempty(manifest.enabled_module_specs)
                raw = manifest.enabled_module_specs;
            elseif isstruct(manifest) && isfield(manifest, 'enabled_modules') ...
                    && ~isempty(manifest.enabled_modules)
                raw = manifest.enabled_modules;
            elseif isstruct(manifest) && isfield(manifest, 'run_request') ...
                    && isstruct(manifest.run_request) ...
                    && isfield(manifest.run_request, 'enabled_modules')
                raw = manifest.run_request.enabled_modules;
            end
            items = bms.app.RunProgressReporter.asCells(raw);
            steps = repmat(bms.app.RunProgressReporter.emptyStep(), 1, numel(items));
            for i = 1:numel(items)
                item = items{i};
                step = bms.app.RunProgressReporter.emptyStep();
                step.index = double(i);
                if isstruct(item)
                    if isfield(item, 'key'), step.key = char(string(item.key)); end
                    if isfield(item, 'label'), step.label = char(string(item.label)); end
                else
                    step.key = char(string(item));
                end
                if isempty(step.label) && ~isempty(step.key)
                    step.label = bms.app.StepDefinition.fromKey(step.key).Label;
                end
                steps(i) = step;
            end
        end

        function tf = isParallelWorker()
            tf = false;
            try
                tf = ~isempty(getCurrentTask());
            catch
                % Parallel Computing Toolbox is optional.  In a normal MATLAB
                % process getCurrentTask either returns [] or is unavailable.
            end
        end
    end
end
