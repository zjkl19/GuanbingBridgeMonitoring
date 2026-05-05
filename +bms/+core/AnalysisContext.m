classdef AnalysisContext
    %ANALYSISCONTEXT Immutable-ish context passed between GUI and pipeline.

    properties
        ProjectRoot char
        DataRoot char
        StartDate char
        EndDate char
        Options struct
        Config struct
        ConfigPath char = ''
        BridgeProfile = []
        StatsDir char
        LogDir char
        RunId char
        CreatedAt datetime
    end

    methods
        function obj = AnalysisContext(dataRoot, startDate, endDate, opts, cfg, varargin)
            if nargin < 4 || isempty(opts), opts = struct(); end
            if nargin < 5 || isempty(cfg), cfg = load_config(); end
            obj.ProjectRoot = bms.core.PathResolver.projectRoot();
            obj.DataRoot = char(dataRoot);
            obj.StartDate = char(startDate);
            obj.EndDate = char(endDate);
            obj.Options = opts;
            obj.Config = cfg;
            if isfield(cfg, 'source') && ~isempty(cfg.source)
                obj.ConfigPath = char(cfg.source);
            end
            obj.BridgeProfile = bms.profile.BridgeProfileRegistry.infer(cfg, obj.DataRoot);
            obj.StatsDir = bms.core.PathResolver.statsDir(obj.DataRoot);
            obj.LogDir = bms.core.PathResolver.logDir(obj.DataRoot);
            obj.CreatedAt = datetime('now');
            obj.RunId = datestr(obj.CreatedAt, 'yyyymmdd_HHMMSS');

            if mod(numel(varargin), 2) ~= 0
                error('AnalysisContext name-value arguments must be paired.');
            end
            for i = 1:2:numel(varargin)
                key = char(varargin{i});
                value = varargin{i+1};
                switch lower(key)
                    case 'projectroot'
                        obj.ProjectRoot = char(value);
                    case 'configpath'
                        obj.ConfigPath = char(value);
                    case 'bridgeprofile'
                        obj.BridgeProfile = value;
                    case 'logdir'
                        obj.LogDir = char(value);
                    case 'runid'
                        obj.RunId = char(value);
                    otherwise
                        error('Unknown AnalysisContext option: %s', key);
                end
            end
        end

        function modules = enabledModules(obj)
            modules = bms.core.ModuleRegistry.enabledNames(obj.Options);
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
            s.run_id = obj.RunId;
            s.created_at = datestr(obj.CreatedAt, 'yyyy-mm-dd HH:MM:ss');
            s.enabled_modules = obj.enabledModules();
            if isa(obj.BridgeProfile, 'bms.profile.BridgeProfile')
                s.bridge_profile = obj.BridgeProfile.toStruct();
            else
                s.bridge_profile = struct();
            end
            s.date_range = struct('start_date', obj.StartDate, 'end_date', obj.EndDate);
        end
    end

    methods (Static)
        function obj = fromLegacy(root, startDate, endDate, opts, cfg)
            obj = bms.core.AnalysisContext(root, startDate, endDate, opts, cfg);
        end
    end
end
