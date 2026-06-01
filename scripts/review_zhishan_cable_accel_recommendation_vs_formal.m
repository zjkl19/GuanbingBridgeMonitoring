function result = review_zhishan_cable_accel_recommendation_vs_formal()
%REVIEW_ZHISHAN_CABLE_ACCEL_RECOMMENDATION_VS_FORMAL Recompute recommendation.
%   Uses the stable display policy JSON and real source data. Formal
%   spectrum/force settings are not modified.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
runLogs = fullfile(dataRoot, 'run_logs');
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
policyPath = fullfile(stableDir, 'CableAccelDisplayRecommendation_policy.json');
policy = readJson(policyPath);

startDate = '2026-03-01';
endDate = '2026-03-31';
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
formalThreshold = 100;
binMinutes = 30;
segmentMinutes = 30;

cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));
cfg.notify.enabled = false;
cfgLoad = removeCableAccelThresholds(cfg);
subfolder = bms.config.ConfigReader.getSubfolder(cfgLoad, 'cable_accel', '');

stamp = datestr(now, 'yyyymmdd_HHMMSS');
runName = ['cable_accel_recommendation_vs_formal_' stamp];
outRoot = fullfile(runLogs, runName);
plotDir = fullfile(outRoot, 'plots');
if ~exist(plotDir, 'dir'), mkdir(plotDir); end

t0 = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
t1 = datetime(endDate, 'InputFormat', 'yyyy-MM-dd') + days(1);
binEdges = t0:minutes(binMinutes):t1;
binCenters = binEdges(1:end-1)' + minutes(binMinutes / 2);
segmentEdges = t0:minutes(segmentMinutes):t1;

rows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    fprintf('recommendation vs formal %s\n', pointId);
    p = policy.points.(matlab.lang.makeValidName(strrep(pointId, '-', '_')));
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
    recClean = clipAbs(values, p.threshold_abs_mps2);
    if p.segment_filter_top_pct_rms30 > 0
        recClean = applyTopRmsSegmentMask(times, recClean, segmentEdges, p.segment_filter_top_pct_rms30);
    end

    formalMetric = binnedMetric(times, formalClean, binEdges, binCenters);
    recMetric = binnedMetric(times, recClean, binEdges, binCenters);
    formalKeepPct = 100 * nnz(isfinite(formalClean) & ~isnat(times)) / baseCount;
    recKeepPct = 100 * nnz(isfinite(recClean) & ~isnat(times)) / baseCount;
    keepDeltaPct = recKeepPct - formalKeepPct;
    rmsReductionPct = pctReduction(formalMetric.rmsMax, recMetric.rmsMax);
    rmsP95ReductionPct = pctReduction(formalMetric.rmsP95, recMetric.rmsP95);
    widthReductionPct = pctReduction(formalMetric.bandWidthP95Median, recMetric.bandWidthP95Median);
    decision = reviewDecision(recKeepPct, keepDeltaPct, rmsReductionPct, p.source);

    plotPaths{i} = plotComparison(plotDir, pointId, binCenters, formalMetric, recMetric, ...
        formalThreshold, p.threshold_abs_mps2, p.segment_filter_top_pct_rms30, ...
        recKeepPct, keepDeltaPct, rmsReductionPct, decision);
    rows(end+1, :) = {pointId, p.source, p.strategy, p.threshold_abs_mps2, ...
        p.segment_filter_top_pct_rms30, baseCount, formalKeepPct, recKeepPct, ...
        keepDeltaPct, formalMetric.rmsMax, recMetric.rmsMax, rmsReductionPct, ...
        formalMetric.rmsP95, recMetric.rmsP95, rmsP95ReductionPct, ...
        formalMetric.bandWidthP95Median, recMetric.bandWidthP95Median, ...
        widthReductionPct, decision, plotPaths{i}}; %#ok<AGROW>
end

summary = cell2table(rows, 'VariableNames', { ...
    'PointID','PolicySource','Strategy','ThresholdAbs','SegmentFilterTopPct', ...
    'BaseFiniteCount','FormalKeepPct','RecommendationKeepPct','KeepDeltaPct', ...
    'FormalRMS30Max','RecommendationRMS30Max','RMS30MaxReductionPct', ...
    'FormalRMS30P95','RecommendationRMS30P95','RMS30P95ReductionPct', ...
    'FormalBandWidthP95Median','RecommendationBandWidthP95Median', ...
    'BandWidthReductionPct','Decision','PlotPath'});

xlsxPath = fullfile(outRoot, 'cable_accel_recommendation_vs_formal.xlsx');
csvPath = fullfile(outRoot, 'cable_accel_recommendation_vs_formal.csv');
markdownPath = fullfile(outRoot, 'cable_accel_recommendation_vs_formal.md');
writetable(summary, xlsxPath, 'Sheet', 'summary');
writetable(summary, csvPath, 'Encoding', 'UTF-8');
boardPath = buildReviewBoard(plotPaths, points, outRoot, 'cable_accel_recommendation_vs_formal_board.jpg');
writeMarkdown(markdownPath, runName, summary, xlsxPath, csvPath, boardPath, policyPath);
stable = writeStableOutputs(stableDir, runName, summary, plotPaths, boardPath);
latestPaths = writeLatest(dataRoot, runName, summary, xlsxPath, csvPath, markdownPath, boardPath, policyPath, stable);

result = struct();
result.run_name = runName;
result.output_folder = outRoot;
result.summary = summary;
result.workbook = xlsxPath;
result.csv = csvPath;
result.board = boardPath;
result.markdown = markdownPath;
result.stable = stable;
result.latest = latestPaths;

fprintf('wrote %s\n', xlsxPath);
fprintf('wrote %s\n', csvPath);
fprintf('review board %s\n', boardPath);
fprintf('stable board %s\n', stable.board);
fprintf('latest html %s\n', latestPaths.html);
disp(summary(:, {'PointID','PolicySource','RecommendationKeepPct','KeepDeltaPct','RMS30MaxReductionPct','Decision'}));
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

function value = pctReduction(beforeValue, afterValue)
if ~isfinite(beforeValue) || beforeValue <= 0 || ~isfinite(afterValue)
    value = NaN;
else
    value = 100 * (beforeValue - afterValue) / max(beforeValue, eps);
end
end

function text = reviewDecision(recKeepPct, keepDeltaPct, rmsReductionPct, policySource)
if recKeepPct < 92
    text = 'review data loss before use';
elseif rmsReductionPct >= 25 && keepDeltaPct >= -6
    text = 'recommended display materially improves formal baseline';
elseif strcmp(policySource, 'grid') && rmsReductionPct >= 15
    text = 'grid recommendation improves formal baseline';
elseif rmsReductionPct >= 15
    text = 'recommended display improves formal baseline';
else
    text = 'limited change from formal baseline';
end
end

function plotPath = plotComparison(plotDir, pointId, binCenters, formalMetric, recMetric, ...
        formalThreshold, thresholdAbs, segmentPct, recKeepPct, keepDeltaPct, rmsReductionPct, decision)
fig = figure('Visible', 'off', 'Position', [100 100 1550 850]);
tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile;
plotEnvelope(ax1, binCenters, formalMetric, 'formal');
title(ax1, sprintf('%s formal display | abs<=%.0f', pointId, formalThreshold), 'Interpreter', 'none');

ax2 = nexttile;
plotEnvelope(ax2, binCenters, recMetric, 'recommendation');
title(ax2, sprintf('recommended | abs<=%.0f | segment %.0f%% | keep %.2f%%', ...
    thresholdAbs, segmentPct, recKeepPct), 'Interpreter', 'none');

ax3 = nexttile;
plot(ax3, binCenters, formalMetric.rms, 'Color', [0.85 0.33 0.10], 'LineWidth', 1.1);
grid(ax3, 'on');
grid(ax3, 'minor');
ylabel(ax3, 'RMS30 (m/s^2)');
xlabel(ax3, 'time');
title(ax3, sprintf('formal RMS30 max %.2f', formalMetric.rmsMax), 'Interpreter', 'none');
xtickformat(ax3, 'yyyy-MM-dd');

ax4 = nexttile;
plot(ax4, binCenters, recMetric.rms, 'Color', [0.30 0.55 0.22], 'LineWidth', 1.1);
grid(ax4, 'on');
grid(ax4, 'minor');
ylabel(ax4, 'RMS30 (m/s^2)');
xlabel(ax4, 'time');
title(ax4, sprintf('recommended RMS30 max %.2f | keep delta %.2f%% | down %.1f%% | %s', ...
    recMetric.rmsMax, keepDeltaPct, rmsReductionPct, decision), 'Interpreter', 'none');
xtickformat(ax4, 'yyyy-MM-dd');

linkaxes([ax1 ax2 ax3 ax4], 'x');
xlim(ax1, [binCenters(1), binCenters(end)]);
plotPath = fullfile(plotDir, sprintf('RecommendationVsFormal_%s.jpg', pointId));
exportgraphics(fig, plotPath, 'Resolution', 150);
close(fig);
end

function plotEnvelope(ax, binCenters, metric, label)
hold(ax, 'on');
fillBand(ax, binCenters, metric.p05, metric.p95, [0.80 0.88 0.96], 0.45, '5%~95%');
fillBand(ax, binCenters, metric.p25, metric.p75, [0.38 0.64 0.86], 0.70, '25%~75%');
plot(ax, binCenters, metric.p50, 'Color', [0 0.18 0.42], 'LineWidth', 1.3, 'DisplayName', 'median');
hold(ax, 'off');
grid(ax, 'on');
grid(ax, 'minor');
ylabel(ax, 'm/s^2');
legend(ax, 'Location', 'northeast', 'Box', 'off');
xtickformat(ax, 'yyyy-MM-dd');
set(ax, 'Tag', label);
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
fig = figure('Visible', 'off', 'Position', [100 100 1900 2200]);
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

function writeMarkdown(path, runName, summary, xlsxPath, csvPath, boardPath, policyPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Recommendation vs Formal Baseline\n\n');
fprintf(fid, '- Run: `%s`\n', runName);
fprintf(fid, '- Workbook: `%s`\n', xlsxPath);
fprintf(fid, '- CSV: `%s`\n', csvPath);
fprintf(fid, '- Review board: `%s`\n', boardPath);
fprintf(fid, '- Policy JSON: `%s`\n\n', policyPath);
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`. This review recomputes display-only recommendations from source data.\n\n');
fprintf(fid, '| Point | Source | Strategy | Rec keep %% | Keep delta %% | RMS30 max reduction %% | Decision |\n');
fprintf(fid, '|---|---|---|---:|---:|---:|---|\n');
for i = 1:height(summary)
    fprintf(fid, '| %s | %s | %s | %.3f | %.3f | %.1f | %s |\n', ...
        summary.PointID{i}, summary.PolicySource{i}, summary.Strategy{i}, ...
        summary.RecommendationKeepPct(i), summary.KeepDeltaPct(i), ...
        summary.RMS30MaxReductionPct(i), summary.Decision{i});
end
end

function stable = writeStableOutputs(stableDir, runName, summary, plotPaths, boardPath)
reviewDir = fullfile(stableDir, 'formal_baseline_review');
if ~exist(reviewDir, 'dir'), mkdir(reviewDir); end
stablePlotPaths = cell(height(summary), 1);
for i = 1:height(summary)
    pointId = summary.PointID{i};
    stablePath = fullfile(reviewDir, sprintf('CableAccelRecommendationVsFormal_%s.jpg', pointId));
    copyfile(plotPaths{i}, stablePath, 'f');
    stablePlotPaths{i} = stablePath;
end
stableBoardPath = fullfile(reviewDir, 'CableAccelRecommendationVsFormal_ReviewBoard.jpg');
copyfile(boardPath, stableBoardPath, 'f');
manifest = summary;
manifest.StablePlotPath = stablePlotPaths;
manifest.SourceRun = repmat({runName}, height(manifest), 1);
manifest.GeneratedAt = repmat({datestr(now, 'yyyy-mm-dd HH:MM:SS')}, height(manifest), 1);
manifestPath = fullfile(reviewDir, 'CableAccelRecommendationVsFormal_manifest.xlsx');
manifestCsvPath = fullfile(reviewDir, 'CableAccelRecommendationVsFormal_manifest.csv');
writetable(manifest, manifestPath, 'Sheet', 'summary');
writetable(manifest, manifestCsvPath, 'Encoding', 'UTF-8');

stable = struct();
stable.dir = reviewDir;
stable.board = stableBoardPath;
stable.manifest = manifestPath;
stable.manifest_csv = manifestCsvPath;
stable.plot_paths = stablePlotPaths;
end

function latestPaths = writeLatest(dataRoot, runName, summary, xlsxPath, csvPath, markdownPath, boardPath, policyPath, stable)
runLogs = fullfile(dataRoot, 'run_logs');
latestPaths = struct( ...
    'json', fullfile(runLogs, 'cable_accel_recommendation_vs_formal_latest.json'), ...
    'markdown', fullfile(runLogs, 'cable_accel_recommendation_vs_formal_latest.md'), ...
    'html', fullfile(runLogs, 'cable_accel_recommendation_vs_formal_latest.html'));
pointer = struct();
pointer.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
pointer.run_name = runName;
pointer.output_folder = relPath(fileparts(xlsxPath), dataRoot);
pointer.summary = relPath(markdownPath, dataRoot);
pointer.workbook = relPath(xlsxPath, dataRoot);
pointer.csv = relPath(csvPath, dataRoot);
pointer.review_board = relPath(boardPath, dataRoot);
pointer.policy_json = relPath(policyPath, dataRoot);
pointer.stable_output_dir = relPath(stable.dir, dataRoot);
pointer.stable_review_board = relPath(stable.board, dataRoot);
pointer.stable_manifest = relPath(stable.manifest, dataRoot);
pointer.review_html = relPath(latestPaths.html, dataRoot);
pointer.formal_policy = 'Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.';

fid = fopen(latestPaths.json, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(pointer));
clear cleaner;

fid = fopen(latestPaths.markdown, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Latest Zhishan Cable Acceleration Recommendation vs Formal\n\n');
fprintf(fid, '- Generated: %s\n', pointer.generated_at);
fprintf(fid, '- Run: `%s`\n', pointer.run_name);
fprintf(fid, '- Summary: `%s`\n', pointer.summary);
fprintf(fid, '- Workbook: `%s`\n', pointer.workbook);
fprintf(fid, '- Review HTML: `%s`\n', pointer.review_html);
fprintf(fid, '- Stable review board: `%s`\n', pointer.stable_review_board);
fprintf(fid, '- Policy JSON: `%s`\n', pointer.policy_json);
fprintf(fid, '- Formal policy: %s\n\n', pointer.formal_policy);
fprintf(fid, '| Point | Source | Rec keep %% | Keep delta %% | RMS30 max reduction %% | Decision |\n');
fprintf(fid, '|---|---|---:|---:|---:|---|\n');
for i = 1:height(summary)
    fprintf(fid, '| %s | %s | %.3f | %.3f | %.1f | %s |\n', ...
        summary.PointID{i}, summary.PolicySource{i}, ...
        summary.RecommendationKeepPct(i), summary.KeepDeltaPct(i), ...
        summary.RMS30MaxReductionPct(i), summary.Decision{i});
end
clear cleaner;

writeLatestHtml(latestPaths.html, pointer, summary);
end

function writeLatestHtml(path, pointer, summary)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Recommendation vs Formal</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.meta,.note{line-height:1.7;color:#4b5563;} .note{background:white;border-left:4px solid #2f6fed;padding:10px 12px;margin:14px 0 20px;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;}');
fprintf(fid, 'th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.gridpick{background:#eaf7ee;} .figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} a{color:#075da8;text-decoration:none;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230;&#25512;&#33616;&#26041;&#26696;&#22797;&#26680; / Recommendation vs Formal</h1>\n');
fprintf(fid, '<div class="meta">Generated: %s<br>Run: <code>%s</code><br>Summary: <a href="%s">%s</a><br>Workbook: <a href="%s">%s</a></div>\n', ...
    htmlText(pointer.generated_at), htmlText(pointer.run_name), htmlPath(pointer.summary), htmlText(pointer.summary), ...
    htmlPath(pointer.workbook), htmlText(pointer.workbook));
fprintf(fid, '<div class="note">&#27491;&#24335;&#39057;&#35889;/&#32034;&#21147;&#35745;&#31639;&#19981;&#21464;: <code>daily_median + [-100,100] m/s^2</code>. &#26412;&#39029;&#29992;&#28304;&#25968;&#25454;&#37325;&#31639;&#27491;&#24335;&#23637;&#31034;&#22522;&#32447;&#21644;&#25512;&#33616;&#23637;&#31034;&#26041;&#26696;&#12290;</div>\n');

fprintf(fid, '<h2>&#22797;&#26680;&#27719;&#24635; / Review Summary</h2>\n<table>\n');
fprintf(fid, '<tr><th>&#27979;&#28857;</th><th>&#31574;&#30053;&#26469;&#28304;</th><th>&#31574;&#30053;</th><th>&#25512;&#33616;&#20445;&#30041;&#29575;</th><th>&#20445;&#30041;&#29575;&#21464;&#21270;</th><th>RMS30 &#38477;&#20302;</th><th>&#21028;&#26029;</th></tr>\n');
for i = 1:height(summary)
    cls = '';
    if strcmp(summary.PolicySource{i}, 'grid')
        cls = ' class="gridpick"';
    end
    fprintf(fid, '<tr%s><td>%s</td><td>%s</td><td>%s</td><td class="num">%.3f%%</td><td class="num">%.3f%%</td><td class="num">%.1f%%</td><td>%s</td></tr>\n', ...
        cls, htmlText(summary.PointID{i}), htmlText(summary.PolicySource{i}), ...
        htmlText(summary.Strategy{i}), summary.RecommendationKeepPct(i), ...
        summary.KeepDeltaPct(i), summary.RMS30MaxReductionPct(i), htmlText(summary.Decision{i}));
end
fprintf(fid, '</table>\n');

fprintf(fid, '<h2>&#25512;&#33616;&#23545;&#27604;&#22270; / Formal vs Recommendation Figures</h2>\n<div class="grid">\n');
for i = 1:height(summary)
    rel = fullfile(pointer.output_folder, 'plots', sprintf('RecommendationVsFormal_%s.jpg', summary.PointID{i}));
    fprintf(fid, '<div class="figure"><h2>%s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(summary.PointID{i}), htmlPath(rel), htmlText(summary.PointID{i}));
end
fprintf(fid, '</div>\n<h2>&#31283;&#23450;&#24635;&#35272;&#22270; / Stable Review Board</h2>\n<div class="figure"><img src="%s" alt="stable review board"></div>\n', ...
    htmlPath(['..' filesep pointer.stable_review_board]));
fprintf(fid, '</body>\n</html>\n');
end

function out = htmlPath(pathText)
out = char(pathText);
prefix = ['run_logs' filesep];
if startsWith(out, prefix)
    out = out(numel(prefix)+1:end);
elseif startsWith(out, ['report_' filesep]) || startsWith(out, 'report_')
    out = fullfile('..', out);
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
