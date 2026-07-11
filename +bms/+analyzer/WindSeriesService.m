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
            params = bms.analyzer.WindSeriesService.params(cfg, pid);
            series = bms.analyzer.WindSeriesService.seriesStruct(pid, [], [], [], [], params);
            row = cell(1, 6);

            dateList = bms.data.TimeSeriesRangeLoader.buildDateList(startDate, endDate);
            perDayMax = bms.analyzer.DynamicSeriesService.rawPlotPerDayMax(cfg, numel(dateList), 50000);

            speedTimes = {};
            speedVals = {};
            dirTimes = {};
            dirVals = {};
            t10Parts = {};
            v10Parts = {};
            speedCount = 0;
            speedSum = 0;
            speedMin = Inf;
            speedMax = -Inf;
            v10Max = NaN;
            t10Max = NaT;
            speedProvenance = bms.analyzer.DynamicSeriesService.initSourceProvenance(numel(dateList));
            directionProvenance = bms.analyzer.DynamicSeriesService.initSourceProvenance(numel(dateList));

            for i = 1:numel(dateList)
                day = dateList{i};
                [tSpeedDay, vSpeedDay, speedMeta] = bms.data.TimeSeriesRangeLoader.loadCalendarDay( ...
                    rootDir, subfolder, pid, day, cfg, 'wind_speed');
                [tDirDay, vDirDay, directionMeta] = bms.data.TimeSeriesRangeLoader.loadCalendarDay( ...
                    rootDir, subfolder, pid, day, cfg, 'wind_direction');
                speedProvenance = bms.analyzer.DynamicSeriesService.accumulateSourceProvenance( ...
                    speedProvenance, day, speedMeta, tSpeedDay, vSpeedDay);
                directionProvenance = bms.analyzer.DynamicSeriesService.accumulateSourceProvenance( ...
                    directionProvenance, day, directionMeta, tDirDay, vDirDay);

                finiteSpeed = isfinite(vSpeedDay);
                if any(finiteSpeed)
                    vals = vSpeedDay(finiteSpeed);
                    speedCount = speedCount + numel(vals);
                    speedSum = speedSum + sum(vals);
                    speedMin = min(speedMin, min(vals));
                    speedMax = max(speedMax, max(vals));
                end

                if ~isempty(vSpeedDay)
                    fs = bms.analyzer.DynamicSeriesService.sampleRate(tSpeedDay, true, 1);
                    [t10Day, v10Day, dayMax, dayTMax] = bms.analyzer.DynamicSeriesService.movingMeanByTimeBins( ...
                        tSpeedDay, vSpeedDay, params.window_minutes, 0.7, fs);
                    if ~isempty(v10Day)
                        t10Parts{end+1, 1} = t10Day; %#ok<AGROW>
                        v10Parts{end+1, 1} = v10Day; %#ok<AGROW>
                    end
                    if isfinite(dayMax) && (~isfinite(v10Max) || dayMax > v10Max)
                        v10Max = dayMax;
                        t10Max = dayTMax;
                    end

                    [td, vd] = bms.analyzer.DynamicSeriesService.limitSeriesPoints(tSpeedDay, vSpeedDay, perDayMax);
                    if ~isempty(vd)
                        speedTimes{end+1, 1} = td; %#ok<AGROW>
                        speedVals{end+1, 1} = vd; %#ok<AGROW>
                    end
                end

                if ~isempty(vDirDay)
                    [td, vd] = bms.analyzer.DynamicSeriesService.limitSeriesPoints(tDirDay, vDirDay, perDayMax);
                    if ~isempty(vd)
                        dirTimes{end+1, 1} = td; %#ok<AGROW>
                        dirVals{end+1, 1} = vd; %#ok<AGROW>
                    end
                end
            end

            if speedCount <= 0
                warning('Wind point %s has no speed data; skipped.', pid);
                return;
            end

            [series.tSpeed, series.vSpeed] = bms.analyzer.WindSeriesService.concatSeries(speedTimes, speedVals);
            [series.tDir, series.vDir] = bms.analyzer.WindSeriesService.concatSeries(dirTimes, dirVals);
            [series.t10, series.v10] = bms.analyzer.WindSeriesService.concatSeries(t10Parts, v10Parts);
            series.speed_source_provenance = ...
                bms.analyzer.DynamicSeriesService.finalizeSourceProvenance(speedProvenance);
            series.direction_source_provenance = ...
                bms.analyzer.DynamicSeriesService.finalizeSourceProvenance(directionProvenance);
            bms.analyzer.WindSeriesService.warnIncompleteSource( ...
                pid, 'wind_speed', series.speed_source_provenance);
            bms.analyzer.WindSeriesService.warnIncompleteSource( ...
                pid, 'wind_direction', series.direction_source_provenance);

            row = {pid, round(speedMin, params.decimals), round(speedMax, params.decimals), ...
                round(speedSum / speedCount, params.decimals), v10Max, t10Max};
        end

        function series = seriesStruct(pid, tSpeed, vSpeed, tDir, vDir, params)
            series = struct( ...
                'pid', pid, ...
                'tSpeed', tSpeed, ...
                'vSpeed', vSpeed, ...
                'tDir', tDir, ...
                'vDir', vDir, ...
                't10', [], ...
                'v10', [], ...
                'speed_source_provenance', bms.analyzer.DynamicSeriesService.initSourceProvenance(0), ...
                'direction_source_provenance', bms.analyzer.DynamicSeriesService.initSourceProvenance(0), ...
                'params', params);
        end

        function warnIncompleteSource(pid, sensorType, provenance)
            if ~isstruct(provenance) || ~isfield(provenance, 'incomplete_day_count') ...
                    || provenance.incomplete_day_count <= 0
                return;
            end
            warning('WindSeriesService:IncompleteSourceCoverage', ...
                '%s %s has incomplete rolling-export source coverage on %d/%d calendar days: %s', ...
                char(string(sensorType)), char(string(pid)), ...
                provenance.incomplete_day_count, ...
                provenance.calendar_day_count_requested, ...
                strjoin(provenance.incomplete_days, ', '));
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

        function [times, vals] = concatSeries(timeParts, valueParts)
            times = [];
            vals = [];
            if isempty(valueParts)
                return;
            end
            times = vertcat(timeParts{:});
            vals = vertcat(valueParts{:});
            if isempty(vals)
                return;
            end
            [times, order] = sort(times);
            vals = vals(order);
        end
    end
end
