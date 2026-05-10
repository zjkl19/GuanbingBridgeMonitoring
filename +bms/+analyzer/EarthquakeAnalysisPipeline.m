classdef EarthquakeAnalysisPipeline
    %EARTHQUAKEANALYSISPIPELINE Earthquake motion time-series workflow.

    methods (Static)
        function run(rootDir, startDate, endDate, subfolder, cfg)
            if nargin < 1 || isempty(rootDir), rootDir = pwd; end
            if nargin < 2 || isempty(startDate), startDate = input('开始日期 (yyyy-MM-dd): ', 's'); end
            if nargin < 3 || isempty(endDate), endDate = input('结束日期 (yyyy-MM-dd): ', 's'); end
            if nargin < 5 || isempty(cfg), cfg = load_config(); end
            if nargin < 4 || isempty(subfolder)
                subfolder = bms.analyzer.EarthquakeAnalysisPipeline.resolveSubfolder(cfg);
            end

            rootDir = char(string(rootDir));
            startDate = char(string(startDate));
            endDate = char(string(endDate));
            subfolder = char(string(subfolder));

            timeStart = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
            fprintf('开始时间: %s\n', char(timeStart));

            points = bms.analyzer.EarthquakeAnalysisPipeline.resolvePoints(cfg);
            style = bms.analyzer.EarthquakeAnalysisPipeline.style(cfg);
            outRoot = fullfile(rootDir, style.output.root_dir);
            bms.core.PathResolver.ensureDir(outRoot);

            parallelPlan = bms.analyzer.EarthquakeAnalysisPipeline.parallelPlan(cfg, numel(points));
            records = bms.analyzer.EarthquakeAnalysisPipeline.collectRecords( ...
                rootDir, subfolder, startDate, endDate, cfg, points, parallelPlan);

            bms.analyzer.EarthquakeAnalysisPipeline.plotRecords( ...
                records, style, outRoot, startDate, endDate, cfg, parallelPlan);

            timeEnd = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
            fprintf('结束时间: %s\n', char(timeEnd));
            fprintf('总用时: %.2f sec\n', seconds(timeEnd - timeStart));
        end

        function subfolder = resolveSubfolder(cfg)
            subfolder = bms.config.ConfigReader.getSubfolder(cfg, 'eq_raw', '波形');
        end

        function points = resolvePoints(cfg)
            points = bms.data.PointResolver.fromConfig(cfg, 'eq', {'EQ-X', 'EQ-Y', 'EQ-Z'});
        end

        function style = style(cfg)
            style = struct();
            style.output = struct( ...
                'root_dir', '地震动结果', ...
                'series_dir', '地震动时程', ...
                'prefix', 'EQ');
            style.ylabel = '地震动加速度 (m/s^2)';
            style.title_prefix = '地震动时程';
            style.ylim_auto = false;
            style.ylim = [];
            style.ylims = [];
            style.main_color = [0 0.447 0.741];

            ps = bms.config.ConfigReader.getStruct(cfg, 'plot_styles.eq', struct());
            if isempty(fieldnames(ps))
                return;
            end
            ps = ps(1);

            if isfield(ps, 'output') && isstruct(ps.output)
                style.output = bms.config.ConfigReader.mergeStruct(style.output, ps.output);
            end
            if isfield(ps, 'ylabel'), style.ylabel = ps.ylabel; end
            if isfield(ps, 'title_prefix'), style.title_prefix = ps.title_prefix; end
            if isfield(ps, 'ylim_auto'), style.ylim_auto = ps.ylim_auto; end
            if isfield(ps, 'ylim'), style.ylim = ps.ylim; end
            if isfield(ps, 'ylims'), style.ylims = ps.ylims; end
            if isfield(ps, 'color'), style.main_color = ps.color; end
        end

        function params = params(cfg, pointId)
            params = struct('alarm_levels', [1, 2]);
            ep = bms.config.ConfigReader.getStruct(cfg, 'eq_params', struct());
            if isfield(ep, 'alarm_levels') && ~isempty(ep.alarm_levels)
                params.alarm_levels = double(ep.alarm_levels(:))';
            end

            if nargin < 2 || isempty(pointId)
                return;
            end
            safeId = strrep(char(string(pointId)), '-', '_');
            [ok, perPoint] = bms.config.ConfigPatch.getPath(cfg, ['per_point.eq.' safeId]);
            if ok && isstruct(perPoint) && isfield(perPoint, 'alarm_levels') && ~isempty(perPoint.alarm_levels)
                params.alarm_levels = double(perPoint.alarm_levels(:))';
            end
        end

        function plan = parallelPlan(cfg, pointCount)
            plan = get_parallel_plan(cfg, pointCount, 'eq');
        end

        function records = collectRecords(rootDir, subfolder, startDate, endDate, cfg, points, parallelPlan)
            records = repmat(bms.analyzer.EarthquakeSeriesService.initRecord(), numel(points), 1);
            if parallelPlan.enabled
                fprintf('地震动分析使用并行数据收集 (%d workers)\n', parallelPlan.worker_count);
                parfor i = 1:numel(points)
                    records(i) = bms.analyzer.EarthquakeAnalysisPipeline.collectRecord( ...
                        rootDir, subfolder, points{i}, startDate, endDate, cfg);
                end
            else
                for i = 1:numel(points)
                    records(i) = bms.analyzer.EarthquakeAnalysisPipeline.collectRecord( ...
                        rootDir, subfolder, points{i}, startDate, endDate, cfg);
                end
            end
        end

        function rec = collectRecord(rootDir, subfolder, pointId, startDate, endDate, cfg)
            rec = bms.analyzer.EarthquakeSeriesService.collectRecord( ...
                rootDir, subfolder, pointId, startDate, endDate, cfg, ...
                bms.analyzer.EarthquakeAnalysisPipeline.params(cfg, pointId));
        end

        function plotRecords(records, style, outRoot, startDate, endDate, cfg, parallelPlan)
            for i = 1:numel(records)
                rec = records(i);
                fprintf('处理测点 %s ...\n', rec.pid);
                if ~rec.has_data
                    warning('测点 %s 无数据，跳过', rec.pid);
                    continue;
                end
                if parallelPlan.enabled
                    record_parallel_offset_correction(cfg, rec.sensor_type, rec.pid, rec.times, rec.vals);
                end
                bms.analyzer.EarthquakeAnalysisPipeline.plotTimeseries( ...
                    rec.times, rec.vals, rec.pid, rec.comp, rec.params, style, outRoot, startDate, endDate, cfg);
            end
        end

        function plotTimeseries(times, vals, pointId, component, params, style, outRoot, startDate, endDate, cfg)
            if nargin < 10
                cfg = struct();
            end

            fig = figure('Position', [100 100 1100 500]);
            [timesPlot, valsPlot] = bms.plot.PlotService.prepareSeries(times, vals);
            plot(timesPlot, valsPlot, 'LineWidth', 1.1, 'Color', style.main_color);
            xlabel('时间');
            ylabel(style.ylabel);
            title(sprintf('%s %s [%s-%s]', style.title_prefix, pointId, startDate, endDate));
            grid on;
            grid minor;
            hold on;

            bms.analyzer.EarthquakeAnalysisPipeline.applyYLim(style, pointId);
            bms.plot.PlotService.setTimeAxis(times);
            bms.analyzer.EarthquakeAnalysisPipeline.drawAlarmLines(params);
            bms.analyzer.EarthquakeAnalysisPipeline.drawMaxMarker(times, vals);

            outDir = fullfile(outRoot, style.output.series_dir);
            bms.core.PathResolver.ensureDir(outDir);
            baseName = sprintf('%s_%s_%s_%s', style.output.prefix, component, startDate, endDate);
            bms.plot.PlotService.saveModuleBundleWithTimestamp(fig, outDir, baseName, cfg);
        end

        function applyYLim(style, pointId)
            if bms.config.ConfigReader.boolValue(style.ylim_auto, false)
                ylim auto;
                return;
            end

            yl = bms.plot.PlotService.resolveNamedYLim(style.ylims, pointId, style.ylim);
            if bms.plot.PlotService.isValidYLim(yl)
                ylim(yl);
            elseif ~isempty(style.ylim)
                ylim(style.ylim);
            end
        end

        function drawAlarmLines(params)
            levels = bms.analyzer.EarthquakeAnalysisPipeline.alarmLevels(params);
            labels = {'E1地震作用加速度峰值', 'E2地震作用加速度峰值'};
            colors = [1 0.85 0; 0.85 0.1 0.1];
            for i = 1:min(numel(levels), numel(labels))
                lv = levels(i);
                if ~isfinite(lv)
                    continue;
                end
                h = yline(lv, '--', sprintf('%s %.2f', labels{i}, lv), 'Color', colors(i, :));
                h.LabelHorizontalAlignment = 'left';
                h.LabelVerticalAlignment = 'bottom';
            end
        end

        function levels = alarmLevels(params)
            levels = [];
            if isstruct(params) && isfield(params, 'alarm_levels') && ~isempty(params.alarm_levels)
                levels = double(params.alarm_levels(:))';
            end
            levels = sort(levels(~isnan(levels)));
        end

        function drawMaxMarker(times, vals)
            [vmax, idx] = max(vals, [], 'omitnan');
            if isempty(idx) || ~isfinite(vmax) || idx < 1 || idx > numel(times)
                return;
            end
            tmax = times(idx);
            plot(tmax, vmax, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 6);
            text(tmax, vmax, sprintf('最大值 %.3f', vmax), ...
                'VerticalAlignment', 'bottom', ...
                'HorizontalAlignment', 'left', ...
                'Color', [0.6 0 0]);
        end
    end
end
