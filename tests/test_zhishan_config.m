classdef test_zhishan_config < matlab.unittest.TestCase
    properties
        Root
        ConfigPath
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.Root = fileparts(fileparts(mfilename('fullpath')));
            tc.ConfigPath = fullfile(tc.Root, 'config', 'zhishan_config.json');
            addpath(tc.Root);
            addpath(fullfile(tc.Root, 'config'));
            addpath(fullfile(tc.Root, 'scripts'));
        end
    end

    methods (Test)
        function configMapsZhishanPointIds(tc)
            cfg = load_config(tc.ConfigPath);

            tc.verifyEqual(cfg.vendor, 'zhishan');
            tc.verifyEqual(bms.data.TimeSeriesLoader.resolveFileId(cfg, 'strain', 'SX-1'), 'C1802191464');
            tc.verifyEqual(bms.data.TimeSeriesLoader.resolveFileId(cfg, 'bearing_displacement', 'DX-4'), 'C210419102');
            tc.verifyEqual(bms.data.TimeSeriesLoader.resolveFileId(cfg, 'acceleration', 'AZ-5'), 'C2007120369');
            tc.verifyEqual(bms.data.TimeSeriesLoader.resolveFileId(cfg, 'cable_accel', 'CF-1'), 'C200303008');

            [ok, sx2] = bms.data.PointResolver.getPointConfig(cfg.per_point.strain, 'SX-2', cfg);
            tc.verifyTrue(ok);
            tc.verifyFalse(isfield(sx2.alarm_bounds, 'level1'));
            tc.verifyEqual(sx2.alarm_bounds.level2(:).', [-200, 400]);
            tc.verifyTrue(isfield(sx2, 'source_note'));

            tc.verifyEqual(cfg.defaults.acceleration.thresholds.min, -0.2);
            tc.verifyEqual(cfg.defaults.acceleration.thresholds.max, 0.2);
            tc.verifyFalse(isfield(cfg.defaults.cable_accel, 'thresholds'));
            tc.verifyEqual(cfg.defaults.cable_accel.offset_correction.mode, 'daily_median');
            tc.verifyFalse(isfield(cfg.defaults.cable_accel, 'value_scale'));
            tc.verifyFalse(bms.analyzer.StructuralPlotConfigService.hasGroups(cfg.groups.cable_accel));
            tc.verifyEqual(cfg.defaults.strain.offset_correction.mode, 'first_day_mean');
            tc.verifyEqual(cfg.defaults.bearing_displacement.offset_correction.mode, 'first_day_mean');
            tc.verifyEqual(cfg.per_point.bearing_displacement.DX_1.alarm_bounds.level2(:).', [-80, 80]);
            tc.verifyEqual(cfg.per_point.bearing_displacement.DX_1.alarm_bounds.level3(:).', [-100, 100]);
            tc.verifyEqual(cfg.per_point.bearing_displacement.DX_1.thresholds.min, -100);
            tc.verifyEqual(cfg.per_point.bearing_displacement.DX_1.thresholds.max, 100);
            tc.verifyEqual(cfg.per_point.bearing_displacement.DX_2.thresholds.min, -100);
            tc.verifyEqual(cfg.per_point.bearing_displacement.DX_2.thresholds.max, 100);
            tc.verifyEqual(cfg.per_point.cable_accel.CF_1.thresholds.min, -300);
            tc.verifyEqual(cfg.per_point.cable_accel.CF_1.thresholds.max, 300);
            tc.verifyEqual(cfg.per_point.cable_accel.CF_5.thresholds.min, -100);
            tc.verifyEqual(cfg.per_point.cable_accel.CF_5.thresholds.max, 120);
            tc.verifyEqual(cfg.per_point.cable_accel.CF_7.thresholds.min, -300);
            tc.verifyEqual(cfg.per_point.cable_accel.CF_7.thresholds.max, 300);
        end

        function spectrumTargetsUseConfirmedZhishanFrequencies(tc)
            cfg = load_config(tc.ConfigPath);

            tc.verifyEqual(cfg.accel_spectrum_params.theor_freqs, 0.385);
            tc.verifyEqual(cfg.accel_spectrum_params.tolerance, 0.05);
            tc.verifyEqual(cfg.per_point.accel_spectrum.AZ_1.target_freqs, 0.610);
            tc.verifyEqual(cfg.per_point.accel_spectrum.AZ_2.target_freqs, 0.623);
            tc.verifyEqual(cfg.per_point.accel_spectrum.AZ_3.target_freqs, 0.620);
            tc.verifyEqual(cfg.per_point.accel_spectrum.AZ_4.target_freqs, 0.620);
            tc.verifyEqual(cfg.per_point.accel_spectrum.AZ_5.target_freqs, 0.640);
        end

        function cableForceUsesCableAccelSpectrumParameters(tc)
            cfg = load_config(tc.ConfigPath);
            spec = bms.analyzer.SpectrumAnalysisPipeline.spec('cable_accel_spectrum');

            tc.verifyEqual(spec.moduleKey, 'cable_accel_spectrum');
            tc.verifyEqual(spec.sensorType, 'cable_accel');
            tc.verifyEqual(spec.perPointKey, 'cable_accel');
            tc.verifyTrue(spec.includeForce);

            keys = arrayfun(@(s)s.Key, bms.module.ModuleRegistry.catalog(), 'UniformOutput', false);
            tc.verifyFalse(ismember('cable_force', keys));

            [rho, L, decimals, hasParams] = bms.analyzer.CableForceService.params(cfg, 'CF-1');
            tc.verifyTrue(hasParams);
            tc.verifyEqual(rho, 57.687);
            tc.verifyEqual(L, 75.61);
            tc.verifyEqual(decimals, 2);

            [ok, cf1] = bms.data.PointResolver.getPointConfig(cfg.per_point.cable_accel, 'CF-1', cfg);
            tc.verifyTrue(ok);
            tc.verifyEqual(cf1.target_freqs, 1.621);
            tc.verifyEqual(cf1.ocr_force_kN, 3466);
            tc.verifyEqual(cf1.completed_force_kN, 3496);
            force = bms.analyzer.CableForceService.compute(cf1.target_freqs, rho, L, decimals);
            tc.verifyEqual(force(1), cf1.force_baseline_kN, 'AbsTol', 0.02);
        end

        function stagingCopiesOnlyConfiguredZhishanIds(tc)
            sourceRoot = tempname;
            targetRoot = tempname;
            cleanup = onCleanup(@() local_cleanup({sourceRoot, targetRoot})); %#ok<NASGU>
            waveDir = fullfile(sourceRoot, '2026-03-03', '波形');
            mkdir(waveDir);
            local_write_csv(fullfile(waveDir, 'C1802191464_1.csv'));
            local_write_csv(fullfile(waveDir, 'C200303008_21.csv'));
            local_write_csv(fullfile(waveDir, 'UNRELATED_1.csv'));

            summary = stage_zhishan_subset( ...
                'SourceRoot', sourceRoot, ...
                'TargetRoot', targetRoot, ...
                'ConfigPath', tc.ConfigPath, ...
                'StartDate', '2026-03-03', ...
                'EndDate', '2026-03-03');

            tc.verifyEqual(summary.copied_files, 2);
            tc.verifyTrue(isfile(fullfile(targetRoot, '2026-03-03', '波形', 'C1802191464_1.csv')));
            tc.verifyTrue(isfile(fullfile(targetRoot, '2026-03-03', '波形', 'C200303008_21.csv')));
            tc.verifyFalse(isfile(fullfile(targetRoot, '2026-03-03', '波形', 'UNRELATED_1.csv')));
        end
    end
end

function local_write_csv(path)
    fid = fopen(path, 'w');
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '开始时间: 2026-03-03 00:00:00.000\n');
    fprintf(fid, '序列号: test\n');
    fprintf(fid, '通道号: test\n');
    fprintf(fid, '2026-03-03 00:00:00.000,1.0\n');
end

function local_cleanup(paths)
    for i = 1:numel(paths)
        if isfolder(paths{i})
            rmdir(paths{i}, 's');
        end
    end
end
