classdef RunRequestRunner
    %RUNREQUESTRUNNER Batch entry for running a serialized RunRequest.

    methods (Static)
        function manifestPath = runFile(requestPath)
            requestPath = char(string(requestPath));
            request = bms.app.RunRequest.readJson(requestPath);
            manifestPath = '';
            bms.app.AsyncRunService.writeStatus(request.AsyncStatusFile, 'running', ...
                struct('request_path', requestPath, 'async_run_id', request.AsyncRunId));
            try
                runner = bms.app.AnalysisRunner(request);
                manifestPath = runner.run();
                finalStatus = bms.app.RunRequestRunner.finalStatusForManifest(manifestPath);
                if ~isempty(request.StopFile) && isfile(request.StopFile)
                    finalStatus = 'stopped';
                end
                bms.app.AsyncRunService.writeStatus(request.AsyncStatusFile, finalStatus, ...
                    struct('request_path', requestPath, ...
                    'async_run_id', request.AsyncRunId, ...
                    'manifest_path', manifestPath));
            catch ME
                bms.app.AsyncRunService.writeStatus(request.AsyncStatusFile, 'failed', ...
                    struct('request_path', requestPath, ...
                    'async_run_id', request.AsyncRunId, ...
                    'error_id', ME.identifier, ...
                    'message', ME.message));
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
                if isstruct(manifest) && isfield(manifest, 'status') ...
                        && any(strcmpi(char(string(manifest.status)), {'fail','failed'}))
                    status = 'failed';
                end
            catch
                % An unreadable final manifest cannot represent a completed run.
                status = 'failed';
            end
        end
    end
end
