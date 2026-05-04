function manifestPath = gbm_run_context(root, start_date, end_date, opts, cfg)
%GBM_RUN_CONTEXT Backward-compatible wrapper for bms_run_context.
    if nargin < 5
        manifestPath = bms_run_context(root, start_date, end_date, opts);
    else
        manifestPath = bms_run_context(root, start_date, end_date, opts, cfg);
    end
end
