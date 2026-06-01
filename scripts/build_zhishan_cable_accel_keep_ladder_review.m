function result = build_zhishan_cable_accel_keep_ladder_review()
%BUILD_ZHISHAN_CABLE_ACCEL_KEEP_LADDER_REVIEW Build keep-rate candidate matrix.
%   Display-only review. It helps compare stricter thresholds by keep-rate
%   target without changing formal spectrum/force calculation.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
outputDir = fullfile(stableDir, 'keep_ladder_review');
plotDir = fullfile(outputDir, 'plots');
if ~exist(plotDir, 'dir'), mkdir(plotDir); end

startDate = '2026-03-01';
endDate = '2026-03-31';
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
keepTargets = [95 93 92 90 88 85];
binMinutes = 30;
segmentMinutes = 30;

latest = readJson(fullfile(dataRoot, 'run_logs', 'cable_accel_display_grid_search_latest.json'));
gridWorkbook = fullfile(dataRoot, latest.workbook);
gridEval = readtable(gridWorkbook, 'Sheet', 'grid_eval');

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
    fprintf('keep ladder %s\n', pointId);
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

    pointMetrics = containers.Map('KeyType', 'char', 'ValueType', 'any');
    pointRows = {};
    for target = keepTargets
        candidate = selectCandidate(gridEval, pointId, target);
        if isempty(candidate)
            continue;
        end
        metric = [];
        sortedCandidates = sortrows(candidate, {'DisplayRMS30Max','KeepPct'}, {'ascend','descend'});
        for c = 1:height(sortedCandidates)
            th = sortedCandidates.ThresholdAbs(c);
            seg = sortedCandidates.SegmentFilterTopPct(c);
            key = sprintf('th%g_seg%g', th, seg);
            if isKey(pointMetrics, key)
                metric = pointMetrics(key);
            else
                metric = computeCandidate(times, values, baseCount, binEdges, ...
                    binCenters, segmentEdges, th, seg);
                pointMetrics(key) = metric;
            end
            if metric.keepPct >= target
                break;
            end
        end
        strategy = strategyText(th, seg, segmentMinutes);
        pass = metric.keepPct >= target;
        pointRows(end+1, :) = {pointId, target, th, seg, strategy, baseCount, ...
            metric.keepPct, metric.rmsMax, metric.rmsP95, pass, ...
            sprintf('lowest RMS30 max found for keep target %.0f%%', target)}; %#ok<AGROW>
    end
    pointTable = cell2table(pointRows, 'VariableNames', manifestColumns());
    plotPaths{i} = plotPointMatrix(plotDir, pointId, pointTable, pointMetrics, ...
        binCenters, keepTargets);
    pointTable.PlotPath = repmat(plotPaths(i), height(pointTable), 1);
    rows = [rows; table2cell(pointTable)]; %#ok<AGROW>
end

manifest = cell2table(rows, 'VariableNames', [manifestColumns(), {'PlotPath'}]);
manifestXlsx = fullfile(outputDir, 'CableAccelKeepLadder_manifest.xlsx');
manifestCsv = fullfile(outputDir, 'CableAccelKeepLadder_manifest.csv');
writetable(manifest, manifestXlsx, 'Sheet', 'manifest');
writetable(manifest, manifestCsv, 'Encoding', 'UTF-8');

contactSheet = buildReviewBoard(plotPaths, points, outputDir, 'CableAccelKeepLadder_ContactSheet.jpg');
htmlPath = fullfile(outputDir, 'index.html');
readmePath = fullfile(outputDir, 'README.md');
writeHtml(htmlPath, manifest, contactSheet, keepTargets);
writeReadme(readmePath, manifest, keepTargets);

result = struct();
result.output_dir = outputDir;
result.html = htmlPath;
result.manifest = manifestXlsx;
result.manifest_csv = manifestCsv;
result.contact_sheet = contactSheet;
result.keep_targets = keepTargets;

fprintf('keep ladder html %s\n', htmlPath);
fprintf('keep ladder manifest %s\n', manifestXlsx);
disp(manifest(:, {'PointID','KeepTargetPct','ThresholdAbsMps2','SegmentFilterTopPctRMS30','KeepPct','RMS30Max','AcceptancePass'}));
end

function names = manifestColumns()
names = {'PointID','KeepTargetPct','ThresholdAbsMps2','SegmentFilterTopPctRMS30', ...
    'Strategy','BaseFiniteCount','KeepPct','RMS30Max','RMS30P95', ...
    'AcceptancePass','Rationale'};
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

function selected = selectCandidate(gridEval, pointId, targetKeep)
mask = strcmp(gridEval.PointID, pointId) & gridEval.KeepPct >= targetKeep;
selected = gridEval(mask, :);
end

function metric = computeCandidate(times, values, baseCount, binEdges, binCenters, ...
        segmentEdges, thresholdAbs, segmentPct)
clean = values;
clean(abs(clean) > thresholdAbs) = NaN;
if segmentPct > 0
    clean = applyTopRmsSegmentMask(times, clean, segmentEdges, segmentPct);
end
binned = binnedMetric(times, clean, binEdges, binCenters);
metric = binned;
metric.keepPct = 100 * nnz(isfinite(clean) & ~isnat(times)) / baseCount;
metric.thresholdAbs = thresholdAbs;
metric.segmentPct = segmentPct;
metric.clean = [];
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
metric.p25 = NaN(nBins, 1);
metric.p50 = NaN(nBins, 1);
metric.p75 = NaN(nBins, 1);
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
metric.p25 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 25), NaN);
metric.p50 = accumarray(idx, vals, [nBins 1], @(x) median(x, 'omitnan'), NaN);
metric.p75 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 75), NaN);
metric.rms = accumarray(idx, vals, [nBins 1], @(x) sqrt(mean(x.^2, 'omitnan')), NaN);
finiteRms = metric.rms(isfinite(metric.rms));
if ~isempty(finiteRms)
    metric.rmsMax = max(finiteRms);
    metric.rmsP95 = prctile(finiteRms, 95);
end
end

function text = strategyText(thresholdAbs, segmentPct, segmentMinutes)
parts = {sprintf('abs<=%.0f display', thresholdAbs)};
if segmentPct > 0
    parts{end+1} = sprintf('drop top %.0f%% RMS%d segments', segmentPct, segmentMinutes); %#ok<AGROW>
end
text = strjoin(parts, ' + ');
end

function plotPath = plotPointMatrix(plotDir, pointId, pointTable, pointMetrics, binCenters, keepTargets)
fig = figure('Visible', 'off', 'Position', [100 100 1500 1500]);
tiledlayout(fig, numel(keepTargets), 1, 'Padding', 'compact', 'TileSpacing', 'compact');
for r = 1:numel(keepTargets)
    target = keepTargets(r);
    ax = nexttile;
    idx = find(pointTable.KeepTargetPct == target, 1);
    if isempty(idx)
        axis(ax, 'off');
        text(ax, 0.5, 0.5, sprintf('keep >= %.0f%% missing', target), ...
            'HorizontalAlignment', 'center', 'Interpreter', 'none');
        continue;
    end
    key = sprintf('th%g_seg%g', pointTable.ThresholdAbsMps2(idx), ...
        pointTable.SegmentFilterTopPctRMS30(idx));
    metric = pointMetrics(key);
    hold(ax, 'on');
    fillBand(ax, binCenters, metric.p25, metric.p75, [0.34 0.62 0.82], 0.50);
    plot(ax, binCenters, metric.p50, 'Color', [0 0.18 0.42], 'LineWidth', 1.0);
    hold(ax, 'off');
    grid(ax, 'on');
    ylabel(ax, 'm/s^2');
    title(ax, sprintf('keep>=%.0f%% | abs<=%.0f | seg %.0f%% | keep %.2f%% | RMS30 max %.2f', ...
        target, pointTable.ThresholdAbsMps2(idx), pointTable.SegmentFilterTopPctRMS30(idx), ...
        pointTable.KeepPct(idx), pointTable.RMS30Max(idx)), 'Interpreter', 'none');
    xtickformat(ax, 'MM-dd');
    xlim(ax, [binCenters(1), binCenters(end)]);
end
sgtitle(fig, sprintf('%s keep-rate ladder candidates', pointId), 'Interpreter', 'none');
plotPath = fullfile(plotDir, sprintf('CableAccelKeepLadder_%s.jpg', pointId));
exportgraphics(fig, plotPath, 'Resolution', 150);
close(fig);
end

function fillBand(ax, t, lo, hi, color, alpha)
ok = isfinite(lo) & isfinite(hi) & ~isnat(t);
if ~any(ok)
    return;
end
runs = continuousRuns(ok);
for k = 1:size(runs, 1)
    idx = runs(k, 1):runs(k, 2);
    x = [t(idx); flipud(t(idx))];
    y = [lo(idx); flipud(hi(idx))];
    fill(ax, x, y, color, 'FaceAlpha', alpha, 'EdgeColor', 'none');
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

function writeHtml(path, manifest, contactSheet, keepTargets)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Keep Ladder Review</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #5b6ee1;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Keep-Rate Ladder Review</h1>\n');
fprintf(fid, '<div class="note">Display-only candidate matrix. Keep targets: %s. Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.</div>\n', htmlText(strjoin(string(keepTargets) + "%", ', ')));
fprintf(fid, '<h2>Contact Sheet</h2><div class="figure"><img src="%s" alt="contact sheet"></div>\n', htmlText(localFileName(contactSheet)));
fprintf(fid, '<h2>Candidate Manifest</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Keep target</th><th>Strategy</th><th>Keep %%</th><th>RMS30 max</th><th>Pass</th></tr>\n');
for i = 1:height(manifest)
    fprintf(fid, '<tr><td>%s</td><td class="num">%.0f</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%d</td></tr>\n', ...
        htmlText(manifest.PointID{i}), manifest.KeepTargetPct(i), ...
        htmlText(manifest.Strategy{i}), manifest.KeepPct(i), ...
        manifest.RMS30Max(i), manifest.AcceptancePass(i));
end
fprintf(fid, '</table>\n<h2>Per-Point Ladder Figures</h2><div class="grid">\n');
points = unique(manifest.PointID, 'stable');
for i = 1:numel(points)
    p = points{i};
    plotPath = manifest.PlotPath{find(strcmp(manifest.PointID, p), 1)};
    fprintf(fid, '<div class="figure"><h2>%s</h2><img src="plots/%s" alt="%s"></div>\n', ...
        htmlText(p), htmlText(localFileName(plotPath)), htmlText(p));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function writeReadme(path, manifest, keepTargets)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Keep-Rate Ladder Review\n\n');
fprintf(fid, '- Display-only candidate matrix.\n');
fprintf(fid, '- Keep targets: `%s`\n', strjoin(string(keepTargets), ', '));
fprintf(fid, '- Open `index.html` for visual review.\n');
fprintf(fid, '- Manifest: `CableAccelKeepLadder_manifest.xlsx`\n\n');
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '| Point | Keep target | Strategy | Keep %% | RMS30 max | Pass |\n');
fprintf(fid, '|---|---:|---|---:|---:|---:|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | %.0f | %s | %.3f | %.3f | %d |\n', ...
        manifest.PointID{i}, manifest.KeepTargetPct(i), manifest.Strategy{i}, ...
        manifest.KeepPct(i), manifest.RMS30Max(i), manifest.AcceptancePass(i));
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
