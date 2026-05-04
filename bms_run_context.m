function manifestPath = bms_run_context(root, start_date, end_date, opts, cfg)
%BMS_RUN_CONTEXT Context-based wrapper around the legacy run_all entrypoint.
%   This keeps the existing analysis modules unchanged while recording a
%   machine-readable run manifest for later report generation and regression.

    if nargin < 5 || isempty(cfg)
        cfg = load_config();
    end
    ctx = bms.core.AnalysisContext.fromLegacy(root, start_date, end_date, opts, cfg);
    manifestPath = '';
    try
        runSummary = run_all(root, start_date, end_date, opts, cfg);
        manifestPath = bms.app.ManifestWriter.write(ctx, runSummary.status, runSummary);
    catch ME
        details = struct('error', ME.message, 'identifier', ME.identifier);
        try
            manifestPath = bms.app.ManifestWriter.write(ctx, 'failed', details);
        catch
        end
        rethrow(ME);
    end
end
