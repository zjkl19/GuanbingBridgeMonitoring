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
            lint = bms.config.ConfigLinter.lint(cfg);
            tc.verifyEqual(lint.status, 'ok', strjoin(lint.warnings, newline));

            tc.verifyEqual(cfg.vendor, 'zhishan');
            tc.verifyEqual(bms.data.TimeSeriesLoader.resolveFileId(cfg, 'strain', 'SX-1'), 'C1802191464');
            tc.verifyEqual(bms.data.TimeSeriesLoader.resolveFileId(cfg, 'bearing_displacement', 'DX-4'), 'C210419102');
            tc.verifyEqual(bms.data.TimeSeriesLoader.resolveFileId(cfg, 'acceleration', 'AZ-5'), 'C2007120369');
            tc.verifyEqual(bms.data.TimeSeriesLoader.resolveFileId(cfg, 'cable_accel', 'CF-1'), 'C200303008');

            [ok, sx2] = bms.data.PointResolver.getPointConfig(cfg.per_point.strain, 'SX-2', cfg);
            tc.verifyTrue(ok);
            tc.verifyFalse(isfield(sx2.alarm_bounds, 'level1'));
            tc.verifyEqual(sx2.alarm_bounds.level2(:).', [-283, 414]);
            tc.verifyTrue(isfield(sx2, 'source_note'));
            tc.verifyEqual(cfg.per_point.strain.SX_3.alarm_bounds.level2(:).', [-218, 298]);
            tc.verifyEqual(cfg.per_point.strain.SX_4.alarm_bounds.level2(:).', [-218, 298]);
            tc.verifyEqual(cfg.per_point.strain.SX_5.alarm_bounds.level2(:).', [-252, 405]);
            tc.verifyEqual(cfg.per_point.strain.SX_6.alarm_bounds.level2(:).', [-252, 405]);
            tc.verifyEqual(cfg.per_point.strain.SX_10.alarm_bounds.level2(:).', [-283, 414]);
            tc.verifyEqual([cfg.per_point.strain.SX_1.thresholds.min], -283);
            tc.verifyEqual([cfg.per_point.strain.SX_1.thresholds.max], 414);
            tc.verifyEqual(cfg.per_point.strain.SX_1.thresholds.t_range_start, '2026-04-01 00:00:00');
            tc.verifyEqual(cfg.per_point.strain.SX_1.thresholds.t_range_end, '2026-06-30 23:59:59');
            tc.verifyEqual([cfg.per_point.strain.SX_3.thresholds.min], -218);
            tc.verifyEqual([cfg.per_point.strain.SX_3.thresholds.max], 298);
            tc.verifyEqual([cfg.per_point.strain.SX_5.thresholds.min], -252);
            tc.verifyEqual([cfg.per_point.strain.SX_5.thresholds.max], 200);
            tc.verifyEqual(cfg.per_point.strain.SX_5.thresholds.t_range_end, '2026-06-30 23:59:59');
            tc.verifyEqual([cfg.per_point.strain.SX_6.thresholds.max], 200);
            tc.verifyEqual([cfg.per_point.strain.SX_7.thresholds.max], 298);
            tc.verifyEqual([cfg.per_point.strain.SX_8.thresholds.max], 200);
            tc.verifyEqual(fieldnames(cfg.groups.strain), {'SX_L2_414_283'; 'SX_L2_298_218'; 'SX_L2_405_252'});
            tc.verifyEqual(cfg.groups.strain.SX_L2_414_283(:).', {'SX-1', 'SX-2', 'SX-9', 'SX-10'});
            tc.verifyEqual(cfg.groups.strain.SX_L2_298_218(:).', {'SX-3', 'SX-4', 'SX-7', 'SX-8'});
            tc.verifyEqual(cfg.groups.strain.SX_L2_405_252(:).', {'SX-5', 'SX-6'});
            tc.verifyEqual(fieldnames(cfg.groups.dynamic_strain), fieldnames(cfg.groups.strain));
            tc.verifyEqual(fieldnames(cfg.groups.dynamic_strain_lowpass), fieldnames(cfg.groups.strain));
            tc.verifyEqual(cfg.groups.dynamic_strain.SX_L2_414_283(:).', cfg.groups.strain.SX_L2_414_283(:).');
            tc.verifyEqual(cfg.groups.dynamic_strain_lowpass.SX_L2_405_252(:).', cfg.groups.strain.SX_L2_405_252(:).');
            dynSx1 = resolve_post_filter_thresholds(cfg, 'dynamic_strain', 'SX-1');
            tc.verifyEqual([dynSx1.min], -283);
            tc.verifyEqual([dynSx1.max], 414);
            tc.verifyEqual(dynSx1.t_range_start, '2026-04-01 00:00:00');
            dynSx3 = resolve_post_filter_thresholds(cfg, 'dynamic_strain', 'SX-3');
            tc.verifyEqual([dynSx3.min], -218);
            tc.verifyEqual([dynSx3.max], 298);
            dynSx5 = resolve_post_filter_thresholds(cfg, 'dynamic_strain', 'SX-5');
            tc.verifyEqual([dynSx5.min], -252);
            tc.verifyEqual([dynSx5.max], 200);
            dynSx8 = resolve_post_filter_thresholds(cfg, 'dynamic_strain', 'SX-8');
            tc.verifyEqual([dynSx8.max], 200);
            lowSx3 = resolve_post_filter_thresholds(cfg, 'dynamic_strain_lowpass', 'SX-3');
            tc.verifyEqual([lowSx3.max], [20, 298]);
            tc.verifyEqual({lowSx3.t_range_start}, {'2026-03-01 00:00:00', '2026-04-01 00:00:00'});
            tc.verifyEqual({lowSx3.t_range_end}, {'2026-03-31 23:59:59', '2026-06-30 23:59:59'});
            lowSx4 = resolve_post_filter_thresholds(cfg, 'dynamic_strain_lowpass', 'SX-4');
            tc.verifyEqual([lowSx4.max], [20, 298]);
            lowSx5 = resolve_post_filter_thresholds(cfg, 'dynamic_strain_lowpass', 'SX-5');
            tc.verifyEqual([lowSx5.max], [20, 200]);
            lowSx6 = resolve_post_filter_thresholds(cfg, 'dynamic_strain_lowpass', 'SX-6');
            tc.verifyEqual([lowSx6.max], [20, 200]);
            lowSx8 = resolve_post_filter_thresholds(cfg, 'dynamic_strain_lowpass', 'SX-8');
            tc.verifyEqual([lowSx8.min], -218);
            tc.verifyEqual([lowSx8.max], 200);
            lowSx10 = resolve_post_filter_thresholds(cfg, 'dynamic_strain_lowpass', 'SX-10');
            tc.verifyEqual([lowSx10.max], 414);

            tc.verifyEqual(cfg.defaults.acceleration.thresholds.min, -0.2);
            tc.verifyEqual(cfg.defaults.acceleration.thresholds.max, 0.2);
            tc.verifyFalse(isfield(cfg.defaults.cable_accel, 'thresholds'));
            tc.verifyEqual(cfg.defaults.cable_accel.offset_correction.mode, 'daily_median');
            tc.verifyFalse(isfield(cfg.defaults.cable_accel, 'value_scale'));
            tc.verifyFalse(bms.analyzer.StructuralPlotConfigService.hasGroups(cfg.groups.cable_accel));
            tc.verifyFalse(isfield(cfg.defaults.strain, 'offset_correction'));
            tc.verifyFalse(isfield(cfg.defaults, 'bearing_displacement'));
            tc.verifyEqual(cfg.per_point.strain.SX_1.offset_correction, 22.72326076, 'AbsTol', 1e-9);
            tc.verifyEqual(cfg.per_point.strain.SX_10.offset_correction, -14.0941581, 'AbsTol', 1e-9);
            tc.verifyEqual(cfg.per_point.bearing_displacement.DX_1.offset_correction, 34.36897508, 'AbsTol', 1e-9);
            tc.verifyEqual(cfg.per_point.bearing_displacement.DX_4.offset_correction, 37.49498676, 'AbsTol', 1e-9);
            tc.verifyEqual(cfg.per_point.bearing_displacement.DX_1.alarm_bounds.level2(:).', [-80, 80]);
            tc.verifyEqual(cfg.per_point.bearing_displacement.DX_1.alarm_bounds.level3(:).', [-100, 100]);
            tc.verifyEqual([cfg.per_point.bearing_displacement.DX_1.thresholds.min], [-100, -80]);
            tc.verifyEqual([cfg.per_point.bearing_displacement.DX_1.thresholds.max], [100, 80]);
            tc.verifyEqual({cfg.per_point.bearing_displacement.DX_1.thresholds.t_range_start}, {'2026-03-01 00:00:00', '2026-04-01 00:00:00'});
            tc.verifyEqual({cfg.per_point.bearing_displacement.DX_1.thresholds.t_range_end}, {'2026-03-31 23:59:59', '2026-06-30 23:59:59'});
            tc.verifyEqual([cfg.per_point.bearing_displacement.DX_2.thresholds.min], [-100, -80]);
            tc.verifyEqual([cfg.per_point.bearing_displacement.DX_2.thresholds.max], [100, 80]);
            tc.verifyEqual(cfg.per_point.cable_accel.CF_1.offset_correction.mode, 'fixed');
            tc.verifyEqual(cfg.per_point.cable_accel.CF_1.offset_correction.value, -2000);
            tc.verifyEqual(cfg.per_point.cable_accel.CF_1.offset_correction.end_date, '2026-06-30');
            tc.verifyEqual(cfg.per_point.cable_accel.CF_2.offset_correction.value, -2000);
            tc.verifyEqual(cfg.per_point.cable_accel.CF_3.offset_correction.value, 29600);
            tc.verifyEqual(cfg.per_point.cable_accel.CF_4.offset_correction.value, 29600);
            tc.verifyEqual(cfg.per_point.cable_accel.CF_5.offset_correction.value, 29800);
            tc.verifyEqual(cfg.per_point.cable_accel.CF_6.offset_correction.value, -200);
            tc.verifyEqual(cfg.per_point.cable_accel.CF_7.offset_correction.value, -1500);
            tc.verifyEqual(cfg.per_point.cable_accel.CF_8.offset_correction.value, 2000);
            tc.verifyEqual(cfg.per_point.cable_accel.CF_8.offset_correction.end_date, '2026-06-30');
            tc.verifyEqual([cfg.per_point.cable_accel.CF_1.thresholds.min], [-500, -500]);
            tc.verifyEqual([cfg.per_point.cable_accel.CF_1.thresholds.max], [500, 500]);
            tc.verifyEqual([cfg.per_point.cable_accel.CF_5.thresholds.min], [-100, -500]);
            tc.verifyEqual([cfg.per_point.cable_accel.CF_5.thresholds.max], [140, 500]);
            tc.verifyEqual([cfg.per_point.cable_accel.CF_6.thresholds.min], [-100, -3000]);
            tc.verifyEqual([cfg.per_point.cable_accel.CF_6.thresholds.max], [100, 3000]);
            tc.verifyEqual([cfg.per_point.cable_accel.CF_8.thresholds.min], [-500, -500]);
            tc.verifyEqual([cfg.per_point.cable_accel.CF_8.thresholds.max], [500, 500]);
            tc.verifyEqual({cfg.per_point.cable_accel.CF_8.thresholds.t_range_start}, {'2026-03-01 00:00:00', '2026-04-01 00:00:00'});
            tc.verifyEqual({cfg.per_point.cable_accel.CF_8.thresholds.t_range_end}, {'2026-03-31 23:59:59', '2026-06-30 23:59:59'});
            tc.verifyTrue(cfg.plot_styles.cable_accel.ylim_auto);
            tc.verifyEmpty(cfg.plot_styles.cable_accel.ylim);
            tc.verifyEmpty(cfg.plot_styles.cable_accel.ylims);
            tc.verifyTrue(contains(cfg.plot_styles.cable_accel.ylabel, 'mm/s^2'));
            tc.verifyTrue(contains(cfg.plot_styles.cable_accel.rms_ylabel, 'mm/s^2'));
            tc.verifyEqual(numel(cfg.plot_styles.cable_accel.group_warn_lines), 2);
            tc.verifyEqual(sort([cfg.plot_styles.cable_accel.group_warn_lines.y]).', [-500; 500]);
            tc.verifyEqual(cfg.plot_common.gap_mode, 'connect');
            tc.verifyEqual(cfg.defaults.dynamic_strain.LowerBound, -60);
            tc.verifyEqual(cfg.defaults.dynamic_strain.UpperBound, 40);
            tc.verifyEqual(cfg.defaults.dynamic_strain.ChunkDays, 1);
            tc.verifyEqual(cfg.defaults.dynamic_strain.ChunkOverlapSec, 300);
            tc.verifyEqual(cfg.plot_styles.dynamic_strain.output_dir_ts, '时程曲线_动应变_高通滤波');
            tc.verifyEqual(cfg.plot_styles.dynamic_strain.group_output_dir_ts, '时程曲线_动应变_高通滤波_组图');
            tc.verifyTrue(isfield(cfg.defaults, 'dynamic_strain_lowpass'));
            tc.verifyTrue(logical(cfg.defaults.dynamic_strain_lowpass.DownsampleBeforeFilter));
            tc.verifyEqual(cfg.defaults.dynamic_strain_lowpass.DownsampleSec, 60);
            tc.verifyEqual(cfg.plot_styles.dynamic_strain_lowpass.output_dir_ts, '时程曲线_动应变_低通滤波');
            tc.verifyEqual(cfg.plot_styles.dynamic_strain_lowpass.group_output_dir_ts, '时程曲线_动应变_低通滤波_组图');
        end

        function spectrumTargetsUseConfirmedZhishanFrequencies(tc)
            cfg = load_config(tc.ConfigPath);

            tc.verifyEqual(cfg.accel_spectrum_params.theor_freqs, 0.593);
            tc.verifyEqual(cfg.accel_spectrum_params.tolerance, 0.02);
            tc.verifyEqual(cfg.accel_spectrum_params.peak_orders.search_half_width_hz, 0.02);

            pointFields = {'AZ_1', 'AZ_2', 'AZ_3', 'AZ_4', 'AZ_5'};
            for k = 1:numel(pointFields)
                pointCfg = cfg.per_point.accel_spectrum.(pointFields{k});
                tc.verifyEqual(pointCfg.target_freqs, 0.640);
                tc.verifyEqual(pointCfg.tolerance, 0.02);
                tc.verifyEqual(pointCfg.peak_orders.search_half_width_hz, 0.02);
            end
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
            tc.verifyEqual(cf1.force_alarm_bounds.level2(:).', [3146, 3846]);
            tc.verifyEqual(cf1.force_alarm_bounds.level3(:).', [2972, 4020]);
            force = bms.analyzer.CableForceService.compute(cf1.target_freqs, rho, L, decimals);
            tc.verifyEqual(force(1), cf1.force_baseline_kN, 'AbsTol', 0.02);

            [ok, cf3] = bms.data.PointResolver.getPointConfig(cfg.per_point.cable_accel, 'CF-3', cfg);
            tc.verifyTrue(ok);
            tc.verifyTrue(cf3.force_reference_from_target);
            tc.verifyEqual(bms.analyzer.CableForceService.referenceFrequency(cfg, 'CF-3'), 1.4665);
            tc.verifyEqual(cf3.force_alarm_bounds.level2(:).', [3419, 4179]);
            tc.verifyEqual(cf3.force_alarm_bounds.level3(:).', [3229, 4369]);
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

        function stagingExtractsOnlyConfiguredZhishanIdsFromZip(tc)
            sourceRoot = tempname;
            targetRoot = tempname;
            zipWorkRoot = tempname;
            cleanup = onCleanup(@() local_cleanup({sourceRoot, targetRoot, zipWorkRoot})); %#ok<NASGU>
            waveDir = fullfile(sourceRoot, '2026-04-01', '波形');
            csvDir = fullfile(zipWorkRoot, 'payload');
            mkdir(waveDir);
            mkdir(csvDir);
            local_write_csv(fullfile(csvDir, 'C1802191464_1.csv'));
            local_write_csv(fullfile(csvDir, 'C200303008_21.csv'));
            local_write_csv(fullfile(csvDir, 'UNRELATED_1.csv'));
            zip(fullfile(waveDir, 'mixed.zip'), {'C1802191464_1.csv', 'C200303008_21.csv', 'UNRELATED_1.csv'}, csvDir);

            summary = stage_zhishan_subset( ...
                'SourceRoot', sourceRoot, ...
                'TargetRoot', targetRoot, ...
                'ConfigPath', tc.ConfigPath, ...
                'StartDate', '2026-04-01', ...
                'EndDate', '2026-04-01', ...
                'SourceMode', 'zip');

            tc.verifyEqual(summary.source_files, 2);
            tc.verifyEqual(summary.extracted_files, 2);
            tc.verifyTrue(contains(fileread(summary.copied_paths{1}), '1.0'), ...
                'Extracted CSV content should be preserved, not zero-filled.');
            tc.verifyTrue(isfile(fullfile(targetRoot, '2026-04-01', '波形', 'C1802191464_1.csv')));
            tc.verifyTrue(isfile(fullfile(targetRoot, '2026-04-01', '波形', 'C200303008_21.csv')));
            tc.verifyFalse(isfile(fullfile(targetRoot, '2026-04-01', '波形', 'UNRELATED_1.csv')));
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
