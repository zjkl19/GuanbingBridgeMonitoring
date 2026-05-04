classdef RunSession < handle
    %RUNSESSION Owns one analysis run lifecycle.

    properties
        Root char
        StartDate char
        EndDate char
        Options struct
        Config struct
        NotifyConfig struct = struct()
        StartTimestamp datetime = NaT
        StatsDir char
        LogDir char
        LogRecords cell = {}
        Results cell = {}
        OffsetLog = []
        ElapsedSec double = 0
        LogFile char = ''
        Summary struct = struct()
    end

    methods
        function obj = RunSession(root, startDate, endDate, opts, cfg)
            if nargin < 4 || isempty(opts), opts = struct(); end
            if nargin < 5, cfg = []; end
            obj.Root = char(root);
            obj.StartDate = char(startDate);
            obj.EndDate = char(endDate);
            obj.Options = opts;
            obj.Config = cfg;
            obj.StatsDir = fullfile(obj.Root, 'stats');
            obj.LogDir = fullfile(obj.Root, 'run_logs');
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
            addpath(projectRoot);
            addpath(fullfile(projectRoot,'pipeline'));
            addpath(fullfile(projectRoot,'config'));
            addpath(fullfile(projectRoot,'analysis'));
            addpath(fullfile(projectRoot,'scripts'));
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
                allLogs, obj.LogFile, obj.OffsetLog, obj.StatsDir, obj.LogDir);
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
                if isempty(logs{i}), continue; end
                fprintf('[%s] %s', upper(logs{i}.status), logs{i}.label);
                if isfield(logs{i}, 'message') && ~isempty(logs{i}.message)
                    fprintf(' - %s', logs{i}.message);
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
                if isempty(logs{i}), continue; end
                fprintf(fid, '[%s] %s', upper(logs{i}.status), logs{i}.label);
                if isfield(logs{i}, 'message') && ~isempty(logs{i}.message)
                    fprintf(fid, ' - %s', logs{i}.message);
                end
                if isfield(logs{i}, 'error_type') && ~isempty(logs{i}.error_type)
                    fprintf(fid, ' (error_type=%s)', logs{i}.error_type);
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

        function tf = shouldStop(~)
            tf = false;
            try
                global RUN_STOP_FLAG;
                tf = ~isempty(RUN_STOP_FLAG) && RUN_STOP_FLAG;
            catch
                tf = false;
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
end
