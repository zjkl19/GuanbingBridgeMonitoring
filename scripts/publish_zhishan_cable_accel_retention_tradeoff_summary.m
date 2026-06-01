function result = publish_zhishan_cable_accel_retention_tradeoff_summary()
%PUBLISH_ZHISHAN_CABLE_ACCEL_RETENTION_TRADEOFF_SUMMARY Summarize tier tradeoffs.
%   Produces a compact evidence table across current-best, aggressive,
%   target80, target75, and visual-best. Display/report review only.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
currentDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([24403 21069 26368 20339 25512 33616 23637 31034])]);
outputDir = fullfile(stableDir, 'retention_tradeoff_summary');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

sources = {
    'current_best', fullfile(currentDir, 'CableAccelCurrentBestReport_manifest.csv'), 'index.html';
    'aggressive', fullfile(stableDir, 'aggressive_display_export', 'CableAccelAggressiveDisplay_manifest.csv'), '../aggressive_display_export/index.html';
    'target80', fullfile(stableDir, 'target80_display_export', 'CableAccelTarget80Display_manifest.csv'), '../target80_display_export/index.html';
    'target75', fullfile(stableDir, 'target75_display_export', 'CableAccelTarget75Display_manifest.csv'), '../target75_display_export/index.html';
    'visual_best', fullfile(stableDir, 'visual_best_display_export', 'CableAccelVisualBestDisplay_manifest.csv'), '../visual_best_display_export/index.html'
    };

current = normalizeManifest('current_best', sources{1, 2}, sources{1, 3});
rows = table2cell(current);
points = unique(current.PointID, 'stable');
for s = 2:size(sources, 1)
    tier = normalizeManifest(sources{s, 1}, sources{s, 2}, sources{s, 3});
    rows = [rows; table2cell(tier)]; %#ok<AGROW>
end

summary = cell2table(rows, 'VariableNames', current.Properties.VariableNames);
summary.KeepDeltaVsCurrentBestPct = NaN(height(summary), 1);
summary.RMS30MaxImprovementVsCurrentBestPct = NaN(height(summary), 1);
for i = 1:height(summary)
    idx = find(strcmp(current.PointID, summary.PointID{i}), 1);
    summary.KeepDeltaVsCurrentBestPct(i) = summary.KeepPct(i) - current.KeepPct(idx);
    summary.RMS30MaxImprovementVsCurrentBestPct(i) = pctReduction(current.RMS30Max(idx), summary.RMS30Max(i));
end

decision = buildDecisionTable(summary, points);
summaryPath = fullfile(outputDir, 'CableAccelRetentionTradeoff_summary.xlsx');
summaryCsv = fullfile(outputDir, 'CableAccelRetentionTradeoff_summary.csv');
decisionCsv = fullfile(outputDir, 'CableAccelRetentionTradeoff_decisions.csv');
htmlPath = fullfile(outputDir, 'index.html');
readmePath = fullfile(outputDir, 'README.md');
writetable(summary, summaryPath, 'Sheet', 'tiers');
writetable(decision, summaryPath, 'Sheet', 'decisions');
writetable(summary, summaryCsv, 'Encoding', 'UTF-8');
writetable(decision, decisionCsv, 'Encoding', 'UTF-8');
writeHtml(htmlPath, summary, decision, sources);
writeReadme(readmePath, decision);

result = struct();
result.output_dir = outputDir;
result.html = htmlPath;
result.summary = summaryPath;
result.summary_csv = summaryCsv;
result.decision_csv = decisionCsv;

fprintf('retention tradeoff summary %s\n', htmlPath);
disp(decision);
end

function out = normalizeManifest(tierName, path, linkRel)
if ~isfile(path)
    error('Missing manifest %s.', path);
end
T = readtable(path, 'Encoding', 'UTF-8');
rows = {};
for i = 1:height(T)
    pointId = T.PointID{i};
    strategy = '';
    if ismember('Strategy', T.Properties.VariableNames)
        strategy = T.Strategy{i};
    elseif ismember('Rationale', T.Properties.VariableNames)
        strategy = T.Rationale{i};
    end
    rows(end+1, :) = {pointId, tierName, strategy, T.KeepPct(i), ...
        T.RMS30Max(i), T.RMS30P95(i), linkRel}; %#ok<AGROW>
end
out = cell2table(rows, 'VariableNames', { ...
    'PointID','Tier','Strategy','KeepPct','RMS30Max','RMS30P95','Link'});
end

function decision = buildDecisionTable(summary, points)
rows = {};
for i = 1:numel(points)
    pointId = points{i};
    P = summary(strcmp(summary.PointID, pointId), :);
    cur = P(strcmp(P.Tier, 'current_best'), :);
    aggr = P(strcmp(P.Tier, 'aggressive'), :);
    target80 = P(strcmp(P.Tier, 'target80'), :);
    target75 = P(strcmp(P.Tier, 'target75'), :);
    visual = P(strcmp(P.Tier, 'visual_best'), :);

    if ~isempty(target75) && target75.KeepPct >= 75 && ...
            target75.RMS30MaxImprovementVsCurrentBestPct - visual.RMS30MaxImprovementVsCurrentBestPct >= 12
        nextTier = 'target75_review_only';
        reason = sprintf('target75 gives %.1f%% RMS improvement but keep is %.1f%%; use only if visual quality is decisive', ...
            target75.RMS30MaxImprovementVsCurrentBestPct, target75.KeepPct);
    elseif ~isempty(visual)
        nextTier = 'visual_best_backup';
        reason = sprintf('visual-best gives %.1f%% RMS improvement with keep %.1f%%; review as the no-pick stricter backup', ...
            visual.RMS30MaxImprovementVsCurrentBestPct, visual.KeepPct);
    elseif ~isempty(aggr)
        nextTier = 'aggressive_backup';
        reason = sprintf('aggressive gives %.1f%% RMS improvement with keep %.1f%%', ...
            aggr.RMS30MaxImprovementVsCurrentBestPct, aggr.KeepPct);
    else
        nextTier = 'current_best';
        reason = 'no stricter candidate available';
    end

    rows(end+1, :) = {pointId, cur.KeepPct, cur.RMS30Max, ...
        valueOrNaN(aggr, 'KeepPct'), valueOrNaN(aggr, 'RMS30MaxImprovementVsCurrentBestPct'), ...
        valueOrNaN(target80, 'KeepPct'), valueOrNaN(target80, 'RMS30MaxImprovementVsCurrentBestPct'), ...
        valueOrNaN(target75, 'KeepPct'), valueOrNaN(target75, 'RMS30MaxImprovementVsCurrentBestPct'), ...
        valueOrNaN(visual, 'KeepPct'), valueOrNaN(visual, 'RMS30MaxImprovementVsCurrentBestPct'), ...
        nextTier, reason}; %#ok<AGROW>
end
decision = cell2table(rows, 'VariableNames', { ...
    'PointID','CurrentBestKeepPct','CurrentBestRMS30Max', ...
    'AggressiveKeepPct','AggressiveImprovementPct', ...
    'Target80KeepPct','Target80ImprovementPct', ...
    'Target75KeepPct','Target75ImprovementPct', ...
    'VisualBestKeepPct','VisualBestImprovementPct', ...
    'NextReviewTier','Reason'});
end

function value = valueOrNaN(T, varName)
if isempty(T)
    value = NaN;
else
    value = T.(varName)(1);
end
end

function writeHtml(path, summary, decision, sources)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Retention Tradeoff</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #2563eb;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.current_best{background:#eef6ff}.visual_best{background:#eaf7f2}.target75{background:#fff1f2}.target80{background:#f4edff}.aggressive{background:#fff7ed} a{color:#075da8;text-decoration:none;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Retention Tradeoff</h1>\n');
fprintf(fid, '<div class="note">Display-only evidence table. Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2. Use this page to decide whether the extra cleanliness is worth the lower keep rate.</div>\n');
fprintf(fid, '<h2>Source Links</h2><ul>\n');
for i = 1:size(sources, 1)
    fprintf(fid, '<li>%s: <a href="%s">%s</a></li>\n', ...
        htmlText(sources{i, 1}), htmlText(sources{i, 3}), htmlText(sources{i, 3}));
end
fprintf(fid, '</ul>\n');
fprintf(fid, '<h2>Next Review Decision</h2>\n<table><tr><th>Point</th><th>Current keep/RMS</th><th>Aggressive keep/improve</th><th>Target80 keep/improve</th><th>Target75 keep/improve</th><th>Visual-best keep/improve</th><th>Next review</th><th>Reason</th></tr>\n');
for i = 1:height(decision)
    fprintf(fid, '<tr><td>%s</td><td class="num">%.2f / %.2f</td><td class="num">%.2f / %.1f</td><td class="num">%.2f / %.1f</td><td class="num">%.2f / %.1f</td><td class="num">%.2f / %.1f</td><td>%s</td><td>%s</td></tr>\n', ...
        htmlText(decision.PointID{i}), decision.CurrentBestKeepPct(i), ...
        decision.CurrentBestRMS30Max(i), decision.AggressiveKeepPct(i), ...
        decision.AggressiveImprovementPct(i), decision.Target80KeepPct(i), ...
        decision.Target80ImprovementPct(i), decision.Target75KeepPct(i), ...
        decision.Target75ImprovementPct(i), decision.VisualBestKeepPct(i), ...
        decision.VisualBestImprovementPct(i), htmlText(decision.NextReviewTier{i}), ...
        htmlText(decision.Reason{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>All Tier Rows</h2>\n<table><tr><th>Point</th><th>Tier</th><th>Keep %%</th><th>RMS30 max</th><th>RMS30 P95</th><th>Keep delta</th><th>RMS improvement %%</th><th>Strategy</th></tr>\n');
for i = 1:height(summary)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td>%s</td></tr>\n', ...
        htmlText(summary.Tier{i}), htmlText(summary.PointID{i}), ...
        htmlText(summary.Tier{i}), summary.KeepPct(i), summary.RMS30Max(i), ...
        summary.RMS30P95(i), summary.KeepDeltaVsCurrentBestPct(i), ...
        summary.RMS30MaxImprovementVsCurrentBestPct(i), htmlText(summary.Strategy{i}));
end
fprintf(fid, '</table>\n</body>\n</html>\n');
end

function writeReadme(path, decision)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Retention Tradeoff\n\n');
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '| Point | Next review | Reason |\n');
fprintf(fid, '|---|---|---|\n');
for i = 1:height(decision)
    fprintf(fid, '| %s | %s | %s |\n', ...
        decision.PointID{i}, decision.NextReviewTier{i}, decision.Reason{i});
end
end

function pct = pctReduction(beforeValue, afterValue)
if ~isfinite(beforeValue) || beforeValue == 0 || ~isfinite(afterValue)
    pct = NaN;
else
    pct = 100 * (beforeValue - afterValue) / abs(beforeValue);
end
end

function out = htmlText(value)
out = char(string(value));
out = strrep(out, '&', '&amp;');
out = strrep(out, '<', '&lt;');
out = strrep(out, '>', '&gt;');
out = strrep(out, '"', '&quot;');
end
