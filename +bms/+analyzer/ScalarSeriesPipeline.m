classdef ScalarSeriesPipeline
    %SCALARSERIESPIPELINE Shared workflow for scalar environment analyzers.

    methods (Static)
        function run(kind, rootDir, pointIds, startDate, endDate, excelFile, subfolder, cfg)
            spec = bms.analyzer.ScalarSeriesPipeline.spec(kind);
            if nargin < 2, rootDir = []; end
            if nargin < 3, pointIds = []; end
            if nargin < 4, startDate = []; end
            if nargin < 5, endDate = []; end
            if nargin < 6, excelFile = []; end
            if nargin < 7, subfolder = []; end
            if nargin < 8, cfg = []; end

            args = bms.analyzer.ScalarSeriesService.resolveInputs( ...
                rootDir, pointIds, startDate, endDate, excelFile, subfolder, cfg, ...
                spec.moduleKey, spec.defaultExcelFile, spec.defaultSubfolder);

            switch spec.moduleKey
                case {'temperature', 'humidity'}
                    bms.analyzer.ScalarSeriesPipeline.runBasic(args, spec);
                case 'rainfall'
                    bms.analyzer.ScalarSeriesPipeline.runRainfall(args, spec);
                otherwise
                    error('ScalarSeriesPipeline:UnsupportedKind', ...
                        'Unsupported scalar pipeline kind: %s', spec.moduleKey);
            end
        end

        function runBasic(args, spec)
            stats = cell(0, 4);
            range = bms.analyzer.ScalarSeriesService.dateRange(args.start_date, args.end_date);
            timestamp = bms.analyzer.ScalarSeriesPipeline.compactTimestamp();
            outDir = fullfile(args.root_dir, spec.outputDir);
            bms.core.PathResolver.ensureDir(outDir);

            for i = 1:numel(args.point_ids)
                bms.app.StopController.throwIfRequested('Stop requested before next scalar point');
                pid = args.point_ids{i};
                fprintf('%s %s...\n', spec.progressPrefix, pid);
                [times, values] = load_timeseries_range( ...
                    args.root_dir, args.subfolder, pid, args.start_date, args.end_date, ...
                    args.cfg, spec.moduleKey);
                if isempty(values)
                    warning('测点 %s 无数据，跳过', pid);
                    continue;
                end

                validValues = bms.analyzer.ScalarSeriesService.finiteValues(values);
                if spec.skipAllNan && isempty(validValues)
                    warning('Point %s contains only NaN values, skipping', pid);
                    continue;
                end

                bms.analyzer.ScalarSeriesPipeline.plotBasicSeries( ...
                    times, values, validValues, pid, range, outDir, timestamp, args.style, args.cfg, spec);
                stats(end + 1, :) = bms.analyzer.ScalarSeriesService.basicStatsRow( ... %#ok<AGROW>
                    pid, validValues, spec.decimals);

                if spec.frequencyEnabled
                    bms.analyzer.ScalarSeriesPipeline.plotHumidityFrequency( ...
                        validValues, pid, args.root_dir, range, args.cfg);
                end
            end

            T = bms.analyzer.ScalarSeriesService.basicStatsTable(stats);
            bms.io.StatsWriter.writeModuleTableChecked(T, args.excel_file, spec.moduleKey);
            fprintf('统计结果已保存至 %s\n', args.excel_file);
        end

        function runRainfall(args, spec)
            stats = cell(numel(args.point_ids), 7);
            range = bms.analyzer.ScalarSeriesService.dateRange(args.start_date, args.end_date);
            timestamp = bms.analyzer.ScalarSeriesPipeline.compactTimestamp();
            outDir = fullfile(args.root_dir, ...
                bms.analyzer.ScalarSeriesService.styleField(args.style, 'output_dir', spec.outputDir));
            bms.core.PathResolver.ensureDir(outDir);

            for i = 1:numel(args.point_ids)
                bms.app.StopController.throwIfRequested('Stop requested before next rainfall point');
                pid = args.point_ids{i};
                fprintf('Processing rainfall %s...\n', pid);
                [times, values] = load_timeseries_range( ...
                    args.root_dir, args.subfolder, pid, args.start_date, args.end_date, ...
                    args.cfg, spec.moduleKey);
                if isempty(values) || isempty(times)
                    warning('雨量测点 %s 无有效数据，跳过', pid);
                    stats{i, 1} = pid;
                    continue;
                end

                valid = isfinite(values) & ~isnat(times);
                if ~any(valid)
                    warning('雨量测点 %s 无有效数据，跳过', pid);
                    stats{i, 1} = pid;
                    continue;
                end

                validTimes = times(valid);
                validValues = values(valid);
                totalMm = bms.analyzer.ScalarSeriesService.rainfallTotalMm(validTimes, validValues);
                maxVal = max(validValues);
                meanVal = mean(validValues);

                bms.analyzer.ScalarSeriesPipeline.plotRainfallSeries( ...
                    times, values, meanVal, pid, range, outDir, timestamp, args.style, args.cfg);

                stats{i, 1} = pid;
                stats{i, 2} = bms.analyzer.ScalarSeriesPipeline.formatTime(min(validTimes));
                stats{i, 3} = bms.analyzer.ScalarSeriesPipeline.formatTime(max(validTimes));
                stats{i, 4} = sum(valid);
                stats{i, 5} = maxVal;
                stats{i, 6} = meanVal;
                stats{i, 7} = totalMm;
            end

            T = bms.analyzer.ScalarSeriesService.rainfallStatsTable(stats);
            bms.io.StatsWriter.writeModuleTableChecked(T, args.excel_file, spec.moduleKey);
            fprintf('雨量统计结果已保存至 %s\n', args.excel_file);
        end

        function plotBasicSeries(times, values, validValues, pointId, range, outDir, timestamp, style, cfg, spec)
            fig = figure('Position', [100 100 1000 469]);
            hold on;
            plotOpts = bms.plot.PlotService.runtimeOptionsFromConfig( ...
                cfg, spec.moduleKey, pointId);
            [timesPlot, valuesPlot] = prepare_plot_series(times, values, plotOpts);
            plot(timesPlot, valuesPlot, 'LineWidth', 1, ...
                'Color', bms.analyzer.ScalarSeriesService.color(style, 1));

            if ~isempty(validValues)
                avgVal = round(mean(validValues), spec.decimals);
                yline(avgVal, '--r', sprintf(spec.averageLabel, avgVal), ...
                    'LabelHorizontalAlignment', 'center', ...
                    'LabelVerticalAlignment', 'bottom');
            end

            bms.analyzer.ScalarSeriesPipeline.applyDateAxis(range);
            xlabel('时间');
            ylabel(bms.analyzer.ScalarSeriesService.styleField(style, 'ylabel', spec.defaultYLabel));
            bms.analyzer.ScalarSeriesService.applyYLim(style, pointId, false);
            grid on; grid minor;
            title(sprintf('%s %s', ...
                bms.analyzer.ScalarSeriesService.styleField(style, 'title_prefix', spec.defaultTitlePrefix), ...
                pointId));

            base = sprintf('%s_%s_%s', pointId, datestr(range.dn0, 'yyyymmdd'), datestr(range.dn1, 'yyyymmdd'));
            bms.plot.PlotService.saveModuleBundle(fig, outDir, [base '_' timestamp], cfg);
        end

        function plotHumidityFrequency(values, pointId, rootDir, range, cfg)
            bins = 20:10:100;
            counts = histcounts(values, bins);
            total = sum(counts);
            percent = counts / total * 100;

            fig = figure('Position', [100 100 1000 469]);
            bar(percent, 'FaceColor', 'flat');
            xticks(1:length(counts));
            xticklabels({'20-30','30-40','40-50','50-60','60-70','70-80','80-90','90-100'});
            ylabel('环境湿度累计持续时间频次分布 (%)');
            xlabel('环境湿度范围 (%)');
            title(sprintf('测点 %s 湿度频次分布', pointId));
            grid on; grid minor;
            for k = 1:length(percent)
                text(k, percent(k) + 1, sprintf('%.2f%%', percent(k)), ...
                    'HorizontalAlignment', 'center');
            end

            outDir = fullfile(rootDir, '频次分布_湿度');
            bms.core.PathResolver.ensureDir(outDir);
            timestamp = bms.analyzer.ScalarSeriesPipeline.dateTimeTimestamp();
            base = sprintf('%s_freq_%s_%s', pointId, datestr(range.dn0, 'yyyymmdd'), datestr(range.dn1, 'yyyymmdd'));
            bms.plot.PlotService.saveModuleBundle(fig, outDir, [base '_' timestamp], cfg);
        end

        function plotRainfallSeries(times, values, meanValue, pointId, range, outDir, timestamp, style, cfg)
            fig = figure('Position', [100 100 1000 469]);
            hold on;
            plotOpts = bms.plot.PlotService.runtimeOptionsFromConfig( ...
                cfg, 'rainfall', pointId);
            [timesPlot, valuesPlot] = prepare_plot_series(times, values, plotOpts);
            plot(timesPlot, valuesPlot, 'LineWidth', 1, ...
                'Color', bms.analyzer.ScalarSeriesService.color(style, 1));
            avgVal = round(meanValue, 2);
            yline(avgVal, '--r', sprintf('平均降雨强度 %.2f mm/h', avgVal), ...
                'LabelHorizontalAlignment', 'center', ...
                'LabelVerticalAlignment', 'bottom');

            bms.analyzer.ScalarSeriesPipeline.applyDateAxis(range);
            xlabel('时间');
            ylabel(bms.analyzer.ScalarSeriesService.styleField(style, 'ylabel', '降雨强度 (mm/h)'));
            bms.analyzer.ScalarSeriesService.applyYLimAutoFirst(style, pointId, true);
            grid on; grid minor;
            title(sprintf('%s %s', ...
                bms.analyzer.ScalarSeriesService.styleField(style, 'title_prefix', '降雨强度时程'), ...
                pointId));

            base = sprintf('Rainfall_%s_%s_%s', pointId, datestr(range.dn0, 'yyyymmdd'), datestr(range.dn1, 'yyyymmdd'));
            bms.plot.PlotService.saveModuleBundle(fig, outDir, [base '_' timestamp], cfg);
        end

        function applyDateAxis(range)
            ticks = bms.analyzer.ScalarSeriesService.dateTicks(range, 5);
            ax = gca;
            ax.XLim = [ticks(1) ticks(end)];
            ax.XTick = ticks;
            xtickformat('yyyy-MM-dd');
        end

        function subfolder = resolveSubfolder(cfg, kind)
            spec = bms.analyzer.ScalarSeriesPipeline.spec(kind);
            subfolder = bms.analyzer.ScalarSeriesService.subfolderFromConfig( ...
                cfg, spec.moduleKey, spec.defaultSubfolder);
        end

        function spec = spec(kind)
            key = lower(char(string(kind)));
            switch key
                case 'temperature'
                    spec = struct( ...
                        'moduleKey', 'temperature', ...
                        'defaultExcelFile', 'temperature_stats.xlsx', ...
                        'defaultSubfolder', '特征值', ...
                        'outputDir', '时程曲线_温度', ...
                        'progressPrefix', 'Processing', ...
                        'defaultYLabel', '温度 (°C)', ...
                        'defaultTitlePrefix', '温度时程', ...
                        'averageLabel', '平均值 %.1f', ...
                        'decimals', 1, ...
                        'skipAllNan', false, ...
                        'frequencyEnabled', false);
                case 'humidity'
                    spec = struct( ...
                        'moduleKey', 'humidity', ...
                        'defaultExcelFile', 'humidity_stats.xlsx', ...
                        'defaultSubfolder', '特征值', ...
                        'outputDir', '时程曲线_湿度', ...
                        'progressPrefix', '处理测点', ...
                        'defaultYLabel', '湿度 (%)', ...
                        'defaultTitlePrefix', '湿度时程', ...
                        'averageLabel', '平均值 %.1f%%', ...
                        'decimals', 1, ...
                        'skipAllNan', true, ...
                        'frequencyEnabled', true);
                case 'rainfall'
                    spec = struct( ...
                        'moduleKey', 'rainfall', ...
                        'defaultExcelFile', 'rainfall_stats.xlsx', ...
                        'defaultSubfolder', '特征值', ...
                        'outputDir', '时程曲线_雨量');
                otherwise
                    error('ScalarSeriesPipeline:UnsupportedKind', ...
                        'Unsupported scalar pipeline kind: %s', key);
            end
        end

        function s = formatTime(t)
            if isempty(t) || isnat(t)
                s = '';
            else
                s = datestr(t, 'yyyy-mm-dd HH:MM:SS');
            end
        end

        function timestamp = compactTimestamp()
            timestamp = datestr(now, 'yyyymmdd_HHMMSS');
        end

        function timestamp = dateTimeTimestamp()
            timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss'));
        end
    end
end
