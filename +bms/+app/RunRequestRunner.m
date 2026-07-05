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
                finalStatus = 'completed';
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
        end
    end
end
