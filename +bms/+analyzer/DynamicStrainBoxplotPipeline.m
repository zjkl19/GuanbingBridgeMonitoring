classdef DynamicStrainBoxplotPipeline
    %DYNAMICSTRAINBOXPLOTPIPELINE Shared orchestration for dynamic strain boxplots.

    methods (Static)
        function run(mode, rootDir, startDate, endDate, varargin)
            spec = bms.analyzer.DynamicStrainBoxplotPipeline.modeSpec(mode);
            opt = bms.analyzer.DynamicStrainBoxplotPipeline.parseInputs(rootDir, startDate, endDate, varargin{:});

            rootDir = char(opt.root_dir);
            dt0 = datetime(opt.start_date, 'InputFormat', 'yyyy-MM-dd');
            dt1 = datetime(opt.end_date, 'InputFormat', 'yyyy-MM-dd');
            startStr = char(string(dt0, 'yyyy-MM-dd'));
            endStr = char(string(dt1, 'yyyy-MM-dd'));
            tag = sprintf('%s-%s', char(string(dt0, 'yyyyMMdd')), char(string(dt1, 'yyyyMMdd')));
            timestamp = char(string(datetime('now'), 'yyyy-MM-dd_HH-mm-ss'));

            cfg = bms.analyzer.DynamicStrainBoxplotPipeline.loadConfig(opt.Cfg);
            ds = bms.analyzer.DynamicStrainBoxplotPipeline.dynamicConfig(cfg, spec);
            bms.analyzer.DynamicStrainBoxplotPipeline.applyPlotCommonRuntime(cfg);

            if ~isempty(opt.Subfolder)
                subfolder = char(opt.Subfolder);
            else
                subfolder = bms.config.ConfigReader.getSubfolder(cfg, 'strain', '特征值');
            end

            outDir = bms.analyzer.DynamicStrainBoxplotPipeline.resolveDir(rootDir, opt.OutputDir, spec.defaultOutputDir);
            outDirTs = bms.analyzer.DynamicStrainBoxplotPipeline.resolveDir(rootDir, opt.OutputDirTs, spec.defaultTimeseriesDir);
            bms.core.PathResolver.ensureDir(outDir);
            bms.core.PathResolver.ensureDir(outDirTs);

            [groups, groupNames, style] = bms.analyzer.DynamicStrainBoxplotPipeline.groupsAndStyle(cfg, spec);

            fprintf('日期范围: %s ~ %s\n', startStr, endStr);
            fprintf('数据目录: %s\\YYYY-MM-DD\\%s\n', rootDir, subfolder);

            for gi = 1:numel(groups)
                groupName = groupNames{gi};
                fprintf('\n== 处理分组 %s ==\n', groupName);
                [dataMat, labels, tsList] = bms.analyzer.DynamicStrainBoxplotPipeline.collectGroupData( ...
                    rootDir, subfolder, startStr, endStr, groups{gi}, ds, cfg, spec);
                bms.analyzer.DynamicStrainBoxplotPipeline.makeBoxplotAndStats( ...
                    dataMat, labels, groupName, outDir, ds, spec, tag, timestamp, dt0, dt1, cfg);
                ylimGroup = bms.analyzer.DynamicStrainBoxplotPipeline.groupYLim(style, groupName, ds);
                bms.analyzer.DynamicStrainBoxplotPipeline.plotTimeseriesGroup( ...
                    tsList, labels, groupName, outDirTs, dt0, dt1, ds, spec, ylimGroup, tag, timestamp, cfg);
            end

            fprintf('\n全部完成。\n');
        end

        function opt = parseInputs(rootDir, startDate, endDate, varargin)
            p = inputParser;
            addRequired(p, 'root_dir', @(s)ischar(s)||isstring(s));
            addRequired(p, 'start_date', @(s)ischar(s)||isstring(s));
            addRequired(p, 'end_date', @(s)ischar(s)||isstring(s));
            addParameter(p, 'Cfg', [], @(x)isstruct(x)||ischar(x)||isstring(x));
            addParameter(p, 'OutputDir', '', @(s)ischar(s)||isstring(s));
            addParameter(p, 'OutputDirTs', '', @(s)ischar(s)||isstring(s));
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

        function [dataMat, labels, tsList] = collectGroupData(rootDir, subfolder, startStr, endStr, pointIds, ds, cfg, spec)
            n = numel(pointIds);
            colData = cell(n, 1);
            labels = pointIds(:).';
            tsList = struct('pid', cell(n, 1), 'times', [], 'vals', []);
            for i = 1:n
                pid = pointIds{i};
                fprintf('  -> 读取 %s ...\n', pid);
                [values, times] = bms.analyzer.DynamicStrainBoxplotService.processPoint( ...
                    rootDir, subfolder, startStr, endStr, pid, ds, cfg, spec.mode);
                colData{i} = values(:);
                tsList(i).pid = pid;
                tsList(i).times = times(:);
                tsList(i).vals = values(:);
                fprintf('    样本数(非NaN): %d\n', nnz(~isnan(values)));
            end

            maxLen = max(cellfun(@numel, colData));
            dataMat = NaN(maxLen, n);
            for i = 1:n
                values = colData{i};
                dataMat(1:numel(values), i) = values;
            end
        end

        function makeBoxplotAndStats(dataMat, labels, groupName, outDir, ds, spec, tag, timestamp, dt0, dt1, cfg)
            fig = figure('Position', [100 100 1100 520]);
            plotMat = bms.analyzer.DynamicStrainBoxplotService.sampleBoxplotMatrix(dataMat, 50000);
            if ds.ShowOutliers
                boxplot(plotMat, 'Labels', labels, 'LabelOrientation', 'horizontal', 'Whisker', ds.Whisker);
            else
                boxplot(plotMat, 'Labels', labels, 'LabelOrientation', 'horizontal', 'Whisker', ds.Whisker, 'Symbol', '');
            end
            xlabel('测点');
            ylabel('应变 (με)');
            title(sprintf(spec.boxTitle, groupName, tag), 'Interpreter', 'none');
            xtickangle(45);
            grid on;
            grid minor;
            if ds.YLimManual
                ylim(ds.YLimRange);
            end

            base = sprintf('boxplot_%s_%s', groupName, tag);
            bms.plot.PlotService.saveModuleBundle(fig, outDir, [base '_' timestamp], cfg);

            statsTable = bms.analyzer.DynamicStrainBoxplotService.statsTable(dataMat, labels);
            txtPath = fullfile(outDir, sprintf('boxplot_stats_%s_%s.txt', groupName, tag));
            xlsxPath = fullfile(outDir, sprintf('boxplot_stats_%s.xlsx', tag));
            bms.analyzer.DynamicStrainBoxplotPipeline.writeStatsTxt(txtPath, statsTable, dt0, dt1, spec);
            bms.io.StatsWriter.writeModuleTableChecked(statsTable, xlsxPath, spec.moduleKey, 'Sheet', groupName);
        end

        function plotTimeseriesGroup(tsList, labels, groupName, outDir, dt0, dt1, ds, spec, ylimGroup, tag, timestamp, cfg)
            fig = figure('Position', [100 100 1100 520]);
            hold on;
            colors = {[0 0 0], [0 0 1], [0 0.7 0], [1 0.4 0.8], [1 0.6 0], [1 0 0]};

            n = numel(tsList);
            labels = labels(:);
            hLines = gobjects(n, 1);
            hasLine = false(n, 1);
            for i = 1:n
                times = tsList(i).times;
                values = tsList(i).vals;
                if isempty(times) || isempty(values)
                    continue;
                end
                color = colors{min(i, numel(colors))};
                [timesPlot, valuesPlot] = prepare_plot_series(times, values);
                if isempty(timesPlot) || isempty(valuesPlot) || ~any(isfinite(valuesPlot))
                    continue;
                end
                lineHandle = plot(timesPlot, valuesPlot, 'LineWidth', 1.0, 'Color', color);
                if ~isempty(lineHandle)
                    hLines(i) = lineHandle(1);
                    hasLine(i) = true;
                end
            end

            xlabel('时间');
            ylabel('应变 (με)');
            title(sprintf(spec.timeseriesTitle, groupName, tag), 'Interpreter', 'none');
            grid on;
            grid minor;

            allTimes = vertcat(tsList.times);
            if ~isempty(allTimes)
                xmin = min(allTimes);
                xmax = max(allTimes);
            else
                xmin = dt0;
                xmax = dt1;
            end
            if xmin == xmax
                xmin = xmin - minutes(1);
                xmax = xmax + minutes(1);
            end
            ax = gca;
            ax.XLim = [xmin xmax];
            ax.XTick = linspace(xmin, xmax, 5);
            if days(xmax - xmin) >= 1
                xtickformat('yyyy-MM-dd');
            else
                xtickformat('MM-dd HH:mm');
            end

            if ~isempty(ylimGroup)
                ylim(ylimGroup);
            elseif ds.YLimManual
                ylim(ds.YLimRange);
            end

            if any(hasLine)
                legend(hLines(hasLine), labels(hasLine), 'Location', 'northeast', 'Box', 'off', 'Interpreter', 'none');
            end

            base = sprintf('%s_%s_%s', spec.timeseriesBase, groupName, tag);
            bms.plot.PlotService.saveModuleBundle(fig, outDir, [base '_' timestamp], cfg);
        end

        function writeStatsTxt(path, statsTable, dt0, dt1, spec)
            fid = fopen(path, 'wt');
            if fid < 0
                error('DynamicStrainBoxplotPipeline:CannotWriteStats', 'Cannot write stats file: %s', path);
            end
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, spec.statsHeader, char(string(dt0, 'yyyy-MM-dd')), char(string(dt1, 'yyyy-MM-dd')));
            fprintf(fid, "字段: PointID, Min, Q1, Median, Q3, Max, Mean, Std, Count\n\n");
            for i = 1:height(statsTable)
                fprintf(fid, '%s\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%d\n', ...
                    statsTable.PointID{i}, statsTable.Min(i), statsTable.Q1(i), statsTable.Median(i), ...
                    statsTable.Q3(i), statsTable.Max(i), statsTable.Mean(i), statsTable.Std(i), statsTable.Count(i));
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
                if ~bms.analyzer.DynamicStrainBoxplotPipeline.isAbsolutePath(path)
                    path = fullfile(rootDir, path);
                end
            else
                path = fullfile(rootDir, defaultName);
            end
        end

        function tf = isAbsolutePath(path)
            tf = ~isempty(regexp(path, '^[A-Za-z]:\\', 'once')) || startsWith(path, filesep) || startsWith(path, '\\');
        end
    end
end
