classdef DynamicStepFactory
    %DYNAMICSTEPFACTORY Builds vibration, cable acceleration, spectra, and dynamic strain steps.

    methods (Static)
        function plan = append(plan, root, startDate, endDate, opts, cfg, statsDir, sub)
            L = @(key) bms.module.ModuleRegistry.fromKey(key).isEnabled(opts);
            D = @bms.app.StepDefinition.fromKey;

            if L('acceleration')
                analyzer = bms.analyzer.AnalyzerFactory.create('acceleration', root, startDate, endDate, statsDir, sub, cfg, {});
                plan = plan.addRun(D('acceleration'), @() analyzer.run());
            end
            if L('cable_accel')
                analyzer = bms.analyzer.AnalyzerFactory.create('cable_accel', root, startDate, endDate, statsDir, sub, cfg, {});
                plan = plan.addRun(D('cable_accel'), @() analyzer.run());
            end

            if L('accel_spectrum')
                defaultPts = {'GB-VIB-G04-001-01','GB-VIB-G05-001-01', ...
                    'GB-VIB-G05-002-01','GB-VIB-G05-003-01', ...
                    'GB-VIB-G06-001-01','GB-VIB-G06-002-01', ...
                    'GB-VIB-G06-003-01','GB-VIB-G07-001-01'};
                accelPts = bms.app.LegacyStepFunctions.getPoints(cfg, 'accel_spectrum', bms.app.LegacyStepFunctions.getPoints(cfg, 'acceleration', defaultPts));
                [freqs, tol] = bms.app.LegacyStepFunctions.getAccelSpecParams(cfg);
                analyzer = bms.analyzer.AnalyzerFactory.create('accel_spectrum', root, startDate, endDate, statsDir, sub, cfg, accelPts, struct('freqs', freqs, 'tol', tol));
                plan = plan.addRun(D('accel_spectrum'), @() analyzer.run());
            end

            if L('cable_accel_spectrum')
                defaultPts = {'GB-VIB-G04-001-01','GB-VIB-G05-001-01', ...
                    'GB-VIB-G05-002-01','GB-VIB-G05-003-01', ...
                    'GB-VIB-G06-001-01','GB-VIB-G06-002-01', ...
                    'GB-VIB-G06-003-01','GB-VIB-G07-001-01'};
                cablePts = bms.app.LegacyStepFunctions.getPoints(cfg, 'cable_accel_spectrum', ...
                    bms.app.LegacyStepFunctions.getPoints(cfg, 'cable_accel', bms.app.LegacyStepFunctions.getPoints(cfg, 'cable_force', defaultPts)));
                [freqs, tol] = bms.app.LegacyStepFunctions.getCableSpecParams(cfg);
                analyzer = bms.analyzer.AnalyzerFactory.create('cable_accel_spectrum', root, startDate, endDate, statsDir, sub, cfg, cablePts, struct('freqs', freqs, 'tol', tol));
                plan = plan.addRun(D('cable_accel_spectrum'), @() analyzer.run());
            end

            if L('dynamic_strain_highpass')
                analyzer = bms.analyzer.AnalyzerFactory.create('dynamic_strain_highpass', root, startDate, endDate, statsDir, sub, cfg, {});
                plan = plan.addRun(D('dynamic_strain_highpass'), @() analyzer.run());
            end

            if L('dynamic_strain_lowpass')
                analyzer = bms.analyzer.AnalyzerFactory.create('dynamic_strain_lowpass', root, startDate, endDate, statsDir, sub, cfg, {});
                plan = plan.addRun(D('dynamic_strain_lowpass'), @() analyzer.run());
            end
        end
    end
end
