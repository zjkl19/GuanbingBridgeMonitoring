function manifestPath = run_request_cli(requestPath)
%RUN_REQUEST_CLI Compile-friendly entry point for serialized analysis runs.
%   BridgeAnalysisRunner.exe <run_request.json> is built from this function.

    if nargin < 1 || isempty(requestPath)
        error('BMS:run_request_cli:MissingRequestPath', ...
            'Usage: run_request_cli(requestPath)');
    end

    projectRoot = fileparts(mfilename('fullpath'));
    addpath(projectRoot, '-begin');
    addpath(fullfile(projectRoot, 'ui'), '-begin');
    addpath(fullfile(projectRoot, 'config'), '-begin');
    addpath(fullfile(projectRoot, 'pipeline'), '-begin');
    addpath(fullfile(projectRoot, 'analysis'), '-begin');
    addpath(fullfile(projectRoot, 'scripts'), '-begin');

    % Compiled runners and MATLAB -batch jobs must not create desktop
    % windows. In a normal interactive MATLAB session this guard preserves
    % the user's existing figure visibility preference.
    plotVisibilityGuard = bms.plot.PlotVisibilityPolicy.enterForCurrentProcess(); %#ok<NASGU>

    requestType = 'analysis';
    try
        raw = bms.io.JsonFile.read(requestPath);
        if isstruct(raw) && isfield(raw, 'request_type') && ~isempty(raw.request_type)
            requestType = lower(char(string(raw.request_type)));
        end
    catch
        % Analysis requests retain the legacy reader/error behavior below.
    end
    if strcmp(requestType, 'auto_threshold_proposal')
        manifestPath = bms.app.AutoThresholdRequestRunner.runFile(requestPath);
    else
        manifestPath = bms.app.RunRequestRunner.runFile(requestPath);
    end
    if nargout == 0 && ~isempty(manifestPath)
        fprintf('Manifest: %s\n', manifestPath);
    end
end
