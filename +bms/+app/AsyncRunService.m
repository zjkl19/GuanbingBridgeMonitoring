classdef AsyncRunService
    %ASYNCRUNSERVICE Starts analysis in a separate process.

    methods (Static)
        function [state, request] = prepare(request, varargin)
            if ~isa(request, 'bms.app.RunRequest')
                error('BMS:AsyncRunService:InvalidRequest', 'request must be a bms.app.RunRequest.');
            end
            options = bms.app.AsyncRunService.parseOptions(varargin{:});
            runId = options.RunId;
            if isempty(runId)
                runId = bms.app.AsyncRunService.newRunId();
            end
            logDir = request.LogDir;
            if isempty(logDir)
                logDir = bms.data.DataLayoutResolver.logDir(request.DataRoot);
            end
            if ~exist(logDir, 'dir')
                mkdir(logDir);
            end

            request.AsyncRunId = runId;
            request.StopFile = fullfile(logDir, ['async_stop_' runId '.flag']);
            request.AsyncStatusFile = fullfile(logDir, ['async_status_' runId '.json']);

            state = struct();
            state.async_run_id = runId;
            state.project_root = request.ProjectRoot;
            state.data_root = request.DataRoot;
            state.log_dir = logDir;
            state.request_path = fullfile(logDir, ['run_request_' runId '.json']);
            state.stop_file = request.StopFile;
            state.status_file = request.AsyncStatusFile;
            state.stdout_log = fullfile(logDir, ['async_stdout_' runId '.log']);
            state.stderr_log = fullfile(logDir, ['async_stderr_' runId '.log']);
            state.launcher_path = fullfile(logDir, ['async_launch_' runId '.ps1']);
            state.started_at = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss');
            state.pid = NaN;
            executor = bms.app.AsyncRunService.resolveExecutor(request.ProjectRoot, options);
            state.executor_type = executor.type;
            state.runner_executable = executor.runner_executable;
            state.matlab_executable = executor.matlab_executable;
            state.status = 'prepared';

            request.writeJson(state.request_path);
            bms.app.AsyncRunService.writeStatus(state.status_file, 'prepared', state);
        end

        function state = start(request, varargin)
            options = bms.app.AsyncRunService.parseOptions(varargin{:});
            [state, request] = bms.app.AsyncRunService.prepare(request, ...
                'RunId', options.RunId, ...
                'RunnerExecutable', options.RunnerExecutable, ...
                'MatlabExecutable', options.MatlabExecutable, ...
                'AutoDetectRunner', options.AutoDetectRunner);
            switch lower(char(string(state.executor_type)))
                case 'compiled_runner'
                    bms.app.AsyncRunService.writeRunnerLauncherScript(state.launcher_path, ...
                        state.runner_executable, state.request_path, state.stdout_log, state.stderr_log);
                case 'matlab_batch'
                    batchCode = bms.app.AsyncRunService.batchCode(request.ProjectRoot, state.request_path);
                    bms.app.AsyncRunService.writeLauncherScript(state.launcher_path, ...
                        state.matlab_executable, batchCode, state.stdout_log, state.stderr_log);
                otherwise
                    error('BMS:AsyncRunService:UnknownExecutor', ...
                        'Unknown async executor type: %s', state.executor_type);
            end
            state.status = 'launching';
            bms.app.AsyncRunService.writeStatus(state.status_file, 'launching', state);
            [status, output] = system(sprintf('powershell -NoProfile -ExecutionPolicy Bypass -File "%s"', state.launcher_path));
            if status ~= 0
                bms.app.AsyncRunService.writeStatus(state.status_file, 'launch_failed', ...
                    bms.app.AsyncRunService.withMessage(state, output));
                error('BMS:AsyncRunService:LaunchFailed', 'Failed to launch async analysis process: %s', output);
            end
            pid = bms.app.AsyncRunService.parsePid(output);
            state.pid = pid;
            state.status = 'launched';
            state.launch_output = output;
            current = bms.app.AsyncRunService.readStatus(state);
            currentStatus = lower(bms.app.AsyncRunService.fieldText(current, 'status'));
            if ~ismember(currentStatus, {'running', 'completed', 'failed'})
                bms.app.AsyncRunService.writeStatus(state.status_file, 'launched', state);
            end
        end

        function status = readStatus(state)
            status = struct('status', 'unknown', 'is_terminal', false);
            if isempty(state) || ~isstruct(state)
                return;
            end
            if isfield(state, 'status_file') && ~isempty(state.status_file) && isfile(state.status_file)
                try
                    status = jsondecode(fileread(state.status_file));
                catch
                    status = struct('status', 'status_read_failed', 'is_terminal', false);
                end
            elseif isfield(state, 'status')
                status.status = char(string(state.status));
            end
            status.is_terminal = any(strcmpi(bms.app.AsyncRunService.fieldText(status, 'status'), ...
                {'completed', 'failed', 'launch_failed', 'stopped'}));
        end

        function requestStop(state, force)
            if nargin < 2
                force = false;
            end
            if isempty(state) || ~isstruct(state) || ~isfield(state, 'stop_file') || isempty(state.stop_file)
                return;
            end
            folder = fileparts(state.stop_file);
            if ~isempty(folder) && ~exist(folder, 'dir')
                mkdir(folder);
            end
            fid = fopen(state.stop_file, 'wt');
            if fid >= 0
                cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
                fprintf(fid, 'stop requested at %s\n', datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss'));
            end
            if force && isfield(state, 'pid') && isnumeric(state.pid) && isfinite(state.pid)
                system(sprintf('taskkill /PID %d /T /F', round(state.pid)));
            end
        end

        function writeStatus(path, statusText, details)
            if nargin < 3 || isempty(details)
                details = struct();
            end
            if isempty(path)
                return;
            end
            payload = details;
            if ~isstruct(payload)
                payload = struct('details', payload);
            end
            payload.status = char(string(statusText));
            payload.updated_at = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss');
            bms.core.Logger.writeJson(path, payload);
        end

        function code = batchCode(projectRoot, requestPath)
            projectRoot = char(string(projectRoot));
            requestPath = char(string(requestPath));
            addParts = {projectRoot, ...
                fullfile(projectRoot, 'ui'), ...
                fullfile(projectRoot, 'config'), ...
                fullfile(projectRoot, 'pipeline'), ...
                fullfile(projectRoot, 'analysis'), ...
                fullfile(projectRoot, 'scripts')};
            code = '';
            for i = 1:numel(addParts)
                code = [code sprintf('addpath(''%s'',''-begin'');', bms.app.AsyncRunService.escapeMatlabString(addParts{i}))]; %#ok<AGROW>
            end
            code = [code sprintf('run_request_cli(''%s'');', ...
                bms.app.AsyncRunService.escapeMatlabString(requestPath))];
        end

        function writeLauncherScript(path, matlabExe, batchCode, stdoutLog, stderrLog)
            lines = {
                '$ErrorActionPreference = ''Stop'''
                ['$matlabExe = ' bms.app.AsyncRunService.psSingleQuote(matlabExe)]
                ['$batchCode = ' bms.app.AsyncRunService.psSingleQuote(batchCode)]
                ['$stdoutLog = ' bms.app.AsyncRunService.psSingleQuote(stdoutLog)]
                ['$stderrLog = ' bms.app.AsyncRunService.psSingleQuote(stderrLog)]
                '$argList = @(''-nosplash'', ''-nodesktop'', ''-batch'', $batchCode)'
                '$p = Start-Process -FilePath $matlabExe -ArgumentList $argList -WindowStyle Hidden -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru'
                '[pscustomobject]@{ pid = $p.Id } | ConvertTo-Json -Compress'
                };
            bms.app.AsyncRunService.writePowerShellScript(path, lines);
        end

        function writeRunnerLauncherScript(path, runnerExe, requestPath, stdoutLog, stderrLog)
            lines = {
                '$ErrorActionPreference = ''Stop'''
                ['$runnerExe = ' bms.app.AsyncRunService.psSingleQuote(runnerExe)]
                ['$requestPath = ' bms.app.AsyncRunService.psSingleQuote(requestPath)]
                ['$stdoutLog = ' bms.app.AsyncRunService.psSingleQuote(stdoutLog)]
                ['$stderrLog = ' bms.app.AsyncRunService.psSingleQuote(stderrLog)]
                '$argList = @($requestPath)'
                '$p = Start-Process -FilePath $runnerExe -ArgumentList $argList -WindowStyle Hidden -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru'
                '[pscustomobject]@{ pid = $p.Id } | ConvertTo-Json -Compress'
                };
            bms.app.AsyncRunService.writePowerShellScript(path, lines);
        end

        function writePowerShellScript(path, lines)
            folder = fileparts(path);
            if ~isempty(folder) && ~exist(folder, 'dir')
                mkdir(folder);
            end
            fid = fopen(path, 'wb');
            if fid < 0
                error('BMS:AsyncRunService:WriteLauncherFailed', 'Unable to write launcher script: %s', path);
            end
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            % Windows PowerShell 5.1 treats UTF-8 without BOM as ANSI, which
            % corrupts Chinese paths in generated launcher scripts.
            fwrite(fid, uint8([239 187 191]), 'uint8');
            for i = 1:numel(lines)
                text = [char(lines{i}) sprintf('\r\n')];
                fwrite(fid, unicode2native(text, 'UTF-8'), 'uint8');
            end
        end
    end

    methods (Static, Access = private)
        function options = parseOptions(varargin)
            options = struct( ...
                'RunId', '', ...
                'RunnerExecutable', '', ...
                'MatlabExecutable', '', ...
                'AutoDetectRunner', true);
            if mod(numel(varargin), 2) ~= 0
                error('BMS:AsyncRunService:InvalidOptions', 'Options must be name-value pairs.');
            end
            for i = 1:2:numel(varargin)
                key = lower(char(string(varargin{i})));
                value = varargin{i+1};
                switch key
                    case 'runid'
                        options.RunId = char(string(value));
                    case 'runnerexecutable'
                        options.RunnerExecutable = char(string(value));
                    case 'matlabexecutable'
                        options.MatlabExecutable = char(string(value));
                    case 'autodetectrunner'
                        options.AutoDetectRunner = logical(value);
                    otherwise
                        error('BMS:AsyncRunService:InvalidOption', 'Unknown option: %s', key);
                end
            end
        end

        function executor = resolveExecutor(projectRoot, options)
            executor = struct('type', '', 'runner_executable', '', 'matlab_executable', '');

            runnerExe = char(string(options.RunnerExecutable));
            if ~isempty(runnerExe)
                if ~isfile(runnerExe)
                    error('BMS:AsyncRunService:RunnerExecutableMissing', ...
                        'Compiled analysis runner not found: %s', runnerExe);
                end
                executor.type = 'compiled_runner';
                executor.runner_executable = runnerExe;
                return;
            end

            if options.AutoDetectRunner
                runnerExe = bms.app.AsyncRunService.findRunnerExecutable(projectRoot);
                if ~isempty(runnerExe)
                    executor.type = 'compiled_runner';
                    executor.runner_executable = runnerExe;
                    return;
                end
            end

            matlabExe = char(string(options.MatlabExecutable));
            if isempty(matlabExe)
                matlabExe = bms.app.AsyncRunService.defaultMatlabExecutable();
            end
            if ~isempty(matlabExe) && isfile(matlabExe)
                executor.type = 'matlab_batch';
                executor.matlab_executable = matlabExe;
                return;
            end

            error('BMS:AsyncRunService:ExecutorMissing', ...
                ['No async executor is available. Build/copy BridgeAnalysisRunner first, ' ...
                'or run from a full MATLAB installation. Checked MATLAB executable: %s'], matlabExe);
        end

        function exe = findRunnerExecutable(projectRoot)
            exe = '';
            candidates = bms.app.AsyncRunService.runnerCandidates(projectRoot);
            for i = 1:numel(candidates)
                if isfile(candidates{i})
                    exe = candidates{i};
                    return;
                end
            end
        end

        function candidates = runnerCandidates(projectRoot)
            projectRoot = char(string(projectRoot));
            exeName = bms.app.AsyncRunService.runnerExecutableName();
            candidates = {
                fullfile(projectRoot, 'bin', 'BridgeAnalysisRunner', exeName)
                fullfile(projectRoot, 'bin', exeName)
                fullfile(projectRoot, 'dist', 'BridgeAnalysisRunner', exeName)
                fullfile(projectRoot, 'dist', exeName)
                fullfile(projectRoot, exeName)
                };
        end

        function name = runnerExecutableName()
            if ispc
                name = 'BridgeAnalysisRunner.exe';
            else
                name = 'BridgeAnalysisRunner';
            end
        end

        function id = newRunId()
            id = char(string(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS')));
        end

        function exe = defaultMatlabExecutable()
            if ispc
                exe = fullfile(matlabroot, 'bin', 'matlab.exe');
            else
                exe = fullfile(matlabroot, 'bin', 'matlab');
            end
        end

        function txt = escapeMatlabString(txt)
            txt = strrep(char(string(txt)), '''', '''''');
        end

        function txt = psSingleQuote(txt)
            txt = ['''' strrep(char(string(txt)), '''', '''''') ''''];
        end

        function pid = parsePid(output)
            pid = NaN;
            try
                decoded = jsondecode(output);
                if isstruct(decoded) && isfield(decoded, 'pid')
                    pid = double(decoded.pid);
                    return;
                end
            catch
            end
            token = regexp(output, '"?pid"?\s*:\s*(\d+)', 'tokens', 'once');
            if ~isempty(token)
                pid = str2double(token{1});
            end
        end

        function s = withMessage(s, message)
            if ~isstruct(s)
                s = struct();
            end
            s.message = char(string(message));
        end

        function text = fieldText(s, name)
            text = '';
            if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
                text = char(string(s.(name)));
            end
        end
    end
end
