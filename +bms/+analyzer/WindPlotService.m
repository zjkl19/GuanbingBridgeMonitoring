classdef WindPlotService
    %WINDPLOTSERVICE Plot generation for wind analysis outputs.

    methods (Static)
        function plotPoint(series, style, outRoot, startDate, endDate, cfg)
            if nargin < 6
                cfg = struct();
            end
            if isempty(series) || isempty(series.vSpeed)
                return;
            end

            bms.analyzer.WindPlotService.plotSpeedTimeseries( ...
                series.tSpeed, series.vSpeed, series.pid, style, outRoot, startDate, endDate, cfg, ...
                series.speed_source_provenance);
            bms.analyzer.WindPlotService.plotDirectionTimeseries( ...
                series.tDir, series.vDir, series.pid, style, outRoot, startDate, endDate, cfg, ...
                series.direction_source_provenance);
            bms.analyzer.WindPlotService.plotSpeed10min( ...
                series.t10, series.v10, series.pid, series.params, style, outRoot, startDate, endDate, cfg, ...
                series.speed_source_provenance);

            if ~isempty(series.vDir)
                [roseSpeed, roseDir] = bms.analyzer.WindRoseService.alignForRose( ...
                    series.tSpeed, series.vSpeed, series.tDir, series.vDir);
                bms.analyzer.WindPlotService.plotWindRose( ...
                    roseDir, roseSpeed, series.pid, series.params, style, outRoot, startDate, endDate, cfg, ...
                    series.speed_source_provenance, series.direction_source_provenance);
            end
        end

        function plotSpeedTimeseries(times, vals, pid, style, outRoot, startDate, endDate, cfg, sourceProvenance)
            if nargin < 8
                cfg = struct();
            end
            if nargin < 9
                sourceProvenance = struct();
            end
            if isempty(vals)
                return;
            end
            fig = figure('Position', [100 100 1100 500]);
            plotOpts = bms.analyzer.DynamicSeriesService.rawPlotOptions(cfg, 50000);
            plotOpts.series_id = pid;
            if isstruct(sourceProvenance) && ~isempty(fieldnames(sourceProvenance))
                plotOpts.source_provenance = sourceProvenance;
            end
            lineWidth = bms.analyzer.DynamicSeriesService.rawPlotLineWidth(cfg, 1.1);
            bms.analyzer.DynamicSeriesService.plotRawSeries( ...
                gca, times, vals, style.speed.color, plotOpts, lineWidth);
            xlabel('时间');
            ylabel(style.speed.ylabel);
            title(sprintf('%s %s [%s-%s]', style.speed.title_prefix, pid, startDate, endDate));
            grid on; grid minor;
            if ~isempty(style.speed.ylim)
                ylim(style.speed.ylim);
            end
            bms.plot.PlotService.setTimeAxis(times);

            outDir = fullfile(outRoot, style.output.speed_dir);
            bms.core.PathResolver.ensureDir(outDir);
            bms.analyzer.WindPlotService.savePlot(fig, outDir, ...
                sprintf('%s_speed_%s_%s', pid, startDate, endDate), cfg);
        end

        function plotDirectionTimeseries(times, vals, pid, style, outRoot, startDate, endDate, cfg, sourceProvenance)
            if nargin < 8
                cfg = struct();
            end
            if nargin < 9
                sourceProvenance = struct();
            end
            if isempty(vals)
                return;
            end
            fig = figure('Position', [100 100 1100 500]);
            plotOpts = bms.analyzer.DynamicSeriesService.rawPlotOptions(cfg, 50000);
            plotOpts.series_id = pid;
            if isstruct(sourceProvenance) && ~isempty(fieldnames(sourceProvenance))
                plotOpts.source_provenance = sourceProvenance;
            end
            lineWidth = bms.analyzer.DynamicSeriesService.rawPlotLineWidth(cfg, 1.0);
            bms.analyzer.DynamicSeriesService.plotRawSeries( ...
                gca, times, vals, style.direction.color, plotOpts, lineWidth);
            xlabel('时间');
            ylabel(style.direction.ylabel);
            title(sprintf('%s %s [%s-%s]', style.direction.title_prefix, pid, startDate, endDate));
            grid on; grid minor;
            ylim([0 360]);
            bms.plot.PlotService.setTimeAxis(times);

            outDir = fullfile(outRoot, style.output.direction_dir);
            bms.core.PathResolver.ensureDir(outDir);
            bms.analyzer.WindPlotService.savePlot(fig, outDir, ...
                sprintf('%s_direction_%s_%s', pid, startDate, endDate), cfg);
        end

        function plotSpeed10min(times, v10, pid, params, style, outRoot, startDate, endDate, cfg, sourceProvenance)
            if nargin < 9
                cfg = struct();
            end
            if nargin < 10
                sourceProvenance = struct();
            end
            if isempty(times) || isempty(v10) || numel(times) ~= numel(v10)
                return;
            end
            fig = figure('Position', [100 100 1100 500]);
            plotOpts = bms.plot.PlotService.runtimeOptionsFromConfig(cfg);
            [timesPlot, v10Plot] = prepare_plot_series(times, v10, plotOpts);
            h = plot(timesPlot, v10Plot, 'LineWidth', 1.2, 'Color', style.speed10.color);
            provenanceOpts = struct('series_id', pid, 'raw_sampling_mode', 'full');
            if isstruct(sourceProvenance) && ~isempty(fieldnames(sourceProvenance))
                provenanceOpts.source_provenance = sourceProvenance;
            end
            bms.analyzer.DynamicSeriesService.attachPlotProvenance( ...
                h, times, v10, v10Plot, 'derived_10min_mean', provenanceOpts);
            xlabel('时间');
            ylabel(style.speed10.ylabel);
            title(sprintf('%s %s [%s-%s]', style.speed10.title_prefix, pid, startDate, endDate));
            grid on; grid minor; hold on;
            if ~isempty(style.speed10.ylim)
                ylim(style.speed10.ylim);
            end
            bms.plot.PlotService.setTimeAxis(times);

            levels = params.alarm_levels(:)';
            if isempty(levels)
                levels = [];
            end
            levels = sort(levels(~isnan(levels)));
            labels = {'一级','二级','三级'};
            colors = [0 0.447 0.741; 1 0.85 0; 0.85 0.1 0.1];
            for i = 1:min(numel(levels), numel(labels))
                lv = levels(i);
                h = yline(lv, '--', labels{i}, 'Color', colors(i,:));
                h.LabelHorizontalAlignment = 'left';
                h.LabelVerticalAlignment = 'bottom';
            end

            outDir = fullfile(outRoot, style.output.speed10_dir);
            bms.core.PathResolver.ensureDir(outDir);
            bms.analyzer.WindPlotService.savePlot(fig, outDir, ...
                sprintf('%s_speed10min_%s_%s', pid, startDate, endDate), cfg);
        end

        function plotWindRose(dirDeg, speed, pid, params, style, outRoot, startDate, endDate, cfg, speedSource, directionSource)
            if nargin < 9
                cfg = struct();
            end
            if nargin < 10
                speedSource = struct();
            end
            if nargin < 11
                directionSource = struct();
            end
            if isempty(dirDeg)
                return;
            end
            [roseMat, sectorEdges, speedEdges, totalCount] = bms.analyzer.WindRoseService.buildMatrix(dirDeg, speed, params);
            if totalCount == 0
                return;
            end

            fig = figure('Position', [100 100 720 640]);
            ax = axes(fig);
            axis(ax, 'equal'); axis(ax, 'off'); hold(ax, 'on');
            titleHandle = title(ax, sprintf('%s %s [%s-%s]', style.rose.title_prefix, pid, startDate, endDate));

            colors = bms.analyzer.WindPlotService.roseColors(style, size(roseMat, 2));
            radialMax = max(sum(roseMat, 2));
            bms.analyzer.WindPlotService.drawWindRose(ax, roseMat, sectorEdges, colors);
            bms.analyzer.WindPlotService.drawPolarGrid(ax, radialMax);
            bms.analyzer.WindPlotService.drawDirectionLabels(ax, radialMax * 1.08);
            bms.analyzer.WindPlotService.formatWindRoseAxes(ax, radialMax, titleHandle);
            bms.analyzer.WindPlotService.attachAggregateProvenance( ...
                ax, numel(speed), nnz(isfinite(speed)), totalCount, ...
                [char(string(pid)) ':wind_speed'], speedSource);
            bms.analyzer.WindPlotService.attachAggregateProvenance( ...
                ax, numel(dirDeg), nnz(isfinite(dirDeg)), totalCount, ...
                [char(string(pid)) ':wind_direction'], directionSource);

            speedLabels = bms.analyzer.WindRoseService.speedBinLabels(speedEdges);
            legendHandles = gobjects(numel(speedLabels), 1);
            for k = 1:numel(speedLabels)
                legendHandles(k) = patch(ax, NaN, NaN, colors(k,:), 'EdgeColor', 'none');
            end
            legend(ax, legendHandles, speedLabels, 'Location', 'eastoutside');

            outDir = fullfile(outRoot, style.output.rose_dir);
            bms.core.PathResolver.ensureDir(outDir);
            baseName = sprintf('%s_windrose_%s_%s', pid, startDate, endDate);
            bms.analyzer.WindPlotService.savePlot(fig, outDir, baseName, cfg);

            bms.analyzer.WindRoseService.writeSummary( ...
                outDir, baseName, pid, dirDeg, speed, sectorEdges, speedEdges, roseMat, totalCount);
        end

        function colors = roseColors(style, nbin)
            if nbin <= 0
                colors = zeros(0, 3);
                return;
            end
            colors = [];
            if isfield(style, 'rose') && isstruct(style.rose) && isfield(style.rose, 'colors')
                colors = style.rose.colors;
            end
            colors = bms.plot.PlotService.normalizeColors(colors, parula(max(nbin, 3)));
            if size(colors, 1) < nbin
                colors = repmat(colors(end,:), nbin, 1);
            end
            colors = colors(1:nbin, :);
        end

        function drawWindRose(ax, mat, sectorEdges, colors)
            if isempty(mat)
                return;
            end
            nSec = size(mat, 1);
            nBin = size(mat, 2);
            angEdges = deg2rad(sectorEdges);
            for si = 1:nSec
                theta1 = angEdges(si);
                theta2 = angEdges(si + 1);
                r0 = 0;
                for bi = 1:nBin
                    r1 = r0 + mat(si, bi);
                    if r1 > r0
                        bms.analyzer.WindPlotService.drawAnnularSector( ...
                            ax, theta1, theta2, r0, r1, colors(bi, :));
                    end
                    r0 = r1;
                end
            end
        end

        function drawAnnularSector(ax, theta1, theta2, r0, r1, color)
            n = 30;
            t = linspace(theta1, theta2, n);
            [x1, y1] = pol2cart(t, r1 * ones(1, n));
            [x0, y0] = pol2cart(fliplr(t), r0 * ones(1, n));
            x = [x1 x0];
            y = [y1 y0];
            patch(ax, x, y, color, 'EdgeColor', 'none', 'FaceAlpha', 0.9);
        end

        function drawPolarGrid(ax, rmax)
            if rmax <= 0
                rmax = 1;
            end
            steps = 4;
            for i = 1:steps
                r = rmax * i / steps;
                t = linspace(0, 2*pi, 120);
                [x, y] = pol2cart(t, r * ones(size(t)));
                plot(ax, x, y, 'Color', [0.8 0.8 0.8], 'LineStyle', ':');
                labelAngle = deg2rad(22.5);
                text(ax, r * cos(labelAngle), r * sin(labelAngle), ...
                    sprintf('%.0f%%', r * 100), 'FontSize', 9, ...
                    'Color', [0.4 0.4 0.4], ...
                    'BackgroundColor', 'w', 'Margin', 1, ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
            end
            for ang = 0:45:315
                t = deg2rad(ang);
                [x, y] = pol2cart([t t], [0 rmax]);
                plot(ax, x, y, 'Color', [0.85 0.85 0.85]);
            end
        end

        function drawDirectionLabels(ax, r)
            labels = {'N','NE','E','SE','S','SW','W','NW'};
            bearings = 0:45:315;
            for i = 1:numel(bearings)
                % Meteorological bearings start at north and increase
                % clockwise; pol2cart starts at east counter-clockwise.
                t = deg2rad(90 - bearings(i));
                [x, y] = pol2cart(t, r);
                text(ax, x, y, labels{i}, 'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'middle', 'FontWeight', 'bold');
            end
        end

        function formatWindRoseAxes(ax, radialMax, titleHandle)
            if ~isfinite(radialMax) || radialMax <= 0
                radialMax = 1;
            end
            xlim(ax, [-1.2 1.2] * radialMax);
            ylim(ax, [-1.2 1.2] * radialMax);
            if nargin >= 3 && isgraphics(titleHandle)
                titleHandle.Units = 'normalized';
                titleHandle.Position(1:2) = [0.5 1.08];
            end
        end

        function savePlot(fig, outDir, baseName, cfg)
            if nargin < 4
                cfg = struct();
            end
            bms.plot.PlotService.saveModuleBundleWithTimestamp(fig, outDir, baseName, cfg);
        end

        function attachAggregateProvenance(ax, inputCount, finiteCount, plottedCount, pointId, sourceProvenance)
            h = plot(ax, NaN, NaN, 'Visible', 'off');
            provenance = struct( ...
                'schema_version', 1, ...
                'sampling_mode', 'full', ...
                'render_mode', 'wind_rose_aggregate', ...
                'input_count', double(inputCount), ...
                'finite_count', double(finiteCount), ...
                'plotted_finite_count', double(plottedCount), ...
                'reduction_applied', false, ...
                'point_id', char(string(pointId)));
            if isstruct(sourceProvenance) && ~isempty(fieldnames(sourceProvenance))
                provenance.source = sourceProvenance;
            end
            set(h, 'UserData', struct('plot_provenance', provenance));
        end

        function style = style(cfg)
            style = struct();
            style.output = struct( ...
                'root_dir', '风速风向结果', ...
                'speed_dir', '风速时程', ...
                'direction_dir', '风向时程', ...
                'speed10_dir', '风速10min', ...
                'rose_dir', '风玫瑰', ...
                'stats_file', 'wind_stats.xlsx');
            style.speed = struct('ylabel', '风速 (m/s)', 'title_prefix', '风速时程', ...
                'ylim', [], 'color', [0 0.447 0.741]);
            style.direction = struct('ylabel', '风向 (°)', 'title_prefix', '风向时程', ...
                'ylim', [0 360], 'color', [0.15 0.5 0.15]);
            style.speed10 = struct('ylabel', '10 min 均值风速 (m/s)', 'title_prefix', '风速10min均值', ...
                'ylim', [], 'color', [0.8500 0.3250 0.0980], ...
                'alarm_color', [0.8 0.1 0.1]);
            style.rose = struct('title_prefix', '风玫瑰', 'color', [0.2 0.4 0.8], 'colors', []);

            if isfield(cfg, 'plot_styles') && isfield(cfg.plot_styles, 'wind')
                ps = cfg.plot_styles.wind;
                if isfield(ps, 'output') && isstruct(ps.output)
                    style.output = bms.config.ConfigReader.mergeStruct(style.output, ps.output);
                end
                if isfield(ps, 'speed') && isstruct(ps.speed)
                    style.speed = bms.config.ConfigReader.mergeStruct(style.speed, ps.speed);
                end
                if isfield(ps, 'direction') && isstruct(ps.direction)
                    style.direction = bms.config.ConfigReader.mergeStruct(style.direction, ps.direction);
                end
                if isfield(ps, 'speed10') && isstruct(ps.speed10)
                    style.speed10 = bms.config.ConfigReader.mergeStruct(style.speed10, ps.speed10);
                end
                if isfield(ps, 'rose') && isstruct(ps.rose)
                    style.rose = bms.config.ConfigReader.mergeStruct(style.rose, ps.rose);
                end
            end
        end
    end
end
