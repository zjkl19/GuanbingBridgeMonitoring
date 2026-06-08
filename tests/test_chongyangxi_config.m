classdef test_chongyangxi_config < matlab.unittest.TestCase
    properties
        Root
        ConfigPath
        TempDir
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.Root = fileparts(fileparts(mfilename('fullpath')));
            tc.ConfigPath = fullfile(tc.Root, 'config', 'chongyangxi_config.json');
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            addpath(tc.Root);
            addpath(fullfile(tc.Root, 'config'));
            addpath(fullfile(tc.Root, 'pipeline'));
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if exist(tc.TempDir, 'dir')
                rmdir(tc.TempDir, 's');
            end
        end
    end

    methods (Test)
        function configMapsChongyangxiPoints(tc)
            cfg = load_config(tc.ConfigPath);
            lint = bms.config.ConfigLinter.lint(cfg);
            tc.verifyEqual(lint.status, 'ok', strjoin(lint.warnings, newline));

            tc.verifyEqual(cfg.vendor, 'chongyangxi');
            tc.verifyEqual(cfg.bridge_id, 'chongyangxi');
            tc.verifyEqual(numel(cfg.points.strain), 8);
            tc.verifyEqual(numel(cfg.points.deflection), 36);
            tc.verifyEqual(numel(cfg.points.tilt), 6);
            tc.verifyEqual(numel(cfg.points.acceleration), 2);
            tc.verifyEqual(numel(cfg.points.crack), 3);

            tc.verifyEqual(bms.data.TimeSeriesLoader.resolveFileId( ...
                cfg, 'deflection', 'CYX-DIS-G02-010-01-Y'), '新增测点24');
            tc.verifyEqual(bms.data.TimeSeriesLoader.resolveFileId( ...
                cfg, 'strain', 'CYX-RSG-G05-005-01'), 'CYX-RSG-G05-005-01');
            tc.verifyEqual(cfg.subfolders.deflection, '特征值');
            tc.verifyEqual(cfg.defaults.tilt.alarm_bounds.level2(:).', [-0.08, 0.08]);

            profile = bms.profile.BridgeProfileRegistry.fromId('chongyangxi', tc.Root);
            tc.verifyTrue(any(strcmp(profile.EnabledModuleHints, 'dynamic_strain_highpass')));
            tc.verifyTrue(any(strcmp(profile.EnabledModuleHints, 'dynamic_strain_lowpass')));
            tc.verifyEqual(profile.BridgeName, '崇阳溪大桥');
            inferred = bms.profile.BridgeProfileRegistry.infer(cfg, 'D:/崇阳溪数据');
            tc.verifyEqual(inferred.BridgeId, 'chongyangxi');

            tc.verifyEqual(numel(fieldnames(cfg.groups.strain)), 4);
            tc.verifyEqual(numel(fieldnames(cfg.groups.dynamic_strain)), 4);
            tc.verifyEqual(numel(fieldnames(cfg.groups.deflection)), 8);
            tc.verifyEqual(cfg.groups.deflection.A_3rd_span_5_12(:).', ...
                {'CYX-DIS-G05-005-01-Y', 'CYX-DIS-G05-012-01-Y'});
            tc.verifyEqual(cfg.groups.deflection.A_3rd_span_7_10(:).', ...
                {'CYX-DIS-G05-007-01-Y', 'CYX-DIS-G05-010-01-Y'});
            tc.verifyEqual(cfg.groups.deflection.B_1st_span_5_12(:).', ...
                {'CYX-DIS-G02-005-01-Y', 'CYX-DIS-G02-012-01-Y'});
            tc.verifyEqual(cfg.groups.deflection.B_1st_span_7_10(:).', ...
                {'CYX-DIS-G02-007-01-Y', 'CYX-DIS-G02-010-01-Y'});
            defSpec = bms.analyzer.StructuralFilteredSeriesPipeline.spec('deflection');
            [defGroups, defGroupNames] = bms.analyzer.StructuralFilteredSeriesService.deflectionGroupsWithNames(cfg, defSpec);
            tc.verifyEqual(numel(defGroups), 8);
            tc.verifyEqual(defGroupNames(1:2).', {'A_3rd_span_5_12', 'A_3rd_span_7_10'});
            tc.verifyEqual( ...
                bms.analyzer.StructuralFilteredSeriesPipeline.deflectionSingleOutputDir( ...
                cfg.plot_styles.deflection, defSpec), '时程曲线_主梁挠度');
            tc.verifyEqual( ...
                bms.analyzer.StructuralFilteredSeriesPipeline.deflectionGroupOutputDir( ...
                cfg.plot_styles.deflection, defSpec), '时程曲线_主梁挠度_组图');
            tc.verifyEqual(cfg.plot_styles.deflection.group_labels.A_3rd_span_5_12, ...
                'A截面 第3跨5#、12#梁');
            tc.verifyEqual(cfg.plot_styles.deflection.group_labels.B_1st_span_7_10, ...
                'B截面 第1跨7#、10#梁');
            tc.verifyLessThan(cfg.dynamic_strain.fc, 0.009);
            tc.verifyFalse(logical(cfg.defaults.dynamic_strain.YLimManual));
            tc.verifyEqual(cfg.defaults.dynamic_strain_lowpass.LowerBound, -1000);
            tc.verifyEqual(cfg.defaults.dynamic_strain_lowpass.UpperBound, 1000);
            [ok, sx5] = bms.data.PointResolver.getPointConfig( ...
                cfg.per_point.strain, 'CYX-RSG-G05-005-01', cfg);
            tc.verifyTrue(ok);
            tc.verifyEqual(sx5.alarm_bounds.level2(:).', [-62, 62]);
            tc.verifyEqual(sx5.alarm_bounds.level3(:).', [-77, 77]);
            [ok, sx7] = bms.data.PointResolver.getPointConfig( ...
                cfg.per_point.strain, 'CYX-RSG-G05-007-01', cfg);
            tc.verifyTrue(ok);
            tc.verifyEqual(sx7.alarm_bounds.level2(:).', [-78, 78]);
            tc.verifyEqual(sx7.alarm_bounds.level3(:).', [-98, 98]);

            [ok, bearing] = bms.data.PointResolver.getPointConfig( ...
                cfg.per_point.bearing_displacement, 'CYX-DIS-G07-005-01', cfg);
            tc.verifyTrue(ok);
            tc.verifyEqual(bearing.alarm_bounds.level2(:).', [-80, 80]);
            tc.verifyEqual(bearing.alarm_bounds.level3(:).', [-100, 100]);
            [ok, tiltY] = bms.data.PointResolver.getPointConfig( ...
                cfg.per_point.tilt, 'CYX-INC-P01-001-01-Y', cfg);
            tc.verifyTrue(ok);
            tc.verifyEqual(tiltY.alarm_bounds.level2(:).', [-0.08, 0.08]);
            tc.verifyEqual(tiltY.alarm_bounds.level3(:).', [-0.1, 0.1]);
            tc.verifyEqual(numel(cfg.plot_styles.tilt.warn_lines), 4);
            tiltSpec = bms.analyzer.StructuralFilteredSeriesPipeline.spec('tilt');
            tc.verifyEqual( ...
                bms.analyzer.StructuralFilteredSeriesPipeline.tiltSingleOutputDir( ...
                cfg.plot_styles.tilt, tiltSpec), '时程曲线_墩身倾角');
            tc.verifyEqual( ...
                bms.analyzer.StructuralFilteredSeriesPipeline.tiltGroupOutputDir( ...
                cfg.plot_styles.tilt, tiltSpec), '时程曲线_墩身倾角_组图');

            tc.verifyEqual(cfg.accel_spectrum_params.target_freqs(:).', 3.2);
            tc.verifyEqual(cfg.accel_spectrum_params.theor_freqs(:).', 2.83);
            tc.verifyEqual(cfg.accel_spectrum_params.theor_labels{1}, '理论竖向一阶自振频率 2.83Hz');
            tc.verifyEqual(cfg.accel_spectrum_params.tolerance, 0.15);
            tc.verifyEqual(cfg.plot_styles.acceleration.group_output_dir, '时程曲线_加速度_组图');
            tc.verifyTrue(contains(cfg.plot_styles.acceleration.ylabel, 'mm/s^2'));
            tc.verifyTrue(contains(cfg.plot_styles.acceleration.rms_ylabel, 'mm/s^2'));
            tc.verifyEqual(cfg.plot_styles.acceleration.warn_unit, 'mm/s^2');
            tc.verifyEqual(numel(cfg.plot_styles.acceleration.rms_warn_lines), 2);
            tc.verifyEqual([cfg.plot_styles.acceleration.rms_warn_lines.y], [315, 500]);
            tc.verifyTrue(cfg.plot_styles.crack.per_point_plot);
            tc.verifyTrue(cfg.plot_styles.crack.group_plot);
            tc.verifyEqual(cfg.plot_styles.crack.single_output_dir_crack, '时程曲线_裂缝宽度');
            tc.verifyEqual(cfg.plot_styles.crack.group_output_dir_crack, '时程曲线_裂缝宽度_组图');
        end

        function rangeLoaderReadsNestedExportEndDayFolder(tc)
            cfg = struct();
            cfg.vendor = 'chongyangxi';
            cfg.defaults = struct('header_marker', '[绝对时间]');
            cfg.subfolders = struct('strain', '特征值');
            cfg.file_patterns = struct('strain', struct('default', '{file_id}_*.csv'));
            cfg.per_point = struct('strain', struct('PT_1', struct('file_id', 'PT-1')));
            cfg.points = struct('strain', {{'PT-1'}});
            cfg.groups = struct();
            cfg.plot_styles = struct();

            exportDir = fullfile(tc.TempDir, '2025-05-21', '特征值', 'uuid-001');
            mkdir(exportDir);
            local_write_donghua_csv(fullfile(exportDir, 'PT-1_峰值_原始数据_1-1.csv'), ...
                {'2025-05-19 23:59:59.000', '2025-05-20 08:00:00.000', '2025-05-20 12:00:00.000', '2025-05-21 00:00:00.000'}, ...
                [0, 1, 2, 3]);

            [t, v, meta] = load_timeseries_range(tc.TempDir, '特征值', 'PT-1', ...
                '2025-05-20', '2025-05-20', cfg, 'strain');

            tc.verifyEqual(numel(v), 2);
            tc.verifyEqual(v(:).', [1, 2]);
            tc.verifyEqual(t(1), datetime(2025, 5, 20, 8, 0, 0));
            tc.verifyEqual(numel(meta.files), 1);
            tc.verifyTrue(contains(meta.files{1}, 'uuid-001'));
        end

        function deflectionLoaderUsesFeatureFolderAndFileId(tc)
            cfg = struct();
            cfg.vendor = 'chongyangxi';
            cfg.defaults = struct('header_marker', '[绝对时间]');
            cfg.subfolders = struct('deflection', '特征值');
            cfg.file_patterns = struct('deflection', struct('default', '{file_id}_*.csv'));
            cfg.per_point = struct('deflection', struct('CYX_DIS_G02_010_01_Y', ...
                struct('file_id', '新增测点24')));
            cfg.points = struct('deflection', {{'CYX-DIS-G02-010-01-Y'}});
            cfg.groups = struct();
            cfg.plot_styles = struct();

            featureDir = fullfile(tc.TempDir, '2025-05-21', '特征值', 'uuid-feature');
            waveDir = fullfile(tc.TempDir, '2025-05-21', '波形', 'uuid-wave');
            mkdir(featureDir);
            mkdir(waveDir);
            local_write_donghua_csv(fullfile(featureDir, '新增测点24_485缓变量_原始数据_1-41-24.csv'), ...
                {'2025-05-19 23:59:59.000', '2025-05-20 08:00:00.000', '2025-05-20 12:00:00.000'}, ...
                [99, 24, 25]);
            local_write_donghua_csv(fullfile(waveDir, '新增测点24_原始数据_1-41-24.csv'), ...
                {'2025-05-20 08:00:00.000'}, ...
                [-999]);

            [t, v, meta] = load_timeseries_range(tc.TempDir, cfg.subfolders.deflection, ...
                'CYX-DIS-G02-010-01-Y', '2025-05-20', '2025-05-20', cfg, 'deflection');

            tc.verifyEqual(v(:).', [24, 25]);
            tc.verifyEqual(t(1), datetime(2025, 5, 20, 8, 0, 0));
            tc.verifyEqual(numel(meta.files), 1);
            tc.verifyTrue(contains(meta.files{1}, '特征值'));
            tc.verifyFalse(contains(meta.files{1}, '波形'));
        end
    end
end

function local_write_donghua_csv(path, times, values)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '开始时间,%s\n', times{1});
    fprintf(fid, '序列号,unit\n');
    fprintf(fid, '通道号,1\n');
    fprintf(fid, '测点路径,unit\n');
    fprintf(fid, '采样频率,20\n');
    fprintf(fid, '通道名称,1-1\n');
    fprintf(fid, '[绝对时间],PT-1[unit]\n');
    for i = 1:numel(values)
        fprintf(fid, '%s,%.3f\n', times{i}, values(i));
    end
end
