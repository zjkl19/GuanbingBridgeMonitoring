classdef test_jlj_adapter < matlab.unittest.TestCase
    % Tests for Jiulongjiang adapter in load_timeseries_range

    properties
        ProjectRoot
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(fullfile(testCase.ProjectRoot, 'config'), ...
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
                {pid}, excelPath, '', [1.2], 0.2, false, cfg);

            testCase.verifyTrue(exist(excelPath, 'file') == 2);
            T = readtable(excelPath, 'Sheet', pid, 'VariableNamingRule', 'preserve');
            freqCol = find(startsWith(string(T.Properties.VariableNames), "Freq_"), 1);
            testCase.verifyNotEmpty(freqCol);
            testCase.verifyFalse(all(isnan(T{:,freqCol})));
            testCase.verifyLessThan(abs(T{1,freqCol} - 1.2), 0.1);

            testCase.verifyTrue(exist(fullfile(root, '频谱峰值曲线_加速度'), 'dir') == 7);
            testCase.verifyTrue(exist(fullfile(root, 'PSD_备查', pid), 'dir') == 7);
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

function cleanup_temp_dir(rootDir)
    if exist(rootDir, 'dir') == 7
        try
            rmdir(rootDir, 's');
        catch
        end
    end
end
