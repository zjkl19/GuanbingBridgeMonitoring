function result = refresh_dynamic_rms_only(rootDir, startDate, endDate, cfgOrPath, kinds, options)
%REFRESH_DYNAMIC_RMS_ONLY Refresh RMS10min artifacts for dynamic modules only.
%   This is intended for report repair after RMS plot logic changes. It
%   recomputes per-point RMS series from the raw time-series data, refreshes
%   RMS plots/group plots, and rewrites the corresponding stats workbook.
%   By default, a module that refreshes zero points fails before its stats
%   workbook is written.  Pass struct('allow_empty_output', true) as OPTIONS
%   only when an intentionally empty replacement workbook is required.

    if nargin < 5 || isempty(kinds)
        kinds = {'acceleration', 'cable_accel'};
    end
    if ischar(kinds) || isstring(kinds)
        kinds = cellstr(string(kinds));
    end
    if nargin < 6 || isempty(options)
        options = struct();
    end
    allowEmptyOutput = bms.config.ConfigReader.boolValue( ...
        localOption(options, 'allow_empty_output', false), false);

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
        moduleResult = refreshOneKind( ...
            rootDir, startDate, endDate, cfg, kind, allowEmptyOutput);
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

function moduleResult = refreshOneKind(rootDir, startDate, endDate, cfg, kind, allowEmptyOutput)
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
        % Use the same vendor-aware, MAT-alias-aware calendar-day loader as
        % the main acceleration analyzers.  The former CSV-pattern precheck
        % rejected valid MAT-only caches before this loader could see them.
        rec = bms.analyzer.DynamicAccelerationSeriesService.collectRecord( ...
            rootDir, subfolder, pid, startDate, endDate, cfg, true, spec, false);
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

        bms.analyzer.DynamicAccelerationPlotService.plotRmsCurve( ...
            rootDir, rec.pid, rmsTimes, rmsVals, rec.fs, style, cfg, spec, rmsTimes, rmsVals);

        rec.rms_times = rmsTimes;
        rec.rms_vals = rmsVals;
        records(i) = rec;
        stats(i, :) = {rec.pid, rec.mn, rec.mx, rec.av, rec.rms_max, rec.rms_time};
        refreshed = refreshed + 1;
    end

    if refreshed == 0 && ~allowEmptyOutput
        error('refresh_dynamic_rms_only:NoPointsRefreshed', ...
            ['Refusing to replace %s stats because zero of %d configured ' ...
             'points produced finite RMS data. Existing artifacts were left unchanged.'], ...
            kind, numel(points));
    end

    bms.analyzer.DynamicAccelerationSeriesService.plotConfiguredRmsGroups( ...
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

function value = localOption(options, name, defaultValue)
    value = defaultValue;
    if isstruct(options) && isfield(options, name) && ~isempty(options.(name))
        value = options.(name);
    end
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
