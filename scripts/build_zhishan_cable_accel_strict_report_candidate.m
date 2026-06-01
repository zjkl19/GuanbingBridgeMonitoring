function result = build_zhishan_cable_accel_strict_report_candidate()
%BUILD_ZHISHAN_CABLE_ACCEL_STRICT_REPORT_CANDIDATE Build cleaner report figures.
%   Display/report-review only. This promotes a stricter visual candidate
%   from the existing auto-visual search matrix plus the below-50 review.
%   Formal cable acceleration spectrum/force calculation remains unchanged.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
outputDir = fullfile(stableDir, 'strict_report_candidate');
imageDir = fullfile(outputDir, 'images');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end
if ~exist(imageDir, 'dir'), mkdir(imageDir); end

startDate = '2026-03-01';
endDate = '2026-03-31';
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
binMinutes = 30;
segmentMinutes = 30;

autoVisualDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([33258 21160 35270 35273 25512 33616 23637 31034])]);
autoManifestPath = fullfile(autoVisualDir, 'CableAccelAutoVisualReport_manifest.csv');
scoreMatrixPath = fullfile(stableDir, 'auto_visual_search', ...
    'CableAccelAutoVisualSearch_score_matrix.csv');
ultraDecisionPath = fullfile(stableDir, 'ultra_clean_review', ...
    'CableAccelUltraCleanReview_decision.csv');

autoManifest = readtable(autoManifestPath, 'Encoding', 'UTF-8');
scoreMatrix = readtable(scoreMatrixPath, 'Encoding', 'UTF-8');
ultraDecision = readtable(ultraDecisionPath, 'Encoding', 'UTF-8');

cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));
cfg.notify.enabled = false;
cfgLoad = removeCableAccelThresholds(cfg);
subfolder = bms.config.ConfigReader.getSubfolder(cfgLoad, 'cable_accel', '');

t0 = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
t1 = datetime(endDate, 'InputFormat', 'yyyy-MM-dd') + days(1);
binEdges = t0:minutes(binMinutes):t1;
binCenters = binEdges(1:end-1)' + minutes(binMinutes / 2);
segmentEdges = t0:minutes(segmentMinutes):t1;

manifestRows = {};
decisionRows = {};
autoPaths = cell(numel(points), 1);
strictPaths = cell(numel(points), 1);

for i = 1:numel(points)
    pointId = points{i};
    fprintf('strict report candidate %s\n', pointId);
    autoRow = rowFor(autoManifest, 'PointID', pointId);
    [candidate, decision] = chooseStrictCandidate(pointId, autoRow, ...
        scoreMatrix, ultraDecision);

    [times, values] = load_timeseries_range(dataRoot, subfolder, pointId, ...
        startDate, endDate, cfgLoad, 'cable_accel');
    times = times(:);
    values = double(values(:));
    baseCount = nnz(isfinite(values) & ~isnat(times));
    metric = computeCandidate(times, values, baseCount, binEdges, ...
        binCenters, segmentEdges, candidate.thresholdAbs, candidate.segmentPct);

    strictPath = fullfile(imageDir, sprintf( ...
        'CableAccelStrictReport_%s_20260301_20260331.jpg', pointId));
    plotCandidate(strictPath, pointId, binCenters, metric, ...
        candidate.strategy, metric.keepPct, metric.rmsMax, metric.rmsP95, ...
        candidate.source, decision.reason, startDate, endDate);

    autoPath = asText(autoRow.PlotPath);
    autoPaths{i} = autoPath;
    strictPaths{i} = strictPath;

    manifestRows(end+1, :) = {pointId, candidate.source, ...
        candidate.thresholdAbs, candidate.segmentPct, metric.keepPct, ...
        metric.rmsMax, metric.rmsP95, metric.bandWidthP95Median, ...
        decision.keepLossPct, decision.rmsGainPct, decision.p95GainPct, ...
        decision.reason, strictPath}; %#ok<AGROW>
    decisionRows(end+1, :) = {pointId, asText(autoRow.AutoClass), ...
        autoRow.ThresholdAbsMps2(1), autoRow.SegmentFilterTopPctRMS30(1), ...
        autoRow.KeepPct(1), autoRow.RMS30Max(1), autoRow.RMS30P95(1), ...
        candidate.thresholdAbs, candidate.segmentPct, metric.keepPct, ...
        metric.rmsMax, metric.rmsP95, decision.keepLossPct, ...
        decision.rmsGainPct, decision.p95GainPct, candidate.source, ...
        decision.reason, autoPath, strictPath}; %#ok<AGROW>
end

manifest = cell2table(manifestRows, 'VariableNames', manifestColumns());
decision = cell2table(decisionRows, 'VariableNames', decisionColumns());

contactSheet = buildContactSheet(strictPaths, manifest, outputDir, ...
    'CableAccelStrictReport_ContactSheet.jpg');
board = buildCompareBoard(autoPaths, strictPaths, decision, outputDir);
manifestXlsx = fullfile(outputDir, 'CableAccelStrictReport_manifest.xlsx');
manifestCsv = fullfile(outputDir, 'CableAccelStrictReport_manifest.csv');
decisionXlsx = fullfile(outputDir, 'CableAccelStrictReport_decision.xlsx');
decisionCsv = fullfile(outputDir, 'CableAccelStrictReport_decision.csv');
summaryJson = fullfile(outputDir, 'CableAccelStrictReport_summary.json');
htmlPath = fullfile(outputDir, 'index.html');
readmePath = fullfile(outputDir, 'README.md');

writetable(manifest, manifestXlsx, 'Sheet', 'manifest');
writetable(manifest, manifestCsv, 'Encoding', 'UTF-8');
writetable(decision, decisionXlsx, 'Sheet', 'decision');
writetable(decision, decisionCsv, 'Encoding', 'UTF-8');
writeJson(summaryJson, manifest, decision);
writeHtml(htmlPath, manifest, decision, contactSheet, board);
writeReadme(readmePath, manifest, decision, contactSheet, board);

result = struct();
result.output_dir = outputDir;
result.html = htmlPath;
result.contact_sheet = contactSheet;
result.board = board;
result.manifest = manifestXlsx;
result.manifest_csv = manifestCsv;
result.decision = decisionXlsx;
result.decision_csv = decisionCsv;
result.summary_json = summaryJson;
result.image_dir = imageDir;

fprintf('strict report candidate %s\n', htmlPath);
disp(decision(:, {'PointID','AutoClass','StrictSource','StrictKeepPct', ...
    'StrictRMS30Max','KeepLossPct','RMS30GainVsAutoPct'}));
end

function names = manifestColumns()
names = {'PointID','Source','ThresholdAbsMps2','SegmentFilterTopPctRMS30', ...
    'KeepPct','RMS30Max','RMS30P95','BandWidthP95Median', ...
    'KeepLossVsAutoPct','RMS30GainVsAutoPct','RMS30P95GainVsAutoPct', ...
    'Reason','PlotPath'};
end

function names = decisionColumns()
names = {'PointID','AutoClass','AutoThresholdAbsMps2', ...
    'AutoSegmentTopPctRMS30','AutoKeepPct','AutoRMS30Max', ...
    'AutoRMS30P95','StrictThresholdAbsMps2','StrictSegmentTopPctRMS30', ...
    'StrictKeepPct','StrictRMS30Max','StrictRMS30P95','KeepLossPct', ...
    'RMS30GainVsAutoPct','RMS30P95GainVsAutoPct','StrictSource', ...
    'Reason','AutoPlotPath','StrictPlotPath'};
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

function [candidate, decision] = chooseStrictCandidate(pointId, autoRow, scoreMatrix, ultraDecision)
autoKeep = autoRow.KeepPct(1);
autoRms = autoRow.RMS30Max(1);
autoP95 = autoRow.RMS30P95(1);
autoClass = asText(autoRow.AutoClass);

candidate = struct();
candidate.source = 'auto_visual_default';
candidate.thresholdAbs = autoRow.ThresholdAbsMps2(1);
candidate.segmentPct = autoRow.SegmentFilterTopPctRMS30(1);
candidate.strategy = sprintf('abs<=%g display + drop top %g%% RMS30 segments', ...
    candidate.thresholdAbs, candidate.segmentPct);
candidate.score = 0;

decision = struct();
decision.keepLossPct = 0;
decision.rmsGainPct = 0;
decision.p95GainPct = 0;
decision.reason = 'kept auto-visual default; no stricter candidate met gain/loss gate';

rows = scoreMatrix(strcmp(string(scoreMatrix.PointID), string(pointId)), :);
if ~isempty(rows)
    rows.KeepLossPct = autoKeep - rows.KeepPct;
    rows.RMS30GainPct = pctReduction(autoRms, rows.RMS30Max);
    rows.RMS30P95GainPct = pctReduction(autoP95, rows.RMS30P95);
    lowerFloor = classKeepFloor(autoClass);
    eligible = rows(rows.KeepLossPct > 0.25 & rows.KeepLossPct <= 5.0 & ...
        rows.KeepPct >= lowerFloor & rows.RMS30GainPct >= 3.0 & ...
        isfinite(rows.RMS30Max), :);
    if ~isempty(eligible)
        eligible.StrictScore = 2.0 * eligible.RMS30GainPct + ...
            finiteOrZero(eligible.RMS30P95GainPct) - ...
            0.8 * eligible.KeepLossPct - ...
            0.05 * eligible.SegmentFilterTopPctRMS30;
        eligible = sortrows(eligible, {'StrictScore','KeepPct'}, ...
            {'descend','descend'});
        best = eligible(1, :);
        candidate = candidateFromRow(best, 'strict_score_matrix');
        candidate.score = best.StrictScore(1);
        decision.keepLossPct = best.KeepLossPct(1);
        decision.rmsGainPct = best.RMS30GainPct(1);
        decision.p95GainPct = best.RMS30P95GainPct(1);
        decision.reason = sprintf(['score-matrix stricter pick: RMS30 gain %.1f%%, ' ...
            'P95 gain %.1f%%, keep loss %.1f%% within %.0f%% class floor'], ...
            decision.rmsGainPct, decision.p95GainPct, ...
            decision.keepLossPct, lowerFloor);
    end
end

ultra = ultraDecision(strcmp(string(ultraDecision.PointID), string(pointId)), :);
if ~isempty(ultra)
    ultraKeepLoss = ultra.KeepLossPct(1);
    ultraGain = ultra.RMS30GainVsAutoPct(1);
    if ultraGain >= 10 && ultraKeepLoss <= 10 && ultra.UltraKeepPct(1) >= 40
        ultraScore = 2.0 * ultraGain - 0.8 * ultraKeepLoss - ...
            0.05 * ultra.UltraSegmentTopPctRMS30(1);
        if strcmp(candidate.source, 'auto_visual_default') || ultraScore > candidate.score
            candidate.source = 'strict_ultra_clean';
            candidate.thresholdAbs = ultra.UltraThresholdAbsMps2(1);
            candidate.segmentPct = ultra.UltraSegmentTopPctRMS30(1);
            candidate.strategy = sprintf('abs<=%g display + drop top %g%% RMS30 segments', ...
                candidate.thresholdAbs, candidate.segmentPct);
            candidate.score = ultraScore;
            decision.keepLossPct = ultraKeepLoss;
            decision.rmsGainPct = ultraGain;
            decision.p95GainPct = pctReduction(autoP95, ultra.UltraRMS30P95(1));
            decision.reason = sprintf(['ultra-clean stricter pick: RMS30 gain %.1f%%, ' ...
                'P95 gain %.1f%%, keep loss %.1f%%; accepted as display-only report candidate'], ...
                decision.rmsGainPct, decision.p95GainPct, decision.keepLossPct);
        end
    end
end
end

function floorValue = classKeepFloor(autoClass)
switch char(autoClass)
    case 'severe_noise'
        floorValue = 40;
    case 'moderate_noise'
        floorValue = 51;
    case 'mixed_noise'
        floorValue = 58;
    otherwise
        floorValue = 80;
end
end

function candidate = candidateFromRow(row, source)
candidate = struct();
candidate.source = source;
candidate.thresholdAbs = row.ThresholdAbsMps2(1);
candidate.segmentPct = row.SegmentFilterTopPctRMS30(1);
candidate.strategy = asText(row.Strategy);
candidate.score = row.StrictScore(1);
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

function plotCandidate(plotPath, pointId, binCenters, metric, strategy, ...
        keepPct, rmsMax, rmsP95, source, reason, startDate, endDate)
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
title(ax1, sprintf('%s cable acceleration strict report | %s to %s', ...
    pointId, startDate, endDate), 'Interpreter', 'none');
subtitle(ax1, sprintf('%s | %s | keep %.2f%%', source, strategy, keepPct), ...
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
title(ax2, sprintf('RMS30 max %.2f | RMS30 P95 %.2f | %s', ...
    rmsMax, rmsP95, truncateText(reason, 78)), 'Interpreter', 'none');
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
        manifest.PointID{i}, manifest.Source{i}, ...
        manifest.KeepPct(i), manifest.RMS30Max(i)), 'Interpreter', 'none');
end
outPath = fullfile(outputDir, fileName);
exportgraphics(fig, outPath, 'Resolution', 150);
close(fig);
end

function boardPath = buildCompareBoard(autoPaths, strictPaths, decision, outputDir)
changed = ~strcmp(string(decision.StrictSource), "auto_visual_default");
if ~any(changed)
    changed = true(height(decision), 1);
end
rowIdx = find(changed);
figHeight = max(1200, 740 * numel(rowIdx));
fig = figure('Visible', 'off', 'Position', [100 100 2400 figHeight], 'Color', 'w');
tiledlayout(fig, numel(rowIdx), 2, 'TileSpacing', 'compact', 'Padding', 'compact');
for k = 1:numel(rowIdx)
    i = rowIdx(k);
    ax1 = nexttile;
    image(ax1, imread(autoPaths{i}));
    axis(ax1, 'image');
    axis(ax1, 'off');
    title(ax1, sprintf('%s auto | keep %.1f%% | RMS30 %.2f', ...
        decision.PointID{i}, decision.AutoKeepPct(i), decision.AutoRMS30Max(i)), ...
        'Interpreter', 'none');

    ax2 = nexttile;
    image(ax2, imread(strictPaths{i}));
    axis(ax2, 'image');
    axis(ax2, 'off');
    title(ax2, sprintf('%s strict | keep %.1f%% | gain %.1f%%', ...
        decision.PointID{i}, decision.StrictKeepPct(i), ...
        decision.RMS30GainVsAutoPct(i)), 'Interpreter', 'none');
end
boardPath = fullfile(outputDir, 'CableAccelStrictReport_CompareBoard.jpg');
exportgraphics(fig, boardPath, 'Resolution', 150);
close(fig);
end

function writeJson(path, manifest, decision)
payload = struct();
payload.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
payload.scope = 'display_report_review_only';
payload.formal_policy = 'Formal cable acceleration remains daily_median + [-100,100] m/s^2.';
payload.selection_rule = ['Promote stricter visual candidates when RMS30 gain is at least 3% ' ...
    'with <=5% keep loss; allow ultra-clean CF-2/CF-7 when gain is at least 10%, ' ...
    'keep loss is <=10%, and keep is >=40%.'];
payload.manifest = table2struct(manifest);
payload.decision = table2struct(decision);
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(payload, 'PrettyPrint', true));
end

function writeHtml(path, manifest, decision, contactSheet, board)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Strict Report Candidate</title>\n');
writeCss(fid);
fprintf(fid, '</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Strict Report Candidate</h1>\n');
fprintf(fid, '<div class="note">Display/report-review only. Formal spectrum/force calculation remains <code>daily_median + [-100,100] m/s^2</code>.</div>\n');
fprintf(fid, '<h2>Decision</h2>\n');
writeDecisionTable(fid, decision);
fprintf(fid, '<h2>Manifest</h2>\n');
writeManifestTable(fid, manifest);
fprintf(fid, '<h2>Contact Sheet</h2><div class="figure"><img src="%s" alt="contact sheet"></div>\n', htmlText(localFileName(contactSheet)));
fprintf(fid, '<h2>Auto vs Strict Board</h2><div class="figure"><img src="%s" alt="compare board"></div>\n', htmlText(localFileName(board)));
fprintf(fid, '<h2>Per-Point Images</h2><div class="grid">\n');
for i = 1:height(manifest)
    [~, imageName] = fileparts(manifest.PlotPath{i});
    imageHref = ['images/' imageName '.jpg'];
    fprintf(fid, '<div class="figure"><h2>%s | %s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(manifest.PointID{i}), htmlText(manifest.Source{i}), ...
        htmlText(imageHref), htmlText(manifest.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function writeReadme(path, manifest, decision, contactSheet, board)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Strict Report Candidate\n\n');
fprintf(fid, 'Display/report-review only. Formal cable acceleration remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '- Contact sheet: `%s`\n', contactSheet);
fprintf(fid, '- Compare board: `%s`\n\n', board);
for i = 1:height(decision)
    fprintf(fid, '- `%s`: `%s`, keep `%.2f%%`, RMS30 gain `%.1f%%`, keep loss `%.1f%%`.\n', ...
        decision.PointID{i}, decision.StrictSource{i}, decision.StrictKeepPct(i), ...
        decision.RMS30GainVsAutoPct(i), decision.KeepLossPct(i));
end
fprintf(fid, '\nSelected manifest rows: %d.\n', height(manifest));
end

function writeDecisionTable(fid, T)
fprintf(fid, '<table><thead><tr>');
cols = {'PointID','AutoClass','StrictSource','StrictThresholdAbsMps2', ...
    'StrictSegmentTopPctRMS30','StrictKeepPct','StrictRMS30Max', ...
    'KeepLossPct','RMS30GainVsAutoPct','Reason'};
for i = 1:numel(cols)
    fprintf(fid, '<th>%s</th>', htmlText(cols{i}));
end
fprintf(fid, '</tr></thead><tbody>\n');
for r = 1:height(T)
    fprintf(fid, '<tr>');
    for c = 1:numel(cols)
        value = T.(cols{c})(r);
        writeCell(fid, value);
    end
    fprintf(fid, '</tr>\n');
end
fprintf(fid, '</tbody></table>\n');
end

function writeManifestTable(fid, T)
fprintf(fid, '<table><thead><tr>');
cols = {'PointID','Source','ThresholdAbsMps2','SegmentFilterTopPctRMS30', ...
    'KeepPct','RMS30Max','RMS30P95','RMS30GainVsAutoPct','PlotPath'};
for i = 1:numel(cols)
    fprintf(fid, '<th>%s</th>', htmlText(cols{i}));
end
fprintf(fid, '</tr></thead><tbody>\n');
for r = 1:height(T)
    fprintf(fid, '<tr>');
    for c = 1:numel(cols)
        value = T.(cols{c})(r);
        writeCell(fid, value);
    end
    fprintf(fid, '</tr>\n');
end
fprintf(fid, '</tbody></table>\n');
end

function writeCell(fid, value)
if isnumeric(value)
    fprintf(fid, '<td class="num">%.4g</td>', value);
elseif iscell(value)
    fprintf(fid, '<td>%s</td>', htmlText(value{1}));
else
    fprintf(fid, '<td>%s</td>', htmlText(char(string(value))));
end
end

function writeCss(fid)
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #0f766e;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n');
end

function row = rowFor(T, key, value)
mask = strcmp(string(T.(key)), string(value));
row = T(mask, :);
if isempty(row)
    error('Missing row for %s=%s.', key, value);
end
row = row(1, :);
end

function value = pctReduction(beforeValue, afterValue)
if isscalar(afterValue)
    template = beforeValue;
else
    template = afterValue;
end
before = beforeValue + zeros(size(template));
after = afterValue + zeros(size(template));
value = NaN(size(template));
valid = isfinite(before) & before > 0 & isfinite(after);
value(valid) = 100 * (before(valid) - after(valid)) ./ max(before(valid), eps);
end

function y = finiteOrZero(x)
y = x;
y(~isfinite(y)) = 0;
end

function text = asText(value)
if iscell(value)
    text = value{1};
elseif isstring(value)
    text = char(value(1));
else
    text = char(string(value));
end
end

function out = truncateText(text, maxChars)
text = char(string(text));
if strlength(string(text)) <= maxChars
    out = text;
else
    out = [char(extractBefore(string(text), maxChars - 2)) '...'];
end
end

function name = localFileName(path)
[~, base, ext] = fileparts(path);
name = [base ext];
end

function s = htmlText(value)
s = char(string(value));
s = strrep(s, '&', '&amp;');
s = strrep(s, '<', '&lt;');
s = strrep(s, '>', '&gt;');
s = strrep(s, '"', '&quot;');
end
