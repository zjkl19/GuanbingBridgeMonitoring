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
        ConfigSha256 char = ''
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
                    case 'configsha256'
                        obj.ConfigSha256 = char(value);
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

            obj.ConfigSha256 = bms.app.RunRequest.bindConfigHash( ...
                obj.ConfigPath, obj.ConfigSha256, obj.ProjectRoot);

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
            s.config_sha256 = obj.ConfigSha256;
            s.stats_dir = obj.StatsDir;
            s.log_dir = obj.LogDir;
            s.data_layout = obj.DataLayout;
            s.enabled_modules = bms.module.ModuleRegistry.enabledKeys(obj.Options);
            s.async_run_id = obj.AsyncRunId;
            s.stop_file = obj.StopFile;
            s.async_status_file = obj.AsyncStatusFile;
            s.plot_sampling = bms.app.RunRequest.plotSamplingSummary(obj.Config);
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
            configSha256 = bms.app.RunRequest.fieldText(s, 'config_sha256');
            if ~isempty(configSha256), args = [args, {'ConfigSha256', configSha256}]; end %#ok<AGROW>
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
            s = bms.io.JsonFile.read(path);
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

        function value = bindConfigHash(configPath, suppliedHash, projectRoot)
            value = lower(strtrim(char(string(suppliedHash))));
            if ~isempty(value) && isempty(regexp(value, '^[0-9a-f]{64}$', 'once'))
                error('BMS:RunRequest:ConfigHashInvalid', ...
                    'config_sha256 must contain exactly 64 hexadecimal characters.');
            end
            resolvedPath = bms.app.RunRequest.resolveConfigPath(configPath, projectRoot);
            if isempty(resolvedPath)
                if ~isempty(value)
                    error('BMS:RunRequest:ConfigFileMissing', ...
                        'Cannot validate config_sha256 because config_path does not exist: %s', configPath);
                end
                return;
            end
            actual = bms.config.ConfigLayerLoader.dependencySha256(resolvedPath);
            if isempty(value)
                value = actual;
            elseif ~strcmpi(value, actual)
                error('BMS:RunRequest:ConfigHashMismatch', ...
                    'Configuration file changed after the analysis request was created: %s', resolvedPath);
            end
        end

        function path = resolveConfigPath(configPath, projectRoot)
            path = '';
            raw = char(string(configPath));
            if isempty(raw)
                return;
            end
            if isfile(raw)
                path = raw;
                return;
            end
            candidate = fullfile(char(string(projectRoot)), raw);
            if isfile(candidate)
                path = candidate;
            end
        end

        function summary = plotSamplingSummary(cfg)
            wind = bms.app.RunRequest.plotSamplingRecord(cfg);
            accelerationCfg = bms.analyzer.DynamicSeriesService.configForRawPlotModule(cfg, 'acceleration');
            cableCfg = bms.analyzer.DynamicSeriesService.configForRawPlotModule(cfg, 'cable_accel');
            acceleration = bms.app.RunRequest.plotSamplingRecord(accelerationCfg);
            cableAcceleration = bms.app.RunRequest.plotSamplingRecord(cableCfg);
            summary = struct( ...
                'mode', wind.sampling_mode, ...
                'group_mode', wind.group_mode, ...
                'render_mode', wind.render_mode, ...
                'line_width', wind.line_width, ...
                'gap_mode', wind.gap_mode, ...
                'raw_emf_disabled', wind.raw_emf_disabled, ...
                'modules', struct( ...
                    'wind', wind, ...
                    'acceleration', acceleration, ...
                    'cable_accel', cableAcceleration));
        end

        function record = plotSamplingRecord(cfg)
            runtime = bms.plot.PlotService.runtimeOptionsFromConfig(cfg);
            record = struct( ...
                'sampling_mode', bms.analyzer.DynamicSeriesService.rawSamplingMode(cfg, 'capped'), ...
                'group_mode', bms.analyzer.DynamicAccelerationSeriesService.groupSamplingMode(cfg), ...
                'render_mode', bms.analyzer.DynamicSeriesService.rawPlotRenderMode(cfg, 'line'), ...
                'line_width', bms.analyzer.DynamicSeriesService.rawPlotLineWidth(cfg, 1.0), ...
                'gap_mode', char(string(runtime.gap_mode)), ...
                'raw_emf_disabled', ~runtime.save_emf);
        end
    end
end
