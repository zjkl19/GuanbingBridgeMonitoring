function result = build_zhishan_cable_accel_ultra_clean_review()
%BUILD_ZHISHAN_CABLE_ACCEL_ULTRA_CLEAN_REVIEW Search below-50% backups.
%   Display/review only. Keeps the current auto-visual package as default
%   and searches only CF-2/CF-7 below the 50% keep floor so the remaining
%   manual tradeoff is quantified instead of guessed.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
outputDir = fullfile(stableDir, 'ultra_clean_review');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

startDate = '2026-03-01';
endDate = '2026-03-31';
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
focusPoints = {'CF-2','CF-7'};
thresholdGrid = [7.5 10 12.5 15 17.5 20];
segmentPctGrid = [12 15 18 20 25 30];
keepFloors = [45 40 35];
binMinutes = 30;
segmentMinutes = 30;
maxSearchSamples = 300000;

autoVisualDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([33258 21160 35270 35273 25512 33616 23637 31034])]);
autoManifestPath = fullfile(autoVisualDir, 'CableAccelAutoVisualReport_manifest.csv');
autoManifest = readtable(autoManifestPath, 'Encoding', 'UTF-8');

cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));
cfg.notify.enabled = false;
cfgLoad = removeCableAccelThresholds(cfg);
subfolder = bms.config.ConfigReader.getSubfolder(cfgLoad, 'cable_accel', '');

t0 = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
t1 = datetime(endDate, 'InputFormat', 'yyyy-MM-dd') + days(1);
binEdges = t0:minutes(binMinutes):t1;
binCenters = binEdges(1:end-1)' + minutes(binMinutes / 2);
segmentEdges = t0:minutes(segmentMinutes):t1;

packageRows = {};
decisionRows = {};
sampleRows = {};
fullRows = {};
packagePaths = cell(numel(points), 1);
autoComparePaths = cell(numel(focusPoints), 1);
ultraComparePaths = cell(numel(focusPoints), 1);

for i = 1:numel(points)
    pointId = points{i};
    autoRow = rowFor(autoManifest, 'PointID', pointId);
    packagePath = fullfile(outputDir, sprintf( ...
        'UltraCleanPackage_%s_20260301_20260331.jpg', pointId));
    copyfile(asText(autoRow.PlotPath), packagePath, 'f');
    packagePaths{i} = packagePath;
    packageRows(end+1, :) = {pointId, 'auto_visual_default', ...
        autoRow.ThresholdAbsMps2(1), autoRow.SegmentFilterTopPctRMS30(1), ...
        autoRow.KeepPct(1), autoRow.RMS30Max(1), autoRow.RMS30P95(1), ...
        'unchanged from current auto-visual package', packagePath}; %#ok<AGROW>
end

for i = 1:numel(focusPoints)
    pointId = focusPoints{i};
    fprintf('ultra clean review %s\n', pointId);
    autoRow = rowFor(autoManifest, 'PointID', pointId);
    [times, values] = load_timeseries_range(dataRoot, subfolder, pointId, ...
        startDate, endDate, cfgLoad, 'cable_accel');
    times = times(:);
    values = double(values(:));
    baseCount = nnz(isfinite(values) & ~isnat(times));

    [sampleTable, fullTable, selected, selection] = searchPointBelowFloor( ...
        pointId, times, values, baseCount, binEdges, binCenters, ...
        segmentEdges, thresholdGrid, segmentPctGrid, keepFloors, ...
        maxSearchSamples, autoRow.KeepPct(1), autoRow.RMS30Max(1));
    sampleRows = [sampleRows; table2cell(sampleTable)]; %#ok<AGROW>
    fullRows = [fullRows; table2cell(fullTable)]; %#ok<AGROW>

    metric = computeCandidate(times, values, baseCount, binEdges, ...
        binCenters, segmentEdges, selected.ThresholdAbsMps2(1), ...
        selected.SegmentFilterTopPctRMS30(1));
    selectedPath = fullfile(outputDir, sprintf( ...
        'UltraCleanSelected_%s_20260301_20260331.jpg', pointId));
    plotCandidate(selectedPath, pointId, binCenters, metric, ...
        selected.Strategy{1}, selected.KeepPct(1), selected.RMS30Max(1), ...
        selected.RMS30P95(1), selection, startDate, endDate);

    autoComparePath = fullfile(outputDir, sprintf( ...
        'AutoVisualCompare_%s_20260301_20260331.jpg', pointId));
    copyfile(asText(autoRow.PlotPath), autoComparePath, 'f');
    autoComparePaths{i} = autoComparePath;
    ultraComparePaths{i} = selectedPath;

    pkgIdx = find(strcmp(string(points), pointId), 1);
    packagePaths{pkgIdx} = fullfile(outputDir, sprintf( ...
        'UltraCleanPackage_%s_20260301_20260331.jpg', pointId));
    copyfile(selectedPath, packagePaths{pkgIdx}, 'f');
    packageRows{pkgIdx, 2} = selection.Recommendation;
    packageRows{pkgIdx, 3} = selected.ThresholdAbsMps2(1);
    packageRows{pkgIdx, 4} = selected.SegmentFilterTopPctRMS30(1);
    packageRows{pkgIdx, 5} = selected.KeepPct(1);
    packageRows{pkgIdx, 6} = selected.RMS30Max(1);
    packageRows{pkgIdx, 7} = selected.RMS30P95(1);
    packageRows{pkgIdx, 8} = selection.Reason;
    packageRows{pkgIdx, 9} = packagePaths{pkgIdx};

    decisionRows(end+1, :) = {pointId, ...
        autoRow.ThresholdAbsMps2(1), autoRow.SegmentFilterTopPctRMS30(1), ...
        autoRow.KeepPct(1), autoRow.RMS30Max(1), ...
        selected.ThresholdAbsMps2(1), selected.SegmentFilterTopPctRMS30(1), ...
        selected.KeepPct(1), selected.RMS30Max(1), selected.RMS30P95(1), ...
        autoRow.KeepPct(1) - selected.KeepPct(1), ...
        pctReduction(autoRow.RMS30Max(1), selected.RMS30Max(1)), ...
        selection.Recommendation, selection.Reason, ...
        autoComparePath, selectedPath}; %#ok<AGROW>
end

packageManifest = cell2table(packageRows, 'VariableNames', packageColumns());
decision = cell2table(decisionRows, 'VariableNames', decisionColumns());
sampleMatrix = cell2table(sampleRows, 'VariableNames', matrixColumns());
fullMatrix = cell2table(fullRows, 'VariableNames', matrixColumns());

contactSheet = buildContactSheet(packagePaths, packageManifest, outputDir, ...
    'CableAccelUltraCleanPackage_ContactSheet.jpg');
boardPath = buildCompareBoard(autoComparePaths, ultraComparePaths, decision, outputDir);
manifestXlsx = fullfile(outputDir, 'CableAccelUltraCleanPackage_manifest.xlsx');
manifestCsv = fullfile(outputDir, 'CableAccelUltraCleanPackage_manifest.csv');
decisionXlsx = fullfile(outputDir, 'CableAccelUltraCleanReview_decision.xlsx');
decisionCsv = fullfile(outputDir, 'CableAccelUltraCleanReview_decision.csv');
sampleCsv = fullfile(outputDir, 'CableAccelUltraCleanReview_sample_matrix.csv');
fullCsv = fullfile(outputDir, 'CableAccelUltraCleanReview_full_shortlist.csv');
summaryJson = fullfile(outputDir, 'CableAccelUltraCleanReview_summary.json');
htmlPath = fullfile(outputDir, 'index.html');
readmePath = fullfile(outputDir, 'README.md');

writetable(packageManifest, manifestXlsx, 'Sheet', 'manifest');
writetable(packageManifest, manifestCsv, 'Encoding', 'UTF-8');
writetable(decision, decisionXlsx, 'Sheet', 'decision');
writetable(decision, decisionCsv, 'Encoding', 'UTF-8');
writetable(sampleMatrix, sampleCsv, 'Encoding', 'UTF-8');
writetable(fullMatrix, fullCsv, 'Encoding', 'UTF-8');
writeJson(summaryJson, packageManifest, decision);
writeHtml(htmlPath, packageManifest, decision, contactSheet, boardPath);
writeReadme(readmePath, packageManifest, decision, contactSheet, boardPath);

result = struct();
result.output_dir = outputDir;
result.html = htmlPath;
result.board = boardPath;
result.contact_sheet = contactSheet;
result.manifest = manifestXlsx;
result.manifest_csv = manifestCsv;
result.decision = decisionXlsx;
result.decision_csv = decisionCsv;
result.summary_json = summaryJson;
result.sample_matrix_csv = sampleCsv;
result.full_shortlist_csv = fullCsv;

fprintf('ultra clean review %s\n', htmlPath);
disp(decision(:, {'PointID','AutoKeepPct','UltraKeepPct', ...
    'KeepLossPct','RMS30GainVsAutoPct','Recommendation'}));
end

function names = packageColumns()
names = {'PointID','Source','ThresholdAbsMps2','SegmentFilterTopPctRMS30', ...
    'KeepPct','RMS30Max','RMS30P95','Reason','PlotPath'};
end

function names = decisionColumns()
names = {'PointID','AutoThresholdAbsMps2','AutoSegmentTopPctRMS30', ...
    'AutoKeepPct','AutoRMS30Max','UltraThresholdAbsMps2', ...
    'UltraSegmentTopPctRMS30','UltraKeepPct','UltraRMS30Max', ...
    'UltraRMS30P95','KeepLossPct','RMS30GainVsAutoPct', ...
    'Recommendation','Reason','AutoPlotPath','UltraPlotPath'};
end

function names = matrixColumns()
names = {'PointID','ThresholdAbsMps2','SegmentFilterTopPctRMS30', ...
    'Strategy','BaseFiniteCount','KeepPct','RMS30Max','RMS30P95', ...
    'BandWidthP95Median','KeepLossVsAutoPct','RMS30GainVsAutoPct', ...
    'CandidateScore'};
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

function [sampleTable, fullTable, selected, selection] = searchPointBelowFloor( ...
        pointId, times, values, baseCount, binEdges, binCenters, ...
        segmentEdges, thresholdGrid, segmentPctGrid, keepFloors, ...
        maxSearchSamples, autoKeepPct, autoRmsMax)
stride = max(1, ceil(numel(values) / maxSearchSamples));
searchTimes = times(1:stride:end);
searchValues = values(1:stride:end);
searchBaseCount = nnz(isfinite(searchValues) & ~isnat(searchTimes));

rows = {};
for th = thresholdGrid
    for segPct = segmentPctGrid
        metric = computeCandidate(searchTimes, searchValues, searchBaseCount, ...
            binEdges, binCenters, segmentEdges, th, segPct);
        keepLoss = autoKeepPct - metric.keepPct;
        gain = pctReduction(autoRmsMax, metric.rmsMax);
        score = gain - 0.35 * max(keepLoss, 0) - 0.08 * segPct;
        rows(end+1, :) = {pointId, th, segPct, strategyText(th, segPct), ...
            searchBaseCount, metric.keepPct, metric.rmsMax, metric.rmsP95, ...
            metric.bandWidthP95Median, keepLoss, gain, score}; %#ok<AGROW>
    end
end
sampleTable = cell2table(rows, 'VariableNames', matrixColumns());

shortlist = table();
for floorValue = keepFloors
    eligible = sampleTable(sampleTable.KeepPct >= floorValue & ...
        sampleTable.KeepPct < autoKeepPct - 0.25 & isfinite(sampleTable.RMS30Max), :);
    if ~isempty(eligible)
        eligible = sortrows(eligible, {'RMS30Max','KeepPct'}, {'ascend','descend'});
        shortlist = [shortlist; eligible(1:min(4, height(eligible)), :)]; %#ok<AGROW>
    end
end
scored = sampleTable(isfinite(sampleTable.CandidateScore) & ...
    sampleTable.KeepPct < autoKeepPct - 0.25, :);
if ~isempty(scored)
    scored = sortrows(scored, {'CandidateScore','KeepPct'}, {'descend','descend'});
    shortlist = [shortlist; scored(1:min(8, height(scored)), :)]; %#ok<AGROW>
end
if isempty(shortlist)
    shortlist = sortrows(sampleTable, {'RMS30Max','KeepPct'}, {'ascend','descend'});
    shortlist = shortlist(1:min(8, height(shortlist)), :);
end
[~, uniqueIdx] = unique([shortlist.ThresholdAbsMps2 shortlist.SegmentFilterTopPctRMS30], ...
    'rows', 'stable');
shortlist = shortlist(uniqueIdx, :);

fullRows = {};
for i = 1:height(shortlist)
    th = shortlist.ThresholdAbsMps2(i);
    segPct = shortlist.SegmentFilterTopPctRMS30(i);
    metric = computeCandidate(times, values, baseCount, binEdges, ...
        binCenters, segmentEdges, th, segPct);
    keepLoss = autoKeepPct - metric.keepPct;
    gain = pctReduction(autoRmsMax, metric.rmsMax);
    score = gain - 0.35 * max(keepLoss, 0) - 0.08 * segPct;
    fullRows(end+1, :) = {pointId, th, segPct, strategyText(th, segPct), ...
        baseCount, metric.keepPct, metric.rmsMax, metric.rmsP95, ...
        metric.bandWidthP95Median, keepLoss, gain, score}; %#ok<AGROW>
end
fullTable = cell2table(fullRows, 'VariableNames', matrixColumns());

selection = struct('Recommendation', 'not_recommended', ...
    'Reason', 'no below-50 candidate gives at least 10% RMS30 improvement');
selected = table();
for floorValue = keepFloors
    eligible = fullTable(fullTable.KeepPct >= floorValue & ...
        fullTable.KeepPct < autoKeepPct - 0.25 & ...
        fullTable.RMS30GainVsAutoPct >= 10 & isfinite(fullTable.RMS30Max), :);
    if isempty(eligible)
        continue;
    end
    eligible = sortrows(eligible, {'RMS30Max','KeepPct'}, {'ascend','descend'});
    selected = eligible(1, :);
    keepLoss = selected.KeepLossVsAutoPct(1);
    gain = selected.RMS30GainVsAutoPct(1);
    if gain >= 15 && keepLoss <= 12
        rec = 'optional_if_visual_priority';
    else
        rec = 'review_destructive_tradeoff';
    end
    selection.Recommendation = rec;
    selection.Reason = sprintf('below-50 floor %.0f%% candidate gains %.1f%% RMS30 for %.1f%% keep loss', ...
        floorValue, gain, keepLoss);
    break;
end
if isempty(selected)
    ranked = sortrows(fullTable, {'CandidateScore','KeepPct'}, {'descend','descend'});
    selected = ranked(1, :);
end
end

function metric = computeCandidate(times, values, baseCount, binEdges, ...
        binCenters, segmentEdges, thresholdAbs, segmentPct)
clean = applyDisplayPolicy(times, values, thresholdAbs, segmentPct, segmentEdges);
metric = binnedMetric(times, clean, binEdges, binCenters);
metric.keepPct = 100 * nnz(isfinite(clean) & ~isnat(times)) / max(baseCount, 1);
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
if ~any(valid), return; end
nSegments = numel(segmentEdges) - 1;
idx = discretize(times(valid), segmentEdges);
good = ~isnan(idx);
vals = clean(valid);
vals = vals(good);
idx = idx(good);
if isempty(vals), return; end
rmsValues = accumarray(idx, vals, [nSegments 1], ...
    @(x) sqrt(mean(x.^2, 'omitnan')), NaN);
ok = isfinite(rmsValues);
if ~any(ok), return; end
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
if ~any(valid), return; end
idx = discretize(times(valid), binEdges);
good = ~isnan(idx);
vals = values(valid);
vals = vals(good);
idx = idx(good);
if isempty(vals), return; end
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

function plotPath = plotCandidate(plotPath, pointId, binCenters, metric, ...
        strategy, keepPct, rmsMax, rmsP95, selection, startDate, endDate)
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
title(ax1, sprintf('%s cable acceleration ultra-clean review | %s to %s', ...
    pointId, startDate, endDate), 'Interpreter', 'none');
subtitle(ax1, sprintf('%s | %s | keep %.2f%%', ...
    selection.Recommendation, strategy, keepPct), 'Interpreter', 'none');
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
title(ax2, sprintf('RMS30 max %.2f | RMS30 P95 %.2f | below-50 review', ...
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
if ~any(mask), return; end
idx = find(mask);
runStart = [1; find(diff(idx) > 1) + 1];
runEnd = [runStart(2:end) - 1; numel(idx)];
for r = 1:numel(runStart)
    runIdx = idx(runStart(r):runEnd(r));
    if numel(runIdx) < 2, continue; end
    xv = x(runIdx);
    loRun = lo(runIdx);
    hiRun = hi(runIdx);
    label = '';
    if r == 1, label = name; end
    h = patch(ax, [xv; flipud(xv)], [loRun; flipud(hiRun)], color, ...
        'FaceAlpha', alphaValue, 'EdgeColor', 'none', 'DisplayName', label);
    if isempty(firstHandle), firstHandle = h; end
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
        manifest.PointID{i}, manifest.Source{i}, ...
        manifest.KeepPct(i), manifest.RMS30Max(i)), 'Interpreter', 'none');
end
outPath = fullfile(outputDir, fileName);
exportgraphics(fig, outPath, 'Resolution', 150);
close(fig);
end

function outPath = buildCompareBoard(autoPaths, ultraPaths, decision, outputDir)
fig = figure('Visible', 'off', 'Position', [100 100 2400 900], 'Color', 'w');
tiledlayout(fig, height(decision), 2, 'TileSpacing', 'compact', 'Padding', 'compact');
for i = 1:height(decision)
    ax1 = nexttile;
    image(ax1, imread(autoPaths{i}));
    axis(ax1, 'image');
    axis(ax1, 'off');
    title(ax1, sprintf('%s auto | keep %.1f%% | RMS30 %.2f', ...
        decision.PointID{i}, decision.AutoKeepPct(i), decision.AutoRMS30Max(i)), ...
        'Interpreter', 'none');
    ax2 = nexttile;
    image(ax2, imread(ultraPaths{i}));
    axis(ax2, 'image');
    axis(ax2, 'off');
    title(ax2, sprintf('below-50 | keep %.1f%% | gain %.1f%%', ...
        decision.UltraKeepPct(i), decision.RMS30GainVsAutoPct(i)), ...
        'Interpreter', 'none');
end
outPath = fullfile(outputDir, 'CableAccelUltraCleanReview_Board.jpg');
exportgraphics(fig, outPath, 'Resolution', 150);
close(fig);
end

function writeJson(path, manifest, decision)
payload = struct();
payload.scope = 'display_review_only';
payload.formal_policy = 'daily_median + [-100,100] m/s^2';
payload.selection_rule = 'Search below 50% keep only for CF-2/CF-7; choose highest keep floor that gains at least 10% RMS30.';
payload.package = table2struct(manifest);
payload.decision = table2struct(decision);
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(payload, 'PrettyPrint', true));
end

function writeHtml(path, manifest, decision, contactSheet, boardPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Ultra-Clean Review</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #991b1b;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.optional_if_visual_priority{background:#fee2e2}.review_destructive_tradeoff{background:#fef3c7}.not_recommended{background:#f3f4f6}.auto_visual_default{background:#e0f2fe}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Ultra-Clean Review</h1>\n');
fprintf(fid, '<div class="note">This page tests whether CF-2/CF-7 should go below the current 50%% keep floor. It is display/review only. Formal spectrum/force calculation remains <code>daily_median + [-100,100] m/s^2</code>.</div>\n');
fprintf(fid, '<h2>Below-50 Decision</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Auto keep %%</th><th>Auto RMS30</th><th>Below-50 keep %%</th><th>Below-50 RMS30</th><th>Keep loss %%</th><th>RMS30 gain %%</th><th>Recommendation</th><th>Reason</th></tr>\n');
for i = 1:height(decision)
    fprintf(fid, '<tr class="%s"><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td>%s</td><td>%s</td></tr>\n', ...
        htmlText(decision.Recommendation{i}), htmlText(decision.PointID{i}), ...
        decision.AutoKeepPct(i), decision.AutoRMS30Max(i), ...
        decision.UltraKeepPct(i), decision.UltraRMS30Max(i), ...
        decision.KeepLossPct(i), decision.RMS30GainVsAutoPct(i), ...
        htmlText(decision.Recommendation{i}), htmlText(decision.Reason{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Package Manifest</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Source</th><th>Threshold</th><th>Drop top %%</th><th>Keep %%</th><th>RMS30 max</th><th>Reason</th></tr>\n');
for i = 1:height(manifest)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td>%s</td></tr>\n', ...
        htmlText(manifest.Source{i}), htmlText(manifest.PointID{i}), ...
        htmlText(manifest.Source{i}), manifest.ThresholdAbsMps2(i), ...
        manifest.SegmentFilterTopPctRMS30(i), manifest.KeepPct(i), ...
        manifest.RMS30Max(i), htmlText(manifest.Reason{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>CF-2/CF-7 Comparison Board</h2><div class="figure"><img src="%s" alt="below-50 comparison board"></div>\n', ...
    htmlText(localFileName(boardPath)));
fprintf(fid, '<h2>Full Optional Package Contact Sheet</h2><div class="figure"><img src="%s" alt="contact sheet"></div>\n', ...
    htmlText(localFileName(contactSheet)));
fprintf(fid, '<h2>Package Images</h2><div class="grid">\n');
for i = 1:height(manifest)
    fprintf(fid, '<div class="figure"><h2>%s | %s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(manifest.PointID{i}), htmlText(manifest.Source{i}), ...
        htmlText(localFileName(manifest.PlotPath{i})), htmlText(manifest.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function writeReadme(path, manifest, decision, contactSheet, boardPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Ultra-Clean Review\n\n');
fprintf(fid, '- Open `index.html` for the review page.\n');
fprintf(fid, '- Contact sheet: `%s`\n', localFileName(contactSheet));
fprintf(fid, '- Comparison board: `%s`\n', localFileName(boardPath));
fprintf(fid, '- Formal policy remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '## Below-50 Decision\n\n');
fprintf(fid, '| Point | Auto keep %% | Below-50 keep %% | Keep loss %% | RMS30 gain %% | Recommendation |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---|\n');
for i = 1:height(decision)
    fprintf(fid, '| %s | %.3f | %.3f | %.3f | %.1f | %s |\n', ...
        decision.PointID{i}, decision.AutoKeepPct(i), decision.UltraKeepPct(i), ...
        decision.KeepLossPct(i), decision.RMS30GainVsAutoPct(i), ...
        decision.Recommendation{i});
end
fprintf(fid, '\n## Package\n\n');
fprintf(fid, '| Point | Source | Keep %% | RMS30 max |\n');
fprintf(fid, '|---|---|---:|---:|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | %s | %.3f | %.3f |\n', ...
        manifest.PointID{i}, manifest.Source{i}, ...
        manifest.KeepPct(i), manifest.RMS30Max(i));
end
end

function r = rowFor(T, key, value)
idx = find(strcmp(string(T.(key)), value), 1);
if isempty(idx)
    error('Missing row where %s=%s.', key, value);
end
r = T(idx, :);
end

function value = pctReduction(baseValue, newValue)
if ~isfinite(baseValue) || ~isfinite(newValue) || abs(baseValue) < eps
    value = 0;
else
    value = 100 * (baseValue - newValue) / baseValue;
end
end

function text = strategyText(thresholdAbs, segmentPct)
text = sprintf('abs<=%g display', thresholdAbs);
if segmentPct > 0
    text = sprintf('%s + drop top %g%% RMS30 segments', text, segmentPct);
end
end

function text = asText(value)
if iscell(value)
    text = char(value{1});
elseif isstring(value)
    text = char(value(1));
else
    text = char(string(value));
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
