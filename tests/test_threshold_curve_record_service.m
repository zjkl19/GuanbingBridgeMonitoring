classdef test_threshold_curve_record_service < matlab.unittest.TestCase
    properties
        TempDir
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TempDir = tempname;
            mkdir(fullfile(tc.TempDir, '2026-01-01', 'features', 'cache'));
        end
    end

    methods (TestMethodTeardown)
        function teardown(tc)
            if isfolder(tc.TempDir), rmdir(tc.TempDir, 's'); end
        end
    end

    methods (Test)
        function generatesSingleCurveFromPreferredMatCache(tc)
            cfg = tc.minimalConfig();
            csvPath = fullfile(tc.TempDir, '2026-01-01', 'features', 'T-1.csv');
            tc.writeCsv(csvPath, 100 + (1:5));
            times = datenum(datetime(2026,1,1) + minutes(0:4)); %#ok<DATNM,NASGU>
            vals = (1:5)'; %#ok<NASGU>
            save(fullfile(tc.TempDir, '2026-01-01', 'features', ...
                'cache', 'T-1.mat'), 'times', 'vals');

            [curve, fullTimes, fullValues] = ...
                bms.config.ThresholdCurveRecordService.generate( ...
                cfg, tc.TempDir, '2026-01-01', '2026-01-01', ...
                'temperature', 'T-1', struct('preview_sample_count', 3));

            tc.verifyEqual(fullValues, (1:5)');
            tc.verifyNumElements(fullTimes, 5);
            tc.verifyEqual(curve.module_key, 'temperature');
            tc.verifyEqual(curve.point_id, 'T-1');
            tc.verifyEqual(curve.source_sample_count, 5);
            tc.verifyEqual(curve.finite_sample_count, 5);
            tc.verifyLessThanOrEqual(curve.sample_count, 3);
            tc.verifyTrue(endsWith(string(curve.source_files{1}), 'T-1.mat'));
            tc.verifyFalse(isfield(curve, 'proposals'));
        end

        function recordLoaderVerifiesPreviewHashAndBinding(tc)
            curve = struct( ...
                'module_key', 'temperature', 'point_id', 'T-1', ...
                'sensor_type', 'temperature', ...
                'times', datetime(2026,1,1), 'values', 1, ...
                'sample_count', 1, 'source_sample_count', 1, ...
                'finite_sample_count', 1, 'source_files', {{'source.mat'}});
            binding = tc.binding();
            previewPath = fullfile(tc.TempDir, 'preview.json');
            recordPath = fullfile(tc.TempDir, 'record.json');
            preview = bms.config.ThresholdCurveRecordService. ...
                buildPreview(binding, curve);
            tc.verifyFalse(isfield(preview, 'preview_series'));
            tc.verifyFalse(isfield(preview.curve_records, 'source_count'));
            tc.verifyFalse(isfield(preview.curve_records, 'finite_count'));
            bms.core.Logger.writeJson(previewPath, preview);
            rawPreview = fileread(previewPath);
            tc.verifyTrue(contains(rawPreview, '"times":['));
            tc.verifyTrue(contains(rawPreview, '"values":['));
            record = bms.config.ThresholdCurveRecordService.buildRecord( ...
                binding, curve, previewPath, bms.io.JsonFile.sha256(previewPath));
            tc.verifyEqual(record.curve_record_count, 1);
            tc.verifyFalse(isfield(record, 'preview_series_count'));
            bms.core.Logger.writeJson(recordPath, record);

            [loaded, loadedPreview] = ...
                bms.config.ThresholdCurveRecordService.readRecord(recordPath);
            tc.verifyEqual(loaded.artifact_type, 'threshold_curve_record');
            tc.verifyEqual(loadedPreview.artifact_type, 'threshold_curve_preview');
            tc.verifyEqual(loadedPreview.curve_records.point_id, 'T-1');

            preview.tampered = true;
            bms.core.Logger.writeJson(previewPath, preview);
            tc.verifyError(@() ...
                bms.config.ThresholdCurveRecordService.readRecord(recordPath), ...
                'BMS:ThresholdCurve:PreviewHashChanged');
        end

        function rejectsLegacySelfContainedCurveRecord(tc)
            legacyPath = fullfile(tc.TempDir, 'legacy_record.json');
            legacy = struct( ...
                'schema_version', 1, ...
                'artifact_type', 'threshold_curve_record', ...
                'request_type', 'threshold_curve_generation', ...
                'request_id', 'legacy_unit', ...
                'curve_records', struct( ...
                    'module_key', 'strain', ...
                    'point_id', 'SK-1', ...
                    'sensor_type', 'strain', ...
                    'times', {{'2026-01-01 00:00:00'}}, ...
                    'values', {{1}}, ...
                    'sample_count', 1));
            bms.core.Logger.writeJson(legacyPath, legacy);

            tc.verifyError(@() ...
                bms.config.ThresholdCurveRecordService.readRecord(legacyPath), ...
                'BMS:ThresholdCurve:InvalidRecord');
        end

        function resolvesHongtangSafeIdToCanonicalPoint(tc)
            cfg = tc.hongtangStyleConfig({'SK-1'});
            strainDir = fullfile(tc.TempDir, '2026-01-01', 'strain_features');
            mkdir(strainDir);
            tc.writeCsv(fullfile(strainDir, 'SK-1.csv'), 1:5);

            curve = bms.config.ThresholdCurveRecordService.generate( ...
                cfg, tc.TempDir, '2026-01-01', '2026-01-01', ...
                'strain', 'SK_1', struct());

            tc.verifyEqual(curve.module_key, 'strain');
            tc.verifyEqual(curve.point_id, 'SK-1');
            tc.verifyEqual(curve.sensor_type, 'strain');
            tc.verifyGreaterThan(curve.source_sample_count, 0);
        end

        function rejectsAmbiguousHongtangSafeId(tc)
            cfg = tc.hongtangStyleConfig({'SK-1', 'SK_1'});

            tc.verifyError(@() ...
                bms.config.ThresholdCurveRecordService.generate( ...
                cfg, tc.TempDir, '2026-01-01', '2026-01-01', ...
                'strain', 'SK_1', struct()), ...
                'BMS:ThresholdCurve:PointAliasAmbiguous');
        end

        function rejectsMultiplePointsAndReverseDates(tc)
            cfg = tc.minimalConfig();
            tc.verifyError(@() bms.config.ThresholdCurveRecordService.generate( ...
                cfg, tc.TempDir, '2026-01-01', '2026-01-01', ...
                'temperature', {'T-1','T-2'}, struct()), ...
                'BMS:ThresholdCurve:SingleSelectionRequired');
            tc.verifyError(@() bms.config.ThresholdCurveRecordService.generate( ...
                cfg, tc.TempDir, '2026-01-02', '2026-01-01', ...
                'temperature', 'T-1', struct()), ...
                'BMS:TimeRange:InvalidRange');
        end
    end

    methods
        function cfg = minimalConfig(~)
            cfg = struct();
            cfg.vendor = 'donghua';
            cfg.time_series = struct('source_mode', 'auto', ...
                'require_metadata', false);
            cfg.defaults = struct('header_marker', '__no_header__', ...
                'temperature', struct('thresholds', struct('min', -1, 'max', 1)));
            cfg.points = struct('temperature', {{'T-1'}});
            cfg.subfolders = struct('temperature', 'features');
            cfg.file_patterns = struct('temperature', struct( ...
                'default', {{'{point}.csv'}}, 'per_point', struct()));
            cfg.per_point = struct();
        end

        function cfg = hongtangStyleConfig(~, points)
            cfg = struct();
            cfg.vendor = 'donghua';
            cfg.time_series = struct('source_mode', 'auto', ...
                'require_metadata', false);
            cfg.defaults = struct('header_marker', '__no_header__');
            cfg.points = struct('strain', {points});
            cfg.subfolders = struct('strain', 'strain_features');
            cfg.file_patterns = struct('strain', struct( ...
                'default', {{'{point}.csv'}}, 'per_point', struct()));
            cfg.per_point = struct('strain', struct( ...
                'SK_1', struct('thresholds', struct('min', -150, 'max', 150))));
        end

        function writeCsv(~, path, values)
            fid = fopen(path, 'wt');
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            for i = 1:numel(values)
                fprintf(fid, '2026-01-01 00:%02d:00,%.6f\n', i - 1, values(i));
            end
        end

        function value = binding(tc)
            value = struct( ...
                'request_type', 'threshold_curve_generation', ...
                'request_id', 'record_unit', ...
                'bridge_id', 'unit_bridge', ...
                'config_path', fullfile(tc.TempDir, 'config.json'), ...
                'config_sha256', repmat('a', 1, 64), ...
                'data_root', tc.TempDir, ...
                'start_date', '2026-01-01', ...
                'end_date', '2026-01-01', ...
                'module_key', 'temperature', ...
                'point_id', 'T-1', ...
                'sensor_type', 'temperature');
        end
    end
end
