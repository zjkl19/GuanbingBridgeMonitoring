classdef StepFactory
    %STEPFACTORY Builds the ordered legacy analysis plan from opts/config.

    methods (Static)
        function plan = buildLegacyPlan(root, startDate, endDate, opts, cfg, statsDir, sub)
            plan = bms.app.StepPlan();
            L = @bms.app.LegacyStepFunctions.isEnabled;
            D = @bms.app.StepDefinition.fromKey;

            if L(opts, 'precheck_zip_count')
                plan = plan.addRun(D('zip_precheck'), @() precheck_zip_count(root, startDate, endDate));
            end
            if L(opts, 'doUnzip')
                plan = plan.addRun(D('unzip'), @() batch_unzip_data_parallel(root, startDate, endDate, true));
            end
            if L(opts, 'doRenameCsv')
                plan = plan.addRun(D('rename_csv'), @() batch_rename_csv(root, startDate, endDate, true));
            end
            if L(opts, 'doRemoveHeader')
                plan = plan.addRun(D('remove_header'), @() batch_remove_header(root, startDate, endDate, true));
            end
            if L(opts, 'doResample')
                plan = plan.addRun(D('resample'), @() batch_resample_data_parallel( ...
                    root, startDate, endDate, 100, true, 'batch_resample_data_parallel_config.csv'));
            end

            if L(opts, 'doTemp')
                fallback = {'GB-RTS-G05-001-01','GB-RTS-G05-001-02','GB-RTS-G05-001-03'};
                pts = bms.app.LegacyStepFunctions.getSensorPoints(cfg, 'temperature', fallback);
                if isempty(pts)
                    plan = plan.addSkip(D('temperature'), 'No temperature points configured');
                else
                    plan = plan.addRun(D('temperature'), @() analyze_temperature_points(root, pts, startDate, endDate, fullfile(statsDir, 'temp_stats.xlsx'), sub.temperature, cfg));
                end
            end

            if L(opts, 'doHumidity')
                fallback = {'GB-RHS-G05-001-01','GB-RHS-G05-001-02','GB-RHS-G05-001-03'};
                pts = bms.app.LegacyStepFunctions.getSensorPoints(cfg, 'humidity', fallback);
                if isempty(pts)
                    plan = plan.addSkip(D('humidity'), 'No humidity points configured');
                else
                    plan = plan.addRun(D('humidity'), @() analyze_humidity_points(root, pts, startDate, endDate, fullfile(statsDir, 'humidity_stats.xlsx'), sub.humidity, cfg));
                end
            end

            if L(opts, 'doRainfall')
                pts = bms.app.LegacyStepFunctions.getSensorPoints(cfg, 'rainfall', {});
                if isempty(pts)
                    plan = plan.addSkip(D('rainfall'), 'No rainfall points configured');
                else
                    plan = plan.addRun(D('rainfall'), @() analyze_rainfall_points(root, pts, startDate, endDate, fullfile(statsDir, 'rainfall_stats.xlsx'), sub.rainfall, cfg));
                end
            end

            if L(opts, 'doGNSS')
                pts = bms.app.LegacyStepFunctions.getSensorPoints(cfg, 'gnss', {});
                if isempty(pts)
                    plan = plan.addSkip(D('gnss'), 'No GNSS points configured');
                else
                    plan = plan.addRun(D('gnss'), @() analyze_gnss_points(root, pts, startDate, endDate, fullfile(statsDir, 'gnss_stats.xlsx'), sub.gnss, cfg));
                end
            end

            if L(opts, 'doWind')
                plan = plan.addRun(D('wind'), @() analyze_wind_points(root, startDate, endDate, sub.wind_raw, cfg));
            end
            if L(opts, 'doEq')
                plan = plan.addRun(D('earthquake'), @() analyze_eq_points(root, startDate, endDate, sub.eq_raw, cfg));
            end
            if L(opts, 'doWIM')
                plan = plan.addRun(D('wim'), @() analyze_wim_reports(root, startDate, endDate, cfg));
            end
            if L(opts, 'doDeflect')
                plan = plan.addRun(D('deflection'), @() analyze_deflection_points(root, startDate, endDate, fullfile(statsDir, 'deflection_stats.xlsx'), sub.deflection, cfg));
            end
            if L(opts, 'doBearingDisplacement')
                plan = plan.addRun(D('bearing_displacement'), @() analyze_bearing_displacement_points(root, startDate, endDate, fullfile(statsDir, 'bearing_displacement_stats.xlsx'), sub.bearing_displacement, cfg));
            end
            if L(opts, 'doTilt')
                plan = plan.addRun(D('tilt'), @() analyze_tilt_points(root, startDate, endDate, fullfile(statsDir, 'tilt_stats.xlsx'), sub.tilt, cfg));
            end
            if L(opts, 'doAccel')
                plan = plan.addRun(D('acceleration'), @() analyze_acceleration_points(root, startDate, endDate, fullfile(statsDir, 'accel_stats.xlsx'), sub.accel, true, cfg));
            end
            if L(opts, 'doCableAccel')
                plan = plan.addRun(D('cable_accel'), @() analyze_cable_acceleration_points(root, startDate, endDate, fullfile(statsDir, 'cable_accel_stats.xlsx'), sub.cable_accel, true, cfg));
            end

            if L(opts, 'doAccelSpectrum')
                defaultPts = {'GB-VIB-G04-001-01','GB-VIB-G05-001-01', ...
                    'GB-VIB-G05-002-01','GB-VIB-G05-003-01', ...
                    'GB-VIB-G06-001-01','GB-VIB-G06-002-01', ...
                    'GB-VIB-G06-003-01','GB-VIB-G07-001-01'};
                accelPts = bms.app.LegacyStepFunctions.getPoints(cfg, 'accel_spectrum', bms.app.LegacyStepFunctions.getPoints(cfg, 'acceleration', defaultPts));
                [freqs, tol] = bms.app.LegacyStepFunctions.getAccelSpecParams(cfg);
                plan = plan.addRun(D('accel_spectrum'), @() analyze_accel_spectrum_points(root, startDate, endDate, accelPts, fullfile(statsDir, 'accel_spec_stats.xlsx'), sub.accel_raw, freqs, tol, false, cfg));
            end

            if L(opts, 'doCableAccelSpectrum')
                defaultPts = {'GB-VIB-G04-001-01','GB-VIB-G05-001-01', ...
                    'GB-VIB-G05-002-01','GB-VIB-G05-003-01', ...
                    'GB-VIB-G06-001-01','GB-VIB-G06-002-01', ...
                    'GB-VIB-G06-003-01','GB-VIB-G07-001-01'};
                cablePts = bms.app.LegacyStepFunctions.getPoints(cfg, 'cable_accel_spectrum', ...
                    bms.app.LegacyStepFunctions.getPoints(cfg, 'cable_accel', bms.app.LegacyStepFunctions.getPoints(cfg, 'cable_force', defaultPts)));
                [freqs, tol] = bms.app.LegacyStepFunctions.getCableSpecParams(cfg);
                plan = plan.addRun(D('cable_accel_spectrum'), @() analyze_cable_accel_spectrum_points(root, startDate, endDate, cablePts, fullfile(statsDir, 'cable_accel_spec_stats.xlsx'), sub.cable_accel_raw, freqs, tol, false, cfg));
            end

            if L(opts, 'doRenameCrk')
                plan = plan.addRun(D('rename_crk'), @() batch_rename_crk_T_to_t(root, startDate, endDate, true));
            end
            if L(opts, 'doCrack')
                plan = plan.addRun(D('crack'), @() analyze_crack_points(root, startDate, endDate, fullfile(statsDir, 'crack_stats.xlsx'), sub.crack, cfg));
            end
            if L(opts, 'doStrain')
                plan = plan.addRun(D('strain'), @() analyze_strain_points(root, startDate, endDate, fullfile(statsDir, 'strain_stats.xlsx'), sub.strain, cfg));
            end

            if L(opts, 'doDynStrainBoxplot')
                plan = plan.addRun(D('dynamic_strain_highpass'), @() analyze_dynamic_strain_boxplot( ...
                    root, startDate, endDate, ...
                    'Cfg',         cfg, ...
                    'Subfolder',   sub.strain, ...
                    'OutputDir',   bms.app.LegacyStepFunctions.dynamicHighpassOutputDir(), ...
                    'Fs',          20, ...
                    'Fc',          0.1, ...
                    'Whisker',     300, ...
                    'ShowOutliers', false, ...
                    'YLimManual',  true, ...
                    'YLimRange',   [-30 30], ...
                    'LowerBound',  -150, ...
                    'UpperBound',   30, ...
                    'EdgeTrimSec',   5));
            end

            if L(opts, 'doDynStrainLowpassBoxplot')
                plan = plan.addRun(D('dynamic_strain_lowpass'), @() analyze_dynamic_strain_lowpass_boxplot(root, startDate, endDate, 'Cfg', cfg, 'Subfolder', sub.strain));
            end
        end
    end
end
