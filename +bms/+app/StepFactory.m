classdef StepFactory
    %STEPFACTORY Builds the ordered legacy analysis plan from opts/config.

    methods (Static)
        function plan = buildLegacyPlan(root, startDate, endDate, opts, cfg, statsDir, sub)
            plan = bms.app.StepPlan();
            plan = bms.app.PreprocessStepFactory.append(plan, root, startDate, endDate, opts, cfg);
            plan = bms.app.EnvironmentStepFactory.appendClimate(plan, root, startDate, endDate, opts, cfg, statsDir, sub);
            plan = bms.app.StructureStepFactory.appendGnss(plan, root, startDate, endDate, opts, cfg, statsDir, sub);
            plan = bms.app.EnvironmentStepFactory.appendWindAndEarthquake(plan, root, startDate, endDate, opts, cfg, statsDir, sub);
            plan = bms.app.WimStepFactory.append(plan, root, startDate, endDate, opts, cfg);
            plan = bms.app.StructureStepFactory.appendStructural(plan, root, startDate, endDate, opts, cfg, statsDir, sub);
            plan = bms.app.DynamicStepFactory.append(plan, root, startDate, endDate, opts, cfg, statsDir, sub);
        end
    end
end
