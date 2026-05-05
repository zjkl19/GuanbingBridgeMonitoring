classdef EnvironmentStepFactory
    %ENVIRONMENTSTEPFACTORY Builds environment/action monitoring steps.

    methods (Static)
        function plan = append(plan, root, startDate, endDate, opts, cfg, statsDir, sub)
            plan = bms.app.EnvironmentStepFactory.appendClimate(plan, root, startDate, endDate, opts, cfg, statsDir, sub);
            plan = bms.app.EnvironmentStepFactory.appendWindAndEarthquake(plan, root, startDate, endDate, opts, cfg, sub);
        end

        function plan = appendClimate(plan, root, startDate, endDate, opts, cfg, statsDir, sub)
            L = @(key) bms.module.ModuleRegistry.fromKey(key).isEnabled(opts);
            D = @bms.app.StepDefinition.fromKey;

            if L('temperature')
                fallback = {'GB-RTS-G05-001-01','GB-RTS-G05-001-02','GB-RTS-G05-001-03'};
                pts = bms.app.LegacyStepFunctions.getSensorPoints(cfg, 'temperature', fallback);
                if isempty(pts)
                    plan = plan.addSkip(D('temperature'), 'No temperature points configured');
                else
                    plan = plan.addRun(D('temperature'), @() analyze_temperature_points(root, pts, startDate, endDate, fullfile(statsDir, 'temp_stats.xlsx'), sub.temperature, cfg));
                end
            end

            if L('humidity')
                fallback = {'GB-RHS-G05-001-01','GB-RHS-G05-001-02','GB-RHS-G05-001-03'};
                pts = bms.app.LegacyStepFunctions.getSensorPoints(cfg, 'humidity', fallback);
                if isempty(pts)
                    plan = plan.addSkip(D('humidity'), 'No humidity points configured');
                else
                    plan = plan.addRun(D('humidity'), @() analyze_humidity_points(root, pts, startDate, endDate, fullfile(statsDir, 'humidity_stats.xlsx'), sub.humidity, cfg));
                end
            end

            if L('rainfall')
                pts = bms.app.LegacyStepFunctions.getSensorPoints(cfg, 'rainfall', {});
                if isempty(pts)
                    plan = plan.addSkip(D('rainfall'), 'No rainfall points configured');
                else
                    plan = plan.addRun(D('rainfall'), @() analyze_rainfall_points(root, pts, startDate, endDate, fullfile(statsDir, 'rainfall_stats.xlsx'), sub.rainfall, cfg));
                end
            end
        end

        function plan = appendWindAndEarthquake(plan, root, startDate, endDate, opts, cfg, sub)
            L = @(key) bms.module.ModuleRegistry.fromKey(key).isEnabled(opts);
            D = @bms.app.StepDefinition.fromKey;

            if L('wind')
                plan = plan.addRun(D('wind'), @() analyze_wind_points(root, startDate, endDate, sub.wind_raw, cfg));
            end
            if L('earthquake')
                plan = plan.addRun(D('earthquake'), @() analyze_eq_points(root, startDate, endDate, sub.eq_raw, cfg));
            end
        end
    end
end
