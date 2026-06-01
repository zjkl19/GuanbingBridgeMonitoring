function build_zhishan_report_assets_v3()
% Build report-only cleaned statistics and figures for Zhishan Bridge.
% Original raw data and formal spectrum statistics are not overwritten.

dataRoot = 'D:\芝山大桥数据\2026年1-3月';
statsDir = fullfile(dataRoot, 'stats');
outRoot = fullfile(dataRoot, 'report_assets_v3');
ensureDir(outRoot);

set(0, 'DefaultAxesFontName', 'Microsoft YaHei');
set(0, 'DefaultTextFontName', 'Microsoft YaHei');

dateNames = {};
for d = 1:31
    name = sprintf('2026-03-%02d', d);
    if isfolder(fullfile(dataRoot, name))
        dateNames{end + 1} = name; %#ok<AGROW>
    end
end

strainMap = {
    'SX-1',  'C1802191464', -283, 414
    'SX-2',  'C1802191462', -283, 414
    'SX-3',  'C1802191467', -218, 298
    'SX-4',  'C1802191469', -218, 298
    'SX-5',  'C1802191470',  -52, 405
    'SX-6',  'C1802191481',  -52, 405
    'SX-7',  'C2006010002', -218, 298
    'SX-8',  'C2006010003', -218, 298
    'SX-9',  'C2006010053', -283, 414
    'SX-10', 'C2006010049', -283, 414
};
accelMap = {
    'AZ-1', 'C2007120226'
    'AZ-2', 'C2006070240'
    'AZ-3', 'C2007120286'
    'AZ-4', 'C2007120373'
    'AZ-5', 'C2007120369'
};
cableMap = {
    'CF-1', 'C200303008', 17.5
    'CF-2', 'C200303004', 17.5
    'CF-3', 'C200303009', 3
    'CF-4', 'C200303005', 3
    'CF-5', 'C200303011', 10
    'CF-6', 'C200303006', 5
    'CF-7', 'C200303010', 17.5
    'CF-8', 'C200303007', 15
};
forceBounds = {
    'CF-1', 3146, 3846, 2972, 4020
    'CF-2', 3325, 4063, 3140, 4248
    'CF-3', 3419, 4179, 3229, 4369
    'CF-4', 3047, 3725, 2878, 3894
    'CF-5', 3474, 4246, 3281, 4439
    'CF-6', 3458, 4226, 3266, 4418
    'CF-7', 3407, 4165, 3218, 4354
    'CF-8', 3293, 4025, 3110, 4208
};

fprintf('Building cleaned strain assets...\n');
buildStrainAssets(dataRoot, outRoot, dateNames, strainMap);

fprintf('Building acceleration assets...\n');
buildAccelAssets(dataRoot, outRoot, dateNames, accelMap);

fprintf('Building cable acceleration display assets...\n');
buildCableAccelAssets(dataRoot, outRoot, dateNames, cableMap);

fprintf('Building per-cable force assets...\n');
buildCableForceAssets(statsDir, outRoot, forceBounds);

fprintf('Done: %s\n', outRoot);
end

function buildStrainAssets(dataRoot, outRoot, dateNames, pointMap)
outDir = fullfile(outRoot, 'strain');
ensureDir(outDir);
thresholdAbs = 1000;
allSamples = cell(size(pointMap, 1), 1);
plotT = cell(size(pointMap, 1), 1);
plotY = cell(size(pointMap, 1), 1);
rows = cell(size(pointMap, 1), 1);

for i = 1:size(pointMap, 1)
    point = pointMap{i, 1};
    fileId = pointMap{i, 2};
    low2 = pointMap{i, 3};
    high2 = pointMap{i, 4};
    [baseline, baselineDate] = firstDayMean(dataRoot, dateNames, fileId);
    totalCount = 0;
    validCount = 0;
    removedCount = 0;
    valuesForStats = [];
    tPlot = datetime.empty(0, 1);
    yPlot = [];
    boxSample = [];

    for d = 1:numel(dateNames)
        [t, y] = loadDailyCache(dataRoot, dateNames{d}, fileId);
        if isempty(t)
            continue;
        end
        y = y - baseline;
        finiteMask = isfinite(y);
        keepMask = finiteMask & abs(y) <= thresholdAbs;
        totalCount = totalCount + nnz(finiteMask);
        validCount = validCount + nnz(keepMask);
        removedCount = removedCount + nnz(finiteMask & ~keepMask);
        valuesForStats = [valuesForStats; y(keepMask)]; %#ok<AGROW>

        yDisplay = y;
        yDisplay(~keepMask) = NaN;
        [td, yd] = thinSeries(t, yDisplay, 650);
        [td, yd] = appendBreak(td, yd);
        tPlot = [tPlot; td]; %#ok<AGROW>
        yPlot = [yPlot; yd]; %#ok<AGROW>

        daySample = y(keepMask);
        if ~isempty(daySample)
            step = max(1, ceil(numel(daySample) / 300));
            boxSample = [boxSample; daySample(1:step:end)]; %#ok<AGROW>
        end
    end

    if isempty(valuesForStats)
        valuesForStats = NaN;
    end
    allSamples{i} = boxSample;
    plotT{i} = tPlot;
    plotY{i} = yPlot;
    rows{i} = {point, min(valuesForStats, [], 'omitnan'), max(valuesForStats, [], 'omitnan'), ...
        mean(valuesForStats, 'omitnan'), std(valuesForStats, 'omitnan'), baseline, string(baselineDate), ...
        validCount, removedCount, safeRatio(removedCount, totalCount), -thresholdAbs, thresholdAbs, low2, high2};
end

stats = cell2table(vertcat(rows{:}), 'VariableNames', ...
    {'PointID', 'Min', 'Max', 'Mean', 'Std', 'Baseline', 'BaselineDate', 'ValidCount', ...
    'RemovedCount', 'RemovedRatio', 'CleanMin', 'CleanMax', 'Level2Min', 'Level2Max'});
writetable(stats, fullfile(outDir, 'strain_stats_report_clean.xlsx'));

fig = figure('Visible', 'off', 'Position', [80, 80, 1500, 900], 'Color', 'w');
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
for k = 1:2
    ax = nexttile(tl);
    hold(ax, 'on');
    idxRange = (1:5) + (k - 1) * 5;
    for j = idxRange
        plot(ax, plotT{j}, plotY{j}, 'LineWidth', 0.75, 'DisplayName', pointMap{j, 1});
    end
    yline(ax, thresholdAbs, '--', '清洗上限', 'Color', [0.85 0.45 0.05], 'LineWidth', 0.9, 'HandleVisibility', 'off');
    yline(ax, -thresholdAbs, '--', '清洗下限', 'Color', [0.85 0.45 0.05], 'LineWidth', 0.9, 'HandleVisibility', 'off');
    grid(ax, 'on');
    xlim(ax, [datetime(2026, 3, 1), datetime(2026, 3, 31, 23, 59, 59)]);
    ylim(ax, [-1050, 1050]);
    xtickformat(ax, 'MM-dd');
    ylabel(ax, '应变 (με)');
    title(ax, sprintf('主梁应变清洗后时程 (%s~%s)', pointMap{idxRange(1), 1}, pointMap{idxRange(end), 1}));
    legend(ax, 'Location', 'southoutside', 'NumColumns', 5);
end
xlabel(tl, '日期');
exportgraphics(fig, fullfile(outDir, 'Strain_SX_ReportClean_20260301_20260331.jpg'), 'Resolution', 220);
close(fig);

fig = figure('Visible', 'off', 'Position', [100, 100, 1350, 760], 'Color', 'w');
ax = axes(fig);
hold(ax, 'on');
boxData = [];
boxGroup = [];
labels = strings(size(pointMap, 1), 1);
for i = 1:size(pointMap, 1)
    vals = allSamples{i};
    if isempty(vals)
        vals = NaN;
    end
    boxData = [boxData; vals(:)]; %#ok<AGROW>
    boxGroup = [boxGroup; i * ones(numel(vals), 1)]; %#ok<AGROW>
    labels(i) = string(pointMap{i, 1});
end
boxchart(ax, categorical(boxGroup, 1:size(pointMap, 1), labels), boxData, 'MarkerStyle', '.');
yline(ax, thresholdAbs, '--', 'Color', [0.85 0.45 0.05], 'LineWidth', 0.9, 'HandleVisibility', 'off');
yline(ax, -thresholdAbs, '--', 'Color', [0.85 0.45 0.05], 'LineWidth', 0.9, 'HandleVisibility', 'off');
grid(ax, 'on');
ylabel(ax, '应变 (με)');
title(ax, '主梁应变清洗后箱线图');
exportgraphics(fig, fullfile(outDir, 'StrainBox_SX_ReportClean_20260301_20260331.jpg'), 'Resolution', 220);
close(fig);
end

function buildAccelAssets(dataRoot, outRoot, dateNames, pointMap)
outDir = fullfile(outRoot, 'acceleration');
ensureDir(outDir);
plotT = cell(size(pointMap, 1), 1);
plotY = cell(size(pointMap, 1), 1);
rmsT = cell(size(pointMap, 1), 1);
rmsY = cell(size(pointMap, 1), 1);

for i = 1:size(pointMap, 1)
    fileId = pointMap{i, 2};
    tPlot = datetime.empty(0, 1);
    yPlot = [];
    rt = datetime.empty(0, 1);
    ry = [];
    for d = 1:numel(dateNames)
        [t, y] = loadDailyCache(dataRoot, dateNames{d}, fileId);
        if isempty(t)
            continue;
        end
        keepMask = isfinite(y) & y >= -0.2 & y <= 0.2;
        yDisplay = y;
        yDisplay(~keepMask) = NaN;
        [td, yd] = thinSeries(t, yDisplay, 1000);
        [td, yd] = appendBreak(td, yd);
        tPlot = [tPlot; td]; %#ok<AGROW>
        yPlot = [yPlot; yd]; %#ok<AGROW>
        [tr, yr] = windowRms10min(t, yDisplay, 20);
        rt = [rt; tr]; %#ok<AGROW>
        ry = [ry; yr]; %#ok<AGROW>
    end
    plotT{i} = tPlot;
    plotY{i} = yPlot;
    rmsT{i} = rt;
    rmsY{i} = ry;
end

fig = figure('Visible', 'off', 'Position', [80, 80, 1500, 760], 'Color', 'w');
ax = axes(fig);
hold(ax, 'on');
for i = 1:size(pointMap, 1)
    plot(ax, plotT{i}, plotY{i}, 'LineWidth', 0.7, 'DisplayName', pointMap{i, 1});
end
yline(ax, 0.2, '--', '过滤上限', 'Color', [0.85 0.20 0.20], 'LineWidth', 0.9, 'HandleVisibility', 'off');
yline(ax, -0.2, '--', '过滤下限', 'Color', [0.85 0.20 0.20], 'LineWidth', 0.9, 'HandleVisibility', 'off');
grid(ax, 'on');
xlim(ax, [datetime(2026, 3, 1), datetime(2026, 3, 31, 23, 59, 59)]);
ylim(ax, [-0.22, 0.22]);
xtickformat(ax, 'MM-dd');
xlabel(ax, '日期');
ylabel(ax, '加速度 (m/s^2)');
title(ax, '主梁加速度清洗后时程');
legend(ax, 'Location', 'southoutside', 'NumColumns', 5);
exportgraphics(fig, fullfile(outDir, 'Accel_AZ_ReportClean_20260301_20260331.jpg'), 'Resolution', 220);
close(fig);

fig = figure('Visible', 'off', 'Position', [80, 80, 1500, 760], 'Color', 'w');
ax = axes(fig);
hold(ax, 'on');
for i = 1:size(pointMap, 1)
    plot(ax, rmsT{i}, rmsY{i}, 'LineWidth', 0.9, 'DisplayName', pointMap{i, 1});
end
yline(ax, 0.315, '--', '一级阈值 0.315', 'Color', [0.95 0.68 0.12], 'LineWidth', 1.0, 'HandleVisibility', 'off');
yline(ax, 0.5, '--', '二级阈值 0.500', 'Color', [0.85 0.20 0.20], 'LineWidth', 1.0, 'HandleVisibility', 'off');
grid(ax, 'on');
xlim(ax, [datetime(2026, 3, 1), datetime(2026, 3, 31, 23, 59, 59)]);
xtickformat(ax, 'MM-dd');
xlabel(ax, '日期');
ylabel(ax, '10分钟RMS (m/s^2)');
title(ax, '主梁加速度10分钟RMS时程');
legend(ax, 'Location', 'southoutside', 'NumColumns', 5);
exportgraphics(fig, fullfile(outDir, 'AccelRMS10_AZ_ReportClean_20260301_20260331.jpg'), 'Resolution', 220);
close(fig);
end

function buildCableAccelAssets(dataRoot, outRoot, dateNames, pointMap)
outDir = fullfile(outRoot, 'cable_accel');
ensureDir(outDir);
for i = 1:size(pointMap, 1)
    point = pointMap{i, 1};
    fileId = pointMap{i, 2};
    threshold = pointMap{i, 3};
    tPlot = datetime.empty(0, 1);
    yPlot = [];
    for d = 1:numel(dateNames)
        [t, y] = loadDailyCache(dataRoot, dateNames{d}, fileId);
        if isempty(t)
            continue;
        end
        base = median(y(isfinite(y)), 'omitnan');
        y = y - base;
        keepMask = isfinite(y) & abs(y) <= threshold;
        yDisplay = y;
        yDisplay(~keepMask) = NaN;
        [td, yd] = thinSeries(t, yDisplay, 900);
        [td, yd] = appendBreak(td, yd);
        tPlot = [tPlot; td]; %#ok<AGROW>
        yPlot = [yPlot; yd]; %#ok<AGROW>
    end
    fig = figure('Visible', 'off', 'Position', [80, 80, 1450, 650], 'Color', 'w');
    ax = axes(fig);
    plot(ax, tPlot, yPlot, 'Color', [0.0 0.32 0.72], 'LineWidth', 0.65);
    hold(ax, 'on');
    yline(ax, threshold, '--', sprintf('+%.1f', threshold), 'Color', [0.85 0.20 0.20], 'LineWidth', 1.0);
    yline(ax, -threshold, '--', sprintf('-%.1f', threshold), 'Color', [0.85 0.20 0.20], 'LineWidth', 1.0);
    grid(ax, 'on');
    xlim(ax, [datetime(2026, 3, 1), datetime(2026, 3, 31, 23, 59, 59)]);
    ylim(ax, [-threshold * 1.08, threshold * 1.08]);
    xtickformat(ax, 'MM-dd');
    xlabel(ax, '日期');
    ylabel(ax, '索力加速度 (m/s^2)');
    title(ax, sprintf('索力加速度清洗展示 %s', point));
    exportgraphics(fig, fullfile(outDir, sprintf('CableAccel_%s_ReportClean_20260301_20260331.jpg', point)), 'Resolution', 220);
    close(fig);
end
end

function buildCableForceAssets(statsDir, outRoot, bounds)
outDir = fullfile(outRoot, 'cable_force');
ensureDir(outDir);
statsPath = fullfile(statsDir, 'cable_accel_spec_stats.xlsx');
for i = 1:size(bounds, 1)
    point = bounds{i, 1};
    level2Low = bounds{i, 2};
    level2High = bounds{i, 3};
    level3Low = bounds{i, 4};
    level3High = bounds{i, 5};
    tbl = readtable(statsPath, 'Sheet', point, 'VariableNamingRule', 'preserve');
    t = tbl.Date;
    force = tbl.CableForce_kN;
    valid = isfinite(force);
    if ~any(valid)
        continue;
    end
    yMin = min([force(valid); level3Low]);
    yMax = max([force(valid); level3High]);
    margin = max(40, (yMax - yMin) * 0.08);
    fig = figure('Visible', 'off', 'Position', [80, 80, 1450, 650], 'Color', 'w');
    ax = axes(fig);
    plot(ax, t, force, '-o', 'Color', [0.0 0.32 0.72], 'MarkerSize', 4, 'LineWidth', 1.0);
    hold(ax, 'on');
    yline(ax, level2Low, '--', '二级下限', 'Color', [0.95 0.68 0.12], 'LineWidth', 1.0);
    yline(ax, level2High, '--', '二级上限', 'Color', [0.95 0.68 0.12], 'LineWidth', 1.0);
    yline(ax, level3Low, '--', '三级下限', 'Color', [0.85 0.20 0.20], 'LineWidth', 1.0);
    yline(ax, level3High, '--', '三级上限', 'Color', [0.85 0.20 0.20], 'LineWidth', 1.0);
    grid(ax, 'on');
    xlim(ax, [datetime(2026, 3, 1), datetime(2026, 3, 31)]);
    ylim(ax, [yMin - margin, yMax + margin]);
    xtickformat(ax, 'MM-dd');
    xlabel(ax, '日期');
    ylabel(ax, '索力 (kN)');
    title(ax, sprintf('%s 索力频谱换算时程', point));
    exportgraphics(fig, fullfile(outDir, sprintf('CableForce_%s_Report_20260301_20260331.jpg', point)), 'Resolution', 220);
    close(fig);
end
end

function [baseline, baselineDate] = firstDayMean(dataRoot, dateNames, fileId)
baseline = 0;
baselineDate = "";
for d = 1:numel(dateNames)
    [~, y] = loadDailyCache(dataRoot, dateNames{d}, fileId);
    if ~isempty(y)
        vals = y(isfinite(y));
        if ~isempty(vals)
            baseline = mean(vals, 'omitnan');
            baselineDate = dateNames{d};
            return;
        end
    end
end
end

function [t, y] = loadDailyCache(dataRoot, dateName, fileId)
t = datetime.empty(0, 1);
y = [];
cacheDir = fullfile(dataRoot, dateName, '波形', 'cache');
files = dir(fullfile(cacheDir, [fileId, '_*.mat']));
if isempty(files)
    return;
end
S = load(fullfile(files(1).folder, files(1).name), 'times', 'vals');
if ~isfield(S, 'times') || ~isfield(S, 'vals')
    return;
end
t = ensureDatetime(S.times(:));
y = double(S.vals(:));
n = min(numel(t), numel(y));
t = t(1:n);
y = y(1:n);
end

function t = ensureDatetime(t)
if isdatetime(t)
    return;
end
if isnumeric(t)
    try
        t = datetime(t, 'ConvertFrom', 'datenum');
    catch
        t = datetime(t, 'ConvertFrom', 'posixtime');
    end
else
    t = datetime(t);
end
end

function [td, yd] = thinSeries(t, y, maxN)
if isempty(t)
    td = datetime.empty(0, 1);
    yd = [];
    return;
end
step = max(1, ceil(numel(t) / maxN));
idx = 1:step:numel(t);
td = t(idx);
yd = y(idx);
end

function [td, yd] = appendBreak(td, yd)
if ~isempty(td)
    td = [td; td(end) + seconds(1)];
    yd = [yd; NaN];
end
end

function [rt, ry] = windowRms10min(t, y, fs)
win = fs * 600;
if numel(y) < win
    rt = datetime.empty(0, 1);
    ry = [];
    return;
end
starts = 1:win:(numel(y) - win + 1);
rt = datetime.empty(numel(starts), 0);
ry = NaN(numel(starts), 1);
for k = 1:numel(starts)
    idx = starts(k):(starts(k) + win - 1);
    vals = y(idx);
    keep = isfinite(vals);
    rt(k, 1) = t(idx(round(end / 2)));
    if nnz(keep) >= win * 0.5
        ry(k) = sqrt(mean(vals(keep).^2, 'omitnan'));
    end
end
end

function r = safeRatio(a, b)
if b <= 0
    r = NaN;
else
    r = a / b;
end
end

function ensureDir(pathText)
if ~isfolder(pathText)
    mkdir(pathText);
end
end
