classdef test_auto_threshold_request_runner < matlab.unittest.TestCase
    properties
        TempDir
    end

    methods (TestMethodSetup)
        function makeTemp(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
        end
    end

    methods (TestMethodTeardown)
        function removeTemp(tc)
            if isfolder(tc.TempDir), rmdir(tc.TempDir, 's'); end
        end
    end

    methods (Test)
        function proposalCarriesEffectiveApplyKey(tc)
            opts = bms.config.AutoThresholdProposalService.defaultOptions();
            opts.use_auto_cut = false;
            opts.use_quantile = true;
            opts.use_mad = false;
            opts.use_iqr = false;
            opts.use_spike_window = false;
            opts.use_zero_or_flat = false;
            opts.min_valid_count = 3;
            opts.max_removed_ratio = 1;
            opts.padding_factor = 0;
            times = datetime(2026,1,1) + seconds(0:5);
            values = [0 1 2 3 4 100];
            rows = bms.config.AutoThresholdProposalService.generateForSeries( ...
                times, values, 'dynamic_strain', 'SX-1', 'strain', opts);
            tc.verifyNotEmpty(rows);
            tc.verifyEqual(rows(1).apply_key, 'dynamic_strain');
            tc.verifyEqual(rows(1).safe_id, 'SX_1');
        end

        function runnerWritesDeterministicStatusAndResult(tc)
            root = fileparts(fileparts(mfilename('fullpath')));
            configPath = fullfile(root, 'tests', 'fixtures', ...
                'workbench_cleaning_threshold_contract.json');
            requestPath = fullfile(tc.TempDir, 'request.json');
            statusPath = fullfile(tc.TempDir, 'status.json');
            resultPath = fullfile(tc.TempDir, 'result.json');
            request = struct();
            request.schema_version = 1;
            request.request_type = 'auto_threshold_proposal';
            request.request_id = 'matlab_unit';
            request.config_path = configPath;
            request.config_sha256 = bms.io.JsonFile.sha256(configPath);
            request.data_root = tc.TempDir;
            request.start_date = '2026-01-01';
            request.end_date = '2026-01-02';
            request.options = struct('module_keys', {{'temperature'}}, ...
                'capture_preview_series', false);
            request.status_path = statusPath;
            request.result_path = resultPath;
            bms.core.Logger.writeJson(requestPath, request);

            actual = bms.app.AutoThresholdRequestRunner.runFile(requestPath);
            tc.verifyEqual(actual, resultPath);
            status = jsondecode(fileread(statusPath));
            result = jsondecode(fileread(resultPath));
            tc.verifyEqual(status.status, 'completed');
            tc.verifyEqual(status.request_id, 'matlab_unit');
            tc.verifyEqual(result.request_type, 'auto_threshold_proposal');
            tc.verifyEqual(result.config_sha256, request.config_sha256);
        end

        function runnerRefusesConfigDriftBeforeProposalGeneration(tc)
            configPath = fullfile(tc.TempDir, 'config.json');
            bms.core.Logger.writeJson(configPath, struct('bridge_name', 'unit'));
            requestPath = fullfile(tc.TempDir, 'request_drift.json');
            request = struct('schema_version', 1, ...
                'request_type', 'auto_threshold_proposal', ...
                'request_id', 'drift_unit', ...
                'config_path', configPath, ...
                'config_sha256', repmat('0', 1, 64), ...
                'data_root', tc.TempDir, ...
                'start_date', '2026-01-01', ...
                'end_date', '2026-01-02', ...
                'options', struct(), ...
                'status_path', fullfile(tc.TempDir, 'drift_status.json'), ...
                'result_path', fullfile(tc.TempDir, 'drift_result.json'));
            bms.core.Logger.writeJson(requestPath, request);

            tc.verifyError(@() bms.app.AutoThresholdRequestRunner.runFile(requestPath), ...
                'BMS:AutoThresholdRequest:ConfigChanged');
            status = jsondecode(fileread(request.status_path));
            tc.verifyEqual(status.status, 'failed');
            tc.verifyEqual(status.error_id, 'BMS:AutoThresholdRequest:ConfigChanged');
            tc.verifyFalse(isfile(request.result_path));
        end

        function jsonReaderAcceptsUtf8Bom(tc)
            path = fullfile(tc.TempDir, 'bom.json');
            fid = fopen(path, 'wb');
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fwrite(fid, uint8([239 187 191]), 'uint8');
            fwrite(fid, unicode2native('{"request_type":"unit"}', 'UTF-8'), 'uint8');
            clear cleanup;
            value = bms.io.JsonFile.read(path);
            tc.verifyEqual(value.request_type, 'unit');
        end
    end
end
