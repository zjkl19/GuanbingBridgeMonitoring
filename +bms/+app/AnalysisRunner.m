classdef AnalysisRunner
    %ANALYSISRUNNER Thin application-layer entry for future run_all migration.
    % This class intentionally delegates to the legacy compatible wrapper for
    % now. New orchestration can be moved here module by module.

    properties
        Context bms.core.AnalysisContext
    end

    methods
        function obj = AnalysisRunner(ctx)
            obj.Context = ctx;
        end

        function manifestPath = run(obj)
            ctx = obj.Context;
            manifestPath = bms_run_context(ctx.DataRoot, ctx.StartDate, ctx.EndDate, ctx.Options, ctx.Config);
        end
    end
end
