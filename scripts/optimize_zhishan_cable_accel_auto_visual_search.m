function result = optimize_zhishan_cable_accel_auto_visual_search()
%OPTIMIZE_ZHISHAN_CABLE_ACCEL_AUTO_VISUAL_SEARCH Dense display-only search.
%   Searches cable-acceleration display thresholds and top-RMS segment
%   removal settings, then exports a no-manual-pick recommendation. This
%   does not change formal spectrum/force calculation settings.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
outputDir = fullfile(stableDir, 'auto_visual_search');
reportDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([33258 21160 35270 35273 25512 33616 23637 31034])]);
if ~exist(outputDir, 'dir'), mkdir(outputDir); end
if ~exist(reportDir, 'dir'), mkdir(reportDir); end

startDate = '2026-03-01';
endDate = '2026-03-31';
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
thresholdGrid = [3 5 7.5 10 12.5 15 17.5 20 25 30 40 50 75 100];
segmentPctGrid = [0 1 2 3 5 8 10 12 15];
binMinutes = 30;
segmentMinutes = 30;
maxSearchSamples = 200000;

cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));
cfg.notify.enabled = false;
cfgLoad = removeCableAccelThresholds(cfg);
subfolder = bms.config.ConfigReader.getSubfolder(cfgLoad, 'cable_accel', '');

t0 = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
t1 = datetime(endDate, 'InputFormat', 'yyyy-MM-dd') + days(1);
binEdges = t0:minutes(binMinutes):t1;
binCenters = binEdges(1:end-1)' + minutes(binMinutes / 2);
segmentEdges = t0:minutes(segmentMinutes):t1;

allRows = {};
selectedRows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    fprintf('auto visual search %s\n', pointId);
    [times, values] = load_timeseries_range(dataRoot, subfolder, pointId, ...
        startDate, endDate, cfgLoad, 'cable_accel');
    times = times(:);
    values = double(values(:));
    validBase = isfinite(values) & ~isnat(times);
    baseCount = nnz(validBase);
    if baseCount == 0
        warning('%s has no finite cable acceleration data.', pointId);
        continue;
    end
    searchStride = max(1, ceil(numel(values) / maxSearchSamples));
    searchTimes = times(1:searchStride:end);
    searchValues = values(1:searchStride:end);
    searchBase = isfinite(searchValues) & ~isnat(searchTimes);
    searchBaseCount = nnz(searchBase);

    formalClean = applyDisplayPolicy(times, values, 100, 0, segmentEdges);
    formalMetric = binnedMetric(times, formalClean, binEdges, binCenters);
    formalSearchClean = applyDisplayPolicy(searchTimes, searchValues, 100, 0, segmentEdges);
    formalSearchMetric = binnedMetric(searchTimes, formalSearchClean, binEdges, binCenters);
    pointRows = {};
    metricCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    for th = thresholdGrid
        for segPct = segmentPctGrid
            metric = computeCandidate(searchTimes, searchValues, searchBaseCount, binEdges, ...
                binCenters, segmentEdges, th, segPct);
            metricCache(cacheKey(th, segPct)) = metric;
            maxReduction = pctReduction(formalSearchMetric.rmsMax, metric.rmsMax);
            p95Reduction = pctReduction(formalSearchMetric.rmsP95, metric.rmsP95);
            widthReduction = pctReduction(formalSearchMetric.bandWidthP95Median, ...
                metric.bandWidthP95Median);
            pointRows(end+1, :) = {pointId, th, segPct, ...
                strategyText(th, segPct, segmentMinutes), searchBaseCount, ...
                metric.keepPct, metric.rmsMax, metric.rmsP95, ...
                metric.bandWidthP95Median, maxReduction, p95Reduction, ...
                widthReduction}; %#ok<AGROW>
        end
    end
    pointTable = cell2table(pointRows, 'VariableNames', matrixColumns());
    [~, autoClass, minKeepPct] = selectAutoCandidate(pointTable);
    fullTable = recomputeShortlist(pointTable, times, values, baseCount, ...
        binEdges, binCenters, segmentEdges, formalMetric, minKeepPct);
    [selected, autoClass, minKeepPct, rationale] = selectAutoCandidate(fullTable, ...
        autoClass, minKeepPct);
    selectedMetric = computeCandidate(times, values, baseCount, binEdges, ...
        binCenters, segmentEdges, selected.ThresholdAbsMps2(1), ...
        selected.SegmentFilterTopPctRMS30(1));
    selected.BaseFiniteCount = baseCount;
    selected.KeepPct = selectedMetric.keepPct;
    selected.RMS30Max = selectedMetric.rmsMax;
    selected.RMS30P95 = selectedMetric.rmsP95;
    selected.BandWidthP95Median = selectedMetric.bandWidthP95Median;
    selected.RMS30MaxReductionPct = pctReduction(formalMetric.rmsMax, selectedMetric.rmsMax);
    selected.RMS30P95ReductionPct = pctReduction(formalMetric.rmsP95, selectedMetric.rmsP95);
    selected.BandWidthReductionPct = pctReduction(formalMetric.bandWidthP95Median, ...
        selectedMetric.bandWidthP95Median);
    selected.AutoClass = {autoClass};
    selected.AutoMinKeepPct = minKeepPct;
    selected.Rationale = {rationale};
    selected.PlotPath = {''};

    outImage = fullfile(reportDir, sprintf( ...
        'CableAccelAutoVisualReport_%s_20260301_20260331.jpg', pointId));
    plotPaths{i} = plotCandidate(outImage, pointId, binCenters, selectedMetric, ...
        selected.Strategy{1}, selected.KeepPct(1), selected.RMS30Max(1), ...
        selected.RMS30P95(1), autoClass, startDate, endDate);
    selected.PlotPath = plotPaths(i);

    fullTable.AutoClass = repmat({autoClass}, height(fullTable), 1);
    fullTable.AutoMinKeepPct = repmat(minKeepPct, height(fullTable), 1);
    fullTable.AutoScore = scoreCandidates(fullTable, minKeepPct);
    fullTable.AutoSelected = isSelectedRow(fullTable, selected);
    allRows = [allRows; table2cell(fullTable)]; %#ok<AGROW>
    selectedRows = [selectedRows; table2cell(selected)]; %#ok<AGROW>
end

scoreMatrix = cell2table(allRows, 'VariableNames', matrixColumnsWithScores());
selectedManifest = cell2table(selectedRows, 'VariableNames', selectedColumns());

contactSheet = buildContactSheet(plotPaths, selectedManifest, reportDir, ...
    'CableAccelAutoVisualReport_ContactSheet.jpg');
reviewBoard = buildContactSheet(plotPaths, selectedManifest, reportDir, ...
    'CableAccelAutoVisualReport_ReviewBoard.jpg');
manifestXlsx = fullfile(reportDir, 'CableAccelAutoVisualReport_manifest.xlsx');
manifestCsv = fullfile(reportDir, 'CableAccelAutoVisualReport_manifest.csv');
scoreXlsx = fullfile(outputDir, 'CableAccelAutoVisualSearch_score_matrix.xlsx');
scoreCsv = fullfile(outputDir, 'CableAccelAutoVisualSearch_score_matrix.csv');
paramJson = fullfile(outputDir, 'CableAccelAutoVisualSearch_parameters.json');
htmlPath = fullfile(outputDir, 'index.html');
reportHtml = fullfile(reportDir, 'index.html');
readmePath = fullfile(outputDir, 'README.md');

writetable(selectedManifest, manifestXlsx, 'Sheet', 'manifest');
writetable(selectedManifest, manifestCsv, 'Encoding', 'UTF-8');
writetable(scoreMatrix, scoreXlsx, 'Sheet', 'score_matrix');
writetable(scoreMatrix, scoreCsv, 'Encoding', 'UTF-8');
writeJson(paramJson, selectedManifest);
writeHtml(htmlPath, selectedManifest, scoreMatrix, contactSheet, reviewBoard, reportDir);
writeReportHtml(reportHtml, selectedManifest, contactSheet, reviewBoard);
writeReadme(readmePath, selectedManifest, htmlPath, reportHtml);

result = struct();
result.output_dir = outputDir;
result.report_dir = reportDir;
result.html = htmlPath;
result.report_html = reportHtml;
result.manifest = manifestXlsx;
result.manifest_csv = manifestCsv;
result.score_matrix = scoreXlsx;
result.score_matrix_csv = scoreCsv;
result.parameters_json = paramJson;
result.contact_sheet = contactSheet;
result.review_board = reviewBoard;

fprintf('auto visual search html %s\n', htmlPath);
fprintf('auto visual report html %s\n', reportHtml);
disp(selectedManifest(:, {'PointID','AutoClass','AutoMinKeepPct', ...
    'Strategy','KeepPct','RMS30Max','RMS30P95'}));
end

function names = matrixColumns()
names = {'PointID','ThresholdAbsMps2','SegmentFilterTopPctRMS30', ...
    'Strategy','BaseFiniteCount','KeepPct','RMS30Max','RMS30P95', ...
    'BandWidthP95Median','RMS30MaxReductionPct','RMS30P95ReductionPct', ...
    'BandWidthReductionPct'};
end

function names = matrixColumnsWithScores()
names = [matrixColumns(), {'AutoClass','AutoMinKeepPct','AutoScore','AutoSelected'}];
end

function names = selectedColumns()
names = [matrixColumns(), {'AutoClass','AutoMinKeepPct','Rationale','PlotPath'}];
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

function metric = computeCandidate(times, values, baseCount, binEdges, ...
        binCenters, segmentEdges, thresholdAbs, segmentPct)
clean = applyDisplayPolicy(times, values, thresholdAbs, segmentPct, segmentEdges);
metric = binnedMetric(times, clean, binEdges, binCenters);
metric.keepPct = 100 * nnz(isfinite(clean) & ~isnat(times)) / baseCount;
end

function clean = applyDisplayPolicy(times, values, thresholdAbs, segmentPct, segmentEdges)
clean = values;
clean(abs(clean) > thresholdAbs) = NaN;
if segmentPct > 0
    clean = applyTopRmsSegmentMask(times, clean, segmentEdges, segmentPct);
end
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
if isempty(vals)
    return;
end
rmsValues = accumarray(idx, vals, [nSegments 1], ...
    @(x) sqrt(mean(x.^2, 'omitnan')), NaN);
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
metric.bandWidthP95Median = NaN;
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
metric.rms = accumarray(idx, vals, [nBins 1], ...
    @(x) sqrt(mean(x.^2, 'omitnan')), NaN);
finiteRms = metric.rms(isfinite(metric.rms));
if ~isempty(finiteRms)
    metric.rmsMax = max(finiteRms);
    metric.rmsP95 = prctile(finiteRms, 95);
end
width = metric.p95 - metric.p05;
width = width(isfinite(width));
if ~isempty(width)
    metric.bandWidthP95Median = median(width, 'omitnan');
end
end

function fullTable = recomputeShortlist(pointTable, times, values, baseCount, ...
        binEdges, binCenters, segmentEdges, formalMetric, minKeepPct)
relaxed = pointTable(pointTable.KeepPct >= minKeepPct - 3 & ...
    isfinite(pointTable.RMS30Max), :);
if isempty(relaxed)
    relaxed = pointTable(isfinite(pointTable.RMS30Max), :);
end
relaxed.AutoScore = scoreCandidates(relaxed, max(minKeepPct - 3, 0));
topScore = sortrows(relaxed, {'AutoScore','KeepPct'}, {'descend','descend'});
topRms = sortrows(relaxed, {'RMS30Max','KeepPct'}, {'ascend','descend'});
anchor = pointTable(pointTable.ThresholdAbsMps2 == 20 & ...
    pointTable.SegmentFilterTopPctRMS30 == 10, :);
baseCols = matrixColumns();
shortlist = [topScore(1:min(10, height(topScore)), baseCols); ...
    topRms(1:min(10, height(topRms)), baseCols)]; %#ok<AGROW>
if ~isempty(anchor)
    shortlist = [shortlist; anchor(:, baseCols)]; %#ok<AGROW>
end
[~, uniqueIdx] = unique([shortlist.ThresholdAbsMps2 shortlist.SegmentFilterTopPctRMS30], ...
    'rows', 'stable');
shortlist = shortlist(uniqueIdx, :);

rows = {};
for i = 1:height(shortlist)
    th = shortlist.ThresholdAbsMps2(i);
    segPct = shortlist.SegmentFilterTopPctRMS30(i);
    metric = computeCandidate(times, values, baseCount, binEdges, ...
        binCenters, segmentEdges, th, segPct);
    rows(end+1, :) = {shortlist.PointID{i}, th, segPct, ...
        strategyText(th, segPct, 30), baseCount, metric.keepPct, ...
        metric.rmsMax, metric.rmsP95, metric.bandWidthP95Median, ...
        pctReduction(formalMetric.rmsMax, metric.rmsMax), ...
        pctReduction(formalMetric.rmsP95, metric.rmsP95), ...
        pctReduction(formalMetric.bandWidthP95Median, ...
        metric.bandWidthP95Median)}; %#ok<AGROW>
end
fullTable = cell2table(rows, 'VariableNames', matrixColumns());
end

function [selected, autoClass, minKeepPct, rationale] = selectAutoCandidate(pointTable, autoClassIn, minKeepPctIn)
anchor = pointTable(pointTable.ThresholdAbsMps2 == 20 & ...
    pointTable.SegmentFilterTopPctRMS30 == 10, :);
if isempty(anchor)
    anchor = sortrows(pointTable, {'ThresholdAbsMps2','SegmentFilterTopPctRMS30'}, ...
        {'ascend','descend'});
    anchor = anchor(1, :);
end
anchorKeep = anchor.KeepPct(1);
if nargin >= 3 && ~isempty(autoClassIn) && ~isempty(minKeepPctIn)
    autoClass = autoClassIn;
    minKeepPct = minKeepPctIn;
else
    if anchorKeep < 55
        minKeepPct = 50;
        autoClass = 'severe_noise';
    elseif anchorKeep < 70
        minKeepPct = 55;
        autoClass = 'moderate_noise';
    elseif anchorKeep < 85
        minKeepPct = 60;
        autoClass = 'mixed_noise';
    else
        minKeepPct = 80;
        autoClass = 'stable_signal';
    end
end

eligible = pointTable(pointTable.KeepPct >= minKeepPct & ...
    isfinite(pointTable.RMS30Max), :);
if isempty(eligible)
    eligible = pointTable(isfinite(pointTable.RMS30Max), :);
end
eligible.AutoScore = scoreCandidates(eligible, minKeepPct);
eligible = sortrows(eligible, {'AutoScore','KeepPct'}, {'descend','descend'});
best = eligible(1, :);
cleanest = sortrows(eligible, {'RMS30Max','KeepPct'}, {'ascend','descend'});
cleanest = cleanest(1, :);
if cleanest.RMS30Max(1) <= best.RMS30Max(1) * 0.94 && ...
        best.KeepPct(1) - cleanest.KeepPct(1) <= 3.0
    selected = cleanest(1, matrixColumns());
    policyText = 'selected cleaner candidate because RMS30 improves at least 6% with keep loss <= 3%';
else
    nearBest = eligible(eligible.RMS30Max <= best.RMS30Max * 1.015, :);
    nearBest = sortrows(nearBest, {'KeepPct','RMS30Max'}, {'descend','ascend'});
    selected = nearBest(1, matrixColumns());
    policyText = 'selected highest-keep candidate within 1.5% RMS30 of best score tier';
end
rationale = sprintf('%s: anchor keep %.2f%% -> min keep %.0f%%; %s', ...
    autoClass, anchorKeep, minKeepPct, policyText);
end

function score = scoreCandidates(T, minKeepPct)
score = T.RMS30MaxReductionPct;
score = score + 0.35 * finiteOrZero(T.RMS30P95ReductionPct);
score = score + 0.12 * finiteOrZero(T.BandWidthReductionPct);
score = score - 1.8 * max(0, minKeepPct - T.KeepPct);
score = score - 0.06 * max(0, 70 - T.KeepPct);
score = score - 0.10 * T.SegmentFilterTopPctRMS30;
score(T.KeepPct < minKeepPct) = -Inf;
end

function y = finiteOrZero(x)
y = x;
y(~isfinite(y)) = 0;
end

function tf = isSelectedRow(T, selected)
tf = strcmp(T.PointID, selected.PointID{1}) & ...
    abs(T.ThresholdAbsMps2 - selected.ThresholdAbsMps2(1)) < 1e-9 & ...
    abs(T.SegmentFilterTopPctRMS30 - selected.SegmentFilterTopPctRMS30(1)) < 1e-9;
end

function value = pctReduction(beforeValue, afterValue)
if ~isfinite(beforeValue) || beforeValue <= 0 || ~isfinite(afterValue)
    value = NaN;
else
    value = 100 * (beforeValue - afterValue) / max(beforeValue, eps);
end
end

function text = strategyText(thresholdAbs, segmentPct, segmentMinutes)
text = sprintf('abs<=%g display', thresholdAbs);
if segmentPct > 0
    text = sprintf('%s + drop top %g%% RMS%d segments', ...
        text, segmentPct, segmentMinutes);
end
end

function key = cacheKey(thresholdAbs, segmentPct)
key = sprintf('th%g_seg%g', thresholdAbs, segmentPct);
end

function plotPath = plotCandidate(plotPath, pointId, binCenters, metric, ...
        strategy, keepPct, rmsMax, rmsP95, autoClass, startDate, endDate)
fig = figure('Visible', 'off', 'Position', [100 100 1300 720], 'Color', 'w');
tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile;
hold(ax1, 'on');
h95 = fillBand(ax1, binCenters, metric.p05, metric.p95, [0.78 0.86 0.93], 0.45, '5%~95%');
h75 = fillBand(ax1, binCenters, metric.p25, metric.p75, [0.23 0.53 0.73], 0.58, '25%~75%');
hMed = plot(ax1, binCenters, metric.p50, 'Color', [0.02 0.20 0.34], ...
    'LineWidth', 1.35, 'DisplayName', 'median');
hold(ax1, 'off');
grid(ax1, 'on');
grid(ax1, 'minor');
ylabel(ax1, 'm/s^2');
title(ax1, sprintf('%s cable acceleration auto visual | %s to %s', ...
    pointId, startDate, endDate), 'Interpreter', 'none');
subtitle(ax1, sprintf('%s | %s | keep %.2f%%', autoClass, strategy, keepPct), ...
    'Interpreter', 'none');
legendHandles = [h95 h75 hMed];
legendHandles = legendHandles(isgraphics(legendHandles));
if ~isempty(legendHandles)
    legend(ax1, legendHandles, 'Location', 'northeast', 'Box', 'off');
end
xtickformat(ax1, 'yyyy-MM-dd');

ax2 = nexttile;
plot(ax2, binCenters, metric.rms, 'Color', [0.58 0.32 0.08], 'LineWidth', 1.15);
grid(ax2, 'on');
grid(ax2, 'minor');
ylabel(ax2, 'RMS30 (m/s^2)');
xlabel(ax2, 'time');
title(ax2, sprintf('RMS30 max %.2f | RMS30 P95 %.2f | auto visual search', ...
    rmsMax, rmsP95), 'Interpreter', 'none');
xtickformat(ax2, 'yyyy-MM-dd');
linkaxes([ax1 ax2], 'x');
xlim(ax1, [binCenters(1), binCenters(end)]);

exportgraphics(fig, plotPath, 'Resolution', 150);
close(fig);
end

function firstHandle = fillBand(ax, x, lo, hi, color, alphaValue, name)
firstHandle = gobjects(0);
mask = isfinite(lo) & isfinite(hi) & ~isnat(x);
if ~any(mask)
    return;
end
idx = find(mask);
runStart = [1; find(diff(idx) > 1) + 1];
runEnd = [runStart(2:end) - 1; numel(idx)];
for r = 1:numel(runStart)
    runIdx = idx(runStart(r):runEnd(r));
    if numel(runIdx) < 2
        continue;
    end
    xv = x(runIdx);
    loRun = lo(runIdx);
    hiRun = hi(runIdx);
    label = '';
    if r == 1
        label = name;
    end
    h = patch(ax, [xv; flipud(xv)], [loRun; flipud(hiRun)], color, ...
        'FaceAlpha', alphaValue, 'EdgeColor', 'none', 'DisplayName', label);
    if isempty(firstHandle)
        firstHandle = h;
    end
end
end

function outPath = buildContactSheet(plotPaths, manifest, outputDir, fileName)
fig = figure('Visible', 'off', 'Position', [100 100 2200 1500], 'Color', 'w');
tiledlayout(fig, 2, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
for i = 1:numel(plotPaths)
    ax = nexttile;
    image(ax, imread(plotPaths{i}));
    axis(ax, 'image');
    axis(ax, 'off');
    title(ax, sprintf('%s | %s | keep %.1f%% | RMS30 %.2f', ...
        manifest.PointID{i}, manifest.AutoClass{i}, ...
        manifest.KeepPct(i), manifest.RMS30Max(i)), 'Interpreter', 'none');
end
outPath = fullfile(outputDir, fileName);
exportgraphics(fig, outPath, 'Resolution', 150);
close(fig);
end

function writeJson(path, manifest)
payload = struct();
payload.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
payload.scope = 'display_report_review_only';
payload.formal_policy = 'Formal cable acceleration remains daily_median + [-100,100] m/s^2.';
payload.selection_rule = 'Dense grid search; auto min keep from abs<=20/drop-top-10 anchor; keep higher-retention candidate only when RMS30 is within 1.5%, otherwise prefer a materially cleaner candidate when keep loss is <=3%.';
payload.parameters = table2struct(manifest);
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(payload, 'PrettyPrint', true));
end

function writeHtml(path, manifest, scoreMatrix, contactSheet, reviewBoard, reportDir)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
[~, reportDirName] = fileparts(reportDir);
reportRel = ['../../' reportDirName '/index.html'];
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Auto Visual Search</title>\n');
writeCss(fid);
fprintf(fid, '</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Auto Visual Search</h1>\n');
fprintf(fid, '<div class="note">Non-LLM dense search. Formal spectrum/force calculation remains <code>daily_median + [-100,100] m/s^2</code>. Report-ready folder: <a href="%s">open images</a>.</div>\n', htmlText(reportRel));
writeManifestTable(fid, manifest);
fprintf(fid, '<h2>Contact Sheet</h2><div class="figure"><img src="../../%s/%s" alt="contact sheet"></div>\n', htmlText(reportDirName), htmlText(localFileName(contactSheet)));
fprintf(fid, '<h2>Review Board</h2><div class="figure"><img src="../../%s/%s" alt="review board"></div>\n', htmlText(reportDirName), htmlText(localFileName(reviewBoard)));
fprintf(fid, '<h2>Selected Candidate Rows</h2>\n');
writeScoreTable(fid, scoreMatrix(scoreMatrix.AutoSelected, :));
fprintf(fid, '<h2>Top Score Matrix</h2>\n');
writeScoreTable(fid, topRowsByPoint(scoreMatrix, 8));
fprintf(fid, '</body>\n</html>\n');
end

function writeReportHtml(path, manifest, contactSheet, reviewBoard)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Auto Visual Report Images</title>\n');
writeCss(fid);
fprintf(fid, '</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Auto Visual Report Images</h1>\n');
fprintf(fid, '<div class="note">Display/report-review only. Formal spectrum/force calculation remains <code>daily_median + [-100,100] m/s^2</code>.</div>\n');
writeManifestTable(fid, manifest);
fprintf(fid, '<h2>Contact Sheet</h2><div class="figure"><img src="%s" alt="contact sheet"></div>\n', htmlText(localFileName(contactSheet)));
fprintf(fid, '<h2>Review Board</h2><div class="figure"><img src="%s" alt="review board"></div>\n', htmlText(localFileName(reviewBoard)));
fprintf(fid, '<h2>Per-Point Images</h2><div class="grid">\n');
for i = 1:height(manifest)
    fprintf(fid, '<div class="figure"><h2>%s | %s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(manifest.PointID{i}), htmlText(manifest.AutoClass{i}), ...
        htmlText(localFileName(manifest.PlotPath{i})), htmlText(manifest.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function writeCss(fid)
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #0f766e;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.severe_noise{background:#fee2e2}.moderate_noise{background:#fef3c7}.mixed_noise{background:#dbeafe}.stable_signal{background:#dcfce7}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;} a{color:#075da8;text-decoration:none;}');
fprintf(fid, '</style>\n');
end

function writeManifestTable(fid, manifest)
fprintf(fid, '<h2>Selected Manifest</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Class</th><th>Min keep</th><th>Strategy</th><th>Keep %%</th><th>RMS30 max</th><th>RMS30 P95</th><th>Rationale</th></tr>\n');
for i = 1:height(manifest)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td class="num">%.0f</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td>%s</td></tr>\n', ...
        htmlText(manifest.AutoClass{i}), htmlText(manifest.PointID{i}), ...
        htmlText(manifest.AutoClass{i}), manifest.AutoMinKeepPct(i), ...
        htmlText(manifest.Strategy{i}), manifest.KeepPct(i), ...
        manifest.RMS30Max(i), manifest.RMS30P95(i), ...
        htmlText(manifest.Rationale{i}));
end
fprintf(fid, '</table>\n');
end

function writeScoreTable(fid, T)
T = sortrows(T, {'PointID','AutoScore'}, {'ascend','descend'});
fprintf(fid, '<table><tr><th>Point</th><th>Threshold</th><th>Drop top %%</th><th>Keep %%</th><th>RMS30 max</th><th>RMS30 P95</th><th>Score</th><th>Selected</th><th>Strategy</th></tr>\n');
for i = 1:height(T)
    fprintf(fid, '<tr class="%s"><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.2f</td><td class="num">%d</td><td>%s</td></tr>\n', ...
        htmlText(T.AutoClass{i}), htmlText(T.PointID{i}), ...
        T.ThresholdAbsMps2(i), T.SegmentFilterTopPctRMS30(i), ...
        T.KeepPct(i), T.RMS30Max(i), T.RMS30P95(i), T.AutoScore(i), ...
        T.AutoSelected(i), htmlText(T.Strategy{i}));
end
fprintf(fid, '</table>\n');
end

function out = topRowsByPoint(scoreMatrix, n)
points = unique(scoreMatrix.PointID, 'stable');
out = table();
for i = 1:numel(points)
    rows = scoreMatrix(strcmp(scoreMatrix.PointID, points{i}), :);
    rows = sortrows(rows, {'AutoScore','KeepPct'}, {'descend','descend'});
    out = [out; rows(1:min(n, height(rows)), :)]; %#ok<AGROW>
end
end

function writeReadme(path, manifest, htmlPath, reportHtml)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Auto Visual Search\n\n');
fprintf(fid, '- Open `%s` for the search page.\n', localFileName(htmlPath));
fprintf(fid, '- Report images: `%s`.\n', reportHtml);
fprintf(fid, '- Scope: display/report review only.\n');
fprintf(fid, '- Formal policy remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '| Point | Class | Min keep | Strategy | Keep %% | RMS30 max |\n');
fprintf(fid, '|---|---|---:|---|---:|---:|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | %s | %.0f | %s | %.3f | %.3f |\n', ...
        manifest.PointID{i}, manifest.AutoClass{i}, manifest.AutoMinKeepPct(i), ...
        manifest.Strategy{i}, manifest.KeepPct(i), manifest.RMS30Max(i));
end
end

function out = htmlText(value)
out = char(string(value));
out = strrep(out, '&', '&amp;');
out = strrep(out, '<', '&lt;');
out = strrep(out, '>', '&gt;');
out = strrep(out, '"', '&quot;');
end

function name = localFileName(pathText)
[~, base, ext] = fileparts(char(pathText));
name = [base ext];
end
