function result = build_zhishan_cable_accel_auto_knee_display_pick()
%BUILD_ZHISHAN_CABLE_ACCEL_AUTO_KNEE_DISPLAY_PICK Export auto-knee candidate.
%   Uses tradeoff-dashboard suggestions to generate a complete display-only
%   candidate. Formal spectrum/force calculation remains unchanged.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
outputDir = fullfile(stableDir, 'auto_knee_display_pick');
plotDir = fullfile(outputDir, 'plots');
if ~exist(plotDir, 'dir'), mkdir(plotDir); end

startDate = '2026-03-01';
endDate = '2026-03-31';
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
binMinutes = 30;
segmentMinutes = 30;
minKeepPct = 90;

suggestions = readtable(fullfile(stableDir, 'tradeoff_dashboard', ...
    'CableAccelTradeoffDashboard_suggestions.csv'), 'Encoding', 'UTF-8');
finalRules = readtable(fullfile(stableDir, 'CableAccelFinalDisplay_rules.csv'), ...
    'Encoding', 'UTF-8');

cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));
cfg.notify.enabled = false;
cfgLoad = removeCableAccelThresholds(cfg);
subfolder = bms.config.ConfigReader.getSubfolder(cfgLoad, 'cable_accel', '');

t0 = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
t1 = datetime(endDate, 'InputFormat', 'yyyy-MM-dd') + days(1);
binEdges = t0:minutes(binMinutes):t1;
binCenters = binEdges(1:end-1)' + minutes(binMinutes / 2);
segmentEdges = t0:minutes(segmentMinutes):t1;

rows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    fprintf('auto knee display %s\n', pointId);
    sIdx = find(strcmp(suggestions.PointID, pointId), 1);
    fIdx = find(strcmp(finalRules.PointID, pointId), 1);
    if isempty(sIdx) || isempty(fIdx)
        error('Missing suggestion or final rule for %s.', pointId);
    end

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

    th = suggestions.SuggestedThresholdAbsMps2(sIdx);
    seg = suggestions.SuggestedSegmentFilterTopPctRMS30(sIdx);
    clean = clipAbs(values, th);
    if seg > 0
        clean = applyTopRmsSegmentMask(times, clean, segmentEdges, seg);
    end
    metric = binnedMetric(times, clean, binEdges, binCenters);
    keepPct = 100 * nnz(isfinite(clean) & ~isnat(times)) / baseCount;

    finalKeepPct = finalRules.KeepPct(fIdx);
    finalRms30Max = finalRules.RMS30Max(fIdx);
    keepDelta = keepPct - finalKeepPct;
    rmsDelta = finalRms30Max - metric.rmsMax;
    rmsDeltaPct = 100 * rmsDelta / max(finalRms30Max, eps);
    useFinal = isnan(suggestions.SuggestedKeepTargetPct(sIdx));
    source = 'auto_knee';
    if useFinal
        source = 'balanced_final';
    end
    pass = keepPct >= minKeepPct && isfinite(metric.rmsMax) && rmsDeltaPct >= -0.5;
    strategy = strategyText(th, seg, segmentMinutes, source);
    rationale = sprintf('%s; RMS30 max delta %.2f (%.1f%%), keep delta %.2f%%', ...
        source, rmsDelta, rmsDeltaPct, keepDelta);

    plotPaths{i} = plotPoint(plotDir, pointId, binCenters, metric, th, seg, ...
        keepPct, finalRms30Max, rmsDeltaPct, pass, source);
    rows(end+1, :) = {pointId, source, strategy, th, seg, baseCount, ...
        keepPct, metric.rmsMax, metric.rmsP95, finalKeepPct, finalRms30Max, ...
        keepDelta, rmsDelta, rmsDeltaPct, pass, rationale, plotPaths{i}}; %#ok<AGROW>
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','SelectedSource','Strategy','ThresholdAbsMps2', ...
    'SegmentFilterTopPctRMS30','BaseFiniteCount','KeepPct', ...
    'RMS30Max','RMS30P95','FinalKeepPct','FinalRMS30Max', ...
    'KeepDeltaVsFinalPct','RMS30MaxDeltaVsFinal', ...
    'RMS30MaxDeltaVsFinalPct','AcceptancePass','Rationale','PlotPath'});

manifestXlsx = fullfile(outputDir, 'CableAccelAutoKnee_manifest.xlsx');
manifestCsv = fullfile(outputDir, 'CableAccelAutoKnee_manifest.csv');
contactSheet = buildReviewBoard(plotPaths, points, outputDir, 'CableAccelAutoKnee_ContactSheet.jpg');
htmlPath = fullfile(outputDir, 'index.html');
readmePath = fullfile(outputDir, 'README.md');
writetable(manifest, manifestXlsx, 'Sheet', 'manifest');
writetable(manifest, manifestCsv, 'Encoding', 'UTF-8');
writeHtml(htmlPath, manifest, contactSheet);
writeReadme(readmePath, manifest);

result = struct();
result.output_dir = outputDir;
result.html = htmlPath;
result.manifest = manifestXlsx;
result.manifest_csv = manifestCsv;
result.contact_sheet = contactSheet;
result.pass = all(manifest.AcceptancePass);

fprintf('auto knee html %s\n', htmlPath);
fprintf('auto knee manifest %s\n', manifestXlsx);
fprintf('auto knee pass %d\n', result.pass);
disp(manifest(:, {'PointID','SelectedSource','KeepPct','RMS30Max','FinalRMS30Max','RMS30MaxDeltaVsFinalPct','AcceptancePass'}));
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

function text = strategyText(thresholdAbs, segmentPct, segmentMinutes, source)
parts = {sprintf('%s abs<=%.0f display', source, thresholdAbs)};
if segmentPct > 0
    parts{end+1} = sprintf('drop top %.0f%% RMS%d segments', segmentPct, segmentMinutes); %#ok<AGROW>
end
text = strjoin(parts, ' + ');
end

function plotPath = plotPoint(plotDir, pointId, binCenters, metric, thresholdAbs, ...
        segmentPct, keepPct, finalRms30Max, rmsDeltaPct, pass, source)
fig = figure('Visible', 'off', 'Position', [100 100 1250 700]);
tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile;
hold(ax1, 'on');
fillBand(ax1, binCenters, metric.p05, metric.p95, [0.80 0.88 0.96], 0.45, '5%~95%');
fillBand(ax1, binCenters, metric.p25, metric.p75, [0.29 0.57 0.79], 0.70, '25%~75%');
plot(ax1, binCenters, metric.p50, 'Color', [0 0.18 0.42], 'LineWidth', 1.3, 'DisplayName', 'median');
hold(ax1, 'off');
grid(ax1, 'on');
grid(ax1, 'minor');
ylabel(ax1, 'm/s^2');
title(ax1, sprintf('%s auto-knee | %s | abs<=%.0f | seg %.0f%% | keep %.2f%%', ...
    pointId, source, thresholdAbs, segmentPct, keepPct), 'Interpreter', 'none');
legend(ax1, 'Location', 'northeast', 'Box', 'off');
xtickformat(ax1, 'yyyy-MM-dd');

ax2 = nexttile;
plot(ax2, binCenters, metric.rms, 'Color', [0.84 0.32 0.10], 'LineWidth', 1.2);
yline(ax2, finalRms30Max, '--', 'balanced final RMS30 max', ...
    'Color', [0.45 0.45 0.45], 'LabelHorizontalAlignment', 'left');
grid(ax2, 'on');
grid(ax2, 'minor');
ylabel(ax2, 'RMS30 (m/s^2)');
xlabel(ax2, 'time');
title(ax2, sprintf('RMS30 max %.2f | final %.2f | delta %.1f%% | pass %d', ...
    metric.rmsMax, finalRms30Max, rmsDeltaPct, pass), 'Interpreter', 'none');
xtickformat(ax2, 'yyyy-MM-dd');
linkaxes([ax1 ax2], 'x');
xlim(ax1, [binCenters(1), binCenters(end)]);

plotPath = fullfile(plotDir, sprintf('CableAccelAutoKnee_%s.jpg', pointId));
exportgraphics(fig, plotPath, 'Resolution', 150);
close(fig);
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

function boardPath = buildReviewBoard(plotPaths, points, outputDir, fileName)
fig = figure('Visible', 'off', 'Position', [100 100 2200 1500]);
tiledlayout(fig, 2, 4, 'Padding', 'compact', 'TileSpacing', 'compact');
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
exportgraphics(fig, boardPath, 'Resolution', 150);
close(fig);
end

function writeHtml(path, manifest, contactSheet)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Auto-Knee Candidate</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #7c3aed;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.auto_knee{background:#f4edff}.balanced_final{background:#eaf7f2}.fail{background:#fff1f2}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Auto-Knee Candidate</h1>\n');
fprintf(fid, '<div class="note">Display-only candidate generated from tradeoff-dashboard knee suggestions. Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.</div>\n');
fprintf(fid, '<h2>Manifest</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Source</th><th>Strategy</th><th>Keep %%</th><th>RMS30 max</th><th>Final RMS30 max</th><th>RMS30 delta %%</th><th>Pass</th></tr>\n');
for i = 1:height(manifest)
    cls = manifest.SelectedSource{i};
    if ~manifest.AcceptancePass(i), cls = 'fail'; end
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%d</td></tr>\n', ...
        htmlText(cls), htmlText(manifest.PointID{i}), htmlText(manifest.SelectedSource{i}), ...
        htmlText(manifest.Strategy{i}), manifest.KeepPct(i), manifest.RMS30Max(i), ...
        manifest.FinalRMS30Max(i), manifest.RMS30MaxDeltaVsFinalPct(i), manifest.AcceptancePass(i));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Contact Sheet</h2><div class="figure"><img src="%s" alt="contact sheet"></div>\n', htmlText(localFileName(contactSheet)));
fprintf(fid, '<h2>Per-Point Figures</h2><div class="grid">\n');
for i = 1:height(manifest)
    fprintf(fid, '<div class="figure"><h2>%s</h2><img src="plots/%s" alt="%s"></div>\n', ...
        htmlText(manifest.PointID{i}), htmlText(localFileName(manifest.PlotPath{i})), ...
        htmlText(manifest.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function writeReadme(path, manifest)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Auto-Knee Candidate\n\n');
fprintf(fid, '- Display-only candidate generated from tradeoff-dashboard knee suggestions.\n');
fprintf(fid, '- Open `index.html` for visual review.\n');
fprintf(fid, '- Manifest: `CableAccelAutoKnee_manifest.xlsx`\n\n');
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '| Point | Source | Strategy | Keep %% | RMS30 max | Final RMS30 max | Delta %% | Pass |\n');
fprintf(fid, '|---|---|---|---:|---:|---:|---:|---:|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | %s | %s | %.3f | %.3f | %.3f | %.1f | %d |\n', ...
        manifest.PointID{i}, manifest.SelectedSource{i}, manifest.Strategy{i}, ...
        manifest.KeepPct(i), manifest.RMS30Max(i), manifest.FinalRMS30Max(i), ...
        manifest.RMS30MaxDeltaVsFinalPct(i), manifest.AcceptancePass(i));
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
