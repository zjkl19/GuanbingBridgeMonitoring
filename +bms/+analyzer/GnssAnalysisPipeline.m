classdef GnssAnalysisPipeline
    %GNSSANALYSISPIPELINE GNSS displacement component analysis workflow.

    methods (Static)
        function run(rootDir, pointIds, startDate, endDate, excelFile, subfolder, cfg)
            if nargin < 1 || isempty(rootDir), rootDir = pwd; end
            if nargin < 2 || isempty(pointIds), error('请提供 GNSS point_ids'); end
            if nargin < 3 || isempty(startDate), error('start_date is required'); end
            if nargin < 4 || isempty(endDate), error('end_date is required'); end
            if nargin < 5 || isempty(excelFile), excelFile = 'gnss_stats.xlsx'; end
            if nargin < 7 || isempty(cfg), cfg = load_config(); end
            if nargin < 6 || isempty(subfolder)
                subfolder = bms.analyzer.GnssAnalysisPipeline.resolveSubfolder(cfg);
            end

            pointIds = bms.data.PointResolver.normalize(pointIds);
            excelFile = resolve_data_output_path(rootDir, excelFile, 'stats');
            style = bms.analyzer.GnssAnalysisPipeline.style(cfg);
            outDir = fullfile(rootDir, char(string( ...
                bms.config.ConfigReader.getField(style, 'output_dir', '时程曲线_GNSS'))));
            bms.core.PathResolver.ensureDir(outDir);

            [dt0, dt1] = bms.analyzer.StructuralTimeSeriesPlotService.dateRange(startDate, endDate);
            components = bms.analyzer.GnssAnalysisPipeline.components();
            colors = bms.analyzer.GnssAnalysisPipeline.colors(style);
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
            stats = cell(0, 10);

            for i = 1:numel(pointIds)
                pid = pointIds{i};
                fprintf('GNSS point %s ...\n', pid);
                [series, rows] = bms.analyzer.GnssAnalysisPipeline.collectPoint( ...
                    rootDir, subfolder, pid, startDate, endDate, cfg, components);
                stats = [stats; rows]; %#ok<AGROW>

                if isempty(series)
                    warning('GNSS 测点 %s 无有效数据，跳过', pid);
                    continue;
                end

                bms.analyzer.GnssAnalysisPipeline.plotPoint( ...
                    rootDir, outDir, pid, series, startDate, endDate, dt0, dt1, style, colors, timestamp, cfg);
            end

            T = bms.analyzer.StructuralSeriesService.componentStatsTable(stats);
            bms.io.StatsWriter.writeModuleTableChecked(T, excelFile, 'gnss');
            fprintf('GNSS stats saved to %s\n', excelFile);
        end

        function subfolder = resolveSubfolder(cfg)
            subfolder = bms.config.ConfigReader.getSubfolder(cfg, 'gnss', '波形');
        end

        function style = style(cfg)
            style = bms.config.ConfigReader.getPlotStyle(cfg, 'gnss');
        end

        function defs = components()
            defs = { ...
                struct('suffix', 'X', 'sensor_type', 'gnss_x', 'label', 'X向位移'), ...
                struct('suffix', 'Y', 'sensor_type', 'gnss_y', 'label', 'Y向位移'), ...
                struct('suffix', 'Z', 'sensor_type', 'gnss_z', 'label', 'Z向位移')};
        end

        function colors = colors(style)
            defaultColors = [0 0.447 0.741; 0.85 0.325 0.098; 0.466 0.674 0.188];
            raw = bms.config.ConfigReader.getField(style, 'colors', defaultColors);
            colors = bms.plot.PlotService.normalizeColors(raw, defaultColors);
        end

        function [series, rows] = collectPoint(rootDir, subfolder, pid, startDate, endDate, cfg, components)
            series = struct('label', {}, 'times', {}, 'vals', {});
            rows = cell(0, 10);
            for j = 1:numel(components)
                comp = components{j};
                [times, vals] = load_timeseries_range(rootDir, subfolder, pid, ...
                    startDate, endDate, cfg, comp.sensor_type);
                if isempty(times) || isempty(vals)
                    continue;
                end
                [times, vals] = bms.analyzer.StructuralSeriesService.validSeries(times, vals);
                if isempty(vals)
                    continue;
                end

                series(end+1) = struct('label', comp.label, 'times', times, 'vals', vals); %#ok<AGROW>
                rows(end+1, :) = bms.analyzer.StructuralSeriesService.componentStatsRow( ...
                    pid, comp.suffix, comp.label, times, vals, 3); %#ok<AGROW>
            end
        end

        function plotPoint(rootDir, outDir, pid, series, startDate, endDate, dt0, dt1, style, colors, timestamp, cfg)
            fig = figure('Position', [100 100 1000 469]);
            hold on;
            hLines = gobjects(numel(series), 1);
            plotOpts = bms.plot.PlotService.runtimeOptionsFromConfig(cfg);
            for j = 1:numel(series)
                [timesPlot, valsPlot] = prepare_plot_series(series(j).times, series(j).vals, plotOpts);
                colorIdx = min(j, size(colors, 1));
                hLines(j) = plot(timesPlot, valsPlot, 'LineWidth', 1.0, 'Color', colors(colorIdx, :));
            end

            lg = legend(hLines, {series.label}, 'Location', 'northeast', 'Box', 'off');
            lg.AutoUpdate = 'off';
            bms.analyzer.StructuralTimeSeriesPlotService.applyDateAxis(dt0, dt1);
            xlabel('时间');
            ylabel(bms.config.ConfigReader.getField(style, 'ylabel', 'GNSS位移 (mm)'));
            title(sprintf('%s %s', bms.config.ConfigReader.getField(style, 'title_prefix', 'GNSS位移时程'), pid));
            bms.analyzer.GnssAnalysisPipeline.applyYLim(style);
            grid on;
            grid minor;

            fileStub = bms.analyzer.GnssAnalysisPipeline.sanitizeFilename( ...
                sprintf('GNSS_%s_%s_%s', pid, datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd')));
            bms.plot.PlotService.saveModuleBundle(fig, outDir, [fileStub '_' timestamp], cfg);
        end

        function applyYLim(style)
            if bms.config.ConfigReader.boolValue(bms.config.ConfigReader.getField(style, 'ylim_auto', true), false)
                ylim auto;
                return;
            end
            yl = bms.config.ConfigReader.getField(style, 'ylim', []);
            if bms.plot.PlotService.isValidYLim(yl)
                ylim(yl);
            else
                ylim auto;
            end
        end

        function out = sanitizeFilename(value)
            out = regexprep(char(string(value)), '[<>:\"/\\\\|?*]+', '_');
            out = regexprep(out, '\s+', '_');
        end
    end
end
