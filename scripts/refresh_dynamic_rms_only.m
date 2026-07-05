function result = refresh_dynamic_rms_only(rootDir, startDate, endDate, cfgOrPath, kinds)
%REFRESH_DYNAMIC_RMS_ONLY Refresh RMS10min artifacts for dynamic modules only.
%   This is intended for report repair after RMS plot logic changes. It
%   recomputes per-point RMS series from the raw time-series data, refreshes
%   RMS plots/group plots, and rewrites the corresponding stats workbook.

    if nargin < 5 || isempty(kinds)
        kinds = {'acceleration', 'cable_accel'};
    end
    if ischar(kinds) || isstring(kinds)
        kinds = cellstr(string(kinds));
    end

    rootDir = char(string(rootDir));
    startDate = char(string(startDate));
    endDate = char(string(endDate));
    cfg = localConfig(cfgOrPath);

    result = struct();
    result.root = rootDir;
    result.start_date = startDate;
    result.end_date = endDate;
    result.modules = struct();

    for k = 1:numel(kinds)
        kind = char(string(kinds{k}));
        fprintf('Refreshing RMS artifacts for %s\n', kind);
        moduleResult = refreshOneKind(rootDir, startDate, endDate, cfg, kind);
        safeKind = matlab.lang.makeValidName(kind);
        result.modules.(safeKind) = moduleResult;
    end
end

function cfg = localConfig(cfgOrPath)
    if nargin < 1 || isempty(cfgOrPath)
        cfg = load_config();
    elseif isstruct(cfgOrPath)
        cfg = cfgOrPath;
    else
        cfg = load_config(char(string(cfgOrPath)));
    end
end

function moduleResult = refreshOneKind(rootDir, startDate, endDate, cfg, kind)
    spec = bms.analyzer.DynamicAccelerationPipeline.spec(kind);
    subfolder = bms.config.ConfigReader.getSubfolder(cfg, spec.subfolderKey, spec.defaultSubfolder);
    points = bms.analyzer.DynamicAccelerationPipeline.resolvePoints(cfg, spec);
    style = bms.analyzer.DynamicAccelerationPipeline.plotStyle(cfg, spec);

    records = repmat(bms.analyzer.DynamicSeriesService.initRecord(), numel(points), 1);
    stats = cell(numel(points), 6);
    refreshed = 0;
    skipped = {};

    for i = 1:numel(points)
        pid = char(string(points{i}));
        fprintf('RMS refresh %s point %s (%d/%d)\n', kind, pid, i, numel(points));
        rec = collectRecordExplicitDays(rootDir, subfolder, pid, startDate, endDate, cfg, spec);
        if ~rec.has_data || isempty(rec.rms_vals)
            warning('refresh_dynamic_rms_only:NoRmsData', ...
                'No RMS data for %s point %s', kind, pid);
            skipped{end+1, 1} = pid; %#ok<AGROW>
            records(i) = rec;
            continue;
        end

        [rmsTimes, rmsVals] = finiteRms(rec.rms_times, rec.rms_vals);
        if isempty(rmsVals)
            warning('refresh_dynamic_rms_only:NoFiniteRmsData', ...
                'No finite RMS data for %s point %s', kind, pid);
            skipped{end+1, 1} = pid; %#ok<AGROW>
            records(i) = rec;
            continue;
        end

        plotVals = zeros(size(rmsVals));
        bms.analyzer.DynamicAccelerationPlotService.plotRmsCurve( ...
            rootDir, rec.pid, rmsTimes, plotVals, rec.fs, style, cfg, spec, rmsTimes, rmsVals);

        rec.rms_times = rmsTimes;
        rec.rms_vals = rmsVals;
        rec.times = rmsTimes;
        rec.vals = plotVals;
        records(i) = rec;
        stats(i, :) = {rec.pid, rec.mn, rec.mx, rec.av, rec.rms_max, rec.rms_time};
        refreshed = refreshed + 1;
    end

    bms.analyzer.DynamicAccelerationSeriesService.plotConfiguredGroups( ...
        rootDir, subfolder, startDate, endDate, cfg, true, style, spec, records);

    statsFile = resolve_data_output_path(rootDir, spec.defaultStatsFile, 'stats');
    tableOut = bms.analyzer.DynamicSeriesService.dynamicStatsTable(stats);
    bms.io.StatsWriter.writeModuleTableChecked(tableOut, statsFile, spec.moduleKey);

    moduleResult = struct();
    moduleResult.kind = kind;
    moduleResult.point_count = numel(points);
    moduleResult.refreshed_count = refreshed;
    moduleResult.skipped_points = {skipped};
    moduleResult.stats_file = statsFile;
end

function rec = collectRecordExplicitDays(rootDir, subfolder, pointId, startDate, endDate, cfg, spec)
    rec = bms.analyzer.DynamicSeriesService.initRecord();
    rec.pid = char(string(pointId));

    dateList = bms.data.TimeSeriesRangeLoader.buildDateList(startDate, endDate);
    totalCount = 0;
    totalSum = 0;
    mn = Inf;
    mx = -Inf;
    bestRms = NaN;
    bestTime = NaT;
    fsValues = [];
    keptRmsTimes = {};
    keptRmsVals = {};

    for i = 1:numel(dateList)
        day = dateList{i};
        if i == 1 || i == numel(dateList) || mod(i, 10) == 0
            fprintf('RMS explicit %s %s checking %s (%d/%d)\n', ...
                char(string(spec.sensorType)), rec.pid, day, i, numel(dateList));
        end

        if ~hasExplicitDayFile(rootDir, subfolder, rec.pid, day, cfg, spec.sensorType)
            continue;
        end

        [times, vals] = load_timeseries_range(rootDir, subfolder, rec.pid, day, day, cfg, spec.sensorType);
        if isempty(vals)
            continue;
        end

        fsDay = bms.analyzer.DynamicSeriesService.sampleRate(times, true, 100);
        if isfinite(fsDay) && fsDay > 0
            fsValues(end+1, 1) = fsDay; %#ok<AGROW>
        end

        finite = isfinite(vals);
        if any(finite)
            dayVals = vals(finite);
            totalCount = totalCount + numel(dayVals);
            totalSum = totalSum + sum(dayVals);
            mn = min(mn, min(dayVals));
            mx = max(mx, max(dayVals));
        end

        [rmsTimesDay, rmsSeriesDay, rmsDay, tDay] = ...
            bms.analyzer.DynamicSeriesService.rmsByTimeBins(times, vals, 10, 0.7, fsDay);
        if isfinite(rmsDay) && (~isfinite(bestRms) || rmsDay > bestRms)
            bestRms = rmsDay;
            bestTime = tDay;
        end
        if ~isempty(rmsSeriesDay)
            keptRmsTimes{end+1, 1} = rmsTimesDay; %#ok<AGROW>
            keptRmsVals{end+1, 1} = rmsSeriesDay; %#ok<AGROW>
        end
    end

    if totalCount <= 0
        return;
    end

    rec.fs = median(fsValues, 'omitnan');
    if isempty(fsValues) || ~isfinite(rec.fs)
        rec.fs = 100;
    end
    rec.mn = round(mn, 3);
    rec.mx = round(mx, 3);
    rec.av = round(totalSum / totalCount, 3);
    if isfinite(bestRms)
        rec.rms_max = round(bestRms, 3);
        rec.rms_time = bestTime;
    end
    rec.has_data = true;

    if ~isempty(keptRmsVals)
        rec.rms_times = vertcat(keptRmsTimes{:});
        rec.rms_vals = vertcat(keptRmsVals{:});
        [rec.rms_times, order] = sort(rec.rms_times);
        rec.rms_vals = rec.rms_vals(order);
    end
    fprintf('RMS explicit %s %s collected rms=%.6g\n', ...
        char(string(spec.sensorType)), rec.pid, rec.rms_max);
end

function tf = hasExplicitDayFile(rootDir, subfolder, pointId, day, cfg, sensorType)
    tf = false;
    dirs = dayCandidateDirs(rootDir, subfolder, day);
    if isempty(dirs)
        return;
    end
    patterns = explicitPatterns(cfg, sensorType, pointId);
    if isempty(patterns)
        tf = true;
        return;
    end
    fileId = bms.data.TimeSeriesLoader.resolveFileId(cfg, sensorType, pointId);
    for i = 1:numel(dirs)
        for j = 1:numel(patterns)
            pat = char(string(patterns{j}));
            pat = strrep(pat, '{point}', char(string(pointId)));
            pat = strrep(pat, '{file_id}', char(string(fileId)));
            hits = dir(fullfile(dirs{i}, pat));
            hits = hits(~[hits.isdir]);
            if ~isempty(hits)
                tf = true;
                return;
            end
        end
    end
end

function dirs = dayCandidateDirs(rootDir, subfolder, day)
    dirs = bms.data.DatedFolderAdapter.candidateDirs(rootDir, subfolder, day, day);
    if ~isempty(dirs)
        return;
    end

    dirs = {};
    dayFolders = bms.data.DatedFolderAdapter.dateFolderCandidates(rootDir, day);
    subfolder = char(string(subfolder));
    for i = 1:numel(dayFolders)
        if ~isfolder(dayFolders{i})
            continue;
        end
        candidates = {fullfile(dayFolders{i}, subfolder), dayFolders{i}};
        for j = 1:numel(candidates)
            if isfolder(candidates{j})
                dirs{end+1, 1} = candidates{j}; %#ok<AGROW>
                break;
            end
        end
    end
    dirs = bms.data.BaseDataSource.uniqueExistingFolders(dirs);
end

function patterns = explicitPatterns(cfg, sensorType, pointId)
    patterns = {};
    sensorType = char(string(sensorType));
    if ~isstruct(cfg) || ~isfield(cfg, 'file_patterns') || ~isstruct(cfg.file_patterns) ...
            || ~isfield(cfg.file_patterns, sensorType)
        return;
    end
    ft = cfg.file_patterns.(sensorType);
    if isstruct(ft) && isfield(ft, 'per_point') && isstruct(ft.per_point)
        [ok, pointPatterns] = bms.data.PointResolver.getPointConfig(ft.per_point, pointId, cfg);
        if ok
            patterns = [patterns; bms.data.TimeSeriesLoader.normalizePatterns(pointPatterns)];
        end
    end
    if isstruct(ft) && isfield(ft, 'default')
        patterns = [patterns; bms.data.TimeSeriesLoader.normalizePatterns(ft.default)];
    end
    patterns = unique(patterns, 'stable');
end

function [timesOut, valsOut] = finiteRms(timesIn, valsIn)
    timesOut = timesIn(:);
    valsOut = valsIn(:);
    if isempty(valsOut) || numel(timesOut) ~= numel(valsOut)
        timesOut = datetime.empty(0, 1);
        valsOut = [];
        return;
    end
    keep = ~isnat(timesOut) & isfinite(valsOut);
    timesOut = timesOut(keep);
    valsOut = valsOut(keep);
    if isempty(valsOut)
        return;
    end
    [timesOut, order] = sort(timesOut);
    valsOut = valsOut(order);
end
