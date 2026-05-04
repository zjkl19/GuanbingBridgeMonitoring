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
            details.expected_stats_files = bms.module.ModuleRegistry.expectedStatsFiles(ctx.StatsDir, opts);
            details.module_preflight = bms.module.ModuleRegistry.preflight(ctx.StatsDir, opts);
            details.enabled_module_specs = bms.module.ModuleRegistry.toStructArray(bms.module.ModuleRegistry.enabledFromOptions(opts), ctx.StatsDir);
        catch
        end
        try
            manifestPath = bms.app.ManifestWriter.write(ctx, 'failed', details);
        catch
        end
        rethrow(ME);
    end
end
