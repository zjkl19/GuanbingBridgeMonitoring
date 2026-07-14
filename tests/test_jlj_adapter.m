classdef test_jlj_adapter < matlab.unittest.TestCase
    % Tests for Jiulongjiang adapter in load_timeseries_range

    properties
        ProjectRoot
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(testCase.ProjectRoot, ...
                    fullfile(testCase.ProjectRoot, 'config'), ...
                    fullfile(testCase.ProjectRoot, 'pipeline'), ...
                    fullfile(testCase.ProjectRoot, 'analysis'));
        end
    end

    methods (Test)
        function test_temperature_single_channel(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            pid = 'WDCGQ-01-K16-X4-G20';
            testCase.assumeTrue(exist(sample_path(testCase.ProjectRoot, pid), 'file') == 2);
            root = fullfile(testCase.ProjectRoot, 'tests','data','_samples','jlj');
            [t, v] = load_timeseries_range(root, '', pid, '2026-01-01', '2026-01-01', cfg, 'temperature');
            testCase.verifyNotEmpty(v);
            testCase.verifyEqual(numel(t), numel(v));
            cachePath = sample_cache_path(testCase.ProjectRoot, pid);
            testCase.verifyTrue(exist(cachePath, 'file') == 2);
        end

        function test_humidity_single_channel(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            pid = 'WSDJ-01-K15-X1-G18';
            testCase.assumeTrue(exist(sample_path(testCase.ProjectRoot, pid), 'file') == 2);
            root = fullfile(testCase.ProjectRoot, 'tests','data','_samples','jlj');
            [t, v] = load_timeseries_range(root, '', pid, '2026-01-01', '2026-01-01', cfg, 'humidity');
            testCase.verifyNotEmpty(v);
            testCase.verifyEqual(numel(t), numel(v));
        end

        function test_humidity_file_id_alias(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            designId = 'WSD-01-11#-S11';
            fileId = 'WSD-01-11#-S02机箱';
            cfg.per_point.humidity = struct();
            cfg.per_point.humidity.(bms.data.PointResolver.legacySafeId(designId)) = struct('file_id', fileId);
            write_jlj_xy_csv(root, datetime(2026,1,1), fileId, [18.5; 19.5], [62.5; 63.5]);

            [t, v] = load_timeseries_range(root, '', designId, '2026-01-01', '2026-01-01', cfg, 'humidity');

            testCase.verifyEqual(numel(t), 2);
            testCase.verifyEqual(v(:), [62.5; 63.5], 'AbsTol', 1e-10);
        end

        function test_temperature_file_id_alias_uses_x_channel(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            designId = 'WSD-01-11#-S11';
            fileId = 'WSD-01-11#-S02机箱';
            cfg.per_point.temperature = struct();
            cfg.per_point.temperature.(bms.data.PointResolver.legacySafeId(designId)) = struct('file_id', fileId);
            write_jlj_xy_csv(root, datetime(2026,1,1), fileId, [18.5; 19.5], [62.5; 63.5]);

            [t, v] = load_timeseries_range(root, '', designId, '2026-01-01', '2026-01-01', cfg, 'temperature');

            testCase.verifyEqual(numel(t), 2);
            testCase.verifyEqual(v(:), [18.5; 19.5], 'AbsTol', 1e-10);
        end

        function test_wind_speed_direction(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            pid = 'CSFSY-01-K16-GD-A20';
            testCase.assumeTrue(exist(sample_path(testCase.ProjectRoot, pid), 'file') == 2);
            root = fullfile(testCase.ProjectRoot, 'tests','data','_samples','jlj');
            [t1, v1] = load_timeseries_range(root, '', pid, '2026-01-01', '2026-01-01', cfg, 'wind_speed');
            [t2, v2] = load_timeseries_range(root, '', pid, '2026-01-01', '2026-01-01', cfg, 'wind_direction');
            testCase.verifyNotEmpty(v1);
            testCase.verifyNotEmpty(v2);
            testCase.verifyEqual(numel(t1), numel(v1));
            testCase.verifyEqual(numel(t2), numel(v2));
        end

        function test_tilt_xy(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            base = 'QJJ-05-BZD-B5';
            testCase.assumeTrue(exist(sample_path(testCase.ProjectRoot, base), 'file') == 2);
            root = fullfile(testCase.ProjectRoot, 'tests','data','_samples','jlj');
            [tX, vX] = load_timeseries_range(root, '', [base '-X'], '2026-01-01', '2026-01-01', cfg, 'tilt');
            [tY, vY] = load_timeseries_range(root, '', [base '-Y'], '2026-01-01', '2026-01-01', cfg, 'tilt');
            testCase.verifyNotEmpty(vX);
            testCase.verifyNotEmpty(vY);
            testCase.verifyEqual(numel(tX), numel(vX));
            testCase.verifyEqual(numel(tY), numel(vY));
        end

        function test_eq_xyz(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            base = 'DZY-01-D15-P15';
            testCase.assumeTrue(exist(sample_path(testCase.ProjectRoot, base), 'file') == 2);
            root = fullfile(testCase.ProjectRoot, 'tests','data','_samples','jlj');
            [tX, vX] = load_timeseries_range(root, '', [base '-X'], '2026-01-01', '2026-01-01', cfg, 'eq_x');
            [tY, vY] = load_timeseries_range(root, '', [base '-Y'], '2026-01-01', '2026-01-01', cfg, 'eq_y');
            [tZ, vZ] = load_timeseries_range(root, '', [base '-Z'], '2026-01-01', '2026-01-01', cfg, 'eq_z');
            testCase.verifyNotEmpty(vX);
            testCase.verifyNotEmpty(vY);
            testCase.verifyNotEmpty(vZ);
            testCase.verifyEqual(numel(tX), numel(vX));
            testCase.verifyEqual(numel(tY), numel(vY));
            testCase.verifyEqual(numel(tZ), numel(vZ));
        end

        function test_data_source_direct_read_file_and_cache(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            base = 'DZY-DS-01';
            day = datetime(2026,1,1);
            write_jlj_eq_csv(root, day, base);

            src = bms.data.JiulongjiangCsvDataSource(root, cfg);
            [dirp, meta] = src.dayDir('2026-01-01', struct());
            fp = bms.data.JiulongjiangCsvDataSource.findFile(dirp, [base '-Y']);
            range = struct('start', day + hours(1), 'end', day + hours(1) + seconds(1));
            [t, v] = bms.data.JiulongjiangCsvDataSource.readFile(fp, 'eq_y', [base '-Y'], cfg, ...
                struct('range', range, 'cache_dir', meta.cache_dir));

            testCase.verifyNotEmpty(t);
            testCase.verifyEqual(numel(t), numel(v));
            testCase.verifyLessThan(numel(t), 2400);
            testCase.verifyTrue(exist(fullfile(meta.cache_dir, [base '.mat']), 'file') == 2);
        end

        function test_standalone_jlj_cache_supports_auto_and_mat_only(testCase)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            cfg = standalone_sxh_config('auto');
            day = datetime(2026, 1, 1);
            pid = 'SL-UT-MAT-01';
            expected = [11.5; 12.5; 13.5];
            [cachePath, csvDir] = write_sxh_mat_cache( ...
                root, day, pid, expected, cfg, true, 'jlj_csv_v2');

            for mode = {'auto', 'mat_only'}
                cfg.data_adapter.time_series.source_mode = mode{1};
                fp = bms.data.JiulongjiangCsvDataSource.findFile( ...
                    csvDir, pid, 'cable_accel', cfg);
                testCase.verifyEqual(fp, cachePath);

                [t, v] = load_timeseries_range( ...
                    root, '', pid, '2026-01-01', '2026-01-01', cfg, 'cable_accel');
                testCase.verifyEqual(numel(t), numel(expected));
                testCase.verifyEqual(v(:), expected, 'AbsTol', 1e-10);
            end
        end

        function test_auto_keeps_csv_priority_when_cache_also_exists(testCase)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            cfg = standalone_sxh_config('auto');
            day = datetime(2026, 1, 1);
            pid = 'SL-UT-CSV-01';
            [cachePath, csvDir] = write_sxh_mat_cache( ...
                root, day, pid, [91; 92], cfg, true, 'jlj_csv_v2');
            write_simple_jlj_csv(csvDir, pid);

            cfg.data_adapter.time_series.source_mode = 'mat_only';
            matFp = bms.data.JiulongjiangCsvDataSource.findFile( ...
                csvDir, pid, 'cable_accel', cfg);
            testCase.verifyEqual(matFp, cachePath);
            [~, matValues] = bms.data.JiulongjiangCsvDataSource.readFile( ...
                matFp, 'cable_accel', pid, cfg);
            testCase.verifyEqual(matValues(:), [91; 92], 'AbsTol', 1e-10);

            cfg.data_adapter.time_series.source_mode = 'auto';
            fp = bms.data.JiulongjiangCsvDataSource.findFile( ...
                csvDir, pid, 'cable_accel', cfg);
            testCase.verifyEqual(fp, fullfile(csvDir, [pid '.csv']));

            [t, v] = load_timeseries_range( ...
                root, '', pid, '2026-01-01', '2026-01-01', cfg, 'cable_accel');
            testCase.verifyEqual(numel(t), 2);
            testCase.verifyEqual(v(:), [12.5; 13.5], 'AbsTol', 1e-10);
        end

        function test_data_index_reuses_jlj_source_mode_resolver(testCase)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            cfg = standalone_sxh_config('prefer_mat');
            day = datetime(2026, 1, 1);
            pid = 'SL-UT-INDEX-01';
            [cachePath, csvDir] = write_sxh_mat_cache( ...
                root, day, pid, [31; 32], cfg, true, 'jlj_csv_v2');
            write_simple_jlj_csv(csvDir, pid);
            csvPath = fullfile(csvDir, [pid '.csv']);
            adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(cfg);
            bms.data.CacheManager.writeMetadata( ...
                cachePath, {csvPath}, adapter, 'jlj_csv_v2');
            testCase.verifyTrue(bms.data.CacheManager.metadataMatches( ...
                cachePath, adapter, 'jlj_csv_v2'));
            testCase.verifyTrue( ...
                bms.data.JiulongjiangCsvDataSource.isUsableStandaloneCache( ...
                cachePath, 'cable_accel', pid, cfg));
            testCase.verifyEqual( ...
                bms.data.JiulongjiangCsvDataSource.findFile( ...
                csvDir, pid, 'cable_accel', cfg), cachePath);
            src = bms.data.DataSourceFactory.create(root, cfg);
            testCase.verifyClass(src, 'bms.data.JiulongjiangCsvDataSource');

            patterns = {[pid '.csv']};
            preferFiles = bms.data.DataIndex.findPointFiles( ...
                src, pid, '', '2026-01-01', '2026-01-01', patterns, cfg, 'cable_accel');
            testCase.verifyEqual(preferFiles, {cachePath});

            cfg.data_adapter.time_series.source_mode = 'auto';
            autoFiles = bms.data.DataIndex.findPointFiles( ...
                src, pid, '', '2026-01-01', '2026-01-01', patterns, cfg, 'cable_accel');
            testCase.verifyEqual(autoFiles, {csvPath});

            cfg.data_adapter.time_series.source_mode = 'mat_only';
            matFiles = bms.data.DataIndex.findPointFiles( ...
                src, pid, '', '2026-01-01', '2026-01-01', patterns, cfg, 'cable_accel');
            testCase.verifyEqual(matFiles, {cachePath});

            delete(cachePath);
            closedFiles = bms.data.DataIndex.findPointFiles( ...
                src, pid, '', '2026-01-01', '2026-01-01', patterns, cfg, 'cable_accel');
            testCase.verifyEmpty(closedFiles);
        end

        function test_prefer_mat_falls_back_to_csv_when_cache_is_invalid(testCase)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            cfg = standalone_sxh_config('prefer_mat');
            day = datetime(2026, 1, 1);
            pid = 'SL-UT-BAD-MAT-01';
            [cachePath, csvDir] = write_sxh_mat_cache( ...
                root, day, pid, [91; 92], cfg, false, 'jlj_csv_v2');
            write_simple_jlj_csv(csvDir, pid);

            fp = bms.data.JiulongjiangCsvDataSource.findFile( ...
                csvDir, pid, 'cable_accel', cfg);
            testCase.verifyEqual(fp, fullfile(csvDir, [pid '.csv']));
            testCase.verifyNotEqual(fp, cachePath);

            [t, v] = bms.data.JiulongjiangCsvDataSource.readFile( ...
                fp, 'cable_accel', pid, cfg);
            testCase.verifyEqual(numel(t), 2);
            testCase.verifyEqual(v(:), [12.5; 13.5], 'AbsTol', 1e-10);
        end

        function test_prefer_mat_falls_back_when_cache_time_type_is_invalid(testCase)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            cfg = standalone_sxh_config('prefer_mat');
            day = datetime(2026, 1, 1);
            pid = 'SL-UT-BAD-TIME-01';
            [cachePath, csvDir] = write_sxh_mat_cache( ...
                root, day, pid, [91; 92], cfg, true, 'jlj_csv_v2');
            S = load(cachePath);
            ts = struct('bad', true); %#ok<NASGU>
            valx = S.valx; valy = S.valy; valz = S.valz; meta = S.meta; %#ok<NASGU>
            save(cachePath, 'ts', 'valx', 'valy', 'valz', 'meta');
            write_simple_jlj_csv(csvDir, pid);

            fp = bms.data.JiulongjiangCsvDataSource.findFile( ...
                csvDir, pid, 'cable_accel', cfg);

            testCase.verifyEqual(fp, fullfile(csvDir, [pid '.csv']));
        end

        function test_prefer_mat_falls_back_when_cache_time_text_is_unparseable(testCase)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            cfg = standalone_sxh_config('prefer_mat');
            day = datetime(2026, 1, 1);
            pid = 'SL-UT-BAD-TEXT-TIME-01';
            [cachePath, csvDir] = write_sxh_mat_cache( ...
                root, day, pid, [91; 92], cfg, true, 'jlj_csv_v2');
            S = load(cachePath);
            ts = ["bad-date"; "still-bad"]; %#ok<NASGU>
            valx = S.valx; valy = S.valy; valz = S.valz; meta = S.meta; %#ok<NASGU>
            save(cachePath, 'ts', 'valx', 'valy', 'valz', 'meta');
            write_simple_jlj_csv(csvDir, pid);

            fp = bms.data.JiulongjiangCsvDataSource.findFile( ...
                csvDir, pid, 'cable_accel', cfg);

            testCase.verifyEqual(fp, fullfile(csvDir, [pid '.csv']));
        end

        function test_standalone_jlj_cache_requires_matching_metadata(testCase)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            cfg = standalone_sxh_config('mat_only');
            day = datetime(2026, 1, 1);
            pid = 'SL-UT-META-01';
            [cachePath, csvDir] = write_sxh_mat_cache( ...
                root, day, pid, [21; 22], cfg, false, 'jlj_csv_v2');

            fp = bms.data.JiulongjiangCsvDataSource.findFile( ...
                csvDir, pid, 'cable_accel', cfg);
            testCase.verifyEqual(fp, cachePath);
            [tMissing, vMissing] = bms.data.JiulongjiangCsvDataSource.readFile( ...
                fp, 'cable_accel', pid, cfg);
            testCase.verifyEmpty(tMissing);
            testCase.verifyEmpty(vMissing);

            adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(cfg);
            bms.data.CacheManager.writeMetadata( ...
                cachePath, {fullfile(csvDir, [pid '.csv'])}, adapter, 'wrong_version');
            [tWrong, vWrong] = bms.data.JiulongjiangCsvDataSource.readFile( ...
                fp, 'cable_accel', pid, cfg);
            testCase.verifyEmpty(tWrong);
            testCase.verifyEmpty(vWrong);

            bms.data.CacheManager.writeMetadata( ...
                cachePath, {fullfile(csvDir, [pid '.csv'])}, adapter, 'jlj_csv_v2');
            [t, v] = bms.data.JiulongjiangCsvDataSource.readFile( ...
                fp, 'cable_accel', pid, cfg);
            testCase.verifyEqual(numel(t), 2);
            testCase.verifyEqual(v(:), [21; 22], 'AbsTol', 1e-10);
        end

        function test_data_source_extracts_daily_zip(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            cfg.data_adapter.zip.staging_root = fullfile(root, 'stage');
            sourceRoot = fullfile(root, 'zip_source');
            csvDir = fullfile(sourceRoot, 'data', 'jlj', 'csv');
            mkdir(csvDir);
            pid = 'WDCGQ-ZIP-01';
            write_simple_jlj_csv(csvDir, pid);
            zip(fullfile(root, 'data_jlj_2026-01-01.zip'), fullfile(sourceRoot, 'data'), sourceRoot);
            rmdir(sourceRoot, 's');

            src = bms.data.JiulongjiangCsvDataSource(root, cfg);
            [dirp, meta] = src.dayDir('2026-01-01', struct());
            fp = bms.data.JiulongjiangCsvDataSource.findFile(dirp, pid);
            [t, v] = bms.data.JiulongjiangCsvDataSource.readFile(fp, 'temperature', pid, cfg, meta);

            testCase.verifyTrue(contains(dirp, fullfile('stage', 'data_jlj_2026-01-01')));
            testCase.verifyTrue(exist(fp, 'file') == 2);
            testCase.verifyEqual(numel(t), 2);
            testCase.verifyEqual(v(:), [12.5; 13.5], 'AbsTol', 1e-10);
        end

        function test_acceleration_single_channel(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            pid = 'ZDCQG-01-K15-X1-G18';
            testCase.assumeTrue(exist(sample_path(testCase.ProjectRoot, pid), 'file') == 2);
            root = fullfile(testCase.ProjectRoot, 'tests','data','_samples','jlj');
            [t, v] = load_timeseries_range(root, '', pid, '2026-01-01', '2026-01-01', cfg, 'acceleration');
            testCase.verifyNotEmpty(v);
            testCase.verifyEqual(numel(t), numel(v));
            cachePath = sample_cache_path(testCase.ProjectRoot, pid);
            testCase.verifyTrue(exist(cachePath, 'file') == 2);
        end

        function test_strain_single_channel(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            pid = 'DYBCGQ-01-K16-X4-G20';
            testCase.assumeTrue(exist(sample_path(testCase.ProjectRoot, pid), 'file') == 2);
            root = fullfile(testCase.ProjectRoot, 'tests','data','_samples','jlj');
            [t, v] = load_timeseries_range(root, '', pid, '2026-01-01', '2026-01-01', cfg, 'strain');
            testCase.verifyNotEmpty(v);
            testCase.verifyEqual(numel(t), numel(v));
            cachePath = sample_cache_path(testCase.ProjectRoot, pid);
            testCase.verifyTrue(exist(cachePath, 'file') == 2);
        end

        function test_deflection_single_channel(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            pid = 'NDY-01-K15-X1-G14';
            testCase.assumeTrue(exist(sample_path(testCase.ProjectRoot, pid), 'file') == 2);
            root = fullfile(testCase.ProjectRoot, 'tests','data','_samples','jlj');
            [t, v] = load_timeseries_range(root, '', pid, '2026-01-01', '2026-01-01', cfg, 'deflection');
            testCase.verifyNotEmpty(v);
            testCase.verifyEqual(numel(t), numel(v));
        end

        function test_bearing_displacement_pipeline(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            pid = 'WYJ-UT-01';
            day = datetime(2026,1,1);
            write_jlj_bearing_csv(root, day, pid);

            cfg.points.bearing_displacement = {pid};
            cfg.groups.bearing_displacement = {};
            cfg.plot_styles.bearing_displacement.output_dir = 'bearing_out';
            cfg.plot_styles.bearing_displacement.ylim_auto = true;

            if ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point)
                cfg.per_point = struct();
            end
            if ~isfield(cfg.per_point, 'bearing_displacement') || ~isstruct(cfg.per_point.bearing_displacement)
                cfg.per_point.bearing_displacement = struct();
            end
            safe_id = strrep(pid, '-', '_');
            cfg.per_point.bearing_displacement.(safe_id) = struct( ...
                'thresholds', [], ...
                'warn_lines', struct('y', 5, 'label', 'Warn', 'color', [1, 0, 0]) ...
            );

            excelPath = fullfile(root, 'bearing_displacement_stats_test.xlsx');
            analyze_bearing_displacement_points(root, '2026-01-01', '2026-01-01', excelPath, '', cfg);

            testCase.verifyTrue(exist(excelPath, 'file') == 2);
            T = readtable(excelPath, 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(height(T), 1);
            testCase.verifyEqual(string(T.PointID{1}), string(pid));
            rawFigs = dir(fullfile(root, 'bearing_out_原始', '*.fig'));
            filtFigs = dir(fullfile(root, 'bearing_out_滤波', '*.fig'));
            testCase.verifyGreaterThanOrEqual(numel(rawFigs), 1);
            testCase.verifyGreaterThanOrEqual(numel(filtFigs), 1);
        end

        function test_acceleration_spectrum_pipeline(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            pid = 'ZDCQG-UT-01';
            day = datetime(2026,1,1);
            write_jlj_accel_csv(root, day, pid);

            excelPath = fullfile(root, 'accel_spec_stats_test.xlsx');
            analyze_accel_spectrum_points(root, '2026-01-01', '2026-01-01', ...
                {pid}, excelPath, '', [1.2 2.4], 0.2, false, cfg);
            analyze_accel_spectrum_points(root, '2026-01-01', '2026-01-01', ...
                {pid}, excelPath, '', [1.2], 0.2, false, cfg);

            testCase.verifyTrue(exist(excelPath, 'file') == 2);
            T = readtable(excelPath, 'Sheet', pid, 'VariableNamingRule', 'preserve');
            vars = string(T.Properties.VariableNames);
            freqCol = find(startsWith(string(T.Properties.VariableNames), "Freq_"), 1);
            testCase.verifyNotEmpty(freqCol);
            testCase.verifyTrue(any(vars == "Freq_1.200Hz"));
            testCase.verifyFalse(any(vars == "Freq_2.400Hz"));
            testCase.verifyFalse(all(isnan(T{:,freqCol})));
            testCase.verifyLessThan(abs(T{1,freqCol} - 1.2), 0.1);

            testCase.verifyTrue(exist(fullfile(root, '频谱峰值曲线_加速度'), 'dir') == 7);
            testCase.verifyTrue(exist(fullfile(root, 'PSD_备查', pid), 'dir') == 7);
        end

        function test_acceleration_spectrum_per_point_params(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            pid = 'ZDCQG-UT-02';
            day = datetime(2026,1,1);
            write_jlj_accel_csv(root, day, pid);

            if ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point)
                cfg.per_point = struct();
            end
            if ~isfield(cfg.per_point, 'accel_spectrum') || ~isstruct(cfg.per_point.accel_spectrum)
                cfg.per_point.accel_spectrum = struct();
            end
            safe_id = strrep(pid, '-', '_');
            cfg.per_point.accel_spectrum.(safe_id) = struct( ...
                'target_freqs', [1.2, 2.4], ...
                'tolerance', 0.2, ...
                'theor_freqs', [1.1, 2.2], ...
                'theor_labels', ["理论一阶 1.1Hz", "理论二阶 2.2Hz"] ...
            );

            excelPath = fullfile(root, 'accel_spec_stats_test_point.xlsx');
            analyze_accel_spectrum_points(root, '2026-01-01', '2026-01-01', ...
                {pid}, excelPath, '', [9.9], 0.01, false, cfg);

            testCase.verifyTrue(exist(excelPath, 'file') == 2);
            T = readtable(excelPath, 'Sheet', pid, 'VariableNamingRule', 'preserve');
            vars = string(T.Properties.VariableNames);
            testCase.verifyTrue(any(vars == "Freq_1.200Hz"));
            testCase.verifyTrue(any(vars == "Freq_2.400Hz"));
            testCase.verifyFalse(any(vars == "Freq_9.900Hz"));
        end


        function test_acceleration_timeseries_pipeline(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            pid = 'ZDCQG-UT-ACC-01';
            day = datetime(2026,1,1);
            write_jlj_accel_csv(root, day, pid);
            cfg.points.acceleration = {pid};

            excelPath = fullfile(root, 'accel_stats_test.xlsx');
            analyze_acceleration_points(root, '2026-01-01', '2026-01-01', excelPath, '', true, cfg);

            testCase.verifyTrue(exist(excelPath, 'file') == 2);
            T = readtable(excelPath, 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(height(T), 1);
            testCase.verifyEqual(string(T.PointID{1}), string(pid));
            testCase.verifyTrue(isfinite(T.Min(1)));
            testCase.verifyTrue(isfinite(T.Max(1)));

            figs = dir(fullfile(root, '**', ['*' pid '*.fig']));
            testCase.verifyGreaterThanOrEqual(numel(figs), 2);
        end


        function test_cable_acceleration_timeseries_pipeline(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            pid = 'SLCGQ-UT-ACC-01';
            day = datetime(2026,1,1);
            write_jlj_accel_csv(root, day, pid);
            cfg.points.cable_accel = {pid};

            excelPath = fullfile(root, 'cable_accel_stats_test.xlsx');
            analyze_cable_acceleration_points(root, '2026-01-01', '2026-01-01', excelPath, '', true, cfg);

            testCase.verifyTrue(exist(excelPath, 'file') == 2);
            T = readtable(excelPath, 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(height(T), 1);
            testCase.verifyEqual(string(T.PointID{1}), string(pid));

            figs = dir(fullfile(root, '**', ['*' pid '*.fig']));
            testCase.verifyGreaterThanOrEqual(numel(figs), 2);
        end

        function test_cable_accel_spectrum_force_pipeline(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            pid = 'SLCGQ-UT-SPEC-01';
            day = datetime(2026,1,1);
            write_jlj_accel_csv(root, day, pid);

            cfg.points.cable_accel_spectrum = {pid};
            if ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point)
                cfg.per_point = struct();
            end
            if ~isfield(cfg.per_point, 'cable_accel') || ~isstruct(cfg.per_point.cable_accel)
                cfg.per_point.cable_accel = struct();
            end
            safe_id = strrep(pid, '-', '_');
            cfg.per_point.cable_accel.(safe_id) = struct( ...
                'thresholds', [], ...
                'rho', 300, ...
                'L', 40, ...
                'force_decimals', 2, ...
                'target_freqs', [1.2] ...
            );

            excelPath = fullfile(root, 'cable_accel_spec_stats_test.xlsx');
            analyze_cable_accel_spectrum_points(root, '2026-01-01', '2026-01-01', ...
                {pid}, excelPath, '', [1.2], 0.2, false, cfg);

            testCase.verifyTrue(exist(excelPath, 'file') == 2);
            T = readtable(excelPath, 'Sheet', pid, 'VariableNamingRule', 'preserve');
            testCase.verifyEqual(height(T), 1);
            testCase.verifyTrue(isfinite(T.CableForce_kN(1)));

            expected = round(4 * 300 * (40^2) * (1.2^2) / 1000, 2);
            testCase.verifyLessThan(abs(T.CableForce_kN(1) - expected), 500);
        end


        function test_wind_module_pipeline(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            pid = 'CSFSY-UT-01';
            day = datetime(2026,1,1);
            write_jlj_wind_csv(root, day, pid);

            cfg.points.wind = {pid};
            cfg.plot_styles.wind.output = struct( ...
                'root_dir', 'wind_out', ...
                'speed_dir', 'speed', ...
                'direction_dir', 'direction', ...
                'speed10_dir', 'speed10', ...
                'rose_dir', 'rose', ...
                'stats_file', 'wind_stats.xlsx' ...
            );

            analyze_wind_points(root, '2026-01-01', '2026-01-01', '', cfg);

            outRoot = fullfile(root, 'wind_out');
            testCase.verifyTrue(exist(fullfile(root, 'stats', 'wind_stats.xlsx'), 'file') == 2);
            testCase.verifyTrue(exist(fullfile(outRoot, 'speed'), 'dir') == 7);
            testCase.verifyTrue(exist(fullfile(outRoot, 'direction'), 'dir') == 7);
            testCase.verifyTrue(exist(fullfile(outRoot, 'speed10'), 'dir') == 7);
            testCase.verifyTrue(exist(fullfile(outRoot, 'rose'), 'dir') == 7);

            roseSummary = dir(fullfile(outRoot, 'rose', '*_summary.txt'));
            testCase.verifyGreaterThanOrEqual(numel(roseSummary), 1);
        end

        function test_eq_module_pipeline(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            base = 'DZY-UT-01';
            day = datetime(2026,1,1);
            write_jlj_eq_csv(root, day, base);

            cfg.points.eq = {[base '-X'], [base '-Y'], [base '-Z']};
            cfg.plot_styles.eq.output = struct( ...
                'root_dir', 'eq_out', ...
                'series_dir', 'series', ...
                'prefix', 'EQ' ...
            );
            cfg.eq_params.alarm_levels = [0.5, 1.0];

            analyze_eq_points(root, '2026-01-01', '2026-01-01', '', cfg);

            outDir = fullfile(root, 'eq_out', 'series');
            testCase.verifyTrue(exist(outDir, 'dir') == 7);
            figs = dir(fullfile(outDir, '*.fig'));
            testCase.verifyGreaterThanOrEqual(numel(figs), 3);
        end

        function test_crack_lfj_pipeline_without_temp(testCase)
            cfg = load_config(fullfile(testCase.ProjectRoot, 'config', 'jiulongjiang_config.json'));
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            pid = 'LFJ-UT-01';
            day = datetime(2026,1,1);
            write_jlj_crack_csv(root, day, pid);

            cfg.points.crack = {pid};
            cfg.groups.crack = struct();
            cfg.plot_styles.crack.per_point_plot = true;
            cfg.plot_styles.crack.group_plot = true;
            cfg.plot_styles.crack.temp_enabled = false;
            cfg.plot_styles.crack.skip_group_if_missing = true;

            excelPath = fullfile(root, 'crack_stats_test.xlsx');
            analyze_crack_points(root, '2026-01-01', '2026-01-01', excelPath, '', cfg);

            testCase.verifyTrue(exist(excelPath, 'file') == 2);
            T = readtable(excelPath);
            testCase.verifyEqual(height(T), 1);
            testCase.verifyEqual(string(T.PointID{1}), string(pid));
            testCase.verifyTrue(isnan(T.TmpMin(1)));
            testCase.verifyTrue(isnan(T.TmpMax(1)));
            testCase.verifyTrue(isnan(T.TmpMean(1)));

            figs = dir(fullfile(root, '**', '*.fig'));
            testCase.verifyEqual(numel(figs), 1);
        end

        function test_preflight_cache_only_coverage_and_mat_only_boundary(testCase)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_temp_dir(root)); %#ok<NASGU>

            pid = 'SL-UT-PREFLIGHT-01';
            cfg = standalone_sxh_config('auto');
            cfg.bridge_id = 'shuixianhua';
            cfg.data_layout = 'jlj_daily_export';
            cfg.points = struct('cable_accel', {{pid}});
            cfg.subfolders = struct('cable_accel', '');
            cfg.file_patterns = struct('cable_accel', ...
                struct('default', '{file_id}_*.csv'));
            opts = struct('doCableAccel', true);

            [cachePath, csvDir] = write_sxh_mat_cache( ...
                root, datetime(2026, 1, 1), pid, [41; 42], cfg, true, 'jlj_csv_v2');
            result = bms.app.RunPreflight.check( ...
                root, '2026-01-01', '2026-01-01', opts, cfg);
            coverage = bms.app.ManifestReader.recordsToCell(result.point_coverage);
            row = coverage{1};
            testCase.verifyEqual(row.key, 'cable_accel');
            testCase.verifyEqual(row.found_count, 1);
            testCase.verifyEqual(row.missing_count, 0);
            testCase.verifyEqual(row.matched_csv_points, {pid});

            % With MAT-only selected, a CSV by itself must remain missing.
            delete(cachePath);
            write_simple_jlj_csv(csvDir, pid);
            cfg.data_adapter.time_series.source_mode = 'mat_only';
            result = bms.app.RunPreflight.check( ...
                root, '2026-01-01', '2026-01-01', opts, cfg);
            coverage = bms.app.ManifestReader.recordsToCell(result.point_coverage);
            row = coverage{1};
            testCase.verifyEqual(row.found_count, 0);
            testCase.verifyEqual(row.missing_count, 1);
            testCase.verifyEmpty(row.matched_csv_points);
        end

    end
end

function p = sample_path(root, pid)
    % map point id to sample file path
    base = regexprep(pid, '[-_][XYZ]$', '');
    p = fullfile(root, 'tests','data','_samples','jlj', ...
        'jljData20260101-20260102','data','csv', [base '.csv']);
end

function p = sample_cache_path(root, pid)
    base = regexprep(pid, '[-_][XYZ]$', '');
    p = fullfile(root, 'tests','data','_samples','jlj', ...
        'jljData20260101-20260102','data','csv','cache', [base '.mat']);
end

function write_jlj_accel_csv(rootDir, day, pid)
    dayStart = datestr(day, 'yyyymmdd');
    dayEnd = datestr(day + days(1), 'yyyymmdd');
    csvDir = fullfile(rootDir, ['jljData' dayStart '-' dayEnd], 'data', 'csv');
    if ~exist(csvDir, 'dir'), mkdir(csvDir); end

    fs = 20;
    dt = 1/fs;
    n = 2400; % 2 minutes at 20 Hz
    t0 = day + hours(5) + minutes(30);
    ts = t0 + seconds((0:n-1) * dt);
    x = 0.01 * sin(2*pi*1.2*(0:n-1)*dt) + 0.001 * randn(1,n);

    fp = fullfile(csvDir, [pid '.csv']);
    fid = fopen(fp, 'wt');
    assert(fid > 0, 'Failed to create test csv: %s', fp);
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'ts,value_x\n');
    for i = 1:n
        fprintf(fid, '"%s",%.8f\n', datestr(ts(i), 'yyyy-mm-dd HH:MM:SS.FFF'), x(i));
    end
end


function write_jlj_crack_csv(rootDir, day, pid)
    dayStart = datestr(day, 'yyyymmdd');
    dayEnd = datestr(day + days(1), 'yyyymmdd');
    csvDir = fullfile(rootDir, ['jljData' dayStart '-' dayEnd], 'data', 'csv');
    if ~exist(csvDir, 'dir'), mkdir(csvDir); end

    n = 24;
    t0 = day;
    ts = t0 + minutes((0:n-1) * 60);
    x = linspace(0.1, 0.25, n);

    fp = fullfile(csvDir, [pid '.csv']);
    fid = fopen(fp, 'wt');
    assert(fid > 0, 'Failed to create test csv: %s', fp);
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'ts,value_x\n');
    for i = 1:n
        fprintf(fid, '"%s",%.6f\n', datestr(ts(i), 'yyyy-mm-dd HH:MM:SS.FFF'), x(i));
    end
end

function write_jlj_bearing_csv(rootDir, day, pid)
    dayStart = datestr(day, 'yyyymmdd');
    dayEnd = datestr(day + days(1), 'yyyymmdd');
    csvDir = fullfile(rootDir, ['jljData' dayStart '-' dayEnd], 'data', 'csv');
    if ~exist(csvDir, 'dir'), mkdir(csvDir); end

    n = 288;
    t0 = day;
    ts = t0 + minutes((0:n-1) * 5);
    x = 12 + 0.8 * sin(2*pi*(0:n-1)/72);

    fp = fullfile(csvDir, [pid '.csv']);
    fid = fopen(fp, 'wt');
    assert(fid > 0, 'Failed to create test csv: %s', fp);
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'ts,value_x\n');
    for i = 1:n
        fprintf(fid, '"%s",%.6f\n', datestr(ts(i), 'yyyy-mm-dd HH:MM:SS.FFF'), x(i));
    end
end


function write_jlj_wind_csv(rootDir, day, pid)
    dayStart = datestr(day, 'yyyymmdd');
    dayEnd = datestr(day + days(1), 'yyyymmdd');
    csvDir = fullfile(rootDir, ['jljData' dayStart '-' dayEnd], 'data', 'csv');
    if ~exist(csvDir, 'dir'), mkdir(csvDir); end

    fs = 1;  % 1 Hz
    n = 3600;
    t0 = day;
    ts = t0 + seconds((0:n-1) / fs);
    spd = 5 + 1.2 * sin(2*pi*(0:n-1)/300);
    drc = mod(180 + 25 * sin(2*pi*(0:n-1)/500), 360);

    fp = fullfile(csvDir, [pid '.csv']);
    fid = fopen(fp, 'wt');
    assert(fid > 0, 'Failed to create test csv: %s', fp);
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'ts,value_x,value_y\n');
    for i = 1:n
        fprintf(fid, '"%s",%.6f,%.6f\n', datestr(ts(i), 'yyyy-mm-dd HH:MM:SS.FFF'), spd(i), drc(i));
    end
end

function write_jlj_eq_csv(rootDir, day, base)
    dayStart = datestr(day, 'yyyymmdd');
    dayEnd = datestr(day + days(1), 'yyyymmdd');
    csvDir = fullfile(rootDir, ['jljData' dayStart '-' dayEnd], 'data', 'csv');
    if ~exist(csvDir, 'dir'), mkdir(csvDir); end

    fs = 20;
    n = 2400;
    t0 = day + hours(1);
    ts = t0 + seconds((0:n-1) / fs);
    x = 0.20 * sin(2*pi*0.8*(0:n-1)/fs);
    y = 0.15 * sin(2*pi*1.2*(0:n-1)/fs + 0.3);
    z = 0.10 * sin(2*pi*1.5*(0:n-1)/fs + 0.8);

    fp = fullfile(csvDir, [base '.csv']);
    fid = fopen(fp, 'wt');
    assert(fid > 0, 'Failed to create test csv: %s', fp);
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'ts,value_x,value_y,value_z\n');
    for i = 1:n
        fprintf(fid, '"%s",%.6f,%.6f,%.6f\n', datestr(ts(i), 'yyyy-mm-dd HH:MM:SS.FFF'), x(i), y(i), z(i));
    end
end

function write_simple_jlj_csv(csvDir, pid)
    if ~exist(csvDir, 'dir'), mkdir(csvDir); end
    fp = fullfile(csvDir, [pid '.csv']);
    fid = fopen(fp, 'wt');
    assert(fid > 0, 'Failed to create test csv: %s', fp);
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'ts,value_x\n');
    fprintf(fid, '"2026-01-01 00:00:00.000",12.5\n');
    fprintf(fid, '"2026-01-01 01:00:00.000",13.5\n');
end

function cfg = standalone_sxh_config(mode)
    cfg = struct();
    cfg.vendor = 'shuixianhua';
    cfg.data_adapter = struct();
    cfg.data_adapter.cache = struct( ...
        'enabled', true, ...
        'dir', 'cache', ...
        'validate', 'mtime_size');
    cfg.data_adapter.time_series = struct( ...
        'source_mode', char(string(mode)), ...
        'require_metadata', true);
end

function [cachePath, csvDir] = write_sxh_mat_cache( ...
        rootDir, day, pid, values, cfg, writeMetadata, version)
    dayText = datestr(day, 'yyyy-mm-dd');
    csvDir = fullfile(rootDir, ['data_sxh_' dayText], 'data', 'sxh', 'csv');
    cacheDir = fullfile(csvDir, 'cache');
    if ~exist(cacheDir, 'dir'), mkdir(cacheDir); end

    ts = day + minutes((0:numel(values)-1)'); %#ok<NASGU>
    valx = values(:); %#ok<NASGU>
    valy = valx + 100; %#ok<NASGU>
    valz = valx + 200; %#ok<NASGU>
    sourcePath = fullfile(csvDir, [pid '.csv']);
    meta = struct('src', sourcePath, 'mtime', 0, 'size', 0); %#ok<NASGU>
    cachePath = fullfile(cacheDir, [pid '.mat']);
    save(cachePath, 'ts', 'valx', 'valy', 'valz', 'meta');

    if writeMetadata
        adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(cfg);
        bms.data.CacheManager.writeMetadata( ...
            cachePath, {sourcePath}, adapter, version);
    end
end

function write_jlj_xy_csv(rootDir, day, pid, x, y)
    dayStart = datestr(day, 'yyyymmdd');
    dayEnd = datestr(day + days(1), 'yyyymmdd');
    csvDir = fullfile(rootDir, ['jljData' dayStart '-' dayEnd], 'data', 'csv');
    if ~exist(csvDir, 'dir'), mkdir(csvDir); end

    fp = fullfile(csvDir, [pid '.csv']);
    fid = fopen(fp, 'wt');
    assert(fid > 0, 'Failed to create test csv: %s', fp);
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'ts,value_x,value_y\n');
    for i = 1:numel(x)
        fprintf(fid, '"%s",%.6f,%.6f\n', datestr(day + hours(i - 1), 'yyyy-mm-dd HH:MM:SS.FFF'), x(i), y(i));
    end
end

function cleanup_temp_dir(rootDir)
    if exist(rootDir, 'dir') == 7
        try
            rmdir(rootDir, 's');
        catch
        end
    end
end
