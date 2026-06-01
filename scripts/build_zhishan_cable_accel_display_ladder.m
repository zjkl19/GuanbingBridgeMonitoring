function result = build_zhishan_cable_accel_display_ladder()
%BUILD_ZHISHAN_CABLE_ACCEL_DISPLAY_LADDER Build tiered display candidates.
%   Searches cable-acceleration display-only policies and compares:
%   formal baseline, current recommendation, cleaner candidate, aggressive
%   candidate. Formal spectrum/force calculation is not modified.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
startDate = '2026-03-01';
endDate = '2026-03-31';
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);

stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
policyPath = fullfile(stableDir, 'CableAccelDisplayRecommendation_policy.json');
ladderDir = fullfile(stableDir, 'ladder_review');
if ~exist(ladderDir, 'dir'), mkdir(ladderDir); end

formalThreshold = 100;
binMinutes = 30;
segmentMinutes = 30;
maxSearchSamples = 160000;

cleanSpec = struct( ...
    'tier', 'cleaner', ...
    'label', 'cleaner candidate', ...
    'minKeepPct', 92, ...
    'thresholdGrid', [5 10 15 20 30 40 50 75 100], ...
    'segmentPctGrid', [0 2 5 8 10], ...
    'reductionWeight', 1.0, ...
    'keepPenaltyWeight', 0.75);
aggressiveSpec = struct( ...
    'tier', 'aggressive', ...
    'label', 'aggressive candidate', ...
    'minKeepPct', 85, ...
    'thresholdGrid', [3 5 7.5 10 15 20 30 40 50 75 100], ...
    'segmentPctGrid', [0 2 5 8 10 15 20], ...
    'reductionWeight', 1.35, ...
    'keepPenaltyWeight', 0.30);

cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));
cfg.notify.enabled = false;
cfgLoad = removeCableAccelThresholds(cfg);
subfolder = bms.config.ConfigReader.getSubfolder(cfgLoad, 'cable_accel', '');
policy = readJson(policyPath);

t0 = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
t1 = datetime(endDate, 'InputFormat', 'yyyy-MM-dd') + days(1);
binEdges = t0:minutes(binMinutes):t1;
binCenters = binEdges(1:end-1)' + minutes(binMinutes / 2);
segmentEdges = t0:minutes(segmentMinutes):t1;

rows = {};
plotPaths = cell(numel(points), 1);

for i = 1:numel(points)
    pointId = points{i};
    fprintf('build cable_accel display ladder %s\n', pointId);
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

    stride = max(1, ceil(numel(values) / maxSearchSamples));
    searchTimes = times(1:stride:end);
    searchValues = values(1:stride:end);
    searchBaseCount = nnz(isfinite(searchValues) & ~isnat(searchTimes));

    formalClean = applyDisplayPolicy(times, values, formalThreshold, 0, segmentEdges);
    formalMetric = binnedMetric(times, formalClean, binEdges, binCenters);
    formalKeepPct = keepPct(times, formalClean, baseCount);

    formalSearchClean = applyDisplayPolicy(searchTimes, searchValues, formalThreshold, 0, segmentEdges);
    formalSearchMetric = binnedMetric(searchTimes, formalSearchClean, binEdges, binCenters);
    formalSearchKeepPct = keepPct(searchTimes, formalSearchClean, searchBaseCount);

    currentPolicy = policy.points.(matlab.lang.makeValidName(strrep(pointId, '-', '_')));
    currentThreshold = currentPolicy.threshold_abs_mps2;
    currentSegment = currentPolicy.segment_filter_top_pct_rms30;
    currentClean = applyDisplayPolicy(times, values, currentThreshold, currentSegment, segmentEdges);
    currentMetric = binnedMetric(times, currentClean, binEdges, binCenters);
    currentKeepPct = keepPct(times, currentClean, baseCount);

    cleanSelected = selectTier(searchTimes, searchValues, segmentEdges, binEdges, binCenters, ...
        formalSearchMetric, formalSearchKeepPct, searchBaseCount, formalThreshold, cleanSpec);
    aggressiveSelected = selectTier(searchTimes, searchValues, segmentEdges, binEdges, binCenters, ...
        formalSearchMetric, formalSearchKeepPct, searchBaseCount, formalThreshold, aggressiveSpec);

    policies = {
        makePolicy('formal', 'formal baseline', formalThreshold, 0, formalKeepPct, ...
            formalMetric, formalMetric, formalKeepPct, NaN, 'formal daily_median + abs<=100');
        makePolicy('current', 'current recommendation', currentThreshold, currentSegment, currentKeepPct, ...
            currentMetric, formalMetric, formalKeepPct, NaN, currentPolicy.strategy);
        recomputeSelected('cleaner', cleanSelected, times, values, segmentEdges, binEdges, ...
            binCenters, formalMetric, formalKeepPct, baseCount);
        recomputeSelected('aggressive', aggressiveSelected, times, values, segmentEdges, binEdges, ...
            binCenters, formalMetric, formalKeepPct, baseCount)
        };

    plotPaths{i} = plotPointLadder(ladderDir, pointId, binCenters, policies, startDate, endDate);
    for k = 1:numel(policies)
        p = policies{k};
        rows(end+1, :) = {pointId, p.tier, p.label, p.thresholdAbs, p.segmentPct, ...
            p.strategy, baseCount, p.keepPct, p.keepLossFromFormalPct, ...
            p.metric.rmsMax, p.metric.rmsP95, p.metric.bandWidthP95Median, ...
            p.rmsMaxReductionPct, p.rmsP95ReductionPct, p.bandWidthReductionPct, ...
            p.score, plotPaths{i}}; %#ok<AGROW>
    end
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','Tier','Label','ThresholdAbs','SegmentFilterTopPct','Strategy', ...
    'BaseFiniteCount','KeepPct','KeepLossFromFormalPct','RMS30Max','RMS30P95', ...
    'BandWidthP95Median','RMS30MaxReductionPct','RMS30P95ReductionPct', ...
    'BandWidthReductionPct','Score','PlotPath'});

manifestPath = fullfile(ladderDir, 'CableAccelDisplayLadder_manifest.xlsx');
manifestCsvPath = fullfile(ladderDir, 'CableAccelDisplayLadder_manifest.csv');
boardPath = buildReviewBoard(plotPaths, points, ladderDir, 'CableAccelDisplayLadder_ReviewBoard.jpg');
htmlPath = writeHtml(ladderDir, manifest, plotPaths, points, boardPath);
writeReadme(fullfile(ladderDir, 'README.md'), manifest, boardPath, htmlPath);
writetable(manifest, manifestPath, 'Sheet', 'ladder');
writetable(manifest, manifestCsvPath, 'Encoding', 'UTF-8');

result = struct();
result.output_dir = ladderDir;
result.manifest = manifestPath;
result.manifest_csv = manifestCsvPath;
result.review_board = boardPath;
result.html = htmlPath;
result.plot_paths = plotPaths;

fprintf('ladder dir %s\n', ladderDir);
fprintf('manifest %s\n', manifestPath);
fprintf('review board %s\n', boardPath);
fprintf('html %s\n', htmlPath);
disp(manifest(:, {'PointID','Tier','Strategy','KeepPct','RMS30MaxReductionPct','Score'}));
end

function data = readJson(path)
fid = fopen(path, 'r', 'n', 'UTF-8');
if fid < 0
    error('Cannot open %s.', path);
end
cleaner = onCleanup(@() fclose(fid));
text = fread(fid, '*char')';
data = jsondecode(text);
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
metric.rms = accumarray(idx, vals, [nBins 1], @(x) sqrt(mean(x.^2, 'omitnan')), NaN);
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

function pct = keepPct(times, clean, baseCount)
if baseCount <= 0
    pct = NaN;
else
    pct = 100 * nnz(isfinite(clean) & ~isnat(times)) / baseCount;
end
end

function selected = selectTier(times, values, segmentEdges, binEdges, binCenters, ...
    formalMetric, formalKeepPct, baseCount, formalThreshold, spec)
rows = {};
for th = spec.thresholdGrid
    for segPct = spec.segmentPctGrid
        clean = applyDisplayPolicy(times, values, th, segPct, segmentEdges);
        metric = binnedMetric(times, clean, binEdges, binCenters);
        kp = keepPct(times, clean, baseCount);
        maxReduction = pctReduction(formalMetric.rmsMax, metric.rmsMax);
        p95Reduction = pctReduction(formalMetric.rmsP95, metric.rmsP95);
        widthReduction = pctReduction(formalMetric.bandWidthP95Median, metric.bandWidthP95Median);
        score = scoreCandidate(kp, maxReduction, p95Reduction, widthReduction, th, segPct, ...
            formalThreshold, spec);
        strategy = strategyText(th, formalThreshold, segPct);
        rows(end+1, :) = {th, segPct, strategy, kp, formalKeepPct - kp, ...
            metric.rmsMax, metric.rmsP95, metric.bandWidthP95Median, ...
            maxReduction, p95Reduction, widthReduction, score}; %#ok<AGROW>
    end
end
evalTable = cell2table(rows, 'VariableNames', { ...
    'ThresholdAbs','SegmentFilterTopPct','Strategy','KeepPct','KeepLossFromFormalPct', ...
    'RMS30Max','RMS30P95','BandWidthP95Median','RMS30MaxReductionPct', ...
    'RMS30P95ReductionPct','BandWidthReductionPct','Score'});
ok = evalTable.KeepPct >= spec.minKeepPct & isfinite(evalTable.Score);
if any(ok)
    candidates = evalTable(ok, :);
else
    candidates = evalTable(isfinite(evalTable.Score), :);
end
if isempty(candidates)
    candidates = evalTable;
end
[~, idx] = max(candidates.Score);
selected = candidates(idx, :);
end

function score = scoreCandidate(keepPctValue, maxReduction, p95Reduction, widthReduction, ...
    thresholdAbs, segmentPct, formalThreshold, spec)
if ~isfinite(keepPctValue)
    score = -Inf;
    return;
end
if ~isfinite(maxReduction), maxReduction = 0; end
if ~isfinite(p95Reduction), p95Reduction = 0; end
if ~isfinite(widthReduction), widthReduction = 0; end
reductionScore = 0.45 * maxReduction + 0.30 * p95Reduction + 0.25 * widthReduction;
keepPenalty = spec.keepPenaltyWeight * max(0, 100 - keepPctValue);
floorPenalty = 8 * max(0, spec.minKeepPct - keepPctValue);
complexityPenalty = 0.08 * segmentPct + 0.04 * max(0, formalThreshold - thresholdAbs);
score = spec.reductionWeight * reductionScore - keepPenalty - floorPenalty - complexityPenalty;
end

function policy = makePolicy(tier, label, thresholdAbs, segmentPct, kp, metric, ...
    formalMetric, formalKeepPct, score, strategy)
policy = struct();
policy.tier = tier;
policy.label = label;
policy.thresholdAbs = thresholdAbs;
policy.segmentPct = segmentPct;
policy.strategy = char(strategy);
policy.keepPct = kp;
policy.keepLossFromFormalPct = formalKeepPct - kp;
policy.metric = metric;
policy.rmsMaxReductionPct = pctReduction(formalMetric.rmsMax, metric.rmsMax);
policy.rmsP95ReductionPct = pctReduction(formalMetric.rmsP95, metric.rmsP95);
policy.bandWidthReductionPct = pctReduction(formalMetric.bandWidthP95Median, metric.bandWidthP95Median);
policy.score = score;
end

function policy = recomputeSelected(tier, selected, times, values, segmentEdges, ...
    binEdges, binCenters, formalMetric, formalKeepPct, baseCount)
clean = applyDisplayPolicy(times, values, selected.ThresholdAbs, selected.SegmentFilterTopPct, segmentEdges);
metric = binnedMetric(times, clean, binEdges, binCenters);
kp = keepPct(times, clean, baseCount);
policy = makePolicy(tier, selectedLabel(tier), selected.ThresholdAbs, ...
    selected.SegmentFilterTopPct, kp, metric, formalMetric, formalKeepPct, ...
    selected.Score, selected.Strategy{1});
end

function label = selectedLabel(tier)
switch tier
    case 'cleaner'
        label = 'cleaner candidate';
    case 'aggressive'
        label = 'aggressive candidate';
    otherwise
        label = tier;
end
end

function strategy = strategyText(thresholdAbs, formalThreshold, segmentPct)
if thresholdAbs == formalThreshold
    base = 'formal abs<=100';
else
    base = sprintf('abs<=%g display', thresholdAbs);
end
if segmentPct > 0
    strategy = sprintf('%s + drop top %g%% RMS30 segments', base, segmentPct);
else
    strategy = base;
end
end

function pct = pctReduction(beforeValue, afterValue)
if ~isfinite(beforeValue) || beforeValue == 0 || ~isfinite(afterValue)
    pct = NaN;
else
    pct = 100 * (beforeValue - afterValue) / abs(beforeValue);
end
end

function plotPath = plotPointLadder(outputDir, pointId, binCenters, policies, startDate, endDate)
fig = figure('Visible', 'off', 'Position', [100 100 1800 1500], 'Color', 'w');
tiledlayout(fig, numel(policies), 2, 'TileSpacing', 'compact', 'Padding', 'compact');
colors = tierColors();
for i = 1:numel(policies)
    p = policies{i};
    color = colors.(p.tier);

    ax1 = nexttile;
    hold(ax1, 'on');
    fillBand(ax1, binCenters, p.metric.p05, p.metric.p95, [0.80 0.88 0.96], 0.42, '5%~95%');
    fillBand(ax1, binCenters, p.metric.p25, p.metric.p75, [0.38 0.64 0.86], 0.65, '25%~75%');
    plot(ax1, binCenters, p.metric.p50, 'Color', color, 'LineWidth', 1.25, 'DisplayName', 'median');
    hold(ax1, 'off');
    grid(ax1, 'on');
    grid(ax1, 'minor');
    ylabel(ax1, 'm/s^2');
    title(ax1, sprintf('%s | %s | keep %.2f%% | RMS max down %.1f%%', ...
        p.label, p.strategy, p.keepPct, p.rmsMaxReductionPct), 'Interpreter', 'none');
    if i == 1
        subtitle(ax1, sprintf('%s cable acceleration ladder | %s to %s', pointId, startDate, endDate), ...
            'Interpreter', 'none');
    end
    xtickformat(ax1, 'MM-dd');

    ax2 = nexttile;
    plot(ax2, binCenters, p.metric.rms, 'Color', color, 'LineWidth', 1.05);
    grid(ax2, 'on');
    grid(ax2, 'minor');
    ylabel(ax2, 'RMS30');
    title(ax2, sprintf('max %.2f | P95 %.2f | band %.2f | score %.1f', ...
        p.metric.rmsMax, p.metric.rmsP95, p.metric.bandWidthP95Median, p.score), ...
        'Interpreter', 'none');
    xtickformat(ax2, 'MM-dd');
end
plotPath = fullfile(outputDir, sprintf('CableAccelDisplayLadder_%s.jpg', pointId));
exportgraphics(fig, plotPath, 'Resolution', 145);
close(fig);
end

function colors = tierColors()
colors = struct();
colors.formal = [0.25 0.25 0.25];
colors.current = [0.00 0.23 0.52];
colors.cleaner = [0.00 0.45 0.40];
colors.aggressive = [0.76 0.22 0.10];
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
        visibility = 'on';
        displayName = label;
    else
        visibility = 'off';
        displayName = '';
    end
    fill(ax, x, y, color, 'FaceAlpha', alpha, 'EdgeColor', 'none', ...
        'HandleVisibility', visibility, 'DisplayName', displayName);
end
end

function runs = continuousRuns(mask)
mask = mask(:);
starts = find(mask & [true; ~mask(1:end-1)]);
ends = find(mask & [~mask(2:end); true]);
runs = [starts ends];
end

function boardPath = buildReviewBoard(plotPaths, points, outputDir, fileName)
fig = figure('Visible', 'off', 'Position', [100 100 2200 2400], 'Color', 'w');
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
boardPath = fullfile(outputDir, fileName);
exportgraphics(fig, boardPath, 'Resolution', 140);
close(fig);
end

function htmlPath = writeHtml(outputDir, manifest, plotPaths, points, boardPath)
htmlPath = fullfile(outputDir, 'index.html');
fid = fopen(htmlPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Display Ladder</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #2f6fed;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.current{background:#eef5ff}.cleaner{background:#eaf7f2}.aggressive{background:#fff0e8}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;}');
fprintf(fid, '.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(760px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230;&#20998;&#26723;&#20505;&#36873; / Display Ladder</h1>\n');
fprintf(fid, '<div class="note">&#26412;&#39029;&#26159;&#33258;&#21160;&#25628;&#32034;&#30340;&#23457;&#22270;&#20998;&#26723;: formal/current/cleaner/aggressive. &#27491;&#24335;&#39057;&#35889;&#21644;&#32034;&#21147;&#35745;&#31639;&#19981;&#21464;&#12290;</div>\n');
fprintf(fid, '<h2>&#20998;&#26723;&#34920; / Candidate Table</h2>\n<table>\n');
fprintf(fid, '<tr><th>Point</th><th>Tier</th><th>Strategy</th><th>Keep %%</th><th>RMS30 max</th><th>RMS30 max reduction %%</th><th>Score</th></tr>\n');
for i = 1:height(manifest)
    cls = '';
    if any(strcmp(manifest.Tier{i}, {'current','cleaner','aggressive'}))
        cls = sprintf(' class="%s"', manifest.Tier{i});
    end
    fprintf(fid, '<tr%s><td>%s</td><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%.1f</td></tr>\n', ...
        cls, htmlText(manifest.PointID{i}), htmlText(manifest.Label{i}), ...
        htmlText(manifest.Strategy{i}), manifest.KeepPct(i), manifest.RMS30Max(i), ...
        manifest.RMS30MaxReductionPct(i), manifest.Score(i));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>&#24635;&#35272; / Review Board</h2>\n<div class="figure"><img src="%s" alt="review board"></div>\n', htmlText(localFileName(boardPath)));
fprintf(fid, '<h2>&#21333;&#28857;&#20998;&#26723;&#22270; / Per-Point Ladder Figures</h2>\n<div class="grid">\n');
for i = 1:numel(points)
    fprintf(fid, '<div class="figure"><h2>%s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(points{i}), htmlText(localFileName(plotPaths{i})), htmlText(points{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function writeReadme(path, manifest, boardPath, htmlPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Display Ladder\n\n');
fprintf(fid, '- Open `index.html` for the visual review page.\n');
fprintf(fid, '- Review board: `%s`\n', localFileName(boardPath));
fprintf(fid, '- Source HTML: `%s`\n\n', localFileName(htmlPath));
fprintf(fid, 'Formal spectrum/force calculation remains unchanged. This package is display-only.\n\n');
fprintf(fid, '| Point | Tier | Strategy | Keep %% | RMS30 max reduction %% | Score |\n');
fprintf(fid, '|---|---|---|---:|---:|---:|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | %s | %s | %.3f | %.1f | %.1f |\n', ...
        manifest.PointID{i}, manifest.Label{i}, manifest.Strategy{i}, ...
        manifest.KeepPct(i), manifest.RMS30MaxReductionPct(i), manifest.Score(i));
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
