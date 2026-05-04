function summary = check_regression_baseline(manifestPath)
%CHECK_REGRESSION_BASELINE Verify that known regression roots are reachable.
%   This is intentionally lightweight: it checks directory and stats/log
%   presence without rerunning the expensive production analyses.

    if nargin < 1 || isempty(manifestPath)
        projectRoot = fileparts(fileparts(mfilename('fullpath')));
        manifestPath = fullfile(projectRoot, 'tests', 'regression_data_manifest.json');
    end
    data = jsondecode(fileread(manifestPath));
    cases = data.cases;
    if ~iscell(cases), cases = num2cell(cases); end
    rows = struct('name', {}, 'status', {}, 'message', {});
    for i = 1:numel(cases)
        c = cases{i};
        name = char(c.name);
        root = char(c.root);
        required = isfield(c, 'required') && logical(c.required);
        if ~exist(root, 'dir')
            status = 'skip';
            if required, status = 'fail'; end
            rows(end+1) = struct('name', name, 'status', status, 'message', ['root missing: ' root]); %#ok<AGROW>
            continue;
        end
        missing = {};
        if isfield(c, 'stats_files')
            stats = c.stats_files;
            if ~iscell(stats), stats = cellstr(stats); end
            for j = 1:numel(stats)
                p = fullfile(root, 'stats', char(stats{j}));
                if ~isfile(p), missing{end+1} = p; end %#ok<AGROW>
            end
        end
        if isfield(c, 'require_log') && logical(c.require_log)
            latestLog = bms.core.PathResolver.latestFile(fullfile(root, 'run_logs'), 'run_log_*.txt');
            if isempty(latestLog), missing{end+1} = fullfile(root, 'run_logs', 'run_log_*.txt'); end %#ok<AGROW>
        end
        if isempty(missing)
            rows(end+1) = struct('name', name, 'status', 'ok', 'message', root); %#ok<AGROW>
        else
            rows(end+1) = struct('name', name, 'status', 'fail', 'message', strjoin(missing, '; ')); %#ok<AGROW>
        end
    end
    summary = rows;
    for i = 1:numel(rows)
        fprintf('[%s] %s - %s\n', upper(rows(i).status), rows(i).name, rows(i).message);
    end
    if any(strcmp({rows.status}, 'fail'))
        error('Regression baseline check failed.');
    end
end
