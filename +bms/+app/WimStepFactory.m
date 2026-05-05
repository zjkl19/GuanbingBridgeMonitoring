classdef WimStepFactory
    %WIMSTEPFACTORY Builds WIM-related analysis steps.

    methods (Static)
        function plan = append(plan, root, startDate, endDate, opts, cfg)
            L = @(key) bms.module.ModuleRegistry.fromKey(key).isEnabled(opts);
            D = @bms.app.StepDefinition.fromKey;
            if L('wim')
                plan = plan.addRun(D('wim'), @() analyze_wim_reports(root, startDate, endDate, cfg));
            end
        end
    end
end
