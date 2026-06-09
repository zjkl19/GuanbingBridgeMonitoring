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

    manifestPath = bms.app.RunRequestRunner.runFile(requestPath);
    if nargout == 0 && ~isempty(manifestPath)
        fprintf('Manifest: %s\n', manifestPath);
    end
end
