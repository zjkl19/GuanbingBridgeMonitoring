classdef AnalysisRunner
    %ANALYSISRUNNER Thin application-layer entry for future run_all migration.
    % This class intentionally delegates to the legacy compatible wrapper for
    % now. New orchestration can be moved here module by module.

    properties
        Context bms.core.AnalysisContext
        Request = []
    end

    methods
        function obj = AnalysisRunner(ctx)
            if isa(ctx, 'bms.app.RunRequest')
                obj.Request = ctx;
                obj.Context = ctx.toContext();
            else
                obj.Context = ctx;
                obj.Request = bms.app.RunRequest.fromContext(ctx);
            end
        end

        function manifestPath = run(obj)
            session = bms.app.RunSession(obj.Request);
            summary = session.run();
            manifestPath = summary.analysis_manifest;
        end
    end
end
