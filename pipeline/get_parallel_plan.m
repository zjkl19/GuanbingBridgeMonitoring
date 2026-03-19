function plan = get_parallel_plan(cfg, task_count, label)
% get_parallel_plan  Best-effort parallel execution plan for analysis loops.

    if nargin < 2 || isempty(task_count)
        task_count = 0;
    end
    if nargin < 3 || isempty(label)
        label = 'analysis';
    end

    plan = struct('enabled', false, 'worker_count', 0, 'reason', '');
    if task_count < 1
        plan.reason = 'no tasks';
        return;
    end

    parallel_cfg = struct();
    if nargin >= 1 && isstruct(cfg) && isfield(cfg, 'parallel') && isstruct(cfg.parallel)
        parallel_cfg = cfg.parallel;
    end

    enabled = get_bool(parallel_cfg, 'enable', true);
    min_tasks = get_num(parallel_cfg, 'min_tasks', 3);
    num_workers = get_num(parallel_cfg, 'num_workers', []);

    if ~enabled
        plan.reason = 'disabled by cfg.parallel.enable';
        return;
    end
    if task_count < min_tasks
        plan.reason = sprintf('task count %d < min_tasks %d', task_count, min_tasks);
        return;
    end
    if exist('parpool', 'file') ~= 2 || ~license('test', 'Distrib_Computing_Toolbox')
        plan.reason = 'Parallel Computing Toolbox unavailable';
        return;
    end

    try
        pool = gcp('nocreate');
        if isempty(pool)
            if isempty(num_workers)
                pool = parpool('local');
            else
                pool = parpool('local', max(1, round(num_workers)));
            end
        end
        plan.enabled = true;
        plan.worker_count = pool.NumWorkers;
        plan.reason = sprintf('%s using %d workers', label, pool.NumWorkers);
    catch ME
        warning('Parallel:%sPoolFailed', upper(regexprep(label, '[^A-Za-z0-9]', '')), ...
            'Parallel pool unavailable for %s, fallback to serial: %s', label, ME.message);
        plan.reason = ME.message;
    end
end

function value = get_bool(s, field, default)
    value = default;
    if ~isstruct(s) || ~isfield(s, field) || isempty(s.(field))
        return;
    end
    raw = s.(field);
    if islogical(raw) && isscalar(raw)
        value = raw;
    elseif isnumeric(raw) && isscalar(raw) && ~isnan(raw)
        value = (raw ~= 0);
    end
end

function value = get_num(s, field, default)
    value = default;
    if ~isstruct(s) || ~isfield(s, field) || isempty(s.(field))
        return;
    end
    raw = s.(field);
    if isnumeric(raw) && isscalar(raw) && isfinite(raw)
        value = double(raw);
    end
end
