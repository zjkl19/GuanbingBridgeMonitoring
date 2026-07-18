classdef AutoThresholdRequestRunner
    %AUTOTHRESHOLDREQUESTRUNNER Compiled-runner entry for Beta proposals.

    methods (Static)
        function resultPath = runFile(requestPath)
            requestPath = char(string(requestPath));
            request = bms.io.JsonFile.read(requestPath);
            required = {'bridge_id', 'config_path', 'config_sha256', ...
                'data_root', 'start_date', 'end_date', 'status_path', 'result_path'};
            for i = 1:numel(required)
                if ~isfield(request, required{i}) || isempty(request.(required{i}))
                    error('BMS:AutoThresholdRequest:MissingField', ...
                        'Auto-threshold request missing field: %s', required{i});
                end
            end
            statusPath = char(string(request.status_path));
            resultPath = char(string(request.result_path));
            requestId = bms.app.AutoThresholdRequestRunner.textField(request, 'request_id');
            stopFile = bms.app.AutoThresholdRequestRunner.stopFile(request);
            timer = tic;
            base = struct( ...
                'request_type', 'auto_threshold_proposal', ...
                'request_id', requestId, ...
                'request_path', requestPath, ...
                'module_key', '', ...
                'point_id', '', ...
                'module_index', 0, ...
                'module_total', 0, ...
                'point_index', 0, ...
                'point_total', 0, ...
                'stage', 'validate_request', ...
                'current_date', '', ...
                'processed_dates', 0, ...
                'total_dates', 0, ...
                'progress_fraction', 0, ...
                'progress_percent', 0, ...
                'elapsed_seconds', 0, ...
                'elapsed_sec', 0, ...
                'stop_file', stopFile, ...
                'stop_requested', bms.app.AutoThresholdRequestRunner. ...
                    stopRequested(stopFile));
            bms.app.AsyncRunService.writeStatus(statusPath, 'running', base);
            bms.app.StopController.configure(stopFile);
            stopGuard = onCleanup(@() bms.app.StopController.clear()); %#ok<NASGU>
            reporterGuard = onCleanup(@() bms.app.RunProgressReporter.clear()); %#ok<NASGU>
            try
                bms.app.StopController.throwIfRequested( ...
                    'Auto-threshold proposal generation was safely stopped.');
                configPath = bms.app.AutoThresholdRequestRunner.canonicalPath(request.config_path);
                expectedConfigHash = lower(char(string(request.config_sha256)));
                actualConfigHash = bms.config.ConfigLayerLoader.dependencySha256(configPath);
                if ~strcmpi(actualConfigHash, expectedConfigHash)
                    error('BMS:AutoThresholdRequest:ConfigChanged', ...
                        'Configuration changed after request creation: %s', configPath);
                end
                cfg = bms.core.ConfigStore.load(configPath);
                opts = struct();
                if isfield(request, 'options') && isstruct(request.options)
                    opts = request.options;
                end
                dataRoot = bms.app.AutoThresholdRequestRunner.canonicalPath(request.data_root);
                startDate = bms.data.TimeRangeResolver.normalizeDateText(request.start_date);
                endDate = bms.data.TimeRangeResolver.normalizeDateText(request.end_date);
                bms.data.TimeRangeResolver.parseRange(startDate, endDate);
                modules = bms.config.AutoThresholdProposalService.modulesForOptions(opts);
                plan = cell(1, numel(modules));
                for i = 1:numel(modules)
                    plan{i} = bms.app.StepDefinition.fromKey(modules{i});
                end
                progressFcn = @(payload) ...
                    bms.app.AutoThresholdRequestRunner.reportProgress( ...
                    statusPath, base, payload, cfg, timer, stopFile);
                bms.app.RunProgressReporter.configure(plan, progressFcn);
                result = bms.config.AutoThresholdProposalService.generate( ...
                    cfg, dataRoot, startDate, endDate, opts);
                bms.app.StopController.throwIfRequested( ...
                    'Auto-threshold proposal generation stopped before publishing artifacts.');

                previewCount = 0;
                previewPath = bms.app.AutoThresholdRequestRunner.textField(request, 'preview_path');
                if isfield(result, 'curve_records')
                    previewCount = numel(result.curve_records);
                    if isempty(previewPath)
                        error('BMS:AutoThresholdRequest:MissingPreviewPath', ...
                            'preview_path is required when capture_curve_records is enabled.');
                    end
                    serializedCurves = bms.config.ThresholdCurveRecordService. ...
                        serializableCurves(result.curve_records);
                    preview = struct('schema_version', 1, ...
                        'artifact_type', 'auto_threshold_preview', ...
                        'request_type', 'auto_threshold_proposal', ...
                        'request_id', requestId, ...
                        'bridge_id', strtrim(char(string(request.bridge_id))), ...
                        'config_sha256', actualConfigHash, ...
                        'data_root', dataRoot, ...
                        'start_date', startDate, ...
                        'end_date', endDate, ...
                        'curve_records', serializedCurves);
                    bms.core.Logger.writeJson(previewPath, preview);
                    result = rmfield(result, 'curve_records');
                    result.preview_path = previewPath;
                    result.preview_sha256 = bms.io.JsonFile.sha256(previewPath);
                    result.curve_record_count = previewCount;
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
                completed = base;
                completed.module_index = numel(modules);
                completed.module_total = numel(modules);
                completed.stage = 'completed';
                completed.progress_fraction = 1;
                completed.progress_percent = 100;
                completed.elapsed_seconds = toc(timer);
                completed.elapsed_sec = completed.elapsed_seconds;
                completed.stop_requested = false;
                completed.result_path = resultPath;
                completed.proposal_count = proposalCount;
                completed.preview_path = previewPath;
                completed.curve_record_count = previewCount;
                bms.app.AsyncRunService.writeStatus(statusPath, 'completed', completed);
            catch ME
                terminal = bms.app.AutoThresholdRequestRunner. ...
                    lastProgress(statusPath, base);
                terminal.elapsed_seconds = toc(timer);
                terminal.elapsed_sec = terminal.elapsed_seconds;
                terminal.stop_requested = bms.app.AutoThresholdRequestRunner. ...
                    stopRequested(stopFile);
                if strcmp(ME.identifier, 'BMS:RunStopped')
                    terminal.stage = 'stopped';
                    terminal.stop_requested = true;
                    terminal.message = '已安全停止自动清洗建议；未发布正式建议产物。';
                    bms.app.AsyncRunService.writeStatus(statusPath, 'stopped', terminal);
                    resultPath = '';
                    return;
                end
                terminal.stage = 'failed';
                terminal.error_id = ME.identifier;
                terminal.message = ME.message;
                bms.app.AsyncRunService.writeStatus(statusPath, 'failed', terminal);
                rethrow(ME);
            end
        end

        function value = textField(s, field)
            value = '';
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                value = char(string(s.(field)));
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
    end

    methods (Static, Access = private)
        function reportProgress(statusPath, base, payload, cfg, timer, stopFile)
            details = base;
            details.module_key = bms.app.AutoThresholdRequestRunner. ...
                textField(payload, 'current_module_key');
            details.point_id = bms.app.AutoThresholdRequestRunner. ...
                textField(payload, 'current_point_id');
            details.module_index = bms.app.AutoThresholdRequestRunner. ...
                numberField(payload, 'module_index', 0);
            details.module_total = bms.app.AutoThresholdRequestRunner. ...
                numberField(payload, 'module_total', 0);
            details.stage = bms.app.AutoThresholdRequestRunner. ...
                textField(payload, 'stage');
            details.current_date = bms.app.AutoThresholdRequestRunner. ...
                textField(payload, 'current_date');
            details.processed_dates = bms.app.AutoThresholdRequestRunner. ...
                numberField(payload, 'processed_dates', 0);
            details.total_dates = bms.app.AutoThresholdRequestRunner. ...
                numberField(payload, 'total_dates', 0);
            [details.point_index, details.point_total] = ...
                bms.app.AutoThresholdRequestRunner.pointPosition( ...
                cfg, details.module_key, details.point_id);
            pointFraction = 0;
            if details.total_dates > 0
                pointFraction = min(1, max(0, ...
                    details.processed_dates / details.total_dates));
            elseif strcmp(details.stage, 'point_complete')
                pointFraction = 1;
            end
            moduleFraction = 0;
            if details.point_total > 0 && details.point_index > 0
                moduleFraction = (details.point_index - 1 + pointFraction) ...
                    / details.point_total;
            elseif ismember(details.stage, {'completed', 'skipped'})
                moduleFraction = 1;
            end
            if details.module_total > 0 && details.module_index > 0
                fraction = (details.module_index - 1 + moduleFraction) ...
                    / details.module_total;
            else
                fraction = 0;
            end
            details.progress_fraction = min(1, max(0, fraction));
            details.progress_percent = details.progress_fraction * 100;
            details.elapsed_seconds = toc(timer);
            details.elapsed_sec = details.elapsed_seconds;
            details.stop_requested = ...
                bms.app.AutoThresholdRequestRunner.stopRequested(stopFile);
            bms.app.AsyncRunService.writeStatus(statusPath, 'running', details);
        end

        function [index, total] = pointPosition(cfg, moduleKey, pointId)
            index = 0;
            total = 0;
            if isempty(moduleKey), return; end
            try
                points = bms.config.ModuleConfigResolver.resolvePoints(cfg, moduleKey, {});
                points = bms.data.PointResolver.normalize(points);
                total = numel(points);
                if ~isempty(pointId)
                    found = find(strcmp(points, pointId), 1, 'first');
                    if ~isempty(found), index = found; end
                end
            catch
            end
        end

        function value = numberField(s, field, fallback)
            value = fallback;
            if isstruct(s) && isfield(s, field) && isnumeric(s.(field)) ...
                    && isscalar(s.(field)) && isfinite(s.(field))
                value = double(s.(field));
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

        function path = stopFile(request)
            path = bms.app.AutoThresholdRequestRunner.textField(request, 'stop_file');
            if ~isempty(path)
                path = bms.app.AutoThresholdRequestRunner.canonicalPath(path);
            end
        end

        function tf = stopRequested(path)
            tf = false;
            try
                tf = ~isempty(path) && isfile(path);
            catch
            end
        end
    end
end
