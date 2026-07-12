classdef AutoThresholdRequestRunner
    %AUTOTHRESHOLDREQUESTRUNNER Compiled-runner entry for proposal generation.

    methods (Static)
        function resultPath = runFile(requestPath)
            requestPath = char(string(requestPath));
            request = bms.io.JsonFile.read(requestPath);
            required = {'config_path', 'config_sha256', 'data_root', 'start_date', 'end_date', ...
                'status_path', 'result_path'};
            for i = 1:numel(required)
                if ~isfield(request, required{i}) || isempty(request.(required{i}))
                    error('BMS:AutoThresholdRequest:MissingField', ...
                        'Auto-threshold request missing field: %s', required{i});
                end
            end
            statusPath = char(string(request.status_path));
            resultPath = char(string(request.result_path));
            requestId = bms.app.AutoThresholdRequestRunner.textField(request, 'request_id');
            bms.app.AsyncRunService.writeStatus(statusPath, 'running', struct( ...
                'request_type', 'auto_threshold_proposal', ...
                'request_id', requestId, 'request_path', requestPath));
            try
                configPath = char(string(request.config_path));
                expectedConfigHash = lower(char(string(request.config_sha256)));
                actualConfigHash = bms.io.JsonFile.sha256(configPath);
                if ~strcmp(actualConfigHash, expectedConfigHash)
                    error('BMS:AutoThresholdRequest:ConfigChanged', ...
                        'Configuration changed after request creation: %s', configPath);
                end
                cfg = bms.core.ConfigStore.load(configPath);
                opts = struct();
                if isfield(request, 'options') && isstruct(request.options)
                    opts = request.options;
                end
                result = bms.config.AutoThresholdProposalService.generate( ...
                    cfg, char(string(request.data_root)), ...
                    char(string(request.start_date)), char(string(request.end_date)), opts);
                previewCount = 0;
                previewPath = bms.app.AutoThresholdRequestRunner.textField(request, 'preview_path');
                if isfield(result, 'preview_series')
                    previewCount = numel(result.preview_series);
                    if isempty(previewPath)
                        error('BMS:AutoThresholdRequest:MissingPreviewPath', ...
                            'preview_path is required when capture_preview_series is enabled.');
                    end
                    preview = struct('schema_version', 1, ...
                        'artifact_type', 'auto_threshold_preview', ...
                        'request_type', 'auto_threshold_proposal', ...
                        'request_id', requestId, ...
                        'config_sha256', actualConfigHash, ...
                        'preview_series', result.preview_series);
                    bms.core.Logger.writeJson(previewPath, preview);
                    result = rmfield(result, 'preview_series');
                    result.preview_path = previewPath;
                    result.preview_sha256 = bms.io.JsonFile.sha256(previewPath);
                    result.preview_series_count = previewCount;
                end
                result.request_type = 'auto_threshold_proposal';
                result.request_id = requestId;
                result.request_path = requestPath;
                result.config_path = configPath;
                result.config_sha256 = actualConfigHash;
                bms.core.Logger.writeJson(resultPath, result);
                proposalCount = 0;
                if isfield(result, 'summary') && isstruct(result.summary) ...
                        && isfield(result.summary, 'proposal_count')
                    proposalCount = result.summary.proposal_count;
                end
                bms.app.AsyncRunService.writeStatus(statusPath, 'completed', struct( ...
                    'request_type', 'auto_threshold_proposal', ...
                    'request_id', requestId, 'request_path', requestPath, ...
                    'result_path', resultPath, 'proposal_count', proposalCount, ...
                    'preview_path', previewPath, 'preview_series_count', previewCount));
            catch ME
                bms.app.AsyncRunService.writeStatus(statusPath, 'failed', struct( ...
                    'request_type', 'auto_threshold_proposal', ...
                    'request_id', requestId, 'request_path', requestPath, ...
                    'error_id', ME.identifier, 'message', ME.message));
                rethrow(ME);
            end
        end

        function value = textField(s, field)
            value = '';
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                value = char(string(s.(field)));
            end
        end
    end
end
