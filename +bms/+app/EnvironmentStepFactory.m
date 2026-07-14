classdef EnvironmentStepFactory
    %ENVIRONMENTSTEPFACTORY Builds environment/action monitoring steps.

    methods (Static)
        function plan = append(plan, root, startDate, endDate, opts, cfg, statsDir, sub)
            plan = bms.app.EnvironmentStepFactory.appendClimate(plan, root, startDate, endDate, opts, cfg, statsDir, sub);
            plan = bms.app.EnvironmentStepFactory.appendWindAndEarthquake(plan, root, startDate, endDate, opts, cfg, statsDir, sub);
        end

        function plan = appendClimate(plan, root, startDate, endDate, opts, cfg, statsDir, sub)
            L = @(key) bms.module.ModuleRegistry.fromKey(key).isEnabled(opts);
            D = @bms.app.StepDefinition.fromKey;

            if L('temperature')
                pts = bms.app.EnvironmentStepFactory.resolveClimatePoints(cfg, 'temperature');
                if isempty(pts)
                    plan = plan.addSkip(D('temperature'), 'No temperature points configured');
                else
                    analyzer = bms.analyzer.AnalyzerFactory.create('temperature', root, startDate, endDate, statsDir, sub, cfg, pts);
                    plan = plan.addRun(D('temperature'), @() analyzer.run());
                end
            end

            if L('humidity')
                pts = bms.app.EnvironmentStepFactory.resolveClimatePoints(cfg, 'humidity');
                if isempty(pts)
                    plan = plan.addSkip(D('humidity'), 'No humidity points configured');
                else
                    analyzer = bms.analyzer.AnalyzerFactory.create('humidity', root, startDate, endDate, statsDir, sub, cfg, pts);
                    plan = plan.addRun(D('humidity'), @() analyzer.run());
                end
            end

            if L('rainfall')
                pts = bms.app.LegacyStepFunctions.getSensorPoints(cfg, 'rainfall', {});
                if isempty(pts)
                    plan = plan.addSkip(D('rainfall'), 'No rainfall points configured');
                else
                    analyzer = bms.analyzer.AnalyzerFactory.create('rainfall', root, startDate, endDate, statsDir, sub, cfg, pts);
                    plan = plan.addRun(D('rainfall'), @() analyzer.run());
                end
            end
        end

        function plan = appendWindAndEarthquake(plan, root, startDate, endDate, opts, cfg, statsDir, sub)
            L = @(key) bms.module.ModuleRegistry.fromKey(key).isEnabled(opts);
            D = @bms.app.StepDefinition.fromKey;

            if L('wind')
                analyzer = bms.analyzer.AnalyzerFactory.create('wind', root, startDate, endDate, statsDir, sub, cfg, {});
                plan = plan.addRun(D('wind'), @() analyzer.run());
            end
            if L('earthquake')
                analyzer = bms.analyzer.AnalyzerFactory.create('earthquake', root, startDate, endDate, statsDir, sub, cfg, {});
                plan = plan.addRun(D('earthquake'), @() analyzer.run());
            end
        end

        function [points, source] = resolveClimatePoints(cfg, key)
            key = lower(char(string(key)));
            switch key
                case 'temperature'
                    fallback = {'GB-RTS-G05-001-01','GB-RTS-G05-001-02','GB-RTS-G05-001-03'};
                case 'humidity'
                    fallback = {'GB-RHS-G05-001-01','GB-RHS-G05-001-02','GB-RHS-G05-001-03'};
                otherwise
                    error('EnvironmentStepFactory:UnsupportedClimateKey', ...
                        'Unsupported climate module key: %s', key);
            end

            configured = bms.config.ModuleConfigResolver.resolvePoints(cfg, key, {});
            points = bms.app.LegacyStepFunctions.getSensorPoints(cfg, key, fallback);
            if isempty(points)
                if isstruct(cfg) && isfield(cfg, 'points') && isstruct(cfg.points) && ...
                        isfield(cfg.points, key)
                    source = 'explicit_empty';
                else
                    source = 'unresolved';
                end
            elseif isequal(points(:), configured(:))
                source = 'configured';
            else
                source = 'runtime_default';
            end
        end
    end
end
