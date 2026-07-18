classdef RunRequestRunner
    %RUNREQUESTRUNNER Batch entry for running a serialized RunRequest.

    methods (Static)
        function manifestPath = runFile(requestPath)
            requestPath = char(string(requestPath));
            request = bms.app.RunRequest.readJson(requestPath);
            manifestPath = '';
            initialProgress = bms.app.RunProgressReporter.reconcile(struct(), {}, 'runtime');
            initialProgress.request_path = requestPath;
            initialProgress.async_run_id = request.AsyncRunId;
            bms.app.AsyncRunService.writeStatus(request.AsyncStatusFile, 'running', ...
                initialProgress);
            try
                runner = bms.app.AnalysisRunner(request);
                manifestPath = runner.run();
                finalStatus = bms.app.RunRequestRunner.finalStatusForManifest(manifestPath);
                if ~isempty(request.StopFile) && isfile(request.StopFile)
                    finalStatus = 'stopped';
                end
                details = bms.app.RunRequestRunner.terminalProgressForManifest( ...
                    manifestPath, finalStatus);
                finalStatus = char(string(details.status));
                details.request_path = requestPath;
                details.async_run_id = request.AsyncRunId;
                details.manifest_path = manifestPath;
                bms.app.AsyncRunService.writeStatus( ...
                    request.AsyncStatusFile, finalStatus, details);
            catch ME
                details = bms.app.RunRequestRunner.readExistingStatus(request.AsyncStatusFile);
                details.request_path = requestPath;
                details.async_run_id = request.AsyncRunId;
                if ~isempty(manifestPath)
                    details.manifest_path = manifestPath;
                end
                details.error_id = ME.identifier;
                details.message = ME.message;
                bms.app.AsyncRunService.writeStatus(request.AsyncStatusFile, 'failed', ...
                    details);
                rethrow(ME);
            end

            % A module-level failure is recorded in the final manifest rather
            % than thrown by RunSession, so propagate it only after the
            % durable async status (including manifest_path) has been written.
            % This preserves the diagnostic artifacts while ensuring the
            % compiled Runner and MATLAB batch callers return a non-zero exit
            % code instead of making a failed analysis look successful.
            if strcmp(finalStatus, 'failed')
                error('BMS:RunRequestRunner:AnalysisFailed', ...
                    'Analysis completed with a failed manifest: %s', manifestPath);
            end
        end

        function status = finalStatusForManifest(manifestPath)
            status = 'completed';
            if isempty(manifestPath) || ~isfile(manifestPath)
                status = 'failed';
                return;
            end
            try
                manifest = bms.io.JsonFile.read(manifestPath);
                if isstruct(manifest) && isfield(manifest, 'status')
                    manifestStatus = lower(char(string(manifest.status)));
                    if any(strcmp(manifestStatus, {'fail','failed','error'}))
                        status = 'failed';
                    elseif any(strcmp(manifestStatus, {'stop','stopped','stopping'}))
                        status = 'stopped';
                    end
                end
            catch
                % An unreadable final manifest cannot represent a completed run.
                status = 'failed';
            end
        end

        function details = terminalProgressForManifest(manifestPath, finalStatus)
            if nargin < 2 || isempty(finalStatus)
                finalStatus = bms.app.RunRequestRunner.finalStatusForManifest(manifestPath);
            end
            manifest = struct();
            if ~isempty(manifestPath) && isfile(manifestPath)
                try
                    manifest = bms.io.JsonFile.read(manifestPath);
                catch
                    manifest = struct();
                end
            end
            details = bms.app.RunProgressReporter.terminalPayloadFromManifest( ...
                manifest, finalStatus);
        end

        function details = readExistingStatus(path)
            details = struct();
            if isempty(path) || ~isfile(path)
                return;
            end
            try
                value = bms.io.JsonFile.read(path);
                if isstruct(value) && isscalar(value)
                    details = value;
                end
            catch
                details = struct();
            end
        end
    end
end
