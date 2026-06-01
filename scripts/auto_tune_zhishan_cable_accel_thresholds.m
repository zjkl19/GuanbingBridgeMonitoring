projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
startDate = '2026-03-01';
endDate = '2026-03-31';
thresholdGrid = [2 5 10 15 20 30 40 50 75 100 150 200 300 500 1000];
formalKeepTargetPct = 97;
visualKeepTargetPct = 95;
visualMinRmsReductionPct = 25;
visualMaxKeepLossPct = 5;
binMinutes = 30;

cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));
cfg.notify.enabled = false;
cfgLoad = removeCableAccelThresholds(cfg);
subfolder = bms.config.ConfigReader.getSubfolder(cfg, 'cable_accel', '');
points = resolveCableAccelPoints(cfg);

stamp = datestr(now, 'yyyymmdd_HHMMSS');
runName = ['cable_accel_auto_tune_' stamp];
outRoot = fullfile(dataRoot, 'run_logs', runName);
plotDir = fullfile(outRoot, 'threshold_plots');
compareDir = fullfile(outRoot, 'formal_vs_selected_compare');
visualRelDir = fullfile('run_logs', runName, 'selected_visual_envelope');
visualDir = fullfile(dataRoot, visualRelDir);
if ~exist(plotDir, 'dir'), mkdir(plotDir); end
if ~exist(compareDir, 'dir'), mkdir(compareDir); end
if ~exist(visualDir, 'dir'), mkdir(visualDir); end

t0 = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
t1 = datetime(endDate, 'InputFormat', 'yyyy-MM-dd') + days(1);
binEdges = t0:minutes(binMinutes):t1;
binCenters = binEdges(1:end-1)' + minutes(binMinutes / 2);

thresholdRows = {};
pointRows = {};
rmsByPoint = struct();

for i = 1:numel(points)
    pointId = points{i};
    fprintf('auto tune cable_accel %s\n', pointId);
    [times, values] = load_timeseries_range(dataRoot, subfolder, pointId, ...
        startDate, endDate, cfgLoad, 'cable_accel');
    times = times(:);
    values = double(values(:));
    baseMask = isfinite(values) & ~isnat(times);
    baseCount = nnz(baseMask);
    if baseCount == 0
        continue;
    end

    metrics = repmat(emptyMetric(), numel(thresholdGrid), 1);
    for j = 1:numel(thresholdGrid)
        th = thresholdGrid(j);
        metrics(j) = thresholdMetric(times, values, th, baseCount, binEdges, binCenters);
        thresholdRows(end+1, :) = {pointId, th, baseCount, metrics(j).kept_count, ...
            metrics(j).keep_pct, metrics(j).clip_pct, metrics(j).rms30_max, ...
            metrics(j).rms30_p95, metrics(j).abs_p99, metrics(j).max_abs};
    end

    formalMetric = metrics(thresholdGrid == 100);
    visualIdx = find([metrics.keep_pct] >= visualKeepTargetPct, 1, 'first');
    if isempty(visualIdx)
        visualIdx = numel(thresholdGrid);
    end
    visualCandidate = metrics(visualIdx);
    visualCandidateThreshold = thresholdGrid(visualIdx);

    formalThreshold = 100;
    rmsReduction = 100 * (formalMetric.rms30_max - visualCandidate.rms30_max) / max(formalMetric.rms30_max, eps);
    keepLoss = formalMetric.keep_pct - visualCandidate.keep_pct;
    if rmsReduction >= visualMinRmsReductionPct && keepLoss <= visualMaxKeepLossPct
        selectedVisualThreshold = visualCandidateThreshold;
        selectedVisualMetric = visualCandidate;
        decision = 'use tighter display threshold';
    else
        selectedVisualThreshold = formalThreshold;
        selectedVisualMetric = formalMetric;
        if rmsReduction < 10
            decision = 'keep formal threshold, little display benefit';
        else
            decision = 'keep formal threshold for calculation stability';
        end
    end
    [diagnosis, needsDataQualityReview] = diagnosePoint(formalThreshold, visualCandidateThreshold, ...
        selectedVisualThreshold, rmsReduction, keepLoss, visualMinRmsReductionPct, visualMaxKeepLossPct);

    pointRows(end+1, :) = {pointId, formalThreshold, visualCandidateThreshold, ...
        selectedVisualThreshold, formalMetric.keep_pct, visualCandidate.keep_pct, ...
        selectedVisualMetric.keep_pct, keepLoss, formalMetric.rms30_max, ...
        visualCandidate.rms30_max, selectedVisualMetric.rms30_max, rmsReduction, ...
        decision, diagnosis, needsDataQualityReview};

    plotThresholdDecision(plotDir, pointId, thresholdGrid, metrics, formalThreshold, ...
        visualCandidateThreshold, selectedVisualThreshold, formalMetric, visualCandidate, binCenters);
    rmsByPoint.(safeField(pointId)).times = times;
    rmsByPoint.(safeField(pointId)).values = values;
    rmsByPoint.(safeField(pointId)).selectedVisualThreshold = selectedVisualThreshold;
end

thresholdEval = cell2table(thresholdRows, 'VariableNames', { ...
    'PointID','ThresholdAbs','BaseFiniteCount','KeptCount','KeepPct','ClipPct', ...
    'RMS30Max','RMS30P95','AbsP99','MaxAbs'});
pointRecommendation = cell2table(pointRows, 'VariableNames', { ...
    'PointID','FormalThresholdAbs','P95CandidateThresholdAbs','SelectedDisplayThresholdAbs', ...
    'FormalKeepPct','P95CandidateKeepPct','SelectedDisplayKeepPct','CandidateKeepLossPct', ...
    'FormalRMS30Max','P95CandidateRMS30Max','SelectedDisplayRMS30Max', ...
    'CandidateRMS30ReductionPct','Decision','Diagnosis','NeedsDataQualityReview'});
globalSummary = buildGlobalSummary(thresholdEval, thresholdGrid, formalKeepTargetPct);

xlsxPath = fullfile(outRoot, 'cable_accel_auto_tune.xlsx');
writetable(thresholdEval, xlsxPath, 'Sheet', 'threshold_eval');
writetable(pointRecommendation, xlsxPath, 'Sheet', 'point_recommendation');
writetable(globalSummary, xlsxPath, 'Sheet', 'global_summary');

csvPath = fullfile(outRoot, 'cable_accel_auto_tune_recommendation.csv');
writetable(pointRecommendation, csvPath, 'Encoding', 'UTF-8');

writeMarkdown(fullfile(outRoot, 'cable_accel_auto_tune_summary.md'), ...
    xlsxPath, csvPath, plotDir, compareDir, visualDir, globalSummary, pointRecommendation, ...
    formalKeepTargetPct, visualKeepTargetPct, visualMinRmsReductionPct, visualMaxKeepLossPct);

styleSpec = bms.analyzer.DynamicAccelerationPipeline.spec('cable_accel');
styleSpec.envelopeOutputDir = visualRelDir;
styleSpec.envelopeFilePrefix = 'AutoTuneVisualEnvelope30';
style = bms.analyzer.DynamicAccelerationPipeline.plotStyle(cfg, styleSpec);
for i = 1:height(pointRecommendation)
    pointId = pointRecommendation.PointID{i};
    rec = rmsByPoint.(safeField(pointId));
    cleanValues = rec.values;
    cleanValues(abs(cleanValues) > rec.selectedVisualThreshold) = NaN;
    bms.analyzer.DynamicAccelerationPlotService.plotEnvelopeCurve( ...
        dataRoot, pointId, rec.times, cleanValues, style, cfg, styleSpec);
    plotFormalSelectedComparison(compareDir, pointId, rec.times, rec.values, ...
        pointRecommendation.FormalThresholdAbs(i), pointRecommendation.SelectedDisplayThresholdAbs(i), ...
        binEdges, binCenters, binMinutes);
end

boardPath = buildReviewBoard(visualDir, outRoot, points);
compareBoardPath = buildCompareBoard(compareDir, outRoot, points);
latestPaths = writeLatestIndex(dataRoot, runName, outRoot, xlsxPath, csvPath, plotDir, compareDir, ...
    visualDir, boardPath, compareBoardPath, globalSummary, pointRecommendation);

fprintf('wrote %s\n', xlsxPath);
fprintf('wrote %s\n', csvPath);
fprintf('wrote %s\n', fullfile(outRoot, 'cable_accel_auto_tune_summary.md'));
fprintf('plots %s\n', plotDir);
fprintf('formal/selected compare %s\n', compareDir);
fprintf('visual envelope %s\n', visualDir);
fprintf('review board %s\n', boardPath);
fprintf('compare board %s\n', compareBoardPath);
fprintf('latest json %s\n', latestPaths.json);
fprintf('latest markdown %s\n', latestPaths.markdown);
fprintf('latest html %s\n', latestPaths.html);
fprintf('acceptance json %s\n', latestPaths.acceptance_json);
fprintf('acceptance markdown %s\n', latestPaths.acceptance_markdown);
disp(globalSummary);
disp(pointRecommendation);

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

function points = resolveCableAccelPoints(cfg)
    points = {};
    if isfield(cfg, 'points') && isfield(cfg.points, 'cable_accel')
        points = cellstr(string(cfg.points.cable_accel(:)));
    end
    if isempty(points)
        points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
    end
end

function m = emptyMetric()
    m = struct('kept_count', 0, 'keep_pct', NaN, 'clip_pct', NaN, ...
        'rms30', [], 'rms30_max', NaN, 'rms30_p95', NaN, ...
        'abs_p99', NaN, 'max_abs', NaN);
end

function m = thresholdMetric(times, values, thresholdAbs, baseCount, binEdges, binCenters)
    m = emptyMetric();
    clean = values;
    clean(abs(clean) > thresholdAbs) = NaN;
    keepMask = isfinite(clean) & ~isnat(times);
    m.kept_count = nnz(keepMask);
    m.keep_pct = 100 * m.kept_count / max(baseCount, 1);
    m.clip_pct = 100 - m.keep_pct;
    if m.kept_count > 0
        kept = clean(keepMask);
        m.abs_p99 = prctile(abs(kept), 99);
        m.max_abs = max(abs(kept), [], 'omitnan');
    end
    [m.rms30, m.rms30_max, m.rms30_p95] = binnedRms(times, clean, binEdges, binCenters);
end

function [rmsValues, rmsMax, rmsP95] = binnedRms(times, values, binEdges, binCenters)
    rmsValues = NaN(numel(binCenters), 1);
    rmsMax = NaN;
    rmsP95 = NaN;
    valid = isfinite(values) & ~isnat(times);
    if ~any(valid)
        return;
    end
    idx = discretize(times(valid), binEdges);
    good = ~isnan(idx);
    if ~any(good)
        return;
    end
    vals = values(valid);
    vals = vals(good);
    idx = idx(good);
    rmsValues = accumarray(idx, vals, [numel(binCenters) 1], @(x) sqrt(mean(x.^2, 'omitnan')), NaN);
    finiteRms = rmsValues(isfinite(rmsValues));
    if ~isempty(finiteRms)
        rmsMax = max(finiteRms);
        rmsP95 = prctile(finiteRms, 95);
    end
end

function [diagnosis, needsDataQualityReview] = diagnosePoint(formalThreshold, visualCandidateThreshold, ...
        selectedVisualThreshold, rmsReduction, keepLoss, minRmsReductionPct, maxKeepLossPct)
    if selectedVisualThreshold < formalThreshold
        diagnosis = 'threshold display tuning helps';
        needsDataQualityReview = false;
    elseif visualCandidateThreshold >= formalThreshold
        diagnosis = 'no safe tighter threshold at target keep rate';
        needsDataQualityReview = true;
    elseif keepLoss > maxKeepLossPct
        diagnosis = 'tighter threshold deletes too much data';
        needsDataQualityReview = true;
    elseif rmsReduction < minRmsReductionPct
        diagnosis = 'safe tighter threshold has limited RMS benefit';
        needsDataQualityReview = true;
    else
        diagnosis = 'keep formal threshold';
        needsDataQualityReview = false;
    end
end

function plotThresholdDecision(plotDir, pointId, thresholdGrid, metrics, formalThreshold, ...
        visualCandidateThreshold, selectedVisualThreshold, formalMetric, visualCandidate, binCenters)
    fig = figure('Visible', 'off', 'Position', [100 100 1200 720]);
    tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    ax1 = nexttile;
    yyaxis(ax1, 'left');
    plot(ax1, thresholdGrid, [metrics.keep_pct], '-o', 'LineWidth', 1.2);
    ylabel(ax1, 'keep of base finite (%)');
    ylim(ax1, [max(0, min([metrics.keep_pct]) - 2), 100.5]);
    yyaxis(ax1, 'right');
    plot(ax1, thresholdGrid, [metrics.rms30_max], '-s', 'LineWidth', 1.2);
    ylabel(ax1, '30 min RMS max (m/s^2)');
    xlabel(ax1, 'absolute threshold (m/s^2)');
    title(ax1, sprintf('Cable acceleration threshold search %s', pointId), 'Interpreter', 'none');
    grid(ax1, 'on');
    xline(ax1, formalThreshold, '--', 'formal', 'LabelVerticalAlignment', 'bottom');
    xline(ax1, visualCandidateThreshold, ':', 'p95 candidate', 'LabelVerticalAlignment', 'middle');
    xline(ax1, selectedVisualThreshold, '-.', 'selected display', 'LabelVerticalAlignment', 'top');

    ax2 = nexttile;
    formalIdx = find(thresholdGrid == formalThreshold, 1);
    candidateIdx = find(thresholdGrid == visualCandidateThreshold, 1);
    selectedIdx = find(thresholdGrid == selectedVisualThreshold, 1);
    hold(ax2, 'on');
    plot(ax2, binCenters, metrics(formalIdx).rms30, 'LineWidth', 1.1, 'DisplayName', sprintf('formal %.0f', formalThreshold));
    plot(ax2, binCenters, metrics(candidateIdx).rms30, 'LineWidth', 1.1, 'DisplayName', sprintf('p95 candidate %.0f', visualCandidateThreshold));
    plot(ax2, binCenters, metrics(selectedIdx).rms30, 'LineWidth', 1.1, 'DisplayName', sprintf('selected %.0f', selectedVisualThreshold));
    hold(ax2, 'off');
    grid(ax2, 'on');
    grid(ax2, 'minor');
    xlim(ax2, [binCenters(1), binCenters(end)]);
    xtickformat(ax2, 'yyyy-MM-dd');
    ylabel(ax2, '30 min RMS (m/s^2)');
    xlabel(ax2, 'time');
    legend(ax2, 'Location', 'northeast', 'Box', 'off');
    subtitle(ax2, sprintf('formal max %.3f, p95 max %.3f', formalMetric.rms30_max, visualCandidate.rms30_max));

    outPath = fullfile(plotDir, sprintf('AutoTuneThreshold_%s.jpg', pointId));
    exportgraphics(fig, outPath, 'Resolution', 150);
    close(fig);
end

function globalSummary = buildGlobalSummary(thresholdEval, thresholdGrid, formalKeepTargetPct)
    rows = {};
    for i = 1:numel(thresholdGrid)
        th = thresholdGrid(i);
        rows(end+1, :) = {th, ...
            min(thresholdEval.KeepPct(thresholdEval.ThresholdAbs == th)), ...
            mean(thresholdEval.KeepPct(thresholdEval.ThresholdAbs == th), 'omitnan'), ...
            max(thresholdEval.RMS30Max(thresholdEval.ThresholdAbs == th)), ...
            mean(thresholdEval.RMS30Max(thresholdEval.ThresholdAbs == th), 'omitnan')}; %#ok<AGROW>
    end
    globalSummary = cell2table(rows, 'VariableNames', ...
        {'ThresholdAbs','MinKeepPct','MeanKeepPct','MaxRMS30Max','MeanRMS30Max'});
    hit = find(globalSummary.MinKeepPct >= formalKeepTargetPct, 1, 'first');
    selected = false(height(globalSummary), 1);
    if ~isempty(hit)
        selected(hit) = true;
    end
    globalSummary.SelectedFormal = selected;
end

function writeMarkdown(path, xlsxPath, csvPath, plotDir, compareDir, visualDir, globalSummary, pointRecommendation, ...
        formalKeepTargetPct, visualKeepTargetPct, visualMinRmsReductionPct, visualMaxKeepLossPct)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    cleaner = onCleanup(@() fclose(fid));
    [runDir, xlsxBase] = fileparts(xlsxPath);
    [~, csvBase] = fileparts(csvPath);
    [~, runName] = fileparts(runDir);
    [~, plotName] = fileparts(plotDir);
    [~, compareName] = fileparts(compareDir);
    [~, visualName] = fileparts(visualDir);
    selected = globalSummary(globalSummary.SelectedFormal, :);
    if isempty(selected)
        selectedThreshold = NaN;
    else
        selectedThreshold = selected.ThresholdAbs(1);
    end
    fprintf(fid, '# Zhishan Cable Acceleration Auto Tune\n\n');
    fprintf(fid, '- Generated: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, '- Data root: configured Zhishan data root.\n');
    fprintf(fid, '- Formal rule: smallest global threshold with every point keep >= %.1f%%.\n', formalKeepTargetPct);
    fprintf(fid, '- Display rule: p95 candidate keeps >= %.1f%%; use it only when RMS30 max drops >= %.1f%% and keep loss <= %.1f%%.\n', ...
        visualKeepTargetPct, visualMinRmsReductionPct, visualMaxKeepLossPct);
    fprintf(fid, '- Selected formal threshold: `[-%.0f, %.0f] m/s^2` after daily median baseline removal.\n', selectedThreshold, selectedThreshold);
    fprintf(fid, '- Output folder: `run_logs/%s`\n', runName);
    fprintf(fid, '- Workbook: `run_logs/%s/%s.xlsx`\n', runName, xlsxBase);
    fprintf(fid, '- CSV: `run_logs/%s/%s.csv`\n', runName, csvBase);
    fprintf(fid, '- Threshold plots: `run_logs/%s/%s`\n', runName, plotName);
    fprintf(fid, '- Formal vs selected comparison plots: `run_logs/%s/%s`\n', runName, compareName);
    fprintf(fid, '- Selected visual envelope plots: `run_logs/%s/%s`\n\n', runName, visualName);

    fprintf(fid, '## Point Recommendations\n\n');
    fprintf(fid, '| Point | Formal abs | P95 candidate abs | Selected display abs | Formal keep %% | Selected keep %% | Formal RMS30 max | Selected RMS30 max | P95 reduction %% | Decision | Diagnosis |\n');
    fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|\n');
    for i = 1:height(pointRecommendation)
        fprintf(fid, '| %s | %.0f | %.0f | %.0f | %.3f | %.3f | %.3f | %.3f | %.1f | %s | %s |\n', ...
            pointRecommendation.PointID{i}, pointRecommendation.FormalThresholdAbs(i), ...
            pointRecommendation.P95CandidateThresholdAbs(i), pointRecommendation.SelectedDisplayThresholdAbs(i), ...
            pointRecommendation.FormalKeepPct(i), pointRecommendation.SelectedDisplayKeepPct(i), ...
            pointRecommendation.FormalRMS30Max(i), pointRecommendation.SelectedDisplayRMS30Max(i), ...
            pointRecommendation.CandidateRMS30ReductionPct(i), pointRecommendation.Decision{i}, ...
            pointRecommendation.Diagnosis{i});
    end
end

function plotFormalSelectedComparison(compareDir, pointId, times, values, formalThreshold, selectedThreshold, ...
        binEdges, binCenters, binMinutes)
    formal = envelopeMetric(times, values, formalThreshold, binEdges, binCenters);
    selected = envelopeMetric(times, values, selectedThreshold, binEdges, binCenters);

    envYLim = paddedLim([formal.p05; formal.p95; selected.p05; selected.p95]);
    rmsYLim = paddedLim([formal.rms30; selected.rms30]);
    fig = figure('Visible', 'off', 'Position', [100 100 1300 720]);
    tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    ax1 = nexttile;
    plotEnvelopeAxes(ax1, binCenters, formal, envYLim, ...
        sprintf('%s formal +/-%.0f m/s^2', pointId, formalThreshold));
    ax2 = nexttile;
    plotEnvelopeAxes(ax2, binCenters, selected, envYLim, ...
        sprintf('%s selected display +/-%.0f m/s^2', pointId, selectedThreshold));

    ax3 = nexttile;
    plotRmsAxes(ax3, binCenters, formal.rms30, rmsYLim, ...
        sprintf('%d min RMS formal, max %.3f', binMinutes, formal.rms30_max));
    ax4 = nexttile;
    plotRmsAxes(ax4, binCenters, selected.rms30, rmsYLim, ...
        sprintf('%d min RMS selected, max %.3f', binMinutes, selected.rms30_max));

    linkaxes([ax1 ax2 ax3 ax4], 'x');
    xlim(ax1, [binCenters(1), binCenters(end)]);
    outPath = fullfile(compareDir, sprintf('FormalVsSelected_%s.jpg', pointId));
    exportgraphics(fig, outPath, 'Resolution', 150);
    close(fig);
end

function metric = envelopeMetric(times, values, thresholdAbs, binEdges, binCenters)
    clean = double(values(:));
    clean(abs(clean) > thresholdAbs) = NaN;
    valid = isfinite(clean) & ~isnat(times);
    nBins = numel(binCenters);
    metric = struct('p05', NaN(nBins, 1), 'p50', NaN(nBins, 1), ...
        'p95', NaN(nBins, 1), 'rms30', NaN(nBins, 1), 'rms30_max', NaN);
    if ~any(valid)
        return;
    end
    idx = discretize(times(valid), binEdges);
    good = ~isnan(idx);
    if ~any(good)
        return;
    end
    vals = clean(valid);
    vals = vals(good);
    idx = idx(good);
    metric.p05 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 5), NaN);
    metric.p50 = accumarray(idx, vals, [nBins 1], @(x) median(x, 'omitnan'), NaN);
    metric.p95 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 95), NaN);
    metric.rms30 = accumarray(idx, vals, [nBins 1], @(x) sqrt(mean(x.^2, 'omitnan')), NaN);
    finiteRms = metric.rms30(isfinite(metric.rms30));
    if ~isempty(finiteRms)
        metric.rms30_max = max(finiteRms);
    end
end

function plotEnvelopeAxes(ax, binCenters, metric, yLimits, titleText)
    hold(ax, 'on');
    bms.analyzer.DynamicAccelerationPlotService.fillEnvelopeBand(ax, binCenters, metric.p05, metric.p95, ...
        [0.55 0.75 0.93], '5%~95%');
    plot(ax, binCenters, metric.p50, 'Color', [0 0.25 0.55], 'LineWidth', 1.1, 'DisplayName', 'median');
    hold(ax, 'off');
    grid(ax, 'on');
    grid(ax, 'minor');
    ylim(ax, yLimits);
    ylabel(ax, 'm/s^2');
    title(ax, titleText, 'Interpreter', 'none');
    legend(ax, 'Location', 'northeast', 'Box', 'off');
    xtickformat(ax, 'yyyy-MM-dd');
end

function plotRmsAxes(ax, binCenters, rmsValues, yLimits, titleText)
    plot(ax, binCenters, rmsValues, 'LineWidth', 1.1, 'Color', [0.85 0.33 0.10]);
    grid(ax, 'on');
    grid(ax, 'minor');
    ylim(ax, yLimits);
    ylabel(ax, 'm/s^2');
    xlabel(ax, 'time');
    title(ax, titleText, 'Interpreter', 'none');
    xtickformat(ax, 'yyyy-MM-dd');
end

function yLimits = paddedLim(values)
    values = values(isfinite(values));
    if isempty(values)
        yLimits = [0 1];
        return;
    end
    lo = min(values);
    hi = max(values);
    if lo == hi
        pad = max(1, abs(lo) * 0.1);
    else
        pad = 0.08 * (hi - lo);
    end
    yLimits = [lo - pad, hi + pad];
end

function boardPath = buildReviewBoard(visualDir, outRoot, points)
    fig = figure('Visible', 'off', 'Position', [100 100 1800 2200]);
    tiledlayout(fig, 4, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
    for i = 1:numel(points)
        pointId = points{i};
        nexttile;
        match = dir(fullfile(visualDir, sprintf('AutoTuneVisualEnvelope30_%s_*.jpg', pointId)));
        if isempty(match)
            axis off;
            text(0.5, 0.5, sprintf('%s missing', pointId), 'HorizontalAlignment', 'center', 'Interpreter', 'none');
        else
            [~, idx] = max([match.datenum]);
            imgPath = fullfile(match(idx).folder, match(idx).name);
            imshow(imread(imgPath));
            title(pointId, 'Interpreter', 'none');
        end
    end
    boardPath = fullfile(outRoot, 'auto_tune_selected_visual_review_board.jpg');
    exportgraphics(fig, boardPath, 'Resolution', 160);
    close(fig);
end

function boardPath = buildCompareBoard(compareDir, outRoot, points)
    fig = figure('Visible', 'off', 'Position', [100 100 2200 2600]);
    tiledlayout(fig, 4, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
    for i = 1:numel(points)
        pointId = points{i};
        nexttile;
        path = fullfile(compareDir, sprintf('FormalVsSelected_%s.jpg', pointId));
        if isfile(path)
            imshow(imread(path));
            title(pointId, 'Interpreter', 'none');
        else
            axis off;
            text(0.5, 0.5, sprintf('%s missing', pointId), 'HorizontalAlignment', 'center', 'Interpreter', 'none');
        end
    end
    boardPath = fullfile(outRoot, 'auto_tune_formal_vs_selected_review_board.jpg');
    exportgraphics(fig, boardPath, 'Resolution', 160);
    close(fig);
end

function latestPaths = writeLatestIndex(dataRoot, runName, outRoot, xlsxPath, csvPath, plotDir, compareDir, ...
        visualDir, boardPath, compareBoardPath, globalSummary, pointRecommendation)
    runLogs = fullfile(dataRoot, 'run_logs');
    latestPaths = struct( ...
        'json', fullfile(runLogs, 'cable_accel_auto_tune_latest.json'), ...
        'markdown', fullfile(runLogs, 'cable_accel_auto_tune_latest.md'), ...
        'html', fullfile(runLogs, 'cable_accel_auto_tune_latest.html'), ...
        'acceptance_json', fullfile(runLogs, 'cable_accel_auto_tune_acceptance_latest.json'), ...
        'acceptance_markdown', fullfile(runLogs, 'cable_accel_auto_tune_acceptance_latest.md'));

    selected = globalSummary(globalSummary.SelectedFormal, :);
    if isempty(selected)
        formalThreshold = NaN;
    else
        formalThreshold = selected.ThresholdAbs(1);
    end

    pointer = struct();
    pointer.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    pointer.run_name = runName;
    pointer.formal_threshold_abs = formalThreshold;
    pointer.formal_threshold_range = [-formalThreshold, formalThreshold];
    pointer.output_folder = relPath(outRoot, dataRoot);
    pointer.summary = fullfile('run_logs', runName, 'cable_accel_auto_tune_summary.md');
    pointer.workbook = relPath(xlsxPath, dataRoot);
    pointer.csv = relPath(csvPath, dataRoot);
    pointer.threshold_plots = relPath(plotDir, dataRoot);
    pointer.formal_vs_selected_compare = relPath(compareDir, dataRoot);
    pointer.selected_visual_envelope = relPath(visualDir, dataRoot);
    pointer.selected_visual_review_board = relPath(boardPath, dataRoot);
    pointer.formal_vs_selected_review_board = relPath(compareBoardPath, dataRoot);
    pointer.review_html = relPath(latestPaths.html, dataRoot);
    pointer.acceptance_json = relPath(latestPaths.acceptance_json, dataRoot);
    pointer.acceptance_markdown = relPath(latestPaths.acceptance_markdown, dataRoot);
    qualityMask = logical(pointRecommendation.NeedsDataQualityReview);
    pointer.threshold_limited_or_quality_review_points = pointList(pointRecommendation.PointID(qualityMask));
    pointer.point_diagnosis = pointDiagnosisStruct(pointRecommendation);
    pointer.display_thresholds = struct();
    for i = 1:height(pointRecommendation)
        field = safeField(pointRecommendation.PointID{i});
        pointer.display_thresholds.(field) = pointRecommendation.SelectedDisplayThresholdAbs(i);
    end

    fid = fopen(latestPaths.json, 'w', 'n', 'UTF-8');
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(pointer));

    writeLatestMarkdown(latestPaths.markdown, pointer, pointRecommendation);
    writeLatestHtml(latestPaths.html, pointer, pointRecommendation);
    acceptance = buildAcceptance(pointer, pointRecommendation, globalSummary);
    writeAcceptanceJson(latestPaths.acceptance_json, acceptance);
    writeAcceptanceMarkdown(latestPaths.acceptance_markdown, acceptance);
end

function writeLatestMarkdown(path, pointer, pointRecommendation)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '# Latest Zhishan Cable Acceleration Auto Tune\n\n');
    fprintf(fid, '- Generated: %s\n', pointer.generated_at);
    fprintf(fid, '- Run: `%s`\n', pointer.run_name);
    fprintf(fid, '- Formal threshold: `[-%.0f, %.0f] m/s^2`\n', ...
        pointer.formal_threshold_abs, pointer.formal_threshold_abs);
    fprintf(fid, '- Summary: `%s`\n', pointer.summary);
    fprintf(fid, '- Workbook: `%s`\n', pointer.workbook);
    fprintf(fid, '- Formal-vs-selected board: `%s`\n', pointer.formal_vs_selected_review_board);
    fprintf(fid, '- Selected-display board: `%s`\n\n', pointer.selected_visual_review_board);
    fprintf(fid, '- Acceptance: `%s`\n\n', pointer.acceptance_markdown);

    fprintf(fid, '| Point | Formal abs | Selected display abs | Selected keep %% | Selected RMS30 max | Decision | Diagnosis |\n');
    fprintf(fid, '|---|---:|---:|---:|---:|---|---|\n');
    for i = 1:height(pointRecommendation)
        fprintf(fid, '| %s | %.0f | %.0f | %.3f | %.3f | %s | %s |\n', ...
            pointRecommendation.PointID{i}, pointRecommendation.FormalThresholdAbs(i), ...
            pointRecommendation.SelectedDisplayThresholdAbs(i), pointRecommendation.SelectedDisplayKeepPct(i), ...
            pointRecommendation.SelectedDisplayRMS30Max(i), pointRecommendation.Decision{i}, ...
            pointRecommendation.Diagnosis{i});
    end
end

function acceptance = buildAcceptance(pointer, pointRecommendation, globalSummary)
    changedMask = pointRecommendation.SelectedDisplayThresholdAbs ~= pointRecommendation.FormalThresholdAbs;
    stableMask = ~changedMask;
    qualityMask = logical(pointRecommendation.NeedsDataQualityReview);
    selectedGlobal = globalSummary(globalSummary.SelectedFormal, :);
    if isempty(selectedGlobal)
        minGlobalKeepPct = NaN;
        meanGlobalKeepPct = NaN;
    else
        minGlobalKeepPct = selectedGlobal.MinKeepPct(1);
        meanGlobalKeepPct = selectedGlobal.MeanKeepPct(1);
    end

    acceptance = struct();
    acceptance.generated_at = pointer.generated_at;
    acceptance.run_name = pointer.run_name;
    acceptance.status = 'review_ready';
    acceptance.formal_calculation_policy = 'Use global cable acceleration threshold only for formal spectrum/force calculation.';
    acceptance.display_policy = 'Use point-level selected display thresholds only for report/review visualization.';
    acceptance.conclusion = ['No single stricter global threshold satisfies both data retention and clean monthly visualization. ', ...
        'Use global formal clipping for spectrum/force, and use point-level display clipping plus 30 min envelope/RMS plots for review.'];
    acceptance.formal_threshold_abs = pointer.formal_threshold_abs;
    acceptance.formal_threshold_range = pointer.formal_threshold_range;
    acceptance.formal_min_keep_pct = minGlobalKeepPct;
    acceptance.formal_mean_keep_pct = meanGlobalKeepPct;
    acceptance.global_tradeoff = globalTradeoff(globalSummary, [20 50 75 100]);
    acceptance.selected_display_min_keep_pct = min(pointRecommendation.SelectedDisplayKeepPct, [], 'omitnan');
    acceptance.selected_display_changed_count = nnz(changedMask);
    acceptance.selected_display_changed_points = pointList(pointRecommendation.PointID(changedMask));
    acceptance.selected_display_stable_points = pointList(pointRecommendation.PointID(stableMask));
    acceptance.threshold_tuning_helpful_points = pointList(pointRecommendation.PointID(changedMask));
    acceptance.threshold_limited_or_quality_review_points = pointList(pointRecommendation.PointID(qualityMask));
    acceptance.threshold_limited_or_quality_review_count = nnz(qualityMask);
    acceptance.point_diagnosis = pointDiagnosisStruct(pointRecommendation);
    acceptance.review_html = pointer.review_html;
    acceptance.summary = pointer.summary;
    acceptance.workbook = pointer.workbook;
    acceptance.formal_vs_selected_review_board = pointer.formal_vs_selected_review_board;
    acceptance.selected_visual_review_board = pointer.selected_visual_review_board;
    acceptance.acceptance_json = pointer.acceptance_json;
    acceptance.acceptance_markdown = pointer.acceptance_markdown;
end

function tradeoff = globalTradeoff(globalSummary, thresholds)
    tradeoff = struct();
    for i = 1:numel(thresholds)
        th = thresholds(i);
        row = globalSummary(globalSummary.ThresholdAbs == th, :);
        field = sprintf('abs_%d', th);
        if isempty(row)
            tradeoff.(field) = struct('min_keep_pct', NaN, 'mean_keep_pct', NaN, ...
                'max_rms30_max', NaN, 'mean_rms30_max', NaN);
        else
            tradeoff.(field) = struct('min_keep_pct', row.MinKeepPct(1), ...
                'mean_keep_pct', row.MeanKeepPct(1), ...
                'max_rms30_max', row.MaxRMS30Max(1), ...
                'mean_rms30_max', row.MeanRMS30Max(1));
        end
    end
end

function diagnosis = pointDiagnosisStruct(pointRecommendation)
    diagnosis = struct();
    for i = 1:height(pointRecommendation)
        field = safeField(pointRecommendation.PointID{i});
        diagnosis.(field) = struct( ...
            'selected_display_threshold_abs', pointRecommendation.SelectedDisplayThresholdAbs(i), ...
            'selected_display_keep_pct', pointRecommendation.SelectedDisplayKeepPct(i), ...
            'candidate_rms30_reduction_pct', pointRecommendation.CandidateRMS30ReductionPct(i), ...
            'decision', pointRecommendation.Decision{i}, ...
            'diagnosis', pointRecommendation.Diagnosis{i}, ...
            'needs_data_quality_review', logical(pointRecommendation.NeedsDataQualityReview(i)));
    end
end

function writeAcceptanceJson(path, acceptance)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(acceptance));
end

function writeAcceptanceMarkdown(path, acceptance)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '# Zhishan Cable Acceleration Auto Tune Acceptance\n\n');
    fprintf(fid, '- Generated: %s\n', acceptance.generated_at);
    fprintf(fid, '- Run: `%s`\n', acceptance.run_name);
    fprintf(fid, '- Status: `%s`\n', acceptance.status);
    fprintf(fid, '- Conclusion: %s\n', acceptance.conclusion);
    fprintf(fid, '- Formal threshold: `[-%.0f, %.0f] m/s^2`\n', ...
        acceptance.formal_threshold_abs, acceptance.formal_threshold_abs);
    fprintf(fid, '- Formal min keep: `%.3f%%`\n', acceptance.formal_min_keep_pct);
    fprintf(fid, '- Formal mean keep: `%.3f%%`\n', acceptance.formal_mean_keep_pct);
    fprintf(fid, '- Selected display min keep: `%.3f%%`\n', acceptance.selected_display_min_keep_pct);
    fprintf(fid, '- Display changed count: `%d`\n', acceptance.selected_display_changed_count);
    fprintf(fid, '- Display changed points: `%s`\n', strjoin(acceptance.selected_display_changed_points, ', '));
    fprintf(fid, '- Stable points: `%s`\n', strjoin(acceptance.selected_display_stable_points, ', '));
    fprintf(fid, '- Threshold-limited or data-quality review points: `%s`\n', ...
        strjoin(acceptance.threshold_limited_or_quality_review_points, ', '));
    fprintf(fid, '- Formal policy: %s\n', acceptance.formal_calculation_policy);
    fprintf(fid, '- Display policy: %s\n\n', acceptance.display_policy);

    fprintf(fid, '## Global Threshold Tradeoff\n\n');
    fprintf(fid, '| Abs threshold | Min keep %% | Mean keep %% | Max RMS30 max | Mean RMS30 max |\n');
    fprintf(fid, '|---:|---:|---:|---:|---:|\n');
    writeTradeoffRow(fid, 20, acceptance.global_tradeoff.abs_20);
    writeTradeoffRow(fid, 50, acceptance.global_tradeoff.abs_50);
    writeTradeoffRow(fid, 75, acceptance.global_tradeoff.abs_75);
    writeTradeoffRow(fid, 100, acceptance.global_tradeoff.abs_100);

    fprintf(fid, '\n## Point Diagnosis\n\n');
    fprintf(fid, '| Point | Display abs | Keep %% | RMS30 reduction %% | Needs review | Diagnosis |\n');
    fprintf(fid, '|---|---:|---:|---:|---|---|\n');
    names = fieldnames(acceptance.point_diagnosis);
    for i = 1:numel(names)
        info = acceptance.point_diagnosis.(names{i});
        fprintf(fid, '| %s | %.0f | %.3f | %.1f | %s | %s |\n', ...
            strrep(names{i}, '_', '-'), info.selected_display_threshold_abs, ...
            info.selected_display_keep_pct, info.candidate_rms30_reduction_pct, ...
            char(string(info.needs_data_quality_review)), info.diagnosis);
    end

    fprintf(fid, '## Output Pointers\n\n');
    fprintf(fid, '- Review HTML: `%s`\n', acceptance.review_html);
    fprintf(fid, '- Summary: `%s`\n', acceptance.summary);
    fprintf(fid, '- Workbook: `%s`\n', acceptance.workbook);
    fprintf(fid, '- Formal-vs-selected board: `%s`\n', acceptance.formal_vs_selected_review_board);
    fprintf(fid, '- Selected-display board: `%s`\n', acceptance.selected_visual_review_board);
end

function writeTradeoffRow(fid, thresholdAbs, row)
    fprintf(fid, '| %.0f | %.3f | %.3f | %.3f | %.3f |\n', thresholdAbs, ...
        row.min_keep_pct, row.mean_keep_pct, row.max_rms30_max, row.mean_rms30_max);
end

function points = pointList(raw)
    if isempty(raw)
        points = {};
        return;
    end
    points = cellstr(string(raw(:)));
end

function writeLatestHtml(path, pointer, pointRecommendation)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n');
    fprintf(fid, '<meta charset="utf-8">\n');
    fprintf(fid, '<title>Zhishan Cable Acceleration Auto Tune</title>\n');
    fprintf(fid, '<style>\n');
    fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
    fprintf(fid, 'h1{font-size:24px;margin:0 0 8px;} h2{font-size:18px;margin:28px 0 12px;}');
    fprintf(fid, '.meta{color:#4b5563;margin-bottom:18px;line-height:1.7;}');
    fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;}');
    fprintf(fid, 'th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;}');
    fprintf(fid, 'th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
    fprintf(fid, '.changed{background:#fff8e1;} .stable{background:#ffffff;}');
    fprintf(fid, '.badge{display:inline-block;border-radius:4px;padding:2px 6px;margin-right:6px;font-size:12px;font-weight:600;}');
    fprintf(fid, '.badge-changed{background:#ffe8a3;color:#684b00;} .badge-stable{background:#e8f1fb;color:#184f7d;}');
    fprintf(fid, '.note{background:#fff;border-left:4px solid #2f6fed;padding:10px 12px;margin:14px 0 20px;line-height:1.7;}');
    fprintf(fid, '.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;}');
    fprintf(fid, 'img{max-width:100%%;height:auto;display:block;margin:auto;}');
    fprintf(fid, '.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:14px;}');
    fprintf(fid, 'a{color:#075da8;text-decoration:none;} a:hover{text-decoration:underline;}');
    fprintf(fid, '</style>\n</head>\n<body>\n');

    fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230;&#33258;&#21160;&#38408;&#20540;&#35843;&#21442; / Zhishan Cable Acceleration Auto Tune</h1>\n');
    fprintf(fid, '<div class="meta">Generated: %s<br>Run: <code>%s</code><br>&#27491;&#24335;&#35745;&#31639;&#38408;&#20540; / Formal threshold: <code>[-%.0f, %.0f] m/s^2</code><br>', ...
        htmlText(pointer.generated_at), htmlText(pointer.run_name), pointer.formal_threshold_abs, pointer.formal_threshold_abs);
    fprintf(fid, 'Summary: <a href="%s">%s</a><br>', htmlPath(pointer.summary), htmlText(pointer.summary));
    fprintf(fid, 'Workbook: <a href="%s">%s</a><br>', htmlPath(pointer.workbook), htmlText(pointer.workbook));
    fprintf(fid, 'Acceptance: <a href="%s">%s</a></div>\n', htmlPath(pointer.acceptance_markdown), htmlText(pointer.acceptance_markdown));

    fprintf(fid, '<div class="note">&#35828;&#26126;: &#27491;&#24335;&#35745;&#31639;&#20351;&#29992;&#20840;&#23616; <code>[-%.0f, %.0f] m/s^2</code>; &#34920;&#26684;&#20013;&#39640;&#20142;&#34892;&#20165;&#34920;&#31034;&#25253;&#21578;/&#23457;&#22270;&#23637;&#31034;&#29992;&#38408;&#20540;&#25910;&#32039;&#65292;&#19981;&#33258;&#21160;&#25913;&#21464;&#39057;&#35889;/&#32034;&#21147;&#27491;&#24335;&#35745;&#31639;&#12290;</div>\n', ...
        pointer.formal_threshold_abs, pointer.formal_threshold_abs);

    fprintf(fid, '<h2>&#38408;&#20540;&#25512;&#33616; / Threshold Recommendations</h2>\n<table>\n');
    fprintf(fid, '<tr><th>&#27979;&#28857; / Point</th><th>&#27491;&#24335;&#32477;&#23545;&#38408;&#20540; / Formal abs</th><th>&#23637;&#31034;&#32477;&#23545;&#38408;&#20540; / Display abs</th><th>&#23637;&#31034;&#20445;&#30041;&#29575; / Keep %%</th><th>&#23637;&#31034; RMS30 &#26368;&#22823;&#20540;</th><th>&#21028;&#26029; / Decision</th><th>&#35786;&#26029; / Diagnosis</th></tr>\n');
    for i = 1:height(pointRecommendation)
        cls = rowClass(pointRecommendation.FormalThresholdAbs(i), pointRecommendation.SelectedDisplayThresholdAbs(i));
        fprintf(fid, '<tr class="%s"><td>%s</td><td class="num">%.0f</td><td class="num">%.0f</td><td class="num">%.3f</td><td class="num">%.3f</td><td>%s</td><td>%s</td></tr>\n', ...
            cls, ...
            htmlText(pointRecommendation.PointID{i}), pointRecommendation.FormalThresholdAbs(i), ...
            pointRecommendation.SelectedDisplayThresholdAbs(i), pointRecommendation.SelectedDisplayKeepPct(i), ...
            pointRecommendation.SelectedDisplayRMS30Max(i), decisionHtml(pointRecommendation.Decision{i}), ...
            htmlText(pointRecommendation.Diagnosis{i}));
    end
    fprintf(fid, '</table>\n');

    fprintf(fid, '<h2>&#24635;&#35272;&#22270; / Overview Boards</h2>\n');
    fprintf(fid, '<div class="figure"><h2>&#27491;&#24335;&#38408;&#20540; vs &#33258;&#21160;&#23637;&#31034;&#38408;&#20540; / Formal vs Selected</h2><img src="%s" alt="formal vs selected"></div>\n', ...
        htmlPath(pointer.formal_vs_selected_review_board));
    fprintf(fid, '<div class="figure"><h2>&#33258;&#21160;&#23637;&#31034;&#25928;&#26524; / Selected Display</h2><img src="%s" alt="selected display"></div>\n', ...
        htmlPath(pointer.selected_visual_review_board));

    fprintf(fid, '<h2>&#21508;&#27979;&#28857;&#23545;&#27604; / Per-Point Comparisons</h2>\n<div class="grid">\n');
    for i = 1:height(pointRecommendation)
        pointId = pointRecommendation.PointID{i};
        rel = fullfile(pointer.formal_vs_selected_compare, sprintf('FormalVsSelected_%s.jpg', pointId));
        fprintf(fid, '<div class="figure"><h2>%s</h2><img src="%s" alt="%s"></div>\n', ...
            htmlText(pointId), htmlPath(rel), htmlText(pointId));
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

function cls = rowClass(formalThreshold, selectedThreshold)
    if abs(double(formalThreshold) - double(selectedThreshold)) > eps
        cls = 'changed';
    else
        cls = 'stable';
    end
end

function out = decisionHtml(decision)
    decision = char(string(decision));
    switch decision
        case 'use tighter display threshold'
            out = ['<span class="badge badge-changed">&#23637;&#31034;&#25910;&#32039;</span>' htmlText(decision)];
        case 'keep formal threshold for calculation stability'
            out = ['<span class="badge badge-stable">&#20445;&#25345;&#27491;&#24335;</span>' htmlText(decision)];
        case 'keep formal threshold, little display benefit'
            out = ['<span class="badge badge-stable">&#25913;&#21892;&#36739;&#23567;</span>' htmlText(decision)];
        otherwise
            out = htmlText(decision);
    end
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

function name = safeField(pointId)
    name = matlab.lang.makeValidName(strrep(pointId, '-', '_'));
end
