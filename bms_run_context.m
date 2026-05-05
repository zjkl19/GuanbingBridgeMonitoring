function manifestPath = bms_run_context(root, start_date, end_date, opts, cfg)
%BMS_RUN_CONTEXT Context-based wrapper around the legacy run_all entrypoint.
%   This keeps the existing analysis modules unchanged while recording a
%   machine-readable run manifest for later report generation and regression.

    if nargin < 5 || isempty(cfg)
        cfg = load_config();
    end
    request = bms.app.RunRequest.fromLegacy(root, start_date, end_date, opts, cfg);
    ctx = request.toContext();
    manifestPath = '';
    try
        session = bms.app.RunSession(request);
        runSummary = session.run();
        if isfield(runSummary, 'analysis_manifest') && ~isempty(runSummary.analysis_manifest) && isfile(runSummary.analysis_manifest)
            manifestPath = runSummary.analysis_manifest;
        else
            manifestPath = bms.app.ManifestWriter.write(ctx, runSummary.status, runSummary);
        end
    catch ME
        details = struct('error', ME.message, 'identifier', ME.identifier);
        try
            details.run_request = request.toStruct();
            details.run_preflight = request.preflight();
        catch
        end
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
