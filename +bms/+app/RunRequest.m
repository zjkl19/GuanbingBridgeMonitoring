classdef RunRequest
    %RUNREQUEST Normalized inputs for one analysis run.

    properties
        ProjectRoot char = ''
        DataRoot char = ''
        StartDate char = ''
        EndDate char = ''
        Options struct = struct()
        Config struct = struct()
        ConfigPath char = ''
        Profile = []
        DataLayout struct = struct()
        StatsDir char = ''
        LogDir char = ''
        StopFile char = ''
        AsyncStatusFile char = ''
        AsyncRunId char = ''
    end

    methods
        function obj = RunRequest(dataRoot, startDate, endDate, opts, cfg, varargin)
            if nargin < 1, dataRoot = ''; end
            if nargin < 2, startDate = ''; end
            if nargin < 3, endDate = ''; end
            if nargin < 4 || isempty(opts), opts = struct(); end
            if nargin < 5 || isempty(cfg), cfg = load_config(); end

            obj.ProjectRoot = bms.core.PathResolver.projectRoot();
            obj.DataRoot = char(dataRoot);
            obj.StartDate = char(startDate);
            obj.EndDate = char(endDate);
            obj.Options = opts;
            obj.Config = bms.config.ConfigMigrator.migrate(cfg);
            obj.ConfigPath = bms.app.RunRequest.configPathFromConfig(cfg);

            if mod(numel(varargin), 2) ~= 0
                error('BMS:RunRequest:InvalidArguments', 'RunRequest name-value arguments must be paired.');
            end
            for i = 1:2:numel(varargin)
                key = lower(char(varargin{i}));
                value = varargin{i+1};
                switch key
                    case 'projectroot'
                        obj.ProjectRoot = char(value);
                    case 'configpath'
                        obj.ConfigPath = char(value);
                    case 'stopfile'
                        obj.StopFile = char(value);
                    case 'asyncstatusfile'
                        obj.AsyncStatusFile = char(value);
                    case 'asyncrunid'
                        obj.AsyncRunId = char(value);
                    otherwise
                        error('BMS:RunRequest:InvalidArgument', 'Unknown RunRequest option: %s', key);
                end
            end

            obj.StatsDir = bms.data.DataLayoutResolver.statsDir(obj.DataRoot);
            obj.LogDir = bms.data.DataLayoutResolver.logDir(obj.DataRoot);
            obj.Profile = bms.profile.BridgeProfileRegistry.infer(obj.Config, obj.DataRoot);
            obj.DataLayout = bms.data.DataLayoutResolver.describe(obj.DataRoot, obj.Config);
        end

        function ctx = toContext(obj)
            ctx = bms.core.AnalysisContext(obj.DataRoot, obj.StartDate, obj.EndDate, obj.Options, obj.Config, ...
                'ProjectRoot', obj.ProjectRoot, ...
                'ConfigPath', obj.ConfigPath, ...
                'BridgeProfile', obj.Profile);
            ctx.StatsDir = obj.StatsDir;
            ctx.LogDir = obj.LogDir;
        end

        function result = preflight(obj)
            result = bms.app.RunPreflight.check(obj);
        end

        function s = toStruct(obj)
            s = struct();
            s.project_root = obj.ProjectRoot;
            s.data_root = obj.DataRoot;
            s.start_date = obj.StartDate;
            s.end_date = obj.EndDate;
            s.config_path = obj.ConfigPath;
            s.stats_dir = obj.StatsDir;
            s.log_dir = obj.LogDir;
            s.data_layout = obj.DataLayout;
            s.enabled_modules = bms.module.ModuleRegistry.enabledKeys(obj.Options);
            s.async_run_id = obj.AsyncRunId;
            s.stop_file = obj.StopFile;
            s.async_status_file = obj.AsyncStatusFile;
            if isa(obj.Profile, 'bms.profile.BridgeProfile')
                s.bridge_profile = obj.Profile.toStruct();
            else
                s.bridge_profile = struct();
            end
        end

        function s = toJsonStruct(obj)
            s = obj.toStruct();
            s.options = obj.Options;
            s.config = obj.Config;
        end

        function writeJson(obj, path)
            bms.core.Logger.writeJson(path, obj.toJsonStruct());
        end
    end

    methods (Static)
        function obj = fromLegacy(root, startDate, endDate, opts, cfg)
            if nargin < 4 || isempty(opts), opts = struct(); end
            if nargin < 5, cfg = []; end
            obj = bms.app.RunRequest(root, startDate, endDate, opts, cfg);
        end

        function obj = fromContext(ctx)
            obj = bms.app.RunRequest(ctx.DataRoot, ctx.StartDate, ctx.EndDate, ctx.Options, ctx.Config, ...
                'ProjectRoot', ctx.ProjectRoot, 'ConfigPath', ctx.ConfigPath);
        end

        function path = configPathFromConfig(cfg)
            path = '';
            if isstruct(cfg) && isfield(cfg, 'source') && ~isempty(cfg.source)
                path = char(cfg.source);
            end
        end

        function obj = fromJsonStruct(s)
            if ~isstruct(s)
                error('BMS:RunRequest:InvalidJson', 'Run request JSON must decode to a struct.');
            end
            opts = bms.app.RunRequest.fieldValue(s, 'options', struct());
            cfg = bms.app.RunRequest.fieldValue(s, 'config', struct());
            args = {};
            configPath = bms.app.RunRequest.fieldText(s, 'config_path');
            if ~isempty(configPath), args = [args, {'ConfigPath', configPath}]; end %#ok<AGROW>
            stopFile = bms.app.RunRequest.fieldText(s, 'stop_file');
            if ~isempty(stopFile), args = [args, {'StopFile', stopFile}]; end %#ok<AGROW>
            statusFile = bms.app.RunRequest.fieldText(s, 'async_status_file');
            if ~isempty(statusFile), args = [args, {'AsyncStatusFile', statusFile}]; end %#ok<AGROW>
            asyncRunId = bms.app.RunRequest.fieldText(s, 'async_run_id');
            if ~isempty(asyncRunId), args = [args, {'AsyncRunId', asyncRunId}]; end %#ok<AGROW>
            projectRoot = bms.app.RunRequest.fieldText(s, 'project_root');
            if ~isempty(projectRoot), args = [args, {'ProjectRoot', projectRoot}]; end %#ok<AGROW>
            obj = bms.app.RunRequest( ...
                bms.app.RunRequest.fieldText(s, 'data_root'), ...
                bms.app.RunRequest.fieldText(s, 'start_date'), ...
                bms.app.RunRequest.fieldText(s, 'end_date'), ...
                opts, cfg, args{:});
        end

        function obj = readJson(path)
            s = jsondecode(fileread(path));
            obj = bms.app.RunRequest.fromJsonStruct(s);
        end

        function value = fieldValue(s, name, defaultValue)
            value = defaultValue;
            if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
                value = s.(name);
            end
        end

        function text = fieldText(s, name)
            text = '';
            if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
                text = char(string(s.(name)));
            end
        end
    end
end
