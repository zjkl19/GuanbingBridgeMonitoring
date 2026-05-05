classdef StructureStepFactory
    %STRUCTURESTEPFACTORY Builds structural response/change monitoring steps.

    methods (Static)
        function plan = append(plan, root, startDate, endDate, opts, cfg, statsDir, sub)
            plan = bms.app.StructureStepFactory.appendGnss(plan, root, startDate, endDate, opts, cfg, statsDir, sub);
            plan = bms.app.StructureStepFactory.appendStructural(plan, root, startDate, endDate, opts, cfg, statsDir, sub);
        end

        function plan = appendGnss(plan, root, startDate, endDate, opts, cfg, statsDir, sub)
            L = @(key) bms.module.ModuleRegistry.fromKey(key).isEnabled(opts);
            D = @bms.app.StepDefinition.fromKey;
            if L('gnss')
                pts = bms.app.LegacyStepFunctions.getSensorPoints(cfg, 'gnss', {});
                if isempty(pts)
                    plan = plan.addSkip(D('gnss'), 'No GNSS points configured');
                else
                    analyzer = bms.analyzer.AnalyzerFactory.create('gnss', root, startDate, endDate, statsDir, sub, cfg, pts);
                    plan = plan.addRun(D('gnss'), @() analyzer.run());
                end
            end
        end

        function plan = appendStructural(plan, root, startDate, endDate, opts, cfg, statsDir, sub)
            L = @(key) bms.module.ModuleRegistry.fromKey(key).isEnabled(opts);
            D = @bms.app.StepDefinition.fromKey;

            if L('deflection')
                analyzer = bms.analyzer.AnalyzerFactory.create('deflection', root, startDate, endDate, statsDir, sub, cfg, {});
                plan = plan.addRun(D('deflection'), @() analyzer.run());
            end
            if L('bearing_displacement')
                analyzer = bms.analyzer.AnalyzerFactory.create('bearing_displacement', root, startDate, endDate, statsDir, sub, cfg, {});
                plan = plan.addRun(D('bearing_displacement'), @() analyzer.run());
            end
            if L('tilt')
                analyzer = bms.analyzer.AnalyzerFactory.create('tilt', root, startDate, endDate, statsDir, sub, cfg, {});
                plan = plan.addRun(D('tilt'), @() analyzer.run());
            end
            if L('rename_crk')
                plan = plan.addRun(D('rename_crk'), @() batch_rename_crk_T_to_t(root, startDate, endDate, true));
            end
            if L('crack')
                analyzer = bms.analyzer.AnalyzerFactory.create('crack', root, startDate, endDate, statsDir, sub, cfg, {});
                plan = plan.addRun(D('crack'), @() analyzer.run());
            end
            if L('strain')
                analyzer = bms.analyzer.AnalyzerFactory.create('strain', root, startDate, endDate, statsDir, sub, cfg, {});
                plan = plan.addRun(D('strain'), @() analyzer.run());
            end
        end

    end
end
