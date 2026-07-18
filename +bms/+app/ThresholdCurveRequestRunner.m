classdef ThresholdCurveRequestRunner
    %THRESHOLDCURVEREQUESTRUNNER Execute one curve-only background request.

    methods (Static)
        function resultPath = runFile(requestPath)
            requestPath = char(string(requestPath));
            request = bms.io.JsonFile.read(requestPath);
            bms.app.ThresholdCurveRequestRunner.validateRequest(request);
            statusPath = bms.app.ThresholdCurveRequestRunner.textField(request, 'status_path');
            resultPath = bms.app.ThresholdCurveRequestRunner.textField(request, 'result_path');
            previewPath = bms.app.ThresholdCurveRequestRunner. ...
                textField(request, 'preview_path');
            recordPath = bms.app.ThresholdCurveRequestRunner. ...
                textField(request, 'record_path');
            stopFile = bms.app.ThresholdCurveRequestRunner.stopFile(request);
            requestId = bms.app.ThresholdCurveRequestRunner.textField(request, 'request_id');
            moduleKey = bms.app.ThresholdCurveRequestRunner.singleText( ...
                request.module_key, 'module_key');
            pointId = bms.app.ThresholdCurveRequestRunner.singleText( ...
                request.point_id, 'point_id');
            timer = tic;
            base = struct( ...
                'request_type', 'threshold_curve_generation', ...
                'request_id', requestId, ...
                'request_path', requestPath, ...
                'module_key', moduleKey, ...
                'point_id', pointId, ...
                'module_index', 1, ...
                'module_total', 1, ...
                'point_index', 1, ...
                'point_total', 1, ...
                'stop_file', stopFile, ...
                'stop_requested', bms.app.ThresholdCurveRequestRunner. ...
                    stopRequested(stopFile));
            totalDates = bms.app.ThresholdCurveRequestRunner.safeDateCount( ...
                request.start_date, request.end_date);
            bms.app.ThresholdCurveRequestRunner.writeProgress( ...
                statusPath, 'running', base, 'validate_request', '', 0, ...
                totalDates, 0, toc(timer));

            bms.app.StopController.configure(stopFile);
            stopGuard = onCleanup(@() bms.app.StopController.clear()); %#ok<NASGU>
            reporterGuard = onCleanup(@() bms.app.RunProgressReporter.clear()); %#ok<NASGU>
            previewTemp = '';
            recordTemp = '';
            resultPathTemp = '';
            publishingStarted = false;
            try
                bms.app.StopController.throwIfRequested( ...
                    'Curve generation was stopped before validation.');
                configPath = bms.app.ThresholdCurveRequestRunner. ...
                    canonicalPath(request.config_path);
                expectedConfigHash = lower(char(string(request.config_sha256)));
                actualConfigHash = ...
                    bms.config.ConfigLayerLoader.dependencySha256(configPath);
                if ~strcmpi(actualConfigHash, expectedConfigHash)
                    error('BMS:ThresholdCurveRequest:ConfigChanged', ...
                        'Configuration changed after request creation: %s', configPath);
                end
                cfg = bms.core.ConfigStore.load(configPath);
                bms.app.ThresholdCurveRequestRunner.verifyBridge(cfg, request.bridge_id);
                dataRoot = bms.app.ThresholdCurveRequestRunner. ...
                    canonicalPath(request.data_root);
                startDate = bms.data.TimeRangeResolver.normalizeDateText(request.start_date);
                endDate = bms.data.TimeRangeResolver.normalizeDateText(request.end_date);
                bms.data.TimeRangeResolver.parseRange(startDate, endDate);
                options = struct();
                if isfield(request, 'options') && isstruct(request.options)
                    options = request.options;
                end

                def = bms.app.StepDefinition.fromKey(moduleKey);
                progressFcn = @(payload) ...
                    bms.app.ThresholdCurveRequestRunner.reporterProgress( ...
                    statusPath, base, payload, timer, stopFile);
                bms.app.RunProgressReporter.configure({def}, progressFcn);
                bms.app.RunProgressReporter.startModule(1);
                [curve, ~, ~, ~] = ...
                    bms.config.ThresholdCurveRecordService.generate( ...
                    cfg, dataRoot, startDate, endDate, moduleKey, pointId, options);
                bms.app.StopController.throwIfRequested( ...
                    'Curve generation was stopped before artifact publication.');

                binding = struct( ...
                    'request_type', 'threshold_curve_generation', ...
                    'request_id', requestId, ...
                    'bridge_id', strtrim(char(string(request.bridge_id))), ...
                    'config_path', configPath, ...
                    'config_sha256', actualConfigHash, ...
                    'data_root', dataRoot, ...
                    'start_date', startDate, ...
                    'end_date', endDate, ...
                    'module_key', moduleKey, ...
                    'point_id', curve.point_id, ...
                    'sensor_type', curve.sensor_type);
                bms.app.ThresholdCurveRequestRunner.assertOutputAbsent( ...
                    {previewPath, recordPath, resultPath});
                preview = bms.config.ThresholdCurveRecordService. ...
                    buildPreview(binding, curve);
                previewTemp = bms.app.ThresholdCurveRequestRunner. ...
                    temporarySibling(previewPath);
                bms.core.Logger.writeJson(previewTemp, preview);
                previewHash = bms.io.JsonFile.sha256(previewTemp);

                record = bms.config.ThresholdCurveRecordService.buildRecord( ...
                    binding, curve, previewPath, previewHash);
                recordTemp = bms.app.ThresholdCurveRequestRunner. ...
                    temporarySibling(recordPath);
                bms.core.Logger.writeJson(recordTemp, record);
                recordHash = bms.io.JsonFile.sha256(recordTemp);
                result = binding;
                result.schema_version = 1;
                result.artifact_type = 'threshold_curve_generation_result';
                result.created_at = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss');
                result.request_path = requestPath;
                result.preview_path = previewPath;
                result.preview_sha256 = previewHash;
                result.record_path = recordPath;
                result.record_sha256 = recordHash;
                result.curve_record_count = 1;
                result.source_sample_count = curve.source_sample_count;
                result.finite_sample_count = curve.finite_sample_count;
                result.sample_count = curve.sample_count;
                resultPathTemp = bms.app.ThresholdCurveRequestRunner. ...
                    temporarySibling(resultPath);
                bms.core.Logger.writeJson(resultPathTemp, result);

                bms.app.StopController.throwIfRequested( ...
                    'Curve generation was stopped before artifact publication.');
                publishingStarted = true;
                bms.app.ThresholdCurveRequestRunner.publish(previewTemp, previewPath);
                bms.app.ThresholdCurveRequestRunner.publish(recordTemp, recordPath);
                bms.app.ThresholdCurveRequestRunner.publish(resultPathTemp, resultPath);
                publishingStarted = false;
                bms.app.RunProgressReporter.completeModule(1, ...
                    struct('status', 'completed', 'message', ...
                    sprintf('Curve generated with %d source samples.', ...
                    curve.source_sample_count)));
                completed = base;
                completed.result_path = resultPath;
                completed.preview_path = previewPath;
                completed.preview_sha256 = previewHash;
                completed.record_path = recordPath;
                completed.record_sha256 = recordHash;
                completed.source_sample_count = curve.source_sample_count;
                completed.finite_sample_count = curve.finite_sample_count;
                completed.sample_count = curve.sample_count;
                bms.app.ThresholdCurveRequestRunner.writeProgress( ...
                    statusPath, 'completed', completed, 'completed', endDate, ...
                    totalDates, totalDates, 1, toc(timer));
            catch ME
                bms.app.ThresholdCurveRequestRunner.deleteFiles( ...
                    {previewTemp, recordTemp, resultPathTemp});
                if publishingStarted
                    % These paths were proven absent immediately before this
                    % request began publication, so rollback removes only
                    % incomplete artifacts created by this request.
                    bms.app.ThresholdCurveRequestRunner.deleteFiles( ...
                        {previewPath, recordPath, resultPath});
                end
                if strcmp(ME.identifier, 'BMS:RunStopped')
                    stopped = bms.app.ThresholdCurveRequestRunner. ...
                        lastProgress(statusPath, base);
                    stopped.stop_requested = true;
                    stopped.message = '已安全停止曲线生成；未发布正式曲线产物。';
                    stoppedDate = bms.app.ThresholdCurveRequestRunner. ...
                        textField(stopped, 'current_date');
                    stoppedProcessed = bms.app.ThresholdCurveRequestRunner. ...
                        numberField(stopped, 'processed_dates', 0);
                    stoppedTotal = bms.app.ThresholdCurveRequestRunner. ...
                        numberField(stopped, 'total_dates', totalDates);
                    stoppedFraction = bms.app.ThresholdCurveRequestRunner. ...
                        numberField(stopped, 'progress_fraction', 0);
                    bms.app.ThresholdCurveRequestRunner.writeProgress( ...
                        statusPath, 'stopped', stopped, 'stopped', stoppedDate, ...
                        stoppedProcessed, stoppedTotal, stoppedFraction, toc(timer));
                    resultPath = '';
                    return;
                end
                failed = bms.app.ThresholdCurveRequestRunner. ...
                    lastProgress(statusPath, base);
                failed.error_id = ME.identifier;
                failed.message = ME.message;
                failedDate = bms.app.ThresholdCurveRequestRunner. ...
                    textField(failed, 'current_date');
                failedProcessed = bms.app.ThresholdCurveRequestRunner. ...
                    numberField(failed, 'processed_dates', 0);
                failedTotal = bms.app.ThresholdCurveRequestRunner. ...
                    numberField(failed, 'total_dates', totalDates);
                failedFraction = bms.app.ThresholdCurveRequestRunner. ...
                    numberField(failed, 'progress_fraction', 0);
                bms.app.ThresholdCurveRequestRunner.writeProgress( ...
                    statusPath, 'failed', failed, 'failed', failedDate, ...
                    failedProcessed, failedTotal, failedFraction, toc(timer));
                rethrow(ME);
            end
        end
    end

    methods (Static, Access = private)
        function validateRequest(request)
            if ~isstruct(request)
                error('BMS:ThresholdCurveRequest:InvalidRequest', ...
                    'Curve request must be a JSON object.');
            end
            required = {'bridge_id', 'config_path', 'config_sha256', ...
                'data_root', 'start_date', 'end_date', 'module_key', ...
                'point_id', 'status_path', 'result_path'};
            for i = 1:numel(required)
                if ~isfield(request, required{i}) || isempty(request.(required{i}))
                    error('BMS:ThresholdCurveRequest:MissingField', ...
                        'Curve request missing field: %s', required{i});
                end
            end
            requestType = bms.app.ThresholdCurveRequestRunner. ...
                textField(request, 'request_type');
            if ~strcmpi(requestType, 'threshold_curve_generation')
                error('BMS:ThresholdCurveRequest:InvalidType', ...
                    'Expected request_type threshold_curve_generation.');
            end
            bms.app.ThresholdCurveRequestRunner.singleText( ...
                request.module_key, 'module_key');
            bms.app.ThresholdCurveRequestRunner.singleText( ...
                request.point_id, 'point_id');
            previewPath = bms.app.ThresholdCurveRequestRunner. ...
                textField(request, 'preview_path');
            recordPath = bms.app.ThresholdCurveRequestRunner. ...
                textField(request, 'record_path');
            if isempty(previewPath)
                error('BMS:ThresholdCurveRequest:MissingField', ...
                    'Curve request missing field: preview_path');
            end
            if isempty(recordPath)
                error('BMS:ThresholdCurveRequest:MissingField', ...
                    'Curve request missing field: record_path');
            end
            paths = {request.result_path, previewPath, recordPath};
            normalized = cellfun(@(value) lower( ...
                bms.app.ThresholdCurveRequestRunner.canonicalPath(value)), ...
                paths, 'UniformOutput', false);
            if numel(unique(normalized)) ~= numel(normalized)
                error('BMS:ThresholdCurveRequest:ArtifactPathCollision', ...
                    'result_path, preview_path and record_path must be different.');
            end
        end

        function reporterProgress(statusPath, base, payload, timer, stopFile)
            processed = bms.app.ThresholdCurveRequestRunner.numberField( ...
                payload, 'processed_dates', 0);
            total = bms.app.ThresholdCurveRequestRunner.numberField( ...
                payload, 'total_dates', 0);
            fraction = 0;
            if total > 0
                fraction = processed / total;
            end
            currentDate = bms.app.ThresholdCurveRequestRunner. ...
                textField(payload, 'current_date');
            stage = bms.app.ThresholdCurveRequestRunner. ...
                textField(payload, 'stage');
            details = base;
            details.stop_requested = ...
                bms.app.ThresholdCurveRequestRunner.stopRequested(stopFile);
            bms.app.ThresholdCurveRequestRunner.writeProgress( ...
                statusPath, 'running', details, stage, currentDate, ...
                processed, total, fraction, toc(timer));
        end

        function writeProgress(statusPath, statusText, details, stage, ...
                currentDate, processedDates, totalDates, fraction, elapsed)
            details.stage = char(string(stage));
            details.current_date = char(string(currentDate));
            details.processed_dates = double(processedDates);
            details.total_dates = double(totalDates);
            details.progress_fraction = min(1, max(0, double(fraction)));
            details.progress_percent = details.progress_fraction * 100;
            details.elapsed_seconds = max(0, double(elapsed));
            details.elapsed_sec = details.elapsed_seconds;
            bms.app.AsyncRunService.writeStatus(statusPath, statusText, details);
        end

        function verifyBridge(cfg, requested)
            if isstruct(cfg) && isfield(cfg, 'bridge_id') ...
                    && ~isempty(cfg.bridge_id) ...
                    && ~strcmpi(strtrim(char(string(cfg.bridge_id))), ...
                    strtrim(char(string(requested))))
                error('BMS:ThresholdCurveRequest:BridgeMismatch', ...
                    'Request bridge_id does not match the loaded configuration.');
            end
        end

        function path = stopFile(request)
            path = bms.app.ThresholdCurveRequestRunner.textField(request, 'stop_file');
            if ~isempty(path)
                path = bms.app.ThresholdCurveRequestRunner.canonicalPath(path);
            end
        end

        function tf = stopRequested(path)
            tf = false;
            try
                tf = ~isempty(path) && isfile(path);
            catch
            end
        end

        function value = textField(s, field)
            value = '';
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                value = char(string(s.(field)));
            end
        end

        function value = numberField(s, field, fallback)
            value = fallback;
            if isstruct(s) && isfield(s, field) && isnumeric(s.(field)) ...
                    && isscalar(s.(field)) && isfinite(s.(field))
                value = double(s.(field));
            end
        end

        function n = safeDateCount(startDate, endDate)
            n = 0;
            try
                n = numel(bms.data.TimeRangeResolver.daysBetween(startDate, endDate));
            catch
            end
        end

        function details = lastProgress(statusPath, fallback)
            details = fallback;
            try
                if isfile(statusPath)
                    value = bms.io.JsonFile.read(statusPath);
                    if isstruct(value)
                        details = value;
                    end
                end
            catch
            end
        end

        function text = singleText(value, field)
            if iscell(value) || (isstring(value) && numel(value) ~= 1) ...
                    || (ischar(value) && size(value, 1) ~= 1)
                error('BMS:ThresholdCurveRequest:SingleSelectionRequired', ...
                    '%s must contain exactly one value.', field);
            end
            text = strtrim(char(string(value)));
            if isempty(text)
                error('BMS:ThresholdCurveRequest:SingleSelectionRequired', ...
                    '%s must contain exactly one non-empty value.', field);
            end
        end

        function path = canonicalPath(value)
            path = char(string(value));
            try
                path = char(java.io.File(path).getCanonicalPath());
            catch
                path = bms.profile.BridgeProfile.normalizePathText(path);
            end
        end

        function path = temporarySibling(finalPath)
            finalPath = char(string(finalPath));
            folder = fileparts(finalPath);
            if ~isempty(folder) && ~isfolder(folder)
                mkdir(folder);
            end
            path = [finalPath '.tmp.' char(java.util.UUID.randomUUID())];
        end

        function publish(tempPath, finalPath)
            [ok, message] = movefile(tempPath, finalPath, 'f');
            if ~ok
                error('BMS:ThresholdCurveRequest:PublishFailed', ...
                    'Unable to publish curve artifact %s: %s', finalPath, message);
            end
        end

        function assertOutputAbsent(paths)
            for i = 1:numel(paths)
                if isfile(paths{i})
                    error('BMS:ThresholdCurveRequest:OutputExists', ...
                        'Curve request refuses to overwrite an existing artifact: %s', ...
                        paths{i});
                end
            end
        end

        function deleteFiles(paths)
            for i = 1:numel(paths)
                try
                    if isfile(paths{i}), delete(paths{i}); end
                catch
                end
            end
        end
    end
end
