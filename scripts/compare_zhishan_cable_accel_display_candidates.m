function result = compare_zhishan_cable_accel_display_candidates()
%COMPARE_ZHISHAN_CABLE_ACCEL_DISPLAY_CANDIDATES Build review comparison.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
runLogs = fullfile(dataRoot, 'run_logs');

conservativePtr = readJson(fullfile(runLogs, 'cable_accel_display_candidate_latest.json'));
gridPtr = readJson(fullfile(runLogs, 'cable_accel_display_grid_search_latest.json'));

conservativeWorkbook = fullfile(dataRoot, conservativePtr.workbook);
gridWorkbook = fullfile(dataRoot, gridPtr.workbook);
conservative = readtable(conservativeWorkbook, 'Sheet', 'summary');
grid = readtable(gridWorkbook, 'Sheet', 'selected_summary');

rows = {};
for i = 1:height(conservative)
    pointId = conservative.PointID{i};
    gIdx = find(strcmp(grid.PointID, pointId), 1);
    if isempty(gIdx)
        warning('Missing grid candidate for %s.', pointId);
        continue;
    end
    cKeep = conservative.DisplayKeepPct(i);
    gKeep = grid.KeepPct(gIdx);
    cReduction = conservative.RMS30MaxReductionPct(i);
    gReduction = grid.RMS30MaxReductionPct(gIdx);
    cRms = conservative.DisplayRMS30Max(i);
    gRms = grid.DisplayRMS30Max(gIdx);
    keepDelta = gKeep - cKeep;
    reductionDelta = gReduction - cReduction;
    rmsDelta = gRms - cRms;
    decision = compareDecision(gKeep, keepDelta, reductionDelta, pointId);
    rows(end+1, :) = {pointId, conservative.Strategy{i}, grid.Strategy{gIdx}, ...
        cKeep, gKeep, keepDelta, cRms, gRms, rmsDelta, cReduction, ...
        gReduction, reductionDelta, decision}; %#ok<AGROW>
end

comparison = cell2table(rows, 'VariableNames', { ...
    'PointID','ConservativeStrategy','GridStrategy', ...
    'ConservativeKeepPct','GridKeepPct','KeepDeltaPct', ...
    'ConservativeRMS30Max','GridRMS30Max','RMS30MaxDelta', ...
    'ConservativeRMS30MaxReductionPct','GridRMS30MaxReductionPct', ...
    'ReductionDeltaPct','Decision'});

stamp = datestr(now, 'yyyymmdd_HHMMSS');
runName = ['cable_accel_display_compare_' stamp];
outRoot = fullfile(runLogs, runName);
if ~exist(outRoot, 'dir'), mkdir(outRoot); end

xlsxPath = fullfile(outRoot, 'cable_accel_display_compare.xlsx');
csvPath = fullfile(outRoot, 'cable_accel_display_compare.csv');
markdownPath = fullfile(outRoot, 'cable_accel_display_compare.md');
writetable(comparison, xlsxPath, 'Sheet', 'comparison');
writetable(comparison, csvPath, 'Encoding', 'UTF-8');

writeMarkdown(markdownPath, runName, comparison, conservativePtr, gridPtr, xlsxPath, csvPath);
latestPaths = writeLatest(dataRoot, runName, comparison, conservativePtr, gridPtr, ...
    xlsxPath, csvPath, markdownPath);

result = struct();
result.run_name = runName;
result.output_folder = outRoot;
result.comparison = comparison;
result.workbook = xlsxPath;
result.csv = csvPath;
result.markdown = markdownPath;
result.latest = latestPaths;

fprintf('wrote %s\n', xlsxPath);
fprintf('wrote %s\n', csvPath);
fprintf('wrote %s\n', markdownPath);
fprintf('latest html %s\n', latestPaths.html);
disp(comparison(:, {'PointID','GridKeepPct','KeepDeltaPct','ReductionDeltaPct','Decision'}));
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

function text = compareDecision(gridKeep, keepDelta, reductionDelta, pointId)
if gridKeep < 92
    text = 'aggressive; review data loss';
elseif reductionDelta >= 15 && keepDelta >= -4
    text = 'prefer grid display';
elseif reductionDelta >= 8 && keepDelta >= -3
    text = 'grid display is reasonable';
elseif any(strcmp(pointId, {'CF-2','CF-8'})) && reductionDelta >= 20
    text = 'grid improves previously limited point';
else
    text = 'conservative display acceptable';
end
end

function writeMarkdown(path, runName, comparison, conservativePtr, gridPtr, xlsxPath, csvPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Display Candidate Comparison\n\n');
fprintf(fid, '- Run: `%s`\n', runName);
fprintf(fid, '- Workbook: `%s`\n', xlsxPath);
fprintf(fid, '- CSV: `%s`\n', csvPath);
fprintf(fid, '- Conservative HTML: `%s`\n', conservativePtr.review_html);
fprintf(fid, '- Grid HTML: `%s`\n\n', gridPtr.review_html);
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`. This comparison is display-only.\n\n');
fprintf(fid, '| Point | Conservative | Grid | Keep delta %% | RMS30 max delta | Reduction delta %% | Decision |\n');
fprintf(fid, '|---|---|---|---:|---:|---:|---|\n');
for i = 1:height(comparison)
    fprintf(fid, '| %s | %s | %s | %.3f | %.3f | %.1f | %s |\n', ...
        comparison.PointID{i}, comparison.ConservativeStrategy{i}, ...
        comparison.GridStrategy{i}, comparison.KeepDeltaPct(i), ...
        comparison.RMS30MaxDelta(i), comparison.ReductionDeltaPct(i), ...
        comparison.Decision{i});
end
end

function latestPaths = writeLatest(dataRoot, runName, comparison, conservativePtr, gridPtr, xlsxPath, csvPath, markdownPath)
runLogs = fullfile(dataRoot, 'run_logs');
latestPaths = struct( ...
    'json', fullfile(runLogs, 'cable_accel_display_compare_latest.json'), ...
    'markdown', fullfile(runLogs, 'cable_accel_display_compare_latest.md'), ...
    'html', fullfile(runLogs, 'cable_accel_display_compare_latest.html'));

pointer = struct();
pointer.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
pointer.run_name = runName;
pointer.output_folder = relPath(fileparts(xlsxPath), dataRoot);
pointer.summary = relPath(markdownPath, dataRoot);
pointer.workbook = relPath(xlsxPath, dataRoot);
pointer.csv = relPath(csvPath, dataRoot);
pointer.review_html = relPath(latestPaths.html, dataRoot);
pointer.conservative_html = conservativePtr.review_html;
pointer.conservative_detail_board = conservativePtr.review_board;
pointer.conservative_trend_board = conservativePtr.trend_review_board;
pointer.grid_html = gridPtr.review_html;
pointer.grid_detail_board = gridPtr.detail_board;
pointer.grid_trend_board = gridPtr.trend_board;
pointer.formal_policy = 'Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.';

fid = fopen(latestPaths.json, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(pointer));
clear cleaner;

fid = fopen(latestPaths.markdown, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Latest Zhishan Cable Acceleration Display Comparison\n\n');
fprintf(fid, '- Generated: %s\n', pointer.generated_at);
fprintf(fid, '- Run: `%s`\n', pointer.run_name);
fprintf(fid, '- Summary: `%s`\n', pointer.summary);
fprintf(fid, '- Workbook: `%s`\n', pointer.workbook);
fprintf(fid, '- Review HTML: `%s`\n', pointer.review_html);
fprintf(fid, '- Conservative HTML: `%s`\n', pointer.conservative_html);
fprintf(fid, '- Grid HTML: `%s`\n', pointer.grid_html);
fprintf(fid, '- Formal policy: %s\n\n', pointer.formal_policy);
fprintf(fid, '| Point | Keep delta %% | RMS30 max delta | Reduction delta %% | Decision |\n');
fprintf(fid, '|---|---:|---:|---:|---|\n');
for i = 1:height(comparison)
    fprintf(fid, '| %s | %.3f | %.3f | %.1f | %s |\n', ...
        comparison.PointID{i}, comparison.KeepDeltaPct(i), ...
        comparison.RMS30MaxDelta(i), comparison.ReductionDeltaPct(i), ...
        comparison.Decision{i});
end
clear cleaner;

writeLatestHtml(latestPaths.html, pointer, comparison);
end

function writeLatestHtml(path, pointer, comparison)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Display Comparison</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.meta,.note{line-height:1.7;color:#4b5563;} .note{background:white;border-left:4px solid #2f6fed;padding:10px 12px;margin:14px 0 20px;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;}');
fprintf(fid, 'th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.prefer{background:#eaf7ee;} .aggressive{background:#fff8e1;} .figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;}');
fprintf(fid, '.boards{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:16px;} img{max-width:100%%;height:auto;display:block;margin:auto;} a{color:#075da8;text-decoration:none;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230;&#23637;&#31034;&#20505;&#36873;&#23545;&#27604; / Display Candidate Comparison</h1>\n');
fprintf(fid, '<div class="meta">Generated: %s<br>Run: <code>%s</code><br>Summary: <a href="%s">%s</a><br>Workbook: <a href="%s">%s</a></div>\n', ...
    htmlText(pointer.generated_at), htmlText(pointer.run_name), htmlPath(pointer.summary), htmlText(pointer.summary), ...
    htmlPath(pointer.workbook), htmlText(pointer.workbook));
fprintf(fid, '<div class="note">&#27491;&#24335;&#39057;&#35889;/&#32034;&#21147;&#35745;&#31639;&#19981;&#21464;: <code>daily_median + [-100,100] m/s^2</code>. &#26412;&#39029;&#23545;&#27604;&#30340;&#37117;&#26159;&#23637;&#31034;/&#23457;&#22270;&#20505;&#36873;&#12290;</div>\n');

fprintf(fid, '<h2>&#25968;&#20540;&#23545;&#27604; / Numeric Comparison</h2>\n<table>\n');
fprintf(fid, '<tr><th>&#27979;&#28857;</th><th>&#20445;&#23432;&#31574;&#30053;</th><th>&#32593;&#26684;&#31574;&#30053;</th><th>&#20445;&#30041;&#29575;&#21464;&#21270;</th><th>RMS30 &#26368;&#22823;&#20540;&#21464;&#21270</th><th>RMS30 &#38477;&#20302;&#22686;&#37327;</th><th>&#21028;&#26029;</th></tr>\n');
for i = 1:height(comparison)
    cls = rowClass(comparison.Decision{i});
    fprintf(fid, '<tr%s><td>%s</td><td>%s</td><td>%s</td><td class="num">%.3f%%</td><td class="num">%.3f</td><td class="num">%.1f%%</td><td>%s</td></tr>\n', ...
        cls, htmlText(comparison.PointID{i}), htmlText(comparison.ConservativeStrategy{i}), ...
        htmlText(comparison.GridStrategy{i}), comparison.KeepDeltaPct(i), ...
        comparison.RMS30MaxDelta(i), comparison.ReductionDeltaPct(i), htmlText(comparison.Decision{i}));
end
fprintf(fid, '</table>\n');

fprintf(fid, '<h2>&#35814;&#32454;&#22270;&#26495; / Detail Boards</h2>\n<div class="boards">\n');
fprintf(fid, '<div class="figure"><h2>Conservative</h2><img src="%s" alt="conservative detail"></div>\n', htmlPath(pointer.conservative_detail_board));
fprintf(fid, '<div class="figure"><h2>Grid Search</h2><img src="%s" alt="grid detail"></div>\n', htmlPath(pointer.grid_detail_board));
fprintf(fid, '</div>\n<h2>&#36235;&#21183;&#22270;&#26495; / Trend Boards</h2>\n<div class="boards">\n');
fprintf(fid, '<div class="figure"><h2>Conservative</h2><img src="%s" alt="conservative trend"></div>\n', htmlPath(pointer.conservative_trend_board));
fprintf(fid, '<div class="figure"><h2>Grid Search</h2><img src="%s" alt="grid trend"></div>\n', htmlPath(pointer.grid_trend_board));
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function cls = rowClass(decision)
if contains(decision, 'prefer grid') || contains(decision, 'reasonable') || contains(decision, 'improves')
    cls = ' class="prefer"';
elseif contains(decision, 'aggressive')
    cls = ' class="aggressive"';
else
    cls = '';
end
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
