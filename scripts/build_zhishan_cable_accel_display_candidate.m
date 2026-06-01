function result = build_zhishan_cable_accel_display_candidate()
%BUILD_ZHISHAN_CABLE_ACCEL_DISPLAY_CANDIDATE Build final display candidate.
%   Display-only diagnostic. Formal spectrum/force outputs remain unchanged.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
startDate = '2026-03-01';
endDate = '2026-03-31';
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
formalThreshold = 100;
displayThresholds = containers.Map( ...
    {'CF-1','CF-2','CF-3','CF-4','CF-5','CF-6','CF-7','CF-8'}, ...
    {50, 100, 5, 5, 100, 10, 100, 100});
segmentPct = containers.Map( ...
    {'CF-1','CF-2','CF-3','CF-4','CF-5','CF-6','CF-7','CF-8'}, ...
    {0, 0, 0, 0, 5, 0, 5, 0});
binMinutes = 30;
segmentMinutes = 30;

cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));
cfg.notify.enabled = false;
cfgLoad = removeCableAccelThresholds(cfg);
subfolder = bms.config.ConfigReader.getSubfolder(cfgLoad, 'cable_accel', '');

stamp = datestr(now, 'yyyymmdd_HHMMSS');
runName = ['cable_accel_display_candidate_' stamp];
outRoot = fullfile(dataRoot, 'run_logs', runName);
plotDir = fullfile(outRoot, 'plots');
if ~exist(plotDir, 'dir'), mkdir(plotDir); end

t0 = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
t1 = datetime(endDate, 'InputFormat', 'yyyy-MM-dd') + days(1);
binEdges = t0:minutes(binMinutes):t1;
binCenters = binEdges(1:end-1)' + minutes(binMinutes / 2);
segmentEdges = t0:minutes(segmentMinutes):t1;

rows = {};
plotPaths = cell(numel(points), 1);
trendPlotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    fprintf('display candidate %s\n', pointId);
    [times, values] = load_timeseries_range(dataRoot, subfolder, pointId, ...
        startDate, endDate, cfgLoad, 'cable_accel');
    times = times(:);
    values = double(values(:));
    baseMask = isfinite(values) & ~isnat(times);
    baseCount = nnz(baseMask);
    if baseCount == 0
        warning('%s has no finite data.', pointId);
        continue;
    end

    formalClean = clipAbs(values, formalThreshold);
    displayThreshold = displayThresholds(pointId);
    displayClean = clipAbs(values, displayThreshold);
    segmentFilterPct = segmentPct(pointId);
    if segmentFilterPct > 0
        displayClean = applyTopRmsSegmentMask(times, displayClean, segmentEdges, segmentFilterPct);
    end

    formalMetric = binnedMetric(times, formalClean, binEdges, binCenters);
    displayMetric = binnedMetric(times, displayClean, binEdges, binCenters);
    formalKeepPct = 100 * nnz(isfinite(formalClean) & ~isnat(times)) / baseCount;
    displayKeepPct = 100 * nnz(isfinite(displayClean) & ~isnat(times)) / baseCount;
    reductionPct = 100 * (formalMetric.rmsMax - displayMetric.rmsMax) / max(formalMetric.rmsMax, eps);
    strategy = strategyText(displayThreshold, formalThreshold, segmentFilterPct, segmentMinutes);
    conclusion = conclusionText(pointId, displayThreshold, formalThreshold, segmentFilterPct, reductionPct);

    plotPaths{i} = plotPoint(plotDir, pointId, binCenters, displayMetric, ...
        displayThreshold, segmentFilterPct, displayKeepPct, reductionPct, conclusion);
    trendPlotPaths{i} = plotTrendPoint(plotDir, pointId, binCenters, displayMetric, ...
        displayThreshold, segmentFilterPct, displayKeepPct, reductionPct, conclusion);
    rows(end+1, :) = {pointId, strategy, formalThreshold, displayThreshold, ...
        segmentFilterPct, baseCount, formalKeepPct, displayKeepPct, ...
        formalMetric.rmsMax, displayMetric.rmsMax, formalMetric.rmsP95, ...
        displayMetric.rmsP95, reductionPct, conclusion, plotPaths{i}, trendPlotPaths{i}}; %#ok<AGROW>
end

summary = cell2table(rows, 'VariableNames', { ...
    'PointID','Strategy','FormalThresholdAbs','DisplayThresholdAbs', ...
    'SegmentFilterTopPct','BaseFiniteCount','FormalKeepPct','DisplayKeepPct', ...
    'FormalRMS30Max','DisplayRMS30Max','FormalRMS30P95','DisplayRMS30P95', ...
    'RMS30MaxReductionPct','Conclusion','PlotPath','TrendPlotPath'});

xlsxPath = fullfile(outRoot, 'cable_accel_display_candidate.xlsx');
csvPath = fullfile(outRoot, 'cable_accel_display_candidate.csv');
writetable(summary, xlsxPath, 'Sheet', 'summary');
writetable(summary, csvPath, 'Encoding', 'UTF-8');
boardPath = buildReviewBoard(plotPaths, points, outRoot);
trendBoardPath = buildReviewBoard(trendPlotPaths, points, outRoot, 'cable_accel_display_trend_review_board.jpg');
stable = writeStableOutputs(dataRoot, runName, summary, plotPaths, trendPlotPaths, boardPath, trendBoardPath);
markdownPath = writeMarkdown(outRoot, runName, summary, xlsxPath, csvPath, boardPath, trendBoardPath);
latestPaths = writeLatest(dataRoot, runName, summary, xlsxPath, csvPath, boardPath, trendBoardPath, markdownPath, stable);

result = struct();
result.run_name = runName;
result.output_folder = outRoot;
result.summary = summary;
result.workbook = xlsxPath;
result.csv = csvPath;
result.board = boardPath;
result.trend_board = trendBoardPath;
result.markdown = markdownPath;
result.latest = latestPaths;
result.stable = stable;

fprintf('wrote %s\n', xlsxPath);
fprintf('wrote %s\n', csvPath);
fprintf('review board %s\n', boardPath);
fprintf('trend board %s\n', trendBoardPath);
fprintf('stable dir %s\n', stable.dir);
fprintf('summary markdown %s\n', markdownPath);
fprintf('latest json %s\n', latestPaths.json);
fprintf('latest markdown %s\n', latestPaths.markdown);
disp(summary(:, {'PointID','Strategy','DisplayKeepPct','DisplayRMS30Max','RMS30MaxReductionPct','Conclusion'}));
end

function cfgOut = removeCableAccelThresholds(cfgIn)
cfgOut = cfgIn;
if isfield(cfgOut, 'defaults') && isfield(cfgOut.defaults, 'cable_accel')
    cfgOut.defaults.cable_accel.thresholds = [];
    if isfield(cfgOut.defaults.cable_accel, 'value_scale')
        cfgOut.defaults.cable_accel = rmfield(cfgOut.defaults.cable_accel, 'value_scale');
    end
end
if isfield(cfgOut, 'per_point') && isfield(cfgOut.per_point, 'cable_accel')
    names = fieldnames(cfgOut.per_point.cable_accel);
    for k = 1:numel(names)
        if isfield(cfgOut.per_point.cable_accel.(names{k}), 'thresholds')
            cfgOut.per_point.cable_accel.(names{k}).thresholds = [];
        end
    end
end
end

function clean = clipAbs(values, thresholdAbs)
clean = values;
clean(abs(clean) > thresholdAbs) = NaN;
end

function clean = applyTopRmsSegmentMask(times, clean, segmentEdges, topPct)
valid = isfinite(clean) & ~isnat(times);
if ~any(valid)
    return;
end
nSegments = numel(segmentEdges) - 1;
idx = discretize(times(valid), segmentEdges);
good = ~isnan(idx);
vals = clean(valid);
vals = vals(good);
idx = idx(good);
rmsValues = accumarray(idx, vals, [nSegments 1], @(x) sqrt(mean(x.^2, 'omitnan')), NaN);
ok = isfinite(rmsValues);
if ~any(ok)
    return;
end
cutoff = prctile(rmsValues(ok), 100 - topPct);
bad = ok & rmsValues >= cutoff;
allIdx = discretize(times, segmentEdges);
hasIdx = ~isnan(allIdx);
reject = false(size(clean));
reject(hasIdx) = bad(allIdx(hasIdx));
clean(reject) = NaN;
end

function metric = binnedMetric(times, values, binEdges, binCenters)
nBins = numel(binCenters);
metric = struct();
metric.p05 = NaN(nBins, 1);
metric.p25 = NaN(nBins, 1);
metric.p50 = NaN(nBins, 1);
metric.p75 = NaN(nBins, 1);
metric.p95 = NaN(nBins, 1);
metric.rms = NaN(nBins, 1);
metric.rmsMax = NaN;
metric.rmsP95 = NaN;
valid = isfinite(values) & ~isnat(times);
if ~any(valid)
    return;
end
idx = discretize(times(valid), binEdges);
good = ~isnan(idx);
vals = values(valid);
vals = vals(good);
idx = idx(good);
if isempty(vals)
    return;
end
metric.p05 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 5), NaN);
metric.p25 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 25), NaN);
metric.p50 = accumarray(idx, vals, [nBins 1], @(x) median(x, 'omitnan'), NaN);
metric.p75 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 75), NaN);
metric.p95 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 95), NaN);
metric.rms = accumarray(idx, vals, [nBins 1], @(x) sqrt(mean(x.^2, 'omitnan')), NaN);
finiteRms = metric.rms(isfinite(metric.rms));
if ~isempty(finiteRms)
    metric.rmsMax = max(finiteRms);
    metric.rmsP95 = prctile(finiteRms, 95);
end
end

function text = strategyText(displayThreshold, formalThreshold, segmentFilterPct, segmentMinutes)
parts = {};
if displayThreshold < formalThreshold
    parts{end+1} = sprintf('abs<=%.0f display', displayThreshold); %#ok<AGROW>
else
    parts{end+1} = sprintf('formal abs<=%.0f', formalThreshold); %#ok<AGROW>
end
if segmentFilterPct > 0
    parts{end+1} = sprintf('drop top %.0f%% RMS%d segments', segmentFilterPct, segmentMinutes); %#ok<AGROW>
end
text = strjoin(parts, ' + ');
end

function text = conclusionText(pointId, displayThreshold, formalThreshold, segmentFilterPct, reductionPct)
if displayThreshold < formalThreshold
    text = 'point threshold display clipping';
elseif segmentFilterPct > 0 && reductionPct >= 25
    text = 'segment quality display filtering';
elseif any(strcmp(pointId, {'CF-2','CF-8'}))
    text = 'persistent wide-band signal; document quality limitation';
else
    text = 'formal display retained';
end
end

function plotPath = plotPoint(plotDir, pointId, binCenters, metric, displayThreshold, ...
        segmentFilterPct, keepPct, reductionPct, conclusion)
fig = figure('Visible', 'off', 'Position', [100 100 1250 700]);
tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile;
hold(ax1, 'on');
fillBand(ax1, binCenters, metric.p05, metric.p95, [0.80 0.88 0.96], 0.45, '5%~95%');
fillBand(ax1, binCenters, metric.p25, metric.p75, [0.38 0.64 0.86], 0.70, '25%~75%');
plot(ax1, binCenters, metric.p50, 'Color', [0 0.18 0.42], 'LineWidth', 1.3, 'DisplayName', 'median');
hold(ax1, 'off');
grid(ax1, 'on');
grid(ax1, 'minor');
ylabel(ax1, 'm/s^2');
title(ax1, sprintf('%s display candidate | abs<=%.0f | segment %.0f%% | keep %.2f%%', ...
    pointId, displayThreshold, segmentFilterPct, keepPct), 'Interpreter', 'none');
legend(ax1, 'Location', 'northeast', 'Box', 'off');
xtickformat(ax1, 'yyyy-MM-dd');

ax2 = nexttile;
plot(ax2, binCenters, metric.rms, 'Color', [0.85 0.33 0.10], 'LineWidth', 1.2);
grid(ax2, 'on');
grid(ax2, 'minor');
ylabel(ax2, 'RMS (m/s^2)');
xlabel(ax2, 'time');
title(ax2, sprintf('RMS30 max %.2f | reduction %.1f%% | %s', ...
    metric.rmsMax, reductionPct, conclusion), 'Interpreter', 'none');
xtickformat(ax2, 'yyyy-MM-dd');
linkaxes([ax1 ax2], 'x');
xlim(ax1, [binCenters(1), binCenters(end)]);

plotPath = fullfile(plotDir, sprintf('DisplayCandidate_%s.jpg', pointId));
exportgraphics(fig, plotPath, 'Resolution', 150);
close(fig);
end

function plotPath = plotTrendPoint(plotDir, pointId, binCenters, metric, displayThreshold, ...
        segmentFilterPct, keepPct, reductionPct, conclusion)
fig = figure('Visible', 'off', 'Position', [100 100 1250 520]);
ax = axes(fig);
hold(ax, 'on');
fillBand(ax, binCenters, metric.p05, metric.p95, [0.72 0.82 0.92], 0.22, '5%~95%');
fillBand(ax, binCenters, metric.p25, metric.p75, [0.22 0.57 0.78], 0.55, '25%~75%');
plot(ax, binCenters, metric.p50, 'Color', [0 0.17 0.38], 'LineWidth', 1.5, 'DisplayName', 'median');
hold(ax, 'off');
grid(ax, 'on');
grid(ax, 'minor');
ylabel(ax, 'm/s^2');
xlabel(ax, 'time');
title(ax, sprintf('%s trend view | abs<=%.0f | segment %.0f%% | keep %.2f%% | RMS max down %.1f%% | %s', ...
    pointId, displayThreshold, segmentFilterPct, keepPct, reductionPct, conclusion), 'Interpreter', 'none');
legend(ax, 'Location', 'northeast', 'Box', 'off');
xtickformat(ax, 'yyyy-MM-dd');
xlim(ax, [binCenters(1), binCenters(end)]);
setTrendYLimits(ax, metric);

plotPath = fullfile(plotDir, sprintf('DisplayTrend_%s.jpg', pointId));
exportgraphics(fig, plotPath, 'Resolution', 150);
close(fig);
end

function setTrendYLimits(ax, metric)
core = [metric.p25(:); metric.p50(:); metric.p75(:)];
core = core(isfinite(core));
if isempty(core)
    return;
end
lo = prctile(core, 1);
hi = prctile(core, 99);
if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
    lo = min(core);
    hi = max(core);
end
if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
    center = median(core, 'omitnan');
    lo = center - 1;
    hi = center + 1;
end
pad = max((hi - lo) * 0.18, 0.5);
ylim(ax, [lo - pad, hi + pad]);
end

function fillBand(ax, t, lo, hi, color, alpha, label)
ok = isfinite(lo) & isfinite(hi) & ~isnat(t);
if ~any(ok)
    return;
end
runs = continuousRuns(ok);
for k = 1:size(runs, 1)
    idx = runs(k, 1):runs(k, 2);
    x = [t(idx); flipud(t(idx))];
    y = [lo(idx); flipud(hi(idx))];
    if k == 1
        displayName = label;
        visibility = 'on';
    else
        displayName = '';
        visibility = 'off';
    end
    fill(ax, x, y, color, 'FaceAlpha', alpha, 'EdgeColor', 'none', ...
        'DisplayName', displayName, 'HandleVisibility', visibility);
end
end

function runs = continuousRuns(mask)
mask = mask(:);
starts = find(mask & [true; ~mask(1:end-1)]);
ends = find(mask & [~mask(2:end); true]);
runs = [starts ends];
end

function boardPath = buildReviewBoard(plotPaths, points, outRoot, fileName)
if nargin < 4 || isempty(fileName)
    fileName = 'cable_accel_display_candidate_review_board.jpg';
end
fig = figure('Visible', 'off', 'Position', [100 100 1800 2200]);
tiledlayout(fig, 4, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
for i = 1:numel(points)
    ax = nexttile;
    if isempty(plotPaths{i}) || ~isfile(plotPaths{i})
        axis(ax, 'off');
        text(ax, 0.5, 0.5, sprintf('%s missing', points{i}), ...
            'HorizontalAlignment', 'center', 'Interpreter', 'none');
    else
        image(ax, imread(plotPaths{i}));
        axis(ax, 'image');
        axis(ax, 'off');
        title(ax, points{i}, 'Interpreter', 'none');
    end
end
boardPath = fullfile(outRoot, fileName);
exportgraphics(fig, boardPath, 'Resolution', 150);
close(fig);
end

function stable = writeStableOutputs(dataRoot, runName, summary, plotPaths, trendPlotPaths, boardPath, trendBoardPath)
stableDir = fullfile(dataRoot, 'report_cable_accel_display_candidate');
if ~exist(stableDir, 'dir'), mkdir(stableDir); end

stablePlotPaths = cell(height(summary), 1);
stableTrendPlotPaths = cell(height(summary), 1);
for i = 1:height(summary)
    pointId = summary.PointID{i};
    stablePath = fullfile(stableDir, sprintf('CableAccelDisplayCandidate_%s.jpg', pointId));
    copyfile(plotPaths{i}, stablePath, 'f');
    stablePlotPaths{i} = stablePath;

    stableTrendPath = fullfile(stableDir, sprintf('CableAccelDisplayTrend_%s.jpg', pointId));
    copyfile(trendPlotPaths{i}, stableTrendPath, 'f');
    stableTrendPlotPaths{i} = stableTrendPath;
end

stableBoardPath = fullfile(stableDir, 'CableAccelDisplayCandidate_ReviewBoard.jpg');
copyfile(boardPath, stableBoardPath, 'f');
stableTrendBoardPath = fullfile(stableDir, 'CableAccelDisplayTrend_ReviewBoard.jpg');
copyfile(trendBoardPath, stableTrendBoardPath, 'f');

manifest = summary;
manifest.StablePlotPath = stablePlotPaths;
manifest.StableTrendPlotPath = stableTrendPlotPaths;
manifest.SourceRun = repmat({runName}, height(manifest), 1);
manifest.GeneratedAt = repmat({datestr(now, 'yyyy-mm-dd HH:MM:SS')}, height(manifest), 1);
manifestPath = fullfile(stableDir, 'CableAccelDisplayCandidate_manifest.xlsx');
writetable(manifest, manifestPath, 'Sheet', 'summary');

markdownPath = fullfile(stableDir, 'CableAccelDisplayCandidate_manifest.md');
fid = fopen(markdownPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Cable Acceleration Display Candidate Stable Outputs\n\n');
fprintf(fid, '- Source run: `%s`\n', runName);
fprintf(fid, '- Review board: `%s`\n', localFileName(stableBoardPath));
fprintf(fid, '- Trend board: `%s`\n', localFileName(stableTrendBoardPath));
fprintf(fid, '- Manifest workbook: `%s`\n\n', localFileName(manifestPath));
fprintf(fid, '| Point | Detail plot | Trend plot | Strategy | Display keep %% | RMS30 max reduction %% | Conclusion |\n');
fprintf(fid, '|---|---|---|---|---:|---:|---|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | `%s` | `%s` | %s | %.3f | %.1f | %s |\n', ...
        manifest.PointID{i}, localFileName(manifest.StablePlotPath{i}), localFileName(manifest.StableTrendPlotPath{i}), manifest.Strategy{i}, ...
        manifest.DisplayKeepPct(i), manifest.RMS30MaxReductionPct(i), manifest.Conclusion{i});
end

stable = struct();
stable.dir = stableDir;
stable.review_board = stableBoardPath;
stable.trend_review_board = stableTrendBoardPath;
stable.manifest = manifestPath;
stable.markdown = markdownPath;
stable.plot_paths = stablePlotPaths;
stable.trend_plot_paths = stableTrendPlotPaths;
end

function markdownPath = writeMarkdown(outRoot, runName, summary, xlsxPath, csvPath, boardPath, trendBoardPath)
markdownPath = fullfile(outRoot, 'cable_accel_display_candidate.md');
fid = fopen(markdownPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Display Candidate\n\n');
fprintf(fid, '- Run: `%s`\n', runName);
fprintf(fid, '- Workbook: `%s`\n', xlsxPath);
fprintf(fid, '- CSV: `%s`\n', csvPath);
fprintf(fid, '- Review board: `%s`\n\n', boardPath);
fprintf(fid, '- Trend board: `%s`\n\n', trendBoardPath);
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`. This candidate is display-only.\n\n');
fprintf(fid, '| Point | Strategy | Display keep %% | RMS30 max | RMS30 max reduction %% | Conclusion |\n');
fprintf(fid, '|---|---|---:|---:|---:|---|\n');
for i = 1:height(summary)
    fprintf(fid, '| %s | %s | %.3f | %.3f | %.1f | %s |\n', ...
        summary.PointID{i}, summary.Strategy{i}, summary.DisplayKeepPct(i), ...
        summary.DisplayRMS30Max(i), summary.RMS30MaxReductionPct(i), summary.Conclusion{i});
end
end

function latestPaths = writeLatest(dataRoot, runName, summary, xlsxPath, csvPath, boardPath, trendBoardPath, markdownPath, stable)
runLogs = fullfile(dataRoot, 'run_logs');
latestPaths = struct( ...
    'json', fullfile(runLogs, 'cable_accel_display_candidate_latest.json'), ...
    'markdown', fullfile(runLogs, 'cable_accel_display_candidate_latest.md'), ...
    'html', fullfile(runLogs, 'cable_accel_display_candidate_latest.html'));

pointer = struct();
pointer.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
pointer.run_name = runName;
pointer.output_folder = relPath(fileparts(xlsxPath), dataRoot);
pointer.summary = relPath(markdownPath, dataRoot);
pointer.workbook = relPath(xlsxPath, dataRoot);
pointer.csv = relPath(csvPath, dataRoot);
pointer.review_board = relPath(boardPath, dataRoot);
pointer.trend_review_board = relPath(trendBoardPath, dataRoot);
pointer.review_html = relPath(latestPaths.html, dataRoot);
pointer.stable_output_dir = relPath(stable.dir, dataRoot);
pointer.stable_review_board = relPath(stable.review_board, dataRoot);
pointer.stable_trend_review_board = relPath(stable.trend_review_board, dataRoot);
pointer.stable_manifest = relPath(stable.manifest, dataRoot);
pointer.stable_markdown = relPath(stable.markdown, dataRoot);
pointer.formal_policy = 'Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.';
pointer.display_policy = 'Display-only candidate: point thresholds for CF-1/3/4/6, RMS30 segment filtering for CF-5/7, quality limitation notes for CF-2/8.';
pointer.points = struct();
for i = 1:height(summary)
    field = matlab.lang.makeValidName(strrep(summary.PointID{i}, '-', '_'));
    pointer.points.(field) = struct( ...
        'strategy', summary.Strategy{i}, ...
        'display_keep_pct', summary.DisplayKeepPct(i), ...
        'display_rms30_max', summary.DisplayRMS30Max(i), ...
        'rms30_max_reduction_pct', summary.RMS30MaxReductionPct(i), ...
        'conclusion', summary.Conclusion{i});
end

fid = fopen(latestPaths.json, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(pointer));
clear cleaner;

fid = fopen(latestPaths.markdown, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Latest Zhishan Cable Acceleration Display Candidate\n\n');
fprintf(fid, '- Generated: %s\n', pointer.generated_at);
fprintf(fid, '- Run: `%s`\n', pointer.run_name);
fprintf(fid, '- Summary: `%s`\n', pointer.summary);
fprintf(fid, '- Workbook: `%s`\n', pointer.workbook);
fprintf(fid, '- Review board: `%s`\n', pointer.review_board);
fprintf(fid, '- Trend board: `%s`\n', pointer.trend_review_board);
fprintf(fid, '- Review HTML: `%s`\n', pointer.review_html);
fprintf(fid, '- Stable output dir: `%s`\n', pointer.stable_output_dir);
fprintf(fid, '- Stable review board: `%s`\n', pointer.stable_review_board);
fprintf(fid, '- Stable trend board: `%s`\n', pointer.stable_trend_review_board);
fprintf(fid, '- Stable manifest: `%s`\n', pointer.stable_manifest);
fprintf(fid, '- Formal policy: %s\n', pointer.formal_policy);
fprintf(fid, '- Display policy: %s\n\n', pointer.display_policy);
fprintf(fid, '| Point | Strategy | Display keep %% | RMS30 max | RMS30 max reduction %% | Conclusion |\n');
fprintf(fid, '|---|---|---:|---:|---:|---|\n');
for i = 1:height(summary)
    fprintf(fid, '| %s | %s | %.3f | %.3f | %.1f | %s |\n', ...
        summary.PointID{i}, summary.Strategy{i}, summary.DisplayKeepPct(i), ...
        summary.DisplayRMS30Max(i), summary.RMS30MaxReductionPct(i), summary.Conclusion{i});
end
clear cleaner;

writeLatestHtml(latestPaths.html, pointer, summary);
end

function writeLatestHtml(path, pointer, summary)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Display Candidate</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.meta,.note{line-height:1.7;color:#4b5563;} .note{background:white;border-left:4px solid #2f6fed;padding:10px 12px;margin:14px 0 20px;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;}');
fprintf(fid, 'th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.quality{background:#fff8e1;} .figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:14px;} a{color:#075da8;text-decoration:none;} a:hover{text-decoration:underline;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230;&#23637;&#31034;&#20505;&#36873; / Zhishan Cable Acceleration Display Candidate</h1>\n');
fprintf(fid, '<div class="meta">Generated: %s<br>Run: <code>%s</code><br>Summary: <a href="%s">%s</a><br>Workbook: <a href="%s">%s</a></div>\n', ...
    htmlText(pointer.generated_at), htmlText(pointer.run_name), htmlPath(pointer.summary), htmlText(pointer.summary), ...
    htmlPath(pointer.workbook), htmlText(pointer.workbook));
fprintf(fid, '<div class="note">&#27491;&#24335;&#39057;&#35889;/&#32034;&#21147;&#35745;&#31639;&#19981;&#21464;: <code>daily_median + [-100,100] m/s^2</code>. &#26412;&#39029;&#20165;&#29992;&#20110;&#25253;&#21578;/&#23457;&#22270;&#23637;&#31034;&#20505;&#36873;&#12290;</div>\n');

fprintf(fid, '<h2>&#31574;&#30053;&#27719;&#24635; / Strategy Summary</h2>\n<table>\n');
fprintf(fid, '<tr><th>&#27979;&#28857;</th><th>&#23637;&#31034;&#31574;&#30053;</th><th>&#20445;&#30041;&#29575;</th><th>RMS30 &#26368;&#22823;&#20540;</th><th>RMS30 &#38477;&#20302;</th><th>&#32467;&#35770;</th></tr>\n');
for i = 1:height(summary)
    cls = '';
    if contains(summary.Conclusion{i}, 'quality limitation')
        cls = ' class="quality"';
    end
    fprintf(fid, '<tr%s><td>%s</td><td>%s</td><td class="num">%.3f%%</td><td class="num">%.3f</td><td class="num">%.1f%%</td><td>%s</td></tr>\n', ...
        cls, htmlText(summary.PointID{i}), htmlText(summary.Strategy{i}), ...
        summary.DisplayKeepPct(i), summary.DisplayRMS30Max(i), ...
        summary.RMS30MaxReductionPct(i), htmlText(summary.Conclusion{i}));
end
fprintf(fid, '</table>\n');

fprintf(fid, '<h2>&#35814;&#32454;&#24635;&#35272;&#22270; / Detail Review Board</h2>\n<div class="figure"><img src="%s" alt="detail review board"></div>\n', htmlPath(pointer.review_board));
fprintf(fid, '<h2>&#36235;&#21183;&#24635;&#35272;&#22270; / Trend Review Board</h2>\n<div class="figure"><img src="%s" alt="trend review board"></div>\n', htmlPath(pointer.trend_review_board));
fprintf(fid, '<h2>&#21333;&#28857;&#35814;&#32454;&#22270; / Per-Point Detail Figures</h2>\n<div class="grid">\n');
for i = 1:height(summary)
    rel = relPath(summary.PlotPath{i}, fileparts(fileparts(path)));
    fprintf(fid, '<div class="figure"><h2>%s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(summary.PointID{i}), htmlPath(rel), htmlText(summary.PointID{i}));
end
fprintf(fid, '</div>\n<h2>&#21333;&#28857;&#36235;&#21183;&#22270; / Per-Point Trend Figures</h2>\n<div class="grid">\n');
for i = 1:height(summary)
    rel = relPath(summary.TrendPlotPath{i}, fileparts(fileparts(path)));
    fprintf(fid, '<div class="figure"><h2>%s trend</h2><img src="%s" alt="%s trend"></div>\n', ...
        htmlText(summary.PointID{i}), htmlPath(rel), htmlText(summary.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function out = htmlPath(pathText)
out = char(pathText);
prefix = ['run_logs' filesep];
if startsWith(out, prefix)
    out = out(numel(prefix)+1:end);
end
out = strrep(out, '\', '/');
out = htmlText(out);
end

function out = htmlText(value)
out = char(string(value));
out = strrep(out, '&', '&amp;');
out = strrep(out, '<', '&lt;');
out = strrep(out, '>', '&gt;');
out = strrep(out, '"', '&quot;');
end

function rel = relPath(pathText, rootText)
pathText = char(pathText);
rootText = char(rootText);
prefix = [rootText filesep];
if startsWith(pathText, prefix)
    rel = pathText(numel(prefix)+1:end);
else
    rel = pathText;
end
end

function name = localFileName(pathText)
[~, base, ext] = fileparts(char(pathText));
name = [base ext];
end
