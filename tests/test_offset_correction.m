classdef test_offset_correction < matlab.unittest.TestCase
    properties
        WorkRoot
        XlsxPath
    end

    methods (TestMethodSetup)
        function setupCase(tc)
            projRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(projRoot, fullfile(projRoot, 'pipeline'), fullfile(projRoot, 'config'));

            tc.WorkRoot = fullfile(projRoot, 'tests', 'tmp', 'offset_correction_unit');
            if exist(tc.WorkRoot, 'dir')
                rmdir(tc.WorkRoot, 's');
            end
            mkdir(fullfile(tc.WorkRoot, 'lowfreq'));
            tc.XlsxPath = fullfile(tc.WorkRoot, 'lowfreq', 'data.xlsx');

            C = {
                'SamplingTime', 'Q1-Z';
                '2025-12-01 00:00:00', '2.0';
                '2025-12-01 01:00:00', '3.0'
            };
            writecell(C, tc.XlsxPath, 'Sheet', 'DataSheet');
            offset_correction_registry('reset');
        end
    end

    methods (TestMethodTeardown)
        function cleanupCase(tc)
            offset_correction_registry('reset');
            if exist(tc.WorkRoot, 'dir')
                rmdir(tc.WorkRoot, 's');
            end
        end
    end

    methods (Test)
        function applyPerPointOffsetDuringLoad(tc)
            cfg = struct();
            cfg.vendor = 'hongtang';
            cfg.defaults = struct();
            cfg.defaults.bearing_displacement = struct('thresholds', [], 'zero_to_nan', false, 'outlier', []);
            cfg.defaults.tilt = struct('thresholds', [], 'zero_to_nan', false, 'outlier', []);
            cfg.data_adapter = struct();
            cfg.data_adapter.hongtang_lowfreq = struct( ...
                'enabled', true, ...
                'file', fullfile('lowfreq', 'data.xlsx'), ...
                'sheet', 'DataSheet', ...
                'time_column', 'SamplingTime', ...
                'sensor_types', {{'tilt'}}, ...
                'missing_tokens', {{'--', ''}}, ...
                'abs_max_valid', 500, ...
                'cache', struct('enabled', true, 'dir', 'cache', 'validate', 'mtime_size'));
            cfg.per_point = struct();
            cfg.per_point.tilt = struct();
            cfg.per_point.tilt.Q1_Z = struct('offset_correction', -1.5);

            [~, vals, meta] = load_timeseries_range(tc.WorkRoot, '', 'Q1-Z', ...
                '2025-12-01', '2025-12-01', cfg, 'tilt');

            tc.verifyEqual(vals, [0.5; 1.5], 'AbsTol', 1e-10);
            tc.verifyEqual(meta.applied_offset_correction, -1.5);
        end

        function writeOffsetCorrectionReport(tc)
            offset_correction_registry('record', struct( ...
                'sensor_type', 'tilt', ...
                'point_id', 'Q1-Z', ...
                'offset_correction', -1.5, ...
                'start_time', datetime(2025,12,1,0,0,0), ...
                'end_time', datetime(2025,12,1,1,0,0), ...
                'sample_count', 2, ...
                'files', {{'a.xlsx'}}));
            offset_correction_registry('record', struct( ...
                'sensor_type', 'tilt', ...
                'point_id', 'Q1-Z', ...
                'offset_correction', -1.5, ...
                'start_time', datetime(2025,12,1,0,30,0), ...
                'end_time', datetime(2025,12,1,2,0,0), ...
                'sample_count', 3, ...
                'files', {{'b.xlsx'}}));

            [filepath, count] = offset_correction_registry('write', tc.WorkRoot, datetime(2026,1,1));
            T = readtable(filepath, 'TextType', 'string');

            tc.verifyTrue(isfile(filepath));
            tc.verifyEqual(count, 1);
            tc.verifyEqual(height(T), 1);
            tc.verifyEqual(T.PointID(1), "Q1-Z");
            tc.verifyEqual(T.OffsetCorrection(1), -1.5, 'AbsTol', 1e-10);
            tc.verifyEqual(T.SampleCount(1), 5);
            tc.verifyEqual(T.LoadCalls(1), 2);
            tc.verifyTrue(contains(T.Files(1), "a.xlsx"));
            tc.verifyTrue(contains(T.Files(1), "b.xlsx"));
        end
    end
end
