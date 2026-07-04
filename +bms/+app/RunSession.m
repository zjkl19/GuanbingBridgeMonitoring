classdef RunSession < handle
    %RUNSESSION Owns one analysis run lifecycle.

    properties
        Root char
        StartDate char
        EndDate char
        Options struct
        Config struct
        Request = []
        NotifyConfig struct = struct()
        StartTimestamp datetime = NaT
        StatsDir char
        LogDir char
        LogRecords cell = {}
        Results cell = {}
        OffsetLog = []
        ElapsedSec double = 0
        LogFile char = ''
        ManifestPath char = ''
        Summary struct = struct()
        Preflight struct = struct()
    end

    methods
        function obj = RunSession(root, startDate, endDate, opts, cfg)
            if nargin == 1 && isa(root, 'bms.app.RunRequest')
                req = root;
            else
                if nargin < 4 || isempty(opts), opts = struct(); end
                if nargin < 5, cfg = []; end
                req = bms.app.RunRequest.fromLegacy(root, startDate, endDate, opts, cfg);
            end
            obj.Request = req;
            obj.Root = req.DataRoot;
            obj.StartDate = req.StartDate;
            obj.EndDate = req.EndDate;
            obj.Options = req.Options;
            obj.Config = req.Config;
            obj.StatsDir = req.StatsDir;
            obj.LogDir = req.LogDir;
        end

        function summary = run(obj)
            global RUN_STOP_FLAG;
            t0 = tic;
            ws = warning('off','MATLAB:table:ModifiedAndSavedVarnames');
            try
                obj.setupPaths();
                obj.loadConfigIfNeeded();
                obj.NotifyConfig = obj.Config;
                plot_runtime_settings('reset');
                plot_runtime_settings('set', bms.app.LegacyStepFunctions.extractPlotCommon(obj.Config));

                obj.LogRecords = {};
                obj.Results = {};
                obj.StartTimestamp = datetime('now');
                obj.Preflight = bms.app.RunPreflight.check(obj.Request);
                preflightPath = bms.app.RunPreflight.writeJson(obj.Request, obj.Preflight);
                if ~isempty(preflightPath)
                    obj.Preflight.preflight_json = preflightPath;
                end
                if strcmp(obj.Preflight.status, 'failed')
                    error('BMS:RunPreflight:Failed', 'Run preflight failed: %s', strjoin(obj.Preflight.errors, '; '));
                end
                offset_correction_registry('reset');
                RUN_STOP_FLAG = false;
                obj.collectConfigWarnings();

                sub = bms.app.LegacyStepFunctions.buildSubfolders(obj.Config);
                plan = bms.app.StepFactory.buildLegacyPlan(obj.Root, obj.StartDate, obj.EndDate, obj.Options, obj.Config, obj.StatsDir, sub);
                obj.Results = plan.execute(@() obj.shouldStop());

                warning(ws);
                obj.ElapsedSec = toc(t0);
                obj.OffsetLog = obj.writeOffsetCorrectionReport();
                if ~isempty(obj.OffsetLog)
                    obj.LogRecords{end+1} = obj.OffsetLog;
                end
                obj.finalizeSuccess();
                summary = obj.Summary;
            catch ME
                warning(ws);
                obj.handleFailure(ME);
                rethrow(ME);
            end
        end
    end

    methods (Access = private)
        function setupPaths(~)
            here = fileparts(mfilename('fullpath'));
            projectRoot = fileparts(fileparts(here));
            addpath(projectRoot, fullfile(projectRoot,'pipeline'), ...
                fullfile(projectRoot,'config'), fullfile(projectRoot,'analysis'), ...
                fullfile(projectRoot,'scripts'), '-begin');
        end

        function loadConfigIfNeeded(obj)
            if isempty(obj.Config)
                obj.Config = load_config();
            end
        end

        function collectConfigWarnings(obj)
            if isfield(obj.Config,'warnings') && ~isempty(obj.Config.warnings)
                for i = 1:numel(obj.Config.warnings)
                    warning('Config: %s', obj.Config.warnings{i});
                    obj.LogRecords{end+1} = struct('key','config', 'label','config', ...
                        'category','config', 'status','warn', 'message', obj.Config.warnings{i}, ...
                        'error_type','config_warning'); %#ok<AGROW>
                end
            end
        end

        function finalizeSuccess(obj)
            fprintf('Total elapsed: %.2f sec\n', obj.ElapsedSec);
            allLogs = [obj.LogRecords, obj.Results];
            obj.printSummary(allLogs);
            obj.LogFile = obj.writeLog(allLogs);
            obj.Summary = bms.app.LegacyRunAllAdapter.buildSummary(obj.Root, obj.StartDate, obj.EndDate, obj.Options, obj.Config, obj.StartTimestamp, obj.ElapsedSec, ...
                allLogs, obj.LogFile, obj.OffsetLog, obj.StatsDir, obj.LogDir, obj.Preflight);
            obj.Summary.run_request = obj.Request.toStruct();
            obj.ManifestPath = bms.app.RunSession.writeManifest(obj, obj.Summary.status, obj.Summary);
            obj.Summary.analysis_manifest = obj.ManifestPath;
            obj.configureFolderViews();
            kind = obj.selectNotifyKind(bms.app.LegacyRunAllAdapter.hasFailures(allLogs));
            if ~isempty(kind)
                obj.safeNotify(kind);
            end
        end

        function handleFailure(obj, ME)
            if ~isnat(obj.StartTimestamp)
                obj.OffsetLog = obj.writeOffsetCorrectionReport();
                if ~isempty(obj.OffsetLog)
                    obj.LogRecords{end+1} = obj.OffsetLog;
                end
            end
            kind = obj.selectNotifyKind(true);
            if ~isempty(kind)
                obj.safeNotify(kind);
            end
            obj.configureFolderViews();
            if isempty(obj.Summary)
                obj.Summary = struct('status','failed','message',ME.message,'error_type',bms.app.ErrorClassifier.classifyException(ME));
            end
            obj.ManifestPath = bms.app.RunSession.writeManifest(obj, 'failed', obj.Summary);
            obj.Summary.analysis_manifest = obj.ManifestPath;
        end

        function logRecord = writeOffsetCorrectionReport(obj)
            logRecord = [];
            try
                [filepath, count] = offset_correction_registry('write', obj.LogDir, obj.StartTimestamp);
                logRecord = struct('key', 'offset_correction_report', 'label', 'offset_correction_report', ...
                    'category', 'postprocess', 'status', 'ok', ...
                    'message', sprintf('%d point(s); %s', count, filepath), ...
                    'error_type', '', 'filepath', filepath, 'point_count', count);
                fprintf('Offset correction report written to %s\n', filepath);
            catch ME
                logRecord = struct('key', 'offset_correction_report', 'label', 'offset_correction_report', ...
                    'category', 'postprocess', 'status', 'warn', 'message', ME.message, ...
                    'error_type', bms.app.ErrorClassifier.classifyException(ME), 'filepath', '', 'point_count', NaN);
                warning('Offset correction report failed: %s', ME.message);
            end
        end

        function printSummary(~, logs)
            if isempty(logs), return; end
            fprintf('--- Run summary ---\n');
            for i = 1:numel(logs)
                rec = bms.app.RunSession.logToStruct(logs{i});
                if isempty(rec), continue; end
                fprintf('[%s] %s', upper(rec.status), rec.label);
                if isfield(rec, 'message') && ~isempty(rec.message)
                    fprintf(' - %s', rec.message);
                end
                fprintf('\n');
            end
            fprintf('----------------\n');
        end

        function logfile = writeLog(obj, logs)
            logfile = '';
            if isempty(logs), return; end
            if ~exist(obj.LogDir,'dir'), mkdir(obj.LogDir); end
            ts = datestr(obj.StartTimestamp,'yyyymmdd_HHMMSS');
            logfile = fullfile(obj.LogDir, ['run_log_' ts '.txt']);
            fid = fopen(logfile,'wt');
            if fid < 0
                warning('Unable to write log file %s', logfile);
                logfile = '';
                return;
            end
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, 'Start: %s\n', datestr(obj.StartTimestamp,'yyyy-mm-dd HH:MM:ss'));
            fprintf(fid, 'Elapsed: %.2f sec\n', obj.ElapsedSec);
            fprintf(fid, 'Summary:\n');
            for i = 1:numel(logs)
                rec = bms.app.RunSession.logToStruct(logs{i});
                if isempty(rec), continue; end
                fprintf(fid, '[%s] %s', upper(rec.status), rec.label);
                if isfield(rec, 'message') && ~isempty(rec.message)
                    fprintf(fid, ' - %s', rec.message);
                end
                if isfield(rec, 'error_type') && ~isempty(rec.error_type)
                    fprintf(fid, ' (error_type=%s)', rec.error_type);
                end
                fprintf(fid, '\n');
            end
            fprintf('Log written to %s\n', logfile);
        end

        function configureFolderViews(obj)
            if ~isempty(obj.Root) && isstruct(obj.Config)
                try
                    configure_result_folder_views(obj.Root, obj.Config);
                catch MEcfg
                    warning('Result folder view setup failed: %s', MEcfg.message);
                end
            end
        end

        function tf = shouldStop(obj)
            tf = false;
            try
                global RUN_STOP_FLAG;
                tf = ~isempty(RUN_STOP_FLAG) && RUN_STOP_FLAG;
                if tf
                    return;
                end
            catch
                tf = false;
            end
            try
                if isprop(obj, 'Request') && isa(obj.Request, 'bms.app.RunRequest') && ...
                        ~isempty(obj.Request.StopFile) && isfile(obj.Request.StopFile)
                    tf = true;
                end
            catch
            end
        end

        function tf = shouldNotify(obj, key, defaultValue)
            if nargin < 3, defaultValue = true; end
            tf = defaultValue;
            cfg = obj.NotifyConfig;
            if ~isstruct(cfg) || ~isfield(cfg, 'notify') || ~isstruct(cfg.notify)
                return;
            end
            ncfg = cfg.notify;
            if isfield(ncfg, 'enabled') && ~isempty(ncfg.enabled)
                tf = tf && logical(ncfg.enabled);
            end
            if isfield(ncfg, key) && ~isempty(ncfg.(key))
                tf = tf && logical(ncfg.(key));
            end
        end

        function kind = selectNotifyKind(obj, hasError)
            kind = '';
            if hasError
                if obj.shouldNotify('on_error', true)
                    kind = 'error';
                    return;
                end
            end
            if obj.shouldNotify('on_task_done', true)
                kind = 'task_done';
            elseif obj.shouldNotify('on_analysis_done', false)
                kind = 'success';
            end
        end

        function safeNotify(obj, kind)
            try
                if exist('play_notify_sound', 'file') == 2
                    play_notify_sound(kind, obj.NotifyConfig);
                else
                    beep;
                end
            catch
            end
        end
    end

    methods (Static)
        function rec = logToStruct(item, statsDir)
            if nargin < 2, statsDir = ''; end
            rec = [];
            if isempty(item)
                return;
            end
            if isa(item, 'bms.app.StepResult')
                rec = item.toStruct(statsDir);
            elseif isstruct(item)
                rec = item;
            end
        end

        function manifestPath = writeManifest(obj, status, details)
            manifestPath = '';
            try
                root = obj.Root;
                startDate = obj.StartDate;
                endDate = obj.EndDate;
                opts = obj.Options;
                cfg = obj.Config;
                ctx = bms.core.AnalysisContext.fromLegacy(root, startDate, endDate, opts, cfg);
                ctx.LogDir = obj.LogDir;
                manifestPath = bms.app.ManifestWriter.write(ctx, status, details);
            catch ME
                if ~isempty(ME.stack)
                    loc = sprintf('%s:%d', ME.stack(1).name, ME.stack(1).line);
                else
                    loc = 'unknown';
                end
                warning('Analysis manifest write failed at %s: %s', loc, ME.message);
            end
        end
    end
end
