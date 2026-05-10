classdef StrainAnalysisPipeline
    %STRAINANALYSISPIPELINE Static strain stats, time series, and boxplots.

    methods (Static)
        function run(rootDir, startDate, endDate, excelFile, subfolder, cfg)
            if nargin < 1 || isempty(rootDir), rootDir = pwd; end
            if nargin < 2 || isempty(startDate), error('start_date is required'); end
            if nargin < 3 || isempty(endDate), error('end_date is required'); end
            if nargin < 4 || isempty(excelFile), excelFile = 'strain_stats.xlsx'; end
            if nargin < 6 || isempty(cfg), cfg = load_config(); end
            if nargin < 5 || isempty(subfolder)
                subfolder = bms.analyzer.StrainAnalysisPipeline.resolveSubfolder(cfg);
            end

            rootDir = char(string(rootDir));
            subfolder = char(string(subfolder));
            excelFile = resolve_data_output_path(rootDir, excelFile, 'stats');
            ctx = bms.analyzer.StrainAnalysisPipeline.context(cfg);

            statsRows = cell(0, 4);
            if ctx.explicit_points
                statsRows = bms.analyzer.StrainAnalysisPipeline.runPoints( ...
                    rootDir, subfolder, startDate, endDate, cfg, ctx, statsRows);
            end

            if ctx.explicit_ts_groups
                [statsRows, ~] = bms.analyzer.StrainAnalysisPipeline.runTimeseriesGroups( ...
                    rootDir, subfolder, startDate, endDate, cfg, ctx, statsRows);
            end

            if ctx.explicit_groups
                [statsRows, ~] = bms.analyzer.StrainAnalysisPipeline.runBoxplotGroups( ...
                    rootDir, subfolder, startDate, endDate, cfg, ctx, statsRows);
            end

            T = bms.analyzer.StructuralSeriesService.basicStatsTable(statsRows);
            bms.io.StatsWriter.writeModuleTableChecked(T, excelFile, 'strain');
            fprintf('Strain stats saved to %s\n', excelFile);
        end

        function subfolder = resolveSubfolder(cfg)
            subfolder = bms.config.ConfigReader.getSubfolder(cfg, 'strain', '特征值');
        end

        function ctx = context(cfg)
            ctx = struct();
            ctx.style = bms.analyzer.StrainAnalysisPipeline.style(cfg);
            ctx.points = bms.analyzer.StrainAnalysisPipeline.resolvePoints(cfg);
            ctx.groups = bms.analyzer.StrainAnalysisPipeline.groups(cfg, 'strain');
            ctx.ts_groups = bms.analyzer.StrainAnalysisPipeline.groups(cfg, 'strain_timeseries');
            ctx.explicit_points = ~isempty(ctx.points);
            ctx.explicit_groups = bms.analyzer.StrainAnalysisPipeline.hasGroups(ctx.groups);
            ctx.explicit_ts_groups = bms.analyzer.StrainAnalysisPipeline.hasGroups(ctx.ts_groups);

            if ~ctx.explicit_ts_groups && ctx.explicit_groups
                ctx.ts_groups = ctx.groups;
                ctx.explicit_ts_groups = true;
            end

            if ~ctx.explicit_points && ~ctx.explicit_groups && ~ctx.explicit_ts_groups
                ctx.groups = bms.analyzer.StrainAnalysisPipeline.legacyGroups();
                ctx.ts_groups = ctx.groups;
                ctx.explicit_groups = true;
                ctx.explicit_ts_groups = true;
            end
        end

        function rows = runPoints(rootDir, subfolder, startDate, endDate, cfg, ctx, rows)
            for i = 1:numel(ctx.points)
                pid = ctx.points{i};
                fprintf('Per-point strain: %s ...\n', pid);
                data = bms.analyzer.StructuralSeriesService.loadPoint( ...
                    rootDir, subfolder, pid, startDate, endDate, cfg, 'strain');
                if isempty(data.vals)
                    warning('Strain point %s has no data, skip', pid);
                    continue;
                end

                rows(end+1, :) = bms.analyzer.StructuralSeriesService.basicStatsRow( ...
                    pid, data.vals, 3); %#ok<AGROW>

                warnLines = bms.analyzer.StrainAnalysisPipeline.resolveWarnLines(ctx.style, cfg, pid);
                bms.analyzer.StrainAnalysisPipeline.plotPointCurve( ...
                    rootDir, data.times, data.vals, startDate, endDate, pid, ctx.style, warnLines, cfg);
            end
        end

        function [rows, plottedGroups] = runTimeseriesGroups(rootDir, subfolder, startDate, endDate, cfg, ctx, rows)
            plottedGroups = {};
            groupsMap = bms.analyzer.StrainAnalysisPipeline.normalizeGroupMap(ctx.ts_groups);
            names = fieldnames(groupsMap);
            for i = 1:numel(names)
                groupName = names{i};
                [dataList, groupRows] = bms.analyzer.StrainAnalysisPipeline.collectGroupData( ...
                    rootDir, subfolder, groupsMap.(groupName), startDate, endDate, cfg);
                if isempty(dataList)
                    continue;
                end

                if ~ctx.explicit_points && ~ctx.explicit_groups
                    rows = [rows; groupRows]; %#ok<AGROW>
                end
                bms.analyzer.StrainAnalysisPipeline.plotGroupTimeseries( ...
                    rootDir, dataList, startDate, endDate, groupName, ctx.style, cfg);
                plottedGroups{end+1, 1} = groupName; %#ok<AGROW>
            end
        end

        function [rows, plottedGroups] = runBoxplotGroups(rootDir, subfolder, startDate, endDate, cfg, ctx, rows)
            plottedGroups = {};
            groupsMap = bms.analyzer.StrainAnalysisPipeline.normalizeGroupMap(ctx.groups);
            names = fieldnames(groupsMap);
            for i = 1:numel(names)
                groupName = names{i};
                [dataList, groupRows] = bms.analyzer.StrainAnalysisPipeline.collectGroupData( ...
                    rootDir, subfolder, groupsMap.(groupName), startDate, endDate, cfg);
                if isempty(dataList)
                    continue;
                end

                if ~ctx.explicit_points
                    rows = [rows; groupRows]; %#ok<AGROW>
                end
                bms.analyzer.StrainAnalysisPipeline.plotGroupBoxplot( ...
                    rootDir, dataList, startDate, endDate, groupName, ctx.style, cfg);
                plottedGroups{end+1, 1} = groupName; %#ok<AGROW>
            end
        end

        function [dataList, statsRows] = collectGroupData(rootDir, subfolder, pointIds, startDate, endDate, cfg)
            [dataList, statsRows] = bms.analyzer.StructuralSeriesService.collectPoints( ...
                rootDir, subfolder, pointIds, startDate, endDate, cfg, 'strain', 3, 'Strain point');
        end

        function plotPointCurve(rootDir, times, vals, startDate, endDate, pointId, style, warnLines, cfg)
            if nargin < 9
                cfg = struct();
            end
            fig = figure('Position', [100 100 1000 469]);
            hold on;
            [timesPlot, valsPlot] = prepare_plot_series(times, vals);
            plot(timesPlot, valsPlot, 'LineWidth', 1.0, 'Color', [0 0.447 0.741]);

            [dt0, dt1] = bms.analyzer.StructuralTimeSeriesPlotService.dateRange(startDate, endDate);
            bms.analyzer.StructuralTimeSeriesPlotService.applyDateAxis(dt0, dt1);

            xlabel('时间');
            ylabel(bms.analyzer.StrainAnalysisPipeline.styleField(style, 'ylabel', '主梁应变 (με)'));
            title(sprintf('%s %s', ...
                bms.analyzer.StrainAnalysisPipeline.styleField(style, 'title_prefix', '应变时程曲线'), ...
                char(string(pointId))), 'Interpreter', 'none');

            if bms.analyzer.StrainAnalysisPipeline.truthy( ...
                    bms.analyzer.StrainAnalysisPipeline.styleField(style, 'show_warn_lines_point', true))
                bms.analyzer.StructuralTimeSeriesPlotService.drawWarnLines(warnLines);
            end

            if bms.analyzer.StrainAnalysisPipeline.truthy( ...
                    bms.analyzer.StrainAnalysisPipeline.styleField(style, 'ylim_auto', false))
                ylim auto;
            else
                ylimRange = bms.analyzer.StrainAnalysisPipeline.pointYLim(style, pointId, ...
                    bms.analyzer.StrainAnalysisPipeline.styleField(style, 'ylim', []));
                bms.analyzer.StructuralTimeSeriesPlotService.applyYLim(ylimRange);
            end

            grid on;
            grid minor;

            outDir = fullfile(rootDir, char(string( ...
                bms.analyzer.StrainAnalysisPipeline.styleField(style, 'output_dir', '时程曲线_应变'))));
            bms.core.PathResolver.ensureDir(outDir);
            baseName = bms.analyzer.StrainAnalysisPipeline.sanitizeFilename( ...
                sprintf('Strain_%s_%s_%s_%s', char(string(pointId)), ...
                datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd'), datestr(now, 'yyyymmdd_HHMMSS')));
            bms.plot.PlotService.saveModuleBundle(fig, outDir, baseName, cfg);
        end

        function plotGroupTimeseries(rootDir, dataList, startDate, endDate, groupName, style, cfg)
            if nargin < 7
                cfg = struct();
            end
            if isempty(dataList)
                return;
            end

            nSeries = numel(dataList);
            if nSeries > 12
                fprintf('[WARN] Strain group %s has %d curves; consider splitting it for readability.\n', ...
                    char(string(groupName)), nSeries);
            end

            [dt0, dt1] = bms.analyzer.StructuralTimeSeriesPlotService.dateRange(startDate, endDate);
            opts = struct();
            opts.style = style;
            opts.outputDir = bms.analyzer.StrainAnalysisPipeline.styleField(style, 'group_output_dir', '时程曲线_应变_组图');
            opts.baseName = sprintf('Strain_%s_%s_%s_%s', char(string(groupName)), ...
                datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd'), datestr(now, 'yyyymmdd_HHMMSS'));
            opts.titleText = sprintf('%s %s', ...
                bms.analyzer.StrainAnalysisPipeline.styleField(style, 'title_prefix', '应变时程曲线'), ...
                char(string(groupName)));
            opts.ylabel = bms.analyzer.StrainAnalysisPipeline.styleField(style, 'ylabel', '主梁应变 (με)');
            opts.ylimRange = bms.analyzer.StrainAnalysisPipeline.groupYLim(style, groupName, []);
            opts.defaultColors = bms.analyzer.StrainAnalysisPipeline.groupColors(style, nSeries);
            opts.legendInterpreter = 'none';
            opts.titleInterpreter = 'none';
            bms.analyzer.StructuralTimeSeriesPlotService.plotDataList( ...
                rootDir, dataList, startDate, endDate, opts, cfg);
        end

        function plotGroupBoxplot(rootDir, dataList, startDate, endDate, groupName, style, cfg)
            if nargin < 7
                cfg = struct();
            end
            if isempty(dataList)
                return;
            end

            labels = {dataList.pid};
            maxPoints = bms.analyzer.StrainAnalysisPipeline.styleField(style, 'boxplot_max_points_per_series', 50000);
            dataMat = bms.analyzer.StrainAnalysisPipeline.buildBoxplotMatrix(dataList, maxPoints);

            fig = figure('Position', [100 100 1200 520]);
            if bms.analyzer.StrainAnalysisPipeline.truthy( ...
                    bms.analyzer.StrainAnalysisPipeline.styleField(style, 'show_boxplot_outliers', false))
                boxplot(dataMat, 'Labels', labels, 'LabelOrientation', 'inline');
            else
                boxplot(dataMat, 'Labels', labels, 'LabelOrientation', 'inline', 'Symbol', '');
            end
            hold on;
            xtickangle(45);

            if bms.analyzer.StrainAnalysisPipeline.truthy( ...
                    bms.analyzer.StrainAnalysisPipeline.styleField(style, 'show_warn_lines_boxplot', true))
                bms.analyzer.StrainAnalysisPipeline.drawBoxplotWarnLines(dataList, style, cfg);
            end

            ylabel(bms.analyzer.StrainAnalysisPipeline.styleField(style, 'ylabel', '主梁应变 (με)'));
            title(sprintf('%s %s', ...
                bms.analyzer.StrainAnalysisPipeline.styleField(style, 'boxplot_title_prefix', '应变箱线图'), ...
                char(string(groupName))), 'Interpreter', 'none');

            bms.analyzer.StructuralTimeSeriesPlotService.applyYLim( ...
                bms.analyzer.StrainAnalysisPipeline.groupYLim(style, groupName, []));
            grid on;
            grid minor;

            dt0 = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
            dt1 = datetime(endDate, 'InputFormat', 'yyyy-MM-dd');
            outDir = fullfile(rootDir, char(string( ...
                bms.analyzer.StrainAnalysisPipeline.styleField(style, 'boxplot_output_dir', '箱线图_应变'))));
            bms.core.PathResolver.ensureDir(outDir);
            baseName = bms.analyzer.StrainAnalysisPipeline.sanitizeFilename( ...
                sprintf('StrainBox_%s_%s_%s_%s', char(string(groupName)), ...
                datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd'), datestr(now, 'yyyymmdd_HHMMSS')));
            bms.plot.PlotService.saveModuleBundle(fig, outDir, baseName, cfg);
        end

        function dataMat = buildBoxplotMatrix(dataList, maxPointsPerSeries)
            if nargin < 2 || isempty(maxPointsPerSeries) || ~isscalar(maxPointsPerSeries) || ...
                    ~isfinite(maxPointsPerSeries) || maxPointsPerSeries < 1000
                maxPointsPerSeries = 50000;
            end
            maxPointsPerSeries = round(maxPointsPerSeries);

            maxLen = 0;
            for i = 1:numel(dataList)
                maxLen = max(maxLen, min(numel(dataList(i).vals), maxPointsPerSeries));
            end
            dataMat = NaN(maxLen, numel(dataList));
            for i = 1:numel(dataList)
                v = dataList(i).vals(:);
                if numel(v) > maxPointsPerSeries
                    idx = unique(round(linspace(1, numel(v), maxPointsPerSeries)), 'stable');
                    v = v(idx);
                end
                dataMat(1:numel(v), i) = v;
            end
        end

        function drawBoxplotWarnLines(dataList, style, cfg)
            for i = 1:numel(dataList)
                warnLines = bms.analyzer.StrainAnalysisPipeline.resolveWarnLines(style, cfg, dataList(i).pid);
                warnLines = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(warnLines);
                for k = 1:numel(warnLines)
                    wl = warnLines{k};
                    if ~isstruct(wl) || ~isfield(wl, 'y') || ~isnumeric(wl.y) || ...
                            ~isscalar(wl.y) || ~isfinite(wl.y)
                        continue;
                    end
                    color = [0.5 0.5 0.5];
                    if isfield(wl, 'color') && isnumeric(wl.color) && numel(wl.color) == 3
                        color = reshape(wl.color, 1, 3);
                    end
                    line([i - 0.28, i + 0.28], [wl.y, wl.y], ...
                        'LineStyle', '--', 'LineWidth', 1.0, 'Color', color);
                end
            end
        end

        function warnLines = resolveWarnLines(style, cfg, pointId)
            warnLines = bms.analyzer.StructuralPlotConfigService.resolveWarnLines(style, cfg, 'strain', pointId);
        end

        function groups = groups(cfg, key)
            groups = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, key, []);
        end

        function groups = normalizeGroupMap(groupsCfg)
            groups = bms.analyzer.StructuralPlotConfigService.normalizeGroupMap(groupsCfg);
        end

        function tf = hasGroups(groupsCfg)
            tf = bms.analyzer.StructuralPlotConfigService.hasGroups(groupsCfg);
        end

        function groups = legacyGroups()
            groups = struct( ...
                'G05', {{'GB-RSG-G05-001-01', 'GB-RSG-G05-001-02', 'GB-RSG-G05-001-03', 'GB-RSG-G05-001-04', 'GB-RSG-G05-001-05', 'GB-RSG-G05-001-06'}}, ...
                'G06', {{'GB-RSG-G06-001-01', 'GB-RSG-G06-001-02', 'GB-RSG-G06-001-03', 'GB-RSG-G06-001-04', 'GB-RSG-G06-001-05', 'GB-RSG-G06-001-06'}}); %#ok<STRNU>
        end

        function points = resolvePoints(cfg)
            points = bms.analyzer.StructuralPlotConfigService.getPoints(cfg, 'strain', {});
        end

        function style = style(cfg)
            style = bms.analyzer.StructuralPlotConfigService.getStyle(cfg, 'strain');
        end

        function value = styleField(style, field, defaultValue)
            value = bms.analyzer.StructuralPlotConfigService.getStyleField(style, field, defaultValue);
        end

        function y = pointYLim(style, pointId, defaultValue)
            y = bms.analyzer.StructuralPlotConfigService.resolveNamedYLim(style, pointId, defaultValue);
        end

        function y = groupYLim(style, groupName, defaultValue)
            y = bms.analyzer.StructuralPlotConfigService.resolveNamedYLim(style, groupName, defaultValue);
        end

        function out = sanitizeFilename(name)
            out = bms.analyzer.StructuralPlotConfigService.sanitizeFilename(name);
        end

        function colors = defaultGroupColors()
            colors = [
                0.0000 0.4470 0.7410
                0.8500 0.3250 0.0980
                0.9290 0.6940 0.1250
                0.4940 0.1840 0.5560
                0.4660 0.6740 0.1880
                0.3010 0.7450 0.9330
            ];
        end

        function colors = groupColors(style, nSeries)
            colors = bms.analyzer.StructuralPlotConfigService.groupColors( ...
                style, nSeries, 'colors_6', bms.analyzer.StrainAnalysisPipeline.defaultGroupColors());
        end

        function tf = truthy(value)
            tf = bms.config.ConfigReader.boolValue(value, false);
        end
    end
end
