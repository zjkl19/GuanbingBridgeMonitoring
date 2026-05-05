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
                    plan = plan.addRun(D('gnss'), @() analyze_gnss_points(root, pts, startDate, endDate, fullfile(statsDir, 'gnss_stats.xlsx'), sub.gnss, cfg));
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
                plan = plan.addRun(D('bearing_displacement'), @() analyze_bearing_displacement_points(root, startDate, endDate, fullfile(statsDir, 'bearing_displacement_stats.xlsx'), sub.bearing_displacement, cfg));
            end
            if L('tilt')
                plan = plan.addRun(D('tilt'), @() analyze_tilt_points(root, startDate, endDate, fullfile(statsDir, 'tilt_stats.xlsx'), sub.tilt, cfg));
            end
            if L('rename_crk')
                plan = plan.addRun(D('rename_crk'), @() batch_rename_crk_T_to_t(root, startDate, endDate, true));
            end
            if L('crack')
                analyzer = bms.analyzer.AnalyzerFactory.create('crack', root, startDate, endDate, statsDir, sub, cfg, {});
                plan = plan.addRun(D('crack'), @() analyzer.run());
            end
            if L('strain')
                plan = plan.addRun(D('strain'), @() analyze_strain_points(root, startDate, endDate, fullfile(statsDir, 'strain_stats.xlsx'), sub.strain, cfg));
            end
        end

    end
end
