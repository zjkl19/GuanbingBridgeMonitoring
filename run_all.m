function summary = run_all(root, start_date, end_date, opts, cfg)
%RUN_ALL Compatible public entry point for the MATLAB analysis workflow.
%   The application-layer orchestration lives in bms.app.RunSession.
    if nargin < 5
        cfg = [];
    end
    if nargin < 4 || isempty(opts)
        opts = struct();
    end
    session = bms.app.RunSession(root, start_date, end_date, opts, cfg);
    summary = session.run();
end
