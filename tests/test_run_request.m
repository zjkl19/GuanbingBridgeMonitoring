classdef test_run_request < matlab.unittest.TestCase
    properties
        TempDir
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'config'), fullfile(proj, 'pipeline'), fullfile(proj, 'analysis'), fullfile(proj, 'scripts'));
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if exist(tc.TempDir, 'dir'), rmdir(tc.TempDir, 's'); end
        end
    end

    methods (Test)
        function requestNormalizesLegacyInputs(tc)
            opts = struct('doTemp', true, 'doAccel', false);
            cfg = struct('source', 'config/default_config.json');
            req = bms.app.RunRequest.fromLegacy(tc.TempDir, '2026-01-01', '2026-01-31', opts, cfg);

            tc.verifyEqual(req.DataRoot, tc.TempDir);
            tc.verifyEqual(req.StatsDir, fullfile(tc.TempDir, 'stats'));
            tc.verifyEqual(req.LogDir, fullfile(tc.TempDir, 'run_logs'));
            tc.verifyEqual(req.Profile.BridgeId, 'guanbing');
            tc.verifyEqual(req.toStruct().enabled_modules, {'temperature'});
        end

        function requestBuildsContext(tc)
            cfg = struct('source', 'config/jiulongjiang_config.json');
            req = bms.app.RunRequest.fromLegacy(tc.TempDir, '2026-03-23', '2026-03-31', struct('doGNSS', true), cfg);
            ctx = req.toContext();

            tc.verifyEqual(ctx.DataRoot, tc.TempDir);
            tc.verifyEqual(ctx.ConfigPath, 'config/jiulongjiang_config.json');
            tc.verifyEqual(ctx.BridgeProfile.BridgeId, 'jiulongjiang');
            tc.verifyEqual(ctx.enabledModules(), {'gnss'});
        end

        function analysisRunnerAcceptsRunRequest(tc)
            req = bms.app.RunRequest.fromLegacy(tc.TempDir, '2026-01-01', '2026-01-01', emptyOpts(), struct());
            runner = bms.app.AnalysisRunner(req);

            tc.verifyEqual(runner.Context.DataRoot, tc.TempDir);
            tc.verifyEqual(runner.Request.DataRoot, tc.TempDir);
        end

        function requestJsonRoundTripsForAsyncRun(tc)
            opts = struct('doTemp', true);
            cfg = struct('source', 'config/default_config.json', 'plot_common', struct( ...
                'gap_mode', 'connect', ...
                'dynamic_raw_sampling_mode', 'full', ...
                'dynamic_group_sampling_mode', 'full', ...
                'dynamic_raw_disable_emf', true));
            req = bms.app.RunRequest(tc.TempDir, '2026-01-01', '2026-01-02', opts, cfg, ...
                'StopFile', fullfile(tc.TempDir, 'stop.flag'), ...
                'AsyncStatusFile', fullfile(tc.TempDir, 'status.json'), ...
                'AsyncRunId', 'test_run');
            path = fullfile(tc.TempDir, 'request.json');

            req.writeJson(path);
            loaded = bms.app.RunRequest.readJson(path);

            tc.verifyEqual(loaded.DataRoot, tc.TempDir);
            tc.verifyEqual(loaded.Options.doTemp, true);
            tc.verifyEqual(loaded.Config.plot_common.gap_mode, 'connect');
            tc.verifyEqual(loaded.toStruct().plot_sampling.mode, 'full');
            tc.verifyEqual(loaded.toStruct().plot_sampling.group_mode, 'full');
            tc.verifyEqual(loaded.toStruct().plot_sampling.render_mode, 'line');
            tc.verifyTrue(loaded.toStruct().plot_sampling.raw_emf_disabled);
            tc.verifyEqual(loaded.StopFile, fullfile(tc.TempDir, 'stop.flag'));
            tc.verifyEqual(loaded.AsyncStatusFile, fullfile(tc.TempDir, 'status.json'));
            tc.verifyEqual(loaded.AsyncRunId, 'test_run');
            tc.verifyEqual(loaded.ConfigSha256, req.ConfigSha256);
            tc.verifyEqual(loaded.toStruct().config_sha256, req.ConfigSha256);
        end

        function requestRejectsChangedPinnedConfig(tc)
            configPath = fullfile(tc.TempDir, 'config.json');
            fid = fopen(configPath, 'wt');
            fprintf(fid, '{"bridge":{"id":"guanbing"}}');
            fclose(fid);
            hash = bms.io.JsonFile.sha256(configPath);
            fid = fopen(configPath, 'wt');
            fprintf(fid, '{"bridge":{"id":"hongtang"}}');
            fclose(fid);

            tc.verifyError(@() bms.app.RunRequest(tc.TempDir, '2026-01-01', '2026-01-01', ...
                emptyOpts(), struct(), 'ConfigPath', configPath, 'ConfigSha256', hash), ...
                'BMS:RunRequest:ConfigHashMismatch');
        end

        function requestRejectsChangedPinnedConfigDependency(tc)
            configPath = fullfile(tc.TempDir, 'project.json');
            layerPath = fullfile(tc.TempDir, 'base.json');
            writeUtf8(configPath, '{"extends":"base.json","bridge":{"id":"guanbing"}}');
            writeUtf8(layerPath, '{"plot_common":{"gap_mode":"connect"}}');
            hash = bms.config.ConfigLayerLoader.dependencySha256(configPath);
            writeUtf8(layerPath, '{"plot_common":{"gap_mode":"break"}}');

            tc.verifyError(@() bms.app.RunRequest(tc.TempDir, '2026-01-01', '2026-01-01', ...
                emptyOpts(), struct(), 'ConfigPath', configPath, 'ConfigSha256', hash), ...
                'BMS:RunRequest:ConfigHashMismatch');
        end

        function plotSamplingReportsEffectiveModuleOverrides(tc)
            cfg = struct('plot_common', struct( ...
                'gap_mode', 'break', ...
                'dynamic_raw_sampling_mode', 'capped', ...
                'dynamic_raw_line_width', 0.7, ...
                'dynamic_raw_modules', struct( ...
                    'acceleration', struct('sampling_mode', 'full', 'line_width', 1.0, 'gap_mode', 'connect'), ...
                    'cable_accel', struct('sampling_mode', 'full', 'line_width', 1.2, 'gap_mode', 'connect'))));
            req = bms.app.RunRequest(tc.TempDir, '2026-01-01', '2026-01-01', emptyOpts(), cfg);
            sampling = req.toStruct().plot_sampling;

            tc.verifyEqual(sampling.modules.wind.sampling_mode, 'capped');
            tc.verifyEqual(sampling.modules.wind.line_width, 0.7);
            tc.verifyEqual(sampling.modules.wind.gap_mode, 'break');
            tc.verifyEqual(sampling.modules.acceleration.sampling_mode, 'full');
            tc.verifyEqual(sampling.modules.acceleration.line_width, 1.0);
            tc.verifyEqual(sampling.modules.acceleration.gap_mode, 'connect');
            tc.verifyTrue(sampling.modules.acceleration.raw_emf_disabled);
            tc.verifyEqual(sampling.modules.cable_accel.sampling_mode, 'full');
            tc.verifyEqual(sampling.modules.cable_accel.line_width, 1.2);
        end

        function asyncRunServicePreparesStatusAndStopFiles(tc)
            req = bms.app.RunRequest.fromLegacy(tc.TempDir, '2026-01-01', '2026-01-01', emptyOpts(), struct());

            [state, prepared] = bms.app.AsyncRunService.prepare(req, ...
                'RunId', 'unit_test', ...
                'AutoDetectRunner', false, ...
                'MatlabExecutable', matlabExecutable());
            status = bms.app.AsyncRunService.readStatus(state);
            bms.app.AsyncRunService.requestStop(state);

            tc.verifyEqual(prepared.AsyncRunId, 'unit_test');
            tc.verifyEqual(state.executor_type, 'matlab_batch');
            tc.verifyTrue(isfile(state.request_path));
            tc.verifyTrue(isfile(state.status_file));
            tc.verifyEqual(status.status, 'prepared');
            tc.verifyFalse(status.is_terminal);
            tc.verifyTrue(isfile(state.stop_file));
            tc.verifyTrue(contains(bms.app.AsyncRunService.batchCode(tc.TempDir, state.request_path), 'run_request_cli'));
        end

        function asyncRunServicePreparesWithCompiledRunner(tc)
            req = bms.app.RunRequest.fromLegacy(tc.TempDir, '2026-01-01', '2026-01-01', emptyOpts(), struct());
            runnerExe = fullfile(tc.TempDir, 'BridgeAnalysisRunner.exe');
            fid = fopen(runnerExe, 'wt');
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, 'fake');

            [state, prepared] = bms.app.AsyncRunService.prepare(req, ...
                'RunId', 'runner_test', ...
                'RunnerExecutable', runnerExe, ...
                'MatlabExecutable', fullfile(tc.TempDir, 'missing_matlab.exe'));

            tc.verifyEqual(prepared.AsyncRunId, 'runner_test');
            tc.verifyEqual(state.executor_type, 'compiled_runner');
            tc.verifyEqual(state.runner_executable, runnerExe);
            tc.verifyTrue(isempty(state.matlab_executable));
            tc.verifyTrue(isfile(state.request_path));
        end

        function asyncLauncherScriptsUseUtf8BomForChinesePaths(tc)
            dataRoot = fullfile(tc.TempDir, '管柄数据', '2026年6月');
            logDir = fullfile(dataRoot, 'run_logs');
            requestPath = fullfile(logDir, 'run_request.json');
            stdoutLog = fullfile(logDir, 'async_stdout.log');
            stderrLog = fullfile(logDir, 'async_stderr.log');

            runnerScript = fullfile(logDir, 'async_runner.ps1');
            bms.app.AsyncRunService.writeRunnerLauncherScript(runnerScript, ...
                fullfile(tc.TempDir, 'bin', runnerExecutableName()), ...
                requestPath, stdoutLog, stderrLog);
            tc.verifyLauncherIsUtf8BomWithChinesePath(runnerScript);

            matlabScript = fullfile(logDir, 'async_matlab.ps1');
            batchCode = bms.app.AsyncRunService.batchCode(fullfile(tc.TempDir, '项目'), requestPath);
            bms.app.AsyncRunService.writeLauncherScript(matlabScript, ...
                fullfile(tc.TempDir, 'MATLAB', 'bin', 'matlab.exe'), ...
                batchCode, stdoutLog, stderrLog);
            tc.verifyLauncherIsUtf8BomWithChinesePath(matlabScript);
        end

        function asyncRunServiceAutoDetectsRunnerUnderProjectBin(tc)
            projectRoot = fullfile(tc.TempDir, 'project');
            dataRoot = fullfile(tc.TempDir, 'data');
            runnerDir = fullfile(projectRoot, 'bin', 'BridgeAnalysisRunner');
            mkdir(runnerDir);
            mkdir(dataRoot);
            runnerExe = fullfile(runnerDir, runnerExecutableName());
            fid = fopen(runnerExe, 'wt');
            fprintf(fid, 'fake');
            fclose(fid);
            req = bms.app.RunRequest(dataRoot, '2026-01-01', '2026-01-01', emptyOpts(), struct(), ...
                'ProjectRoot', projectRoot);

            [state, ~] = bms.app.AsyncRunService.prepare(req, ...
                'RunId', 'autodetect_runner', ...
                'MatlabExecutable', fullfile(tc.TempDir, 'missing_matlab.exe'));

            tc.verifyEqual(state.executor_type, 'compiled_runner');
            tc.verifyEqual(state.runner_executable, runnerExe);
        end

        function asyncRunServiceRejectsMissingRunnerExecutable(tc)
            req = bms.app.RunRequest.fromLegacy(tc.TempDir, '2026-01-01', '2026-01-01', emptyOpts(), struct());

            tc.verifyError(@() bms.app.AsyncRunService.prepare(req, ...
                'RunId', 'bad_runner', ...
                'RunnerExecutable', fullfile(tc.TempDir, 'missing_runner.exe'), ...
                'MatlabExecutable', matlabExecutable()), ...
                'BMS:AsyncRunService:RunnerExecutableMissing');
        end

        function asyncRunServiceRejectsMissingExecutor(tc)
            req = bms.app.RunRequest.fromLegacy(tc.TempDir, '2026-01-01', '2026-01-01', emptyOpts(), struct());

            tc.verifyError(@() bms.app.AsyncRunService.prepare(req, ...
                'RunId', 'bad_exe', ...
                'AutoDetectRunner', false, ...
                'MatlabExecutable', fullfile(tc.TempDir, 'missing_matlab.exe')), ...
                'BMS:AsyncRunService:ExecutorMissing');
        end
    end

    methods
        function verifyLauncherIsUtf8BomWithChinesePath(tc, path)
            bytes = readBinary(path);
            tc.verifyGreaterThanOrEqual(numel(bytes), 3);
            tc.verifyEqual(bytes(1:3), uint8([239 187 191]));
            text = native2unicode(bytes(4:end), 'UTF-8');
            tc.verifyTrue(contains(text, '管柄数据'));
            tc.verifyTrue(contains(text, '2026年6月'));
        end
    end
end

function opts = emptyOpts()
    opts = struct();
    keys = {'precheck_zip_count','doUnzip','doRenameCsv','doRemoveHeader','doResample', ...
        'doTemp','doHumidity','doRainfall','doGNSS','doWind','doEq','doWIM', ...
        'doDeflect','doBearingDisplacement','doTilt','doAccel','doAccelSpectrum', ...
        'doCableAccel','doCableAccelSpectrum','doRenameCrk','doCrack','doStrain', ...
        'doDynStrainBoxplot','doDynStrainLowpassBoxplot'};
    for i = 1:numel(keys)
        opts.(keys{i}) = false;
    end
end

function exe = matlabExecutable()
    if ispc
        exe = fullfile(matlabroot, 'bin', 'matlab.exe');
    else
        exe = fullfile(matlabroot, 'bin', 'matlab');
    end
end

function exe = runnerExecutableName()
    if ispc
        exe = 'BridgeAnalysisRunner.exe';
    else
        exe = 'BridgeAnalysisRunner';
    end
end

function bytes = readBinary(path)
    fid = fopen(path, 'rb');
    if fid < 0
        error('test_run_request:ReadFailed', 'Unable to read %s', path);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes = fread(fid, Inf, '*uint8')';
end

function writeUtf8(path, text)
    fid = fopen(path, 'wt', 'n', 'UTF-8');
    if fid < 0
        error('test_run_request:WriteFailed', 'Unable to write %s', path);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', text);
end
