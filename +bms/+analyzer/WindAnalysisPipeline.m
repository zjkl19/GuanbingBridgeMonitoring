classdef WindAnalysisPipeline
    %WINDANALYSISPIPELINE Shared wind speed/direction analysis workflow.

    methods (Static)
        function run(rootDir, startDate, endDate, subfolder, cfg)
            if nargin < 1 || isempty(rootDir), rootDir = pwd; end
            if nargin < 2 || isempty(startDate), startDate = input('开始日期 (yyyy-MM-dd): ', 's'); end
            if nargin < 3 || isempty(endDate), endDate = input('结束日期 (yyyy-MM-dd): ', 's'); end
            if nargin < 5 || isempty(cfg), cfg = load_config(); end
            if nargin < 4 || isempty(subfolder)
                subfolder = bms.analyzer.WindAnalysisPipeline.resolveSubfolder(cfg);
            end

            timeStart = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
            fprintf('开始时间: %s\n', char(timeStart));

            points = bms.analyzer.WindAnalysisPipeline.resolvePoints(cfg);
            style = bms.analyzer.WindAnalysisPipeline.style(cfg);
            stats = cell(numel(points), 6);
            statsFile = resolve_data_output_path(rootDir, ...
                bms.analyzer.WindAnalysisPipeline.statsFileName(cfg), 'stats');

            outRoot = fullfile(rootDir, style.output.root_dir);
            bms.core.PathResolver.ensureDir(outRoot);

            for i = 1:numel(points)
                pid = points{i};
                fprintf('处理测点 %s ...\n', pid);
                stats(i, :) = bms.analyzer.WindAnalysisPipeline.analyzePoint( ...
                    rootDir, subfolder, pid, startDate, endDate, cfg, style, outRoot);
            end

            T = bms.analyzer.DynamicSeriesService.windStatsTable(stats);
            bms.io.StatsWriter.writeModuleTableChecked(T, statsFile, 'wind');
            fprintf('Wind stats saved to %s\n', statsFile);

            timeEnd = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
            fprintf('结束时间: %s\n', char(timeEnd));
            elapsed = seconds(timeEnd - timeStart);
            fprintf('总用时: %.2f 秒\n', elapsed);
        end

        function subfolder = resolveSubfolder(cfg)
            if isfield(cfg, 'subfolders') && isfield(cfg.subfolders, 'wind_raw')
                subfolder = cfg.subfolders.wind_raw;
            else
                subfolder = '波形';
            end
        end

        function points = resolvePoints(cfg)
            points = bms.data.PointResolver.fromConfig(cfg, 'wind', {'W1', 'W2'});
        end

        function statsFile = statsFileName(cfg)
            statsFile = 'wind_stats.xlsx';
            if isfield(cfg, 'plot_styles') && isfield(cfg.plot_styles, 'wind') ...
                    && isstruct(cfg.plot_styles.wind) ...
                    && isfield(cfg.plot_styles.wind, 'output') ...
                    && isstruct(cfg.plot_styles.wind.output) ...
                    && isfield(cfg.plot_styles.wind.output, 'stats_file') ...
                    && ~isempty(cfg.plot_styles.wind.output.stats_file)
                statsFile = cfg.plot_styles.wind.output.stats_file;
            end
        end

        function row = analyzePoint(rootDir, subfolder, pid, startDate, endDate, cfg, style, outRoot)
            [tSpeed, vSpeed] = load_timeseries_range(rootDir, subfolder, pid, startDate, endDate, cfg, 'wind_speed');
            [tDir, vDir] = load_timeseries_range(rootDir, subfolder, pid, startDate, endDate, cfg, 'wind_direction');

            row = cell(1, 6);
            if isempty(vSpeed)
                warning('测点 %s 风速无数据，跳过', pid);
                return;
            end

            fs = bms.analyzer.DynamicSeriesService.sampleRate(tSpeed, true, 1);
            params = bms.analyzer.WindAnalysisPipeline.params(cfg, pid);

            [v10, v10Max, t10Max] = bms.analyzer.DynamicSeriesService.movingMeanSeries( ...
                tSpeed, vSpeed, fs, params.window_minutes, 0.7);

            speedStats = bms.analyzer.StructuralSeriesService.statsTriple(vSpeed, params.decimals);
            row = {pid, speedStats(1), speedStats(2), speedStats(3), v10Max, t10Max};

            bms.analyzer.WindAnalysisPipeline.plotSpeedTimeseries( ...
                tSpeed, vSpeed, pid, style, outRoot, startDate, endDate, cfg);
            bms.analyzer.WindAnalysisPipeline.plotDirectionTimeseries( ...
                tDir, vDir, pid, style, outRoot, startDate, endDate, cfg);
            bms.analyzer.WindAnalysisPipeline.plotSpeed10min( ...
                tSpeed, v10, pid, params, style, outRoot, startDate, endDate, cfg);

            if ~isempty(vDir)
                [roseSpeed, roseDir] = bms.analyzer.WindRoseService.alignForRose(tSpeed, vSpeed, tDir, vDir);
                bms.analyzer.WindAnalysisPipeline.plotWindRose( ...
                    roseDir, roseSpeed, pid, params, style, outRoot, startDate, endDate, cfg);
            end
        end

        function plotSpeedTimeseries(times, vals, pid, style, outRoot, startDate, endDate, cfg)
            if nargin < 8
                cfg = struct();
            end
            if isempty(vals)
                return;
            end
            fig = figure('Position', [100 100 1100 500]);
            [timesPlot, valsPlot] = prepare_plot_series(times, vals);
            plot(timesPlot, valsPlot, 'LineWidth', 1.1, 'Color', style.speed.color);
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
            bms.analyzer.WindAnalysisPipeline.savePlot(fig, outDir, ...
                sprintf('%s_speed_%s_%s', pid, startDate, endDate), cfg);
        end

        function plotDirectionTimeseries(times, vals, pid, style, outRoot, startDate, endDate, cfg)
            if nargin < 8
                cfg = struct();
            end
            if isempty(vals)
                return;
            end
            fig = figure('Position', [100 100 1100 500]);
            [timesPlot, valsPlot] = prepare_plot_series(times, vals);
            plot(timesPlot, valsPlot, 'LineWidth', 1.0, 'Color', style.direction.color);
            xlabel('时间');
            ylabel(style.direction.ylabel);
            title(sprintf('%s %s [%s-%s]', style.direction.title_prefix, pid, startDate, endDate));
            grid on; grid minor;
            ylim([0 360]);
            bms.plot.PlotService.setTimeAxis(times);

            outDir = fullfile(outRoot, style.output.direction_dir);
            bms.core.PathResolver.ensureDir(outDir);
            bms.analyzer.WindAnalysisPipeline.savePlot(fig, outDir, ...
                sprintf('%s_direction_%s_%s', pid, startDate, endDate), cfg);
        end

        function plotSpeed10min(times, v10, pid, params, style, outRoot, startDate, endDate, cfg)
            if nargin < 9
                cfg = struct();
            end
            if isempty(v10)
                return;
            end
            fig = figure('Position', [100 100 1100 500]);
            [timesPlot, v10Plot] = prepare_plot_series(times, v10);
            plot(timesPlot, v10Plot, 'LineWidth', 1.2, 'Color', style.speed10.color);
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
            bms.analyzer.WindAnalysisPipeline.savePlot(fig, outDir, ...
                sprintf('%s_speed10min_%s_%s', pid, startDate, endDate), cfg);
        end

        function plotWindRose(dirDeg, speed, pid, params, style, outRoot, startDate, endDate, cfg)
            if nargin < 9
                cfg = struct();
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
            title(ax, sprintf('%s %s [%s-%s]', style.rose.title_prefix, pid, startDate, endDate));

            colors = bms.analyzer.WindAnalysisPipeline.roseColors(style, size(roseMat, 2));
            bms.analyzer.WindAnalysisPipeline.drawWindRose(ax, roseMat, sectorEdges, colors);
            bms.analyzer.WindAnalysisPipeline.drawPolarGrid(ax, max(sum(roseMat, 2)));
            bms.analyzer.WindAnalysisPipeline.drawDirectionLabels(ax, max(sum(roseMat, 2)) * 1.08);

            speedLabels = bms.analyzer.WindRoseService.speedBinLabels(speedEdges);
            legendHandles = gobjects(numel(speedLabels), 1);
            for k = 1:numel(speedLabels)
                legendHandles(k) = patch(ax, NaN, NaN, colors(k,:), 'EdgeColor', 'none');
            end
            legend(ax, legendHandles, speedLabels, 'Location', 'eastoutside');

            outDir = fullfile(outRoot, style.output.rose_dir);
            bms.core.PathResolver.ensureDir(outDir);
            baseName = sprintf('%s_windrose_%s_%s', pid, startDate, endDate);
            bms.analyzer.WindAnalysisPipeline.savePlot(fig, outDir, baseName, cfg);

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
                        bms.analyzer.WindAnalysisPipeline.drawAnnularSector( ...
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
                text(ax, r, 0, sprintf('%.0f%%', r * 100), 'FontSize', 9, 'Color', [0.4 0.4 0.4]);
            end
            for ang = 0:45:315
                t = deg2rad(ang);
                [x, y] = pol2cart([t t], [0 rmax]);
                plot(ax, x, y, 'Color', [0.85 0.85 0.85]);
            end
        end

        function drawDirectionLabels(ax, r)
            labels = {'N','NE','E','SE','S','SW','W','NW'};
            angles = 0:45:315;
            for i = 1:numel(angles)
                t = deg2rad(angles(i));
                [x, y] = pol2cart(t, r);
                text(ax, x, y, labels{i}, 'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'middle', 'FontWeight', 'bold');
            end
        end

        function savePlot(fig, outDir, baseName, cfg)
            if nargin < 4
                cfg = struct();
            end
            bms.plot.PlotService.saveModuleBundleWithTimestamp(fig, outDir, baseName, cfg);
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
                    style.output = bms.analyzer.WindAnalysisPipeline.mergeStruct(style.output, ps.output);
                end
                if isfield(ps, 'speed') && isstruct(ps.speed)
                    style.speed = bms.analyzer.WindAnalysisPipeline.mergeStruct(style.speed, ps.speed);
                end
                if isfield(ps, 'direction') && isstruct(ps.direction)
                    style.direction = bms.analyzer.WindAnalysisPipeline.mergeStruct(style.direction, ps.direction);
                end
                if isfield(ps, 'speed10') && isstruct(ps.speed10)
                    style.speed10 = bms.analyzer.WindAnalysisPipeline.mergeStruct(style.speed10, ps.speed10);
                end
                if isfield(ps, 'rose') && isstruct(ps.rose)
                    style.rose = bms.analyzer.WindAnalysisPipeline.mergeStruct(style.rose, ps.rose);
                end
            end
        end

        function params = params(cfg, pid)
            params = struct();
            params.alarm_levels = [25, 29.92, 37.4];
            params.window_minutes = 10;
            params.decimals = 2;
            params.speed_bins = [0 2 4 6 8 10 15 20 25 30 35 40];
            params.sector_deg = 22.5;

            if isfield(cfg, 'wind_params') && isstruct(cfg.wind_params)
                params = bms.analyzer.WindAnalysisPipeline.mergeWindParams(params, cfg.wind_params);
            end

            if nargin < 2 || isempty(pid)
                return;
            end
            safeId = strrep(pid, '-', '_');
            if isfield(cfg, 'per_point') && isfield(cfg.per_point, 'wind') ...
                    && isfield(cfg.per_point.wind, safeId)
                params = bms.analyzer.WindAnalysisPipeline.mergeWindParams( ...
                    params, cfg.per_point.wind.(safeId));
            end
        end

        function params = mergeWindParams(params, override)
            if isfield(override, 'alarm_levels') && ~isempty(override.alarm_levels)
                params.alarm_levels = double(override.alarm_levels(:))';
            end
            if isfield(override, 'window_minutes') && ~isempty(override.window_minutes)
                params.window_minutes = double(override.window_minutes);
            end
            if isfield(override, 'decimals') && ~isempty(override.decimals)
                params.decimals = double(override.decimals);
            end
            if isfield(override, 'speed_bins') && ~isempty(override.speed_bins)
                params.speed_bins = double(override.speed_bins(:))';
            end
            if isfield(override, 'sector_deg') && ~isempty(override.sector_deg)
                params.sector_deg = double(override.sector_deg);
            end
        end

        function out = mergeStruct(base, override)
            out = base;
            fns = fieldnames(override);
            for i = 1:numel(fns)
                fn = fns{i};
                out.(fn) = override.(fn);
            end
        end
    end
end
