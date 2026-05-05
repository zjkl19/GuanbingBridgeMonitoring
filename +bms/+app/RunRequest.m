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
            if isa(obj.Profile, 'bms.profile.BridgeProfile')
                s.bridge_profile = obj.Profile.toStruct();
            else
                s.bridge_profile = struct();
            end
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
    end
end
