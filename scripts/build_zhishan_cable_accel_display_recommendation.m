function result = build_zhishan_cable_accel_display_recommendation()
%BUILD_ZHISHAN_CABLE_ACCEL_DISPLAY_RECOMMENDATION Build final display pick.
%   Synthesizes the conservative and grid-search display candidates.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
runLogs = fullfile(dataRoot, 'run_logs');

conservativePtr = readJson(fullfile(runLogs, 'cable_accel_display_candidate_latest.json'));
gridPtr = readJson(fullfile(runLogs, 'cable_accel_display_grid_search_latest.json'));

conservative = readtable(fullfile(dataRoot, conservativePtr.workbook), 'Sheet', 'summary');
grid = readtable(fullfile(dataRoot, gridPtr.workbook), 'Sheet', 'selected_summary');
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
useGrid = containers.Map({'CF-2','CF-6','CF-8'}, {true, true, true});

rows = {};
for i = 1:numel(points)
    pointId = points{i};
    if isKey(useGrid, pointId)
        idx = find(strcmp(grid.PointID, pointId), 1);
        rows(end+1, :) = {pointId, 'grid', grid.Strategy{idx}, ...
            grid.KeepPct(idx), grid.DisplayRMS30Max(idx), ...
            grid.RMS30MaxReductionPct(idx), rationale(pointId, 'grid'), ...
            gridDetailPath(dataRoot, gridPtr.output_folder, pointId), ...
            gridTrendPath(dataRoot, gridPtr.output_folder, pointId)}; %#ok<AGROW>
    else
        idx = find(strcmp(conservative.PointID, pointId), 1);
        rows(end+1, :) = {pointId, 'conservative', conservative.Strategy{idx}, ...
            conservative.DisplayKeepPct(idx), conservative.DisplayRMS30Max(idx), ...
            conservative.RMS30MaxReductionPct(idx), rationale(pointId, 'conservative'), ...
            conservative.PlotPath{idx}, conservative.TrendPlotPath{idx}}; %#ok<AGROW>
    end
end

recommendation = cell2table(rows, 'VariableNames', { ...
    'PointID','RecommendedSource','Strategy','KeepPct','RMS30Max', ...
    'RMS30MaxReductionPct','Rationale','DetailImage','TrendImage'});

stamp = datestr(now, 'yyyymmdd_HHMMSS');
runName = ['cable_accel_display_recommendation_' stamp];
outRoot = fullfile(runLogs, runName);
if ~exist(outRoot, 'dir'), mkdir(outRoot); end

xlsxPath = fullfile(outRoot, 'cable_accel_display_recommendation.xlsx');
csvPath = fullfile(outRoot, 'cable_accel_display_recommendation.csv');
markdownPath = fullfile(outRoot, 'cable_accel_display_recommendation.md');
writetable(recommendation, xlsxPath, 'Sheet', 'recommendation');
writetable(recommendation, csvPath, 'Encoding', 'UTF-8');
writeMarkdown(markdownPath, runName, recommendation, xlsxPath, csvPath);
stable = writeStableOutputs(dataRoot, runName, recommendation);
htmlRecommendation = recommendation;
htmlRecommendation.DetailImage = stable.detail_paths;
htmlRecommendation.TrendImage = stable.trend_paths;
latestPaths = writeLatest(dataRoot, runName, htmlRecommendation, xlsxPath, csvPath, ...
    markdownPath, conservativePtr, gridPtr, stable);

result = struct();
result.run_name = runName;
result.output_folder = outRoot;
result.recommendation = recommendation;
result.workbook = xlsxPath;
result.csv = csvPath;
result.markdown = markdownPath;
result.stable = stable;
result.latest = latestPaths;

fprintf('wrote %s\n', xlsxPath);
fprintf('wrote %s\n', csvPath);
fprintf('wrote %s\n', markdownPath);
fprintf('stable dir %s\n', stable.dir);
fprintf('stable policy %s\n', stable.policy_json);
fprintf('latest html %s\n', latestPaths.html);
disp(recommendation(:, {'PointID','RecommendedSource','Strategy','KeepPct','RMS30MaxReductionPct','Rationale'}));
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

function text = rationale(pointId, source)
if strcmp(source, 'grid')
    if strcmp(pointId, 'CF-8')
        text = 'grid search improves a previously limited point';
    else
        text = 'grid search gives meaningful RMS reduction with acceptable retention';
    end
elseif strcmp(pointId, 'CF-5')
    text = 'keep conservative option; grid variant is marked aggressive for data-loss review';
else
    text = 'conservative option is sufficient after comparison';
end
end

function path = gridDetailPath(dataRoot, outputFolder, pointId)
path = fullfile(dataRoot, outputFolder, 'plots', sprintf('GridSelected_%s.jpg', pointId));
end

function path = gridTrendPath(dataRoot, outputFolder, pointId)
path = fullfile(dataRoot, outputFolder, 'plots', sprintf('GridSelectedTrend_%s.jpg', pointId));
end

function writeMarkdown(path, runName, recommendation, xlsxPath, csvPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Display Recommendation\n\n');
fprintf(fid, '- Run: `%s`\n', runName);
fprintf(fid, '- Workbook: `%s`\n', xlsxPath);
fprintf(fid, '- CSV: `%s`\n\n', csvPath);
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`. This recommendation is display-only.\n\n');
fprintf(fid, '| Point | Source | Strategy | Keep %% | RMS30 max | RMS30 max reduction %% | Rationale |\n');
fprintf(fid, '|---|---|---|---:|---:|---:|---|\n');
for i = 1:height(recommendation)
    fprintf(fid, '| %s | %s | %s | %.3f | %.3f | %.1f | %s |\n', ...
        recommendation.PointID{i}, recommendation.RecommendedSource{i}, ...
        recommendation.Strategy{i}, recommendation.KeepPct(i), ...
        recommendation.RMS30Max(i), recommendation.RMS30MaxReductionPct(i), ...
        recommendation.Rationale{i});
end
end

function stable = writeStableOutputs(dataRoot, runName, recommendation)
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
if ~exist(stableDir, 'dir'), mkdir(stableDir); end

detailPaths = cell(height(recommendation), 1);
trendPaths = cell(height(recommendation), 1);
for i = 1:height(recommendation)
    pointId = recommendation.PointID{i};
    detailPath = fullfile(stableDir, sprintf('CableAccelDisplayRecommendationDetail_%s.jpg', pointId));
    trendPath = fullfile(stableDir, sprintf('CableAccelDisplayRecommendationTrend_%s.jpg', pointId));
    copyfile(recommendation.DetailImage{i}, detailPath, 'f');
    copyfile(recommendation.TrendImage{i}, trendPath, 'f');
    detailPaths{i} = detailPath;
    trendPaths{i} = trendPath;
end

manifest = recommendation;
manifest.StableDetailImage = detailPaths;
manifest.StableTrendImage = trendPaths;
manifest.SourceRun = repmat({runName}, height(manifest), 1);
manifest.GeneratedAt = repmat({datestr(now, 'yyyy-mm-dd HH:MM:SS')}, height(manifest), 1);

manifestPath = fullfile(stableDir, 'CableAccelDisplayRecommendation_manifest.xlsx');
manifestCsvPath = fullfile(stableDir, 'CableAccelDisplayRecommendation_manifest.csv');
markdownPath = fullfile(stableDir, 'CableAccelDisplayRecommendation_manifest.md');
policyPath = fullfile(stableDir, 'CableAccelDisplayRecommendation_policy.json');
writetable(manifest, manifestPath, 'Sheet', 'recommendation');
writetable(manifest, manifestCsvPath, 'Encoding', 'UTF-8');
writeStableMarkdown(markdownPath, runName, manifest);
writePolicyJson(policyPath, runName, recommendation);

stable = struct();
stable.dir = stableDir;
stable.manifest = manifestPath;
stable.manifest_csv = manifestCsvPath;
stable.markdown = markdownPath;
stable.policy_json = policyPath;
stable.detail_paths = detailPaths;
stable.trend_paths = trendPaths;
end

function writeStableMarkdown(path, runName, manifest)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Cable Acceleration Display Recommendation Stable Outputs\n\n');
fprintf(fid, '- Source run: `%s`\n', runName);
fprintf(fid, '- Manifest workbook: `%s`\n', localFileName(strrep(path, '.md', '.xlsx')));
fprintf(fid, '- Policy JSON: `CableAccelDisplayRecommendation_policy.json`\n\n');
fprintf(fid, '| Point | Source | Strategy | Keep %% | RMS30 max reduction %% | Detail image | Trend image |\n');
fprintf(fid, '|---|---|---|---:|---:|---|---|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | %s | %s | %.3f | %.1f | `%s` | `%s` |\n', ...
        manifest.PointID{i}, manifest.RecommendedSource{i}, manifest.Strategy{i}, ...
        manifest.KeepPct(i), manifest.RMS30MaxReductionPct(i), ...
        localFileName(manifest.StableDetailImage{i}), localFileName(manifest.StableTrendImage{i}));
end
end

function writePolicyJson(path, runName, recommendation)
policy = struct();
policy.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
policy.source_run = runName;
policy.scope = 'display_only';
policy.formal_policy = 'Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.';
policy.note = 'Use this policy for report/review display only unless the user explicitly approves formal calculation changes.';
policy.points = struct();
for i = 1:height(recommendation)
    pointId = recommendation.PointID{i};
    [thresholdAbs, segmentPct] = parseStrategy(recommendation.Strategy{i});
    field = matlab.lang.makeValidName(strrep(pointId, '-', '_'));
    policy.points.(field) = struct( ...
        'point_id', pointId, ...
        'source', recommendation.RecommendedSource{i}, ...
        'strategy', recommendation.Strategy{i}, ...
        'threshold_abs_mps2', thresholdAbs, ...
        'segment_filter_top_pct_rms30', segmentPct, ...
        'keep_pct', recommendation.KeepPct(i), ...
        'rms30_max', recommendation.RMS30Max(i), ...
        'rms30_max_reduction_pct', recommendation.RMS30MaxReductionPct(i), ...
        'rationale', recommendation.Rationale{i});
end
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(policy));
end

function [thresholdAbs, segmentPct] = parseStrategy(strategy)
strategy = char(strategy);
thresholdAbs = NaN;
segmentPct = 0;
token = regexp(strategy, 'abs<=([0-9.]+)', 'tokens', 'once');
if ~isempty(token)
    thresholdAbs = str2double(token{1});
end
token = regexp(strategy, 'drop top ([0-9.]+)%', 'tokens', 'once');
if ~isempty(token)
    segmentPct = str2double(token{1});
end
end

function latestPaths = writeLatest(dataRoot, runName, recommendation, xlsxPath, csvPath, markdownPath, conservativePtr, gridPtr, stable)
runLogs = fullfile(dataRoot, 'run_logs');
latestPaths = struct( ...
    'json', fullfile(runLogs, 'cable_accel_display_recommendation_latest.json'), ...
    'markdown', fullfile(runLogs, 'cable_accel_display_recommendation_latest.md'), ...
    'html', fullfile(runLogs, 'cable_accel_display_recommendation_latest.html'));

pointer = struct();
pointer.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
pointer.run_name = runName;
pointer.output_folder = relPath(fileparts(xlsxPath), dataRoot);
pointer.summary = relPath(markdownPath, dataRoot);
pointer.workbook = relPath(xlsxPath, dataRoot);
pointer.csv = relPath(csvPath, dataRoot);
pointer.review_html = relPath(latestPaths.html, dataRoot);
pointer.conservative_html = conservativePtr.review_html;
pointer.grid_html = gridPtr.review_html;
pointer.stable_output_dir = relPath(stable.dir, dataRoot);
pointer.stable_manifest = relPath(stable.manifest, dataRoot);
pointer.stable_markdown = relPath(stable.markdown, dataRoot);
pointer.stable_policy_json = relPath(stable.policy_json, dataRoot);
pointer.formal_policy = 'Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.';
pointer.display_policy = 'Recommended display-only hybrid: conservative except grid for CF-2/6/8.';

fid = fopen(latestPaths.json, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(pointer));
clear cleaner;

fid = fopen(latestPaths.markdown, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Latest Zhishan Cable Acceleration Display Recommendation\n\n');
fprintf(fid, '- Generated: %s\n', pointer.generated_at);
fprintf(fid, '- Run: `%s`\n', pointer.run_name);
fprintf(fid, '- Summary: `%s`\n', pointer.summary);
fprintf(fid, '- Workbook: `%s`\n', pointer.workbook);
fprintf(fid, '- Review HTML: `%s`\n', pointer.review_html);
fprintf(fid, '- Stable output dir: `%s`\n', pointer.stable_output_dir);
fprintf(fid, '- Stable policy JSON: `%s`\n', pointer.stable_policy_json);
fprintf(fid, '- Formal policy: %s\n', pointer.formal_policy);
fprintf(fid, '- Display policy: %s\n\n', pointer.display_policy);
fprintf(fid, '| Point | Source | Strategy | Keep %% | RMS30 max reduction %% | Rationale |\n');
fprintf(fid, '|---|---|---|---:|---:|---|\n');
for i = 1:height(recommendation)
    fprintf(fid, '| %s | %s | %s | %.3f | %.1f | %s |\n', ...
        recommendation.PointID{i}, recommendation.RecommendedSource{i}, ...
        recommendation.Strategy{i}, recommendation.KeepPct(i), ...
        recommendation.RMS30MaxReductionPct(i), recommendation.Rationale{i});
end
clear cleaner;

writeLatestHtml(latestPaths.html, pointer, recommendation);
end

function writeLatestHtml(path, pointer, recommendation)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Display Recommendation</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.meta,.note{line-height:1.7;color:#4b5563;} .note{background:white;border-left:4px solid #2f6fed;padding:10px 12px;margin:14px 0 20px;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;}');
fprintf(fid, 'th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.gridpick{background:#eaf7ee;} .figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;}');
fprintf(fid, '.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;} a{color:#075da8;text-decoration:none;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230;&#25512;&#33616;&#23637;&#31034;&#26041;&#26696; / Display Recommendation</h1>\n');
fprintf(fid, '<div class="meta">Generated: %s<br>Run: <code>%s</code><br>Summary: <a href="%s">%s</a><br>Workbook: <a href="%s">%s</a></div>\n', ...
    htmlText(pointer.generated_at), htmlText(pointer.run_name), htmlPath(pointer.summary), htmlText(pointer.summary), ...
    htmlPath(pointer.workbook), htmlText(pointer.workbook));
fprintf(fid, '<div class="note">&#27491;&#24335;&#39057;&#35889;/&#32034;&#21147;&#35745;&#31639;&#19981;&#21464;: <code>daily_median + [-100,100] m/s^2</code>. &#26412;&#39029;&#26159;&#33258;&#21160;&#25628;&#32034;&#21518;&#30340;&#25512;&#33616;&#23637;&#31034;&#26041;&#26696;&#12290;</div>\n');

fprintf(fid, '<h2>&#25512;&#33616;&#31574;&#30053; / Recommended Strategy</h2>\n<table>\n');
fprintf(fid, '<tr><th>&#27979;&#28857;</th><th>&#26469;&#28304;</th><th>&#31574;&#30053;</th><th>&#20445;&#30041;&#29575;</th><th>RMS30 &#26368;&#22823;&#20540;</th><th>RMS30 &#38477;&#20302;</th><th>&#29702;&#30001;</th></tr>\n');
for i = 1:height(recommendation)
    cls = '';
    if strcmp(recommendation.RecommendedSource{i}, 'grid')
        cls = ' class="gridpick"';
    end
    fprintf(fid, '<tr%s><td>%s</td><td>%s</td><td>%s</td><td class="num">%.3f%%</td><td class="num">%.3f</td><td class="num">%.1f%%</td><td>%s</td></tr>\n', ...
        cls, htmlText(recommendation.PointID{i}), htmlText(recommendation.RecommendedSource{i}), ...
        htmlText(recommendation.Strategy{i}), recommendation.KeepPct(i), ...
        recommendation.RMS30Max(i), recommendation.RMS30MaxReductionPct(i), ...
        htmlText(recommendation.Rationale{i}));
end
fprintf(fid, '</table>\n');

fprintf(fid, '<h2>&#21333;&#28857;&#35814;&#32454;&#22270; / Detail Figures</h2>\n<div class="grid">\n');
for i = 1:height(recommendation)
    fprintf(fid, '<div class="figure"><h2>%s</h2><img src="%s" alt="%s detail"></div>\n', ...
        htmlText(recommendation.PointID{i}), htmlPath(relForHtml(recommendation.DetailImage{i})), ...
        htmlText(recommendation.PointID{i}));
end
fprintf(fid, '</div>\n<h2>&#21333;&#28857;&#36235;&#21183;&#22270; / Trend Figures</h2>\n<div class="grid">\n');
for i = 1:height(recommendation)
    fprintf(fid, '<div class="figure"><h2>%s trend</h2><img src="%s" alt="%s trend"></div>\n', ...
        htmlText(recommendation.PointID{i}), htmlPath(relForHtml(recommendation.TrendImage{i})), ...
        htmlText(recommendation.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function rel = relForHtml(pathText)
dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
rel = relPath(pathText, dataRoot);
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

function name = localFileName(pathText)
[~, base, ext] = fileparts(char(pathText));
name = [base ext];
end
