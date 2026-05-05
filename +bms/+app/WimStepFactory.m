classdef WimStepFactory
    %WIMSTEPFACTORY Builds WIM-related analysis steps.

    methods (Static)
        function plan = append(plan, root, startDate, endDate, opts, cfg)
            L = @(key) bms.module.ModuleRegistry.fromKey(key).isEnabled(opts);
            D = @bms.app.StepDefinition.fromKey;
            if L('wim')
                analyzer = bms.analyzer.AnalyzerFactory.create('wim', root, startDate, endDate, bms.core.PathResolver.statsDir(root), struct(), cfg, {});
                plan = plan.addRun(D('wim'), @() analyzer.run());
            end
        end
    end
end
