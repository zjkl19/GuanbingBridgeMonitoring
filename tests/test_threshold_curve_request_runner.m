classdef test_threshold_curve_request_runner < matlab.unittest.TestCase
    properties
        TempDir
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TempDir = tempname;
            mkdir(fullfile(tc.TempDir, 'data', '2026-01-01', 'features'));
            tc.writeCsv(fullfile(tc.TempDir, 'data', '2026-01-01', ...
                'features', 'T-1.csv'));
        end
    end

    methods (TestMethodTeardown)
        function teardown(tc)
            bms.app.StopController.clear();
            bms.app.RunProgressReporter.clear();
            if isfolder(tc.TempDir), rmdir(tc.TempDir, 's'); end
        end
    end

    methods (Test)
        function runnerPublishesBoundPreviewRecordAndResult(tc)
            request = tc.request('completed');
            requestPath = fullfile(tc.TempDir, 'request.json');
            bms.core.Logger.writeJson(requestPath, request);

            actual = bms.app.ThresholdCurveRequestRunner.runFile(requestPath);

            tc.verifyEqual(actual, request.result_path);
            status = bms.io.JsonFile.read(request.status_path);
            result = bms.io.JsonFile.read(request.result_path);
            preview = bms.io.JsonFile.read(request.preview_path);
            record = bms.io.JsonFile.read(request.record_path);
            tc.verifyEqual(status.status, 'completed');
            tc.verifyEqual(status.progress_fraction, 1);
            tc.verifyEqual(status.progress_percent, 100);
            tc.verifyEqual(status.module_index, 1);
            tc.verifyEqual(status.module_total, 1);
            tc.verifyEqual(status.point_index, 1);
            tc.verifyEqual(status.point_total, 1);
            tc.verifyFalse(status.stop_requested);
            tc.verifyGreaterThanOrEqual(status.elapsed_seconds, 0);
            tc.verifyEqual(result.request_type, 'threshold_curve_generation');
            tc.verifyEqual(result.artifact_type, 'threshold_curve_generation_result');
            tc.verifyEqual(result.curve_record_count, 1);
            tc.verifyFalse(isfield(result, 'preview_series_count'));
            tc.verifyEqual(preview.artifact_type, 'threshold_curve_preview');
            tc.verifyEqual(preview.curve_records.point_id, 'T-1');
            tc.verifyFalse(isfield(preview, 'preview_series'));
            tc.verifyEqual(record.artifact_type, 'threshold_curve_record');
            tc.verifyEqual(record.curve_record_count, 1);
            tc.verifyFalse(isfield(record, 'preview_series_count'));
            tc.verifyEqual(record.preview_sha256, ...
                bms.io.JsonFile.sha256(request.preview_path));
            tc.verifyEqual(record.config_sha256, request.config_sha256);
            tc.verifyEqual(record.data_root, ...
                char(java.io.File(request.data_root).getCanonicalPath()));
            bms.config.ThresholdCurveRecordService.readRecord(request.record_path);
        end

        function preexistingStopFlagPublishesNoArtifacts(tc)
            request = tc.request('stopped');
            fid = fopen(request.stop_file, 'wt');
            fprintf(fid, 'stop\n');
            fclose(fid);
            requestPath = fullfile(tc.TempDir, 'stopped_request.json');
            bms.core.Logger.writeJson(requestPath, request);

            actual = bms.app.ThresholdCurveRequestRunner.runFile(requestPath);

            tc.verifyEmpty(actual);
            status = bms.io.JsonFile.read(request.status_path);
            tc.verifyEqual(status.status, 'stopped');
            tc.verifyTrue(status.stop_requested);
            tc.verifyFalse(isfield(status, 'stop_path'));
            tc.verifyEqual(status.total_dates, 1);
            tc.verifyEqual(status.progress_fraction, 0);
            tc.verifyFalse(isfile(request.result_path));
            tc.verifyFalse(isfile(request.preview_path));
            tc.verifyFalse(isfile(request.record_path));
            tc.verifyEmpty(dir(fullfile(tc.TempDir, '*.tmp.*')));
        end

        function dispatcherRoutesCurveRequest(tc)
            request = tc.request('dispatch');
            requestPath = fullfile(tc.TempDir, 'dispatch_request.json');
            bms.core.Logger.writeJson(requestPath, request);

            actual = run_request_cli(requestPath);

            tc.verifyEqual(actual, request.result_path);
            tc.verifyTrue(isfile(request.preview_path));
            tc.verifyTrue(isfile(request.record_path));
        end

        function legacyArtifactPathAliasesAreRejected(tc)
            request = tc.request('legacy_paths');
            request.threshold_curve_preview_path = request.preview_path;
            request.threshold_curve_record_path = request.record_path;
            request = rmfield(request, {'preview_path', 'record_path'});
            requestPath = fullfile(tc.TempDir, 'legacy_paths_request.json');
            bms.core.Logger.writeJson(requestPath, request);

            tc.verifyError(@() ...
                bms.app.ThresholdCurveRequestRunner.runFile(requestPath), ...
                'BMS:ThresholdCurveRequest:MissingField');
        end

        function hongtangSafeIdPublishesCanonicalPointId(tc)
            tc.writeCsv(fullfile(tc.TempDir, 'data', '2026-01-01', ...
                'features', 'SK-1.csv'));
            request = tc.request('hongtang_safe_id');
            cfg = tc.config();
            cfg.points = struct('strain', {{'SK-1'}});
            cfg.subfolders = struct('strain', 'features');
            cfg.file_patterns = struct('strain', struct( ...
                'default', {{'{point}.csv'}}, 'per_point', struct()));
            cfg.per_point = struct('strain', struct( ...
                'SK_1', struct('thresholds', struct('min', -150, 'max', 150))));
            bms.core.Logger.writeJson(request.config_path, cfg);
            request.config_sha256 = bms.io.JsonFile.sha256(request.config_path);
            request.module_key = 'strain';
            request.point_id = 'SK_1';
            requestPath = fullfile(tc.TempDir, 'hongtang_safe_id_request.json');
            bms.core.Logger.writeJson(requestPath, request);

            actual = bms.app.ThresholdCurveRequestRunner.runFile(requestPath);

            tc.verifyEqual(actual, request.result_path);
            result = bms.io.JsonFile.read(request.result_path);
            preview = bms.io.JsonFile.read(request.preview_path);
            record = bms.io.JsonFile.read(request.record_path);
            tc.verifyEqual(result.point_id, 'SK-1');
            tc.verifyEqual(preview.point_id, 'SK-1');
            tc.verifyEqual(preview.curve_records.point_id, 'SK-1');
            tc.verifyEqual(record.point_id, 'SK-1');
            tc.verifyFalse(isfield(preview, 'preview_series'));
        end

        function rejectsMultiplePointSelection(tc)
            request = tc.request('multi');
            request.point_id = {'T-1','T-2'};
            requestPath = fullfile(tc.TempDir, 'multi_request.json');
            bms.core.Logger.writeJson(requestPath, request);
            tc.verifyError(@() ...
                bms.app.ThresholdCurveRequestRunner.runFile(requestPath), ...
                'BMS:ThresholdCurveRequest:SingleSelectionRequired');
        end

        function invalidDateRangeWritesFailedStatus(tc)
            request = tc.request('bad_dates');
            request.start_date = '2026-01-02';
            request.end_date = '2026-01-01';
            requestPath = fullfile(tc.TempDir, 'bad_dates_request.json');
            bms.core.Logger.writeJson(requestPath, request);

            tc.verifyError(@() ...
                bms.app.ThresholdCurveRequestRunner.runFile(requestPath), ...
                'BMS:TimeRange:InvalidRange');
            status = bms.io.JsonFile.read(request.status_path);
            tc.verifyEqual(status.status, 'failed');
            tc.verifyEqual(status.error_id, 'BMS:TimeRange:InvalidRange');
            tc.verifyFalse(isfile(request.result_path));
        end
    end

    methods
        function request = request(tc, suffix)
            configPath = fullfile(tc.TempDir, ['config_' suffix '.json']);
            bms.core.Logger.writeJson(configPath, tc.config());
            request = struct( ...
                'schema_version', 1, ...
                'request_type', 'threshold_curve_generation', ...
                'request_id', ['curve_' suffix], ...
                'bridge_id', 'unit_bridge', ...
                'config_path', configPath, ...
                'config_sha256', bms.io.JsonFile.sha256(configPath), ...
                'data_root', fullfile(tc.TempDir, 'data'), ...
                'start_date', '2026-01-01', ...
                'end_date', '2026-01-01', ...
                'module_key', 'temperature', ...
                'point_id', 'T-1', ...
                'options', struct('preview_sample_count', 10), ...
                'stop_file', fullfile(tc.TempDir, ...
                    ['threshold_curve_stop_' suffix '.flag']), ...
                'status_path', fullfile(tc.TempDir, ['status_' suffix '.json']), ...
                'result_path', fullfile(tc.TempDir, ['result_' suffix '.json']), ...
                'preview_path', fullfile(tc.TempDir, ['preview_' suffix '.json']), ...
                'record_path', fullfile(tc.TempDir, ['record_' suffix '.json']));
        end

        function cfg = config(~)
            cfg = struct( ...
                'bridge_id', 'unit_bridge', ...
                'vendor', 'donghua', ...
                'time_series', struct('require_metadata', false), ...
                'defaults', struct('header_marker', '__no_header__'), ...
                'points', struct('temperature', {{'T-1'}}), ...
                'subfolders', struct('temperature', 'features'), ...
                'file_patterns', struct('temperature', struct( ...
                    'default', {{'{point}.csv'}}, 'per_point', struct())), ...
                'per_point', struct());
        end

        function writeCsv(~, path)
            fid = fopen(path, 'wt');
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            for i = 1:12
                fprintf(fid, '2026-01-01 00:%02d:00,%.6f\n', i - 1, sin(i));
            end
        end
    end
end
