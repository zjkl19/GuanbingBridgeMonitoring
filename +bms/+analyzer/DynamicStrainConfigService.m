classdef DynamicStrainConfigService
    %DYNAMICSTRAINCONFIGSERVICE Configuration helpers for dynamic strain boxplots.

    methods (Static)
        function opt = parseInputs(rootDir, startDate, endDate, varargin)
            p = inputParser;
            addRequired(p, 'root_dir', @(s)ischar(s)||isstring(s));
            addRequired(p, 'start_date', @(s)ischar(s)||isstring(s));
            addRequired(p, 'end_date', @(s)ischar(s)||isstring(s));
            addParameter(p, 'Cfg', [], @(x)isstruct(x)||ischar(x)||isstring(x));
            addParameter(p, 'OutputDir', '', @(s)ischar(s)||isstring(s));
            addParameter(p, 'OutputDirTs', '', @(s)ischar(s)||isstring(s));
            addParameter(p, 'StatsFile', '', @(s)ischar(s)||isstring(s));
            addParameter(p, 'Subfolder', '', @(s)ischar(s)||isstring(s));
            addParameter(p, 'Fs', [], @(x)(isnumeric(x)&&isscalar(x))||isempty(x));
            addParameter(p, 'Fc', [], @(x)(isnumeric(x)&&isscalar(x))||isempty(x));
            addParameter(p, 'CutoffPeriodMinutes', [], @(x)(isnumeric(x)&&isscalar(x))||isempty(x));
            addParameter(p, 'FilterOrder', [], @(x)(isnumeric(x)&&isscalar(x))||isempty(x));
            addParameter(p, 'Whisker', [], @(x)(isnumeric(x)&&isscalar(x))||isempty(x));
            addParameter(p, 'ShowOutliers', [], @(x)islogical(x)||isnumeric(x));
            addParameter(p, 'YLimManual', [], @(x)islogical(x)||isnumeric(x));
            addParameter(p, 'YLimRange', [], @(x)isnumeric(x)&&numel(x)==2);
            addParameter(p, 'LowerBound', [], @(x)(isnumeric(x)&&isscalar(x))||isempty(x));
            addParameter(p, 'UpperBound', [], @(x)(isnumeric(x)&&isscalar(x))||isempty(x));
            addParameter(p, 'EdgeTrimSec', [], @(x)(isnumeric(x)&&isscalar(x))||isempty(x));
            parse(p, rootDir, startDate, endDate, varargin{:});
            opt = p.Results;
        end

        function cfg = loadConfig(raw)
            if isempty(raw)
                cfg = load_config();
            elseif ischar(raw) || isstring(raw)
                cfg = load_config(raw);
            else
                cfg = raw;
            end
        end

        function spec = modeSpec(mode)
            mode = lower(char(string(mode)));
            switch mode
                case {'highpass', 'high'}
                    spec.mode = 'highpass';
                    spec.defaultKey = 'dynamic_strain';
                    spec.legacyDefaultKey = 'defaults_dynamic_strain';
                    spec.groupKeys = {'dynamic_strain'};
                    spec.legacyGroupKeys = {'groups_dynamic_strain'};
                    spec.styleKeys = {'dynamic_strain'};
                    spec.legacyStyleKeys = {'plot_styles_dynamic_strain'};
                    spec.defaultOutputDir = '动应变箱线图_高通滤波';
                    spec.defaultTimeseriesDir = '时程曲线_动应变_高通滤波';
                    spec.defaultStatsFile = 'dynamic_strain_highpass_stats.xlsx';
                    spec.moduleKey = 'dynamic_strain_highpass';
                    spec.timeseriesBase = 'dynstrain_hp';
                    spec.boxTitle = '动应变箱线图（高通滤波后）%s [%s]';
                    spec.timeseriesTitle = '动应变时程（高通滤波后）%s [%s]';
                    spec.statsHeader = '动应变箱线图统计（高通滤波后） 日期范围: %s ~ %s\n';
                    spec.defaults = struct('Fs', [], 'Fc', 0.1, 'Whisker', 300, 'ShowOutliers', false, ...
                        'YLimManual', true, 'YLimRange', [-30 30], ...
                        'LowerBound', -150, 'UpperBound', 150, 'EdgeTrimSec', 5);
                case {'lowpass', 'low'}
                    spec.mode = 'lowpass';
                    spec.defaultKey = 'dynamic_strain_lowpass';
                    spec.legacyDefaultKey = 'defaults_dynamic_strain_lowpass';
                    spec.groupKeys = {'dynamic_strain_lowpass', 'dynamic_strain'};
                    spec.legacyGroupKeys = {'groups_dynamic_strain_lowpass', 'groups_dynamic_strain'};
                    spec.styleKeys = {'dynamic_strain_lowpass', 'dynamic_strain'};
                    spec.legacyStyleKeys = {'plot_styles_dynamic_strain_lowpass', 'plot_styles_dynamic_strain'};
                    spec.defaultOutputDir = '动应变箱线图_低通滤波';
                    spec.defaultTimeseriesDir = '时程曲线_动应变_低通滤波';
                    spec.defaultStatsFile = 'dynamic_strain_lowpass_stats.xlsx';
                    spec.moduleKey = 'dynamic_strain_lowpass';
                    spec.timeseriesBase = 'dynstrain_lp';
                    spec.boxTitle = '动应变箱线图（低通滤波后）%s [%s]';
                    spec.timeseriesTitle = '动应变时程（低通滤波后）%s [%s]';
                    spec.statsHeader = '动应变箱线图统计（低通滤波后） 日期范围: %s ~ %s\n';
                    spec.defaults = struct('FilterMode', 'auto', 'AutoPreset', 'temperature', ...
                        'AutoCutoffPeriodMinutes', 720, 'MinSamplesPerCutoff', 20, ...
                        'Fs', [], 'Fc', [], 'CutoffPeriodMinutes', [], 'FilterOrder', 2, ...
                        'Whisker', 300, 'ShowOutliers', false, ...
                        'YLimManual', false, 'YLimRange', [-150 150], ...
                        'LowerBound', -150, 'UpperBound', 150, 'EdgeTrimSec', 5, ...
                        'MaxGapSec', []);
                otherwise
                    error('DynamicStrainBoxplotPipeline:UnsupportedMode', 'Unsupported dynamic strain mode: %s', mode);
            end
        end

        function ds = dynamicConfig(cfg, spec)
            ds = spec.defaults;
            d = struct();
            if isfield(cfg, 'defaults') && isstruct(cfg.defaults) && isfield(cfg.defaults, spec.defaultKey)
                d = cfg.defaults.(spec.defaultKey);
            elseif isfield(cfg, spec.legacyDefaultKey)
                d = cfg.(spec.legacyDefaultKey);
            end
            fields = fieldnames(ds);
            for i = 1:numel(fields)
                field = fields{i};
                if isstruct(d) && isfield(d, field) && ~isempty(d.(field))
                    ds.(field) = d.(field);
                end
            end
        end

        function [groups, names, style] = groupsAndStyle(cfg, spec)
            rawGroups = [];
            for i = 1:numel(spec.groupKeys)
                key = spec.groupKeys{i};
                if isfield(cfg, 'groups') && isstruct(cfg.groups) && isfield(cfg.groups, key)
                    rawGroups = cfg.groups.(key);
                    break;
                end
            end
            if isempty(rawGroups)
                for i = 1:numel(spec.legacyGroupKeys)
                    key = spec.legacyGroupKeys{i};
                    if isfield(cfg, key)
                        rawGroups = cfg.(key);
                        break;
                    end
                end
            end

            groups = {};
            names = {};
            if isstruct(rawGroups)
                names = fieldnames(rawGroups);
                for i = 1:numel(names)
                    groups{i} = cellstr(rawGroups.(names{i})(:)); %#ok<AGROW>
                end
            elseif iscell(rawGroups)
                groups = rawGroups;
                names = arrayfun(@(i)sprintf('Group%d', i), 1:numel(rawGroups), 'UniformOutput', false);
            end
            if isempty(groups)
                error('DynamicStrainBoxplotPipeline:MissingGroups', ...
                    'Dynamic strain groups are not configured. Configure groups.dynamic_strain_lowpass or groups.dynamic_strain.');
            end

            style = struct();
            for i = 1:numel(spec.styleKeys)
                key = spec.styleKeys{i};
                if isfield(cfg, 'plot_styles') && isstruct(cfg.plot_styles) && isfield(cfg.plot_styles, key)
                    style = cfg.plot_styles.(key);
                    return;
                end
            end
            for i = 1:numel(spec.legacyStyleKeys)
                key = spec.legacyStyleKeys{i};
                if isfield(cfg, key)
                    style = cfg.(key);
                    return;
                end
            end
        end

        function ylimValue = groupYLim(style, groupName, ds)
            ylimValue = [];
            if isstruct(style) && isfield(style, 'ylims') && isfield(style.ylims, groupName)
                ylimValue = style.ylims.(groupName);
            elseif ds.YLimManual
                ylimValue = ds.YLimRange;
            end
        end

        function applyPlotCommonRuntime(cfg)
            try
                if isstruct(cfg) && isfield(cfg, 'plot_common') && isstruct(cfg.plot_common)
                    plot_runtime_settings('set', cfg.plot_common);
                end
            catch
            end
        end

        function path = resolveDir(rootDir, userPath, defaultName)
            if ~isempty(userPath)
                path = char(userPath);
                if ~bms.analyzer.DynamicStrainConfigService.isAbsolutePath(path)
                    path = fullfile(rootDir, path);
                end
            else
                path = fullfile(rootDir, defaultName);
            end
        end

        function path = resolveTimeseriesSingleDir(rootDir, userPath, style, spec)
            if ~isempty(userPath)
                path = bms.analyzer.DynamicStrainConfigService.resolveDir(rootDir, userPath, spec.defaultTimeseriesDir);
            elseif isstruct(style) && isfield(style, 'output_dir_ts') && ~isempty(style.output_dir_ts)
                path = bms.analyzer.DynamicStrainConfigService.resolveDir(rootDir, style.output_dir_ts, spec.defaultTimeseriesDir);
            else
                path = bms.analyzer.DynamicStrainConfigService.resolveDir(rootDir, '', spec.defaultTimeseriesDir);
            end
        end

        function path = resolveTimeseriesGroupDir(rootDir, singleDir, style)
            if isstruct(style) && isfield(style, 'group_output_dir_ts') && ~isempty(style.group_output_dir_ts)
                path = char(style.group_output_dir_ts);
                if ~bms.analyzer.DynamicStrainConfigService.isAbsolutePath(path)
                    path = fullfile(rootDir, path);
                end
            else
                path = [char(singleDir), char([95 32452 22270])];
            end
        end

        function path = resolveStatsFile(rootDir, userPath, defaultName)
            if ~isempty(userPath)
                path = char(userPath);
                if ~bms.analyzer.DynamicStrainConfigService.isAbsolutePath(path)
                    path = fullfile(rootDir, 'stats', path);
                end
            else
                path = fullfile(rootDir, 'stats', defaultName);
            end
            bms.data.DataLayoutResolver.ensureParentDir(path);
        end

        function tf = isAbsolutePath(path)
            tf = ~isempty(regexp(path, '^[A-Za-z]:\\', 'once')) || startsWith(path, filesep) || startsWith(path, '\\');
        end
    end
end
