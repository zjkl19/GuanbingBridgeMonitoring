classdef WindSeriesService
    %WINDSERIESSERVICE Data loading and statistics for wind analysis.

    methods (Static)
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

        function [row, series] = analyzePoint(rootDir, subfolder, pid, startDate, endDate, cfg)
            [tSpeed, vSpeed] = load_timeseries_range(rootDir, subfolder, pid, startDate, endDate, cfg, 'wind_speed');
            [tDir, vDir] = load_timeseries_range(rootDir, subfolder, pid, startDate, endDate, cfg, 'wind_direction');

            params = bms.analyzer.WindSeriesService.params(cfg, pid);
            series = bms.analyzer.WindSeriesService.seriesStruct(pid, tSpeed, vSpeed, tDir, vDir, params);
            row = cell(1, 6);
            if isempty(vSpeed)
                warning('测点 %s 风速无数据，跳过', pid);
                return;
            end

            fs = bms.analyzer.DynamicSeriesService.sampleRate(tSpeed, true, 1);
            [series.v10, v10Max, t10Max] = bms.analyzer.DynamicSeriesService.movingMeanSeries( ...
                tSpeed, vSpeed, fs, params.window_minutes, 0.7);

            speedStats = bms.analyzer.StructuralSeriesService.statsTriple(vSpeed, params.decimals);
            row = {pid, speedStats(1), speedStats(2), speedStats(3), v10Max, t10Max};
        end

        function series = seriesStruct(pid, tSpeed, vSpeed, tDir, vDir, params)
            series = struct( ...
                'pid', pid, ...
                'tSpeed', tSpeed, ...
                'vSpeed', vSpeed, ...
                'tDir', tDir, ...
                'vDir', vDir, ...
                'v10', [], ...
                'params', params);
        end

        function params = params(cfg, pid)
            params = struct();
            params.alarm_levels = [25, 29.92, 37.4];
            params.window_minutes = 10;
            params.decimals = 2;
            params.speed_bins = [0 2 4 6 8 10 15 20 25 30 35 40];
            params.sector_deg = 22.5;

            if isfield(cfg, 'wind_params') && isstruct(cfg.wind_params)
                params = bms.analyzer.WindSeriesService.mergeWindParams(params, cfg.wind_params);
            end

            if nargin < 2 || isempty(pid)
                return;
            end
            if isfield(cfg, 'per_point') && isfield(cfg.per_point, 'wind') ...
                    && isstruct(cfg.per_point.wind)
                [ok, pointCfg] = bms.data.PointResolver.getPointConfig(cfg.per_point.wind, pid, cfg);
                if ok
                    params = bms.analyzer.WindSeriesService.mergeWindParams(params, pointCfg);
                end
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
    end
end
