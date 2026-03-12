classdef test_hongtang_lowfreq_loader < matlab.unittest.TestCase
    % Tests for hongtang low-frequency Excel adapter in load_timeseries_range.

    properties
        WorkRoot
        XlsxPath
        Cfg
    end

    methods (TestMethodSetup)
        function setupCase(tc)
            projRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(projRoot, fullfile(projRoot, 'pipeline'), fullfile(projRoot, 'config'));

            tc.WorkRoot = fullfile(projRoot, 'tests', 'tmp', 'hongtang_lowfreq_unit');
            if exist(tc.WorkRoot, 'dir')
                rmdir(tc.WorkRoot, 's');
            end
            mkdir(fullfile(tc.WorkRoot, 'lowfreq'));
            tc.XlsxPath = fullfile(tc.WorkRoot, 'lowfreq', 'data.xlsx');

            % Create data sheet used by the adapter.
            C = {
                'SamplingTime', 'Z11-1', 'Q1-Z', 'SB-1';
                '2025-12-01 00:00:00', '1.2', '0.010', '-100';
                '2025-12-01 01:00:00', '--', '0.020', '50';
                '2025-12-01 02:00:00', '700', '0.030', '600';
                '2025-12-01 03:00:00', '-2.5', '-0.010', '80'
            };
            writecell(C, tc.XlsxPath, 'Sheet', 'DataSheet');

            tc.Cfg = struct();
            tc.Cfg.vendor = 'hongtang';
            tc.Cfg.defaults = struct();
            tc.Cfg.defaults.bearing_displacement = struct('thresholds', [], 'zero_to_nan', false, 'outlier', []);
            tc.Cfg.defaults.tilt = struct('thresholds', [], 'zero_to_nan', false, 'outlier', []);
            tc.Cfg.defaults.strain = struct('thresholds', [], 'zero_to_nan', false, 'outlier', []);
            tc.Cfg.data_adapter = struct();
            tc.Cfg.data_adapter.hongtang_lowfreq = struct( ...
                'enabled', true, ...
                'file', fullfile('lowfreq', 'data.xlsx'), ...
                'sheet', 'DataSheet', ...
                'time_column', 'SamplingTime', ...
                'sensor_types', {{'bearing_displacement', 'tilt', 'strain'}}, ...
                'missing_tokens', {{'--', ''}}, ...
                'abs_max_valid', 500, ...
                'cache', struct('enabled', true, 'dir', 'cache', 'validate', 'mtime_size'));
        end
    end

    methods (TestMethodTeardown)
        function cleanupCase(tc)
            if exist(tc.WorkRoot, 'dir')
                rmdir(tc.WorkRoot, 's');
            end
        end
    end

    methods (Test)
        function testReadLowfreqPointAndFilterInvalid(tc)
            [t, v, meta] = load_timeseries_range(tc.WorkRoot, '', 'Z11-1', ...
                '2025-12-01', '2025-12-01', tc.Cfg, 'bearing_displacement');

            tc.verifyEqual(numel(t), 4);
            tc.verifyEqual(v(1), 1.2, 'AbsTol', 1e-10);
            tc.verifyTrue(isnan(v(2))); % '--'
            tc.verifyTrue(isnan(v(3))); % abs(value)>500
            tc.verifyEqual(v(4), -2.5, 'AbsTol', 1e-10);
            tc.verifyEqual(numel(meta.files), 1);
            tc.verifyTrue(contains(meta.files{1}, 'data.xlsx'));
        end

        function testAutoSheetSelection(tc)
            cfg = tc.Cfg;
            cfg.data_adapter.hongtang_lowfreq.sheet = 'auto_first_non_empty';
            [t, v] = load_timeseries_range(tc.WorkRoot, '', 'Z11-1', ...
                '2025-12-01', '2025-12-01', cfg, 'bearing_displacement');
            tc.verifyEqual(numel(t), 4);
            tc.verifyEqual(numel(v), 4);
        end

        function testReadRangeFiltering(tc)
            [t, v] = load_timeseries_range(tc.WorkRoot, '', 'Z11-1', ...
                '2025-12-01', '2025-12-01', tc.Cfg, 'bearing_displacement');
            tc.verifyEqual(numel(t), 4);
            tc.verifyEqual(numel(v), 4);

            [t2, v2] = load_timeseries_range(tc.WorkRoot, '', 'Z11-1', ...
                '2025-12-02', '2025-12-02', tc.Cfg, 'bearing_displacement');
            tc.verifyEmpty(t2);
            tc.verifyEmpty(v2);
        end

        function testReadLowfreqTiltPoint(tc)
            [t, v, meta] = load_timeseries_range(tc.WorkRoot, '', 'Q1-Z', ...
                '2025-12-01', '2025-12-01', tc.Cfg, 'tilt');

            tc.verifyEqual(numel(t), 4);
            tc.verifyEqual(v(1), 0.010, 'AbsTol', 1e-10);
            tc.verifyEqual(v(2), 0.020, 'AbsTol', 1e-10);
            tc.verifyEqual(v(3), 0.030, 'AbsTol', 1e-10);
            tc.verifyEqual(v(4), -0.010, 'AbsTol', 1e-10);
            tc.verifyEqual(numel(meta.files), 1);
            tc.verifyTrue(contains(meta.files{1}, 'data.xlsx'));
        end

        function testReadLowfreqStrainPoint(tc)
            [t, v, meta] = load_timeseries_range(tc.WorkRoot, '', 'SB-1', ...
                '2025-12-01', '2025-12-01', tc.Cfg, 'strain');

            tc.verifyEqual(numel(t), 4);
            tc.verifyEqual(v(1), -100, 'AbsTol', 1e-10);
            tc.verifyEqual(v(2), 50, 'AbsTol', 1e-10);
            tc.verifyTrue(isnan(v(3))); % abs(value)>500
            tc.verifyEqual(v(4), 80, 'AbsTol', 1e-10);
            tc.verifyEqual(numel(meta.files), 1);
            tc.verifyTrue(contains(meta.files{1}, 'data.xlsx'));
        end
    end
end
