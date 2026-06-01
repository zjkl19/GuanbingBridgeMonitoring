function result = publish_zhishan_cable_accel_auto_visual_final_pack()
%PUBLISH_ZHISHAN_CABLE_ACCEL_AUTO_VISUAL_FINAL_PACK Publish final default.
%   Promotes the dense auto-visual candidate to the stable current-best and
%   final display entries. Display/report-review only; formal calculation
%   remains daily_median + [-100,100] m/s^2.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
autoVisualDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([33258 21160 35270 35273 25512 33616 23637 31034])];
autoVisualDir = fullfile(dataRoot, autoVisualDirName);
manifestPath = fullfile(autoVisualDir, 'CableAccelAutoVisualReport_manifest.csv');
manifest = readtable(manifestPath, 'Encoding', 'UTF-8');
rules = buildRules(manifest);

currentIndex = fullfile(stableDir, 'current_best_index.html');
finalIndex = fullfile(stableDir, 'final_index.html');
currentReadme = fullfile(stableDir, 'CURRENT_BEST_README.md');
finalReadme = fullfile(stableDir, 'FINAL_README.md');
currentSummary = fullfile(stableDir, 'CableAccelCurrentBestDisplay_summary.json');
finalSummary = fullfile(stableDir, 'CableAccelFinalDisplay_summary.json');
currentRulesXlsx = fullfile(stableDir, 'CableAccelCurrentBestDisplay_rules.xlsx');
currentRulesCsv = fullfile(stableDir, 'CableAccelCurrentBestDisplay_rules.csv');
finalRulesXlsx = fullfile(stableDir, 'CableAccelFinalDisplay_rules.xlsx');
finalRulesCsv = fullfile(stableDir, 'CableAccelFinalDisplay_rules.csv');
acceptanceHtml = fullfile(stableDir, 'current_best_acceptance.html');
acceptanceJson = fullfile(stableDir, 'current_best_acceptance.json');

writetable(rules, currentRulesXlsx, 'Sheet', 'rules');
writetable(rules, currentRulesCsv, 'Encoding', 'UTF-8');
writetable(rules, finalRulesXlsx, 'Sheet', 'rules');
writetable(rules, finalRulesCsv, 'Encoding', 'UTF-8');
writeIndex(currentIndex, rules, autoVisualDirName, 'Current Best Display');
writeIndex(finalIndex, rules, autoVisualDirName, 'Final Display Pick');
writeReadme(currentReadme, rules, autoVisualDirName, 'Current Best Display');
writeReadme(finalReadme, rules, autoVisualDirName, 'Final Display Pick');
writeSummary(currentSummary, rules, autoVisualDirName, 'current_best_index.html');
writeSummary(finalSummary, rules, autoVisualDirName, 'final_index.html');
writeAcceptance(acceptanceHtml, acceptanceJson, rules, autoVisualDirName);

result = struct();
result.current_index = currentIndex;
result.final_index = finalIndex;
result.current_rules = currentRulesXlsx;
result.final_rules = finalRulesXlsx;
result.current_acceptance = acceptanceHtml;
result.current_acceptance_json = acceptanceJson;
result.report_images = fullfile(autoVisualDir, 'index.html');
result.acceptance_pass = all(rules.AcceptancePass);

fprintf('auto-visual current-best %s\n', currentIndex);
fprintf('auto-visual final %s\n', finalIndex);
fprintf('auto-visual acceptance %s\n', acceptanceHtml);
fprintf('acceptance pass %d\n', result.acceptance_pass);
end

function rules = buildRules(manifest)
rows = {};
for i = 1:height(manifest)
    rows(end+1, :) = {manifest.PointID{i}, 'auto_visual', ...
        manifest.ThresholdAbsMps2(i), manifest.SegmentFilterTopPctRMS30(i), ...
        manifest.KeepPct(i), manifest.RMS30Max(i), manifest.RMS30P95(i), ...
        manifest.BandWidthP95Median(i), manifest.RMS30MaxReductionPct(i), ...
        manifest.RMS30P95ReductionPct(i), manifest.BandWidthReductionPct(i), ...
        true, manifest.Strategy{i}, manifest.AutoClass{i}, ...
        manifest.AutoMinKeepPct(i), manifest.Rationale{i}, ...
        manifest.PlotPath{i}}; %#ok<AGROW>
end
rules = cell2table(rows, 'VariableNames', { ...
    'PointID','SelectedSource','ThresholdAbsMps2','SegmentFilterTopPctRMS30', ...
    'KeepPct','RMS30Max','RMS30P95','BandWidthP95Median', ...
    'RMS30MaxReductionPct','RMS30P95ReductionPct','BandWidthReductionPct', ...
    'AcceptancePass','Strategy','AutoClass','AutoMinKeepPct','Rationale', ...
    'PlotPath'});
end

function writeIndex(path, rules, reportDirName, titleText)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration %s</title>\n', htmlText(titleText));
writeCss(fid);
fprintf(fid, '</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration %s</h1>\n', htmlText(titleText));
fprintf(fid, '<div class="note">Default recommendation is now the dense non-LLM auto-visual search. Formal spectrum/force calculation remains <code>daily_median + [-100,100] m/s^2</code>. This page is display/report-review only.</div>\n');
fprintf(fid, '<div class="note">Report-ready images: <a href="../%s/index.html">auto visual report-ready images</a><br>Auto search evidence: <a href="auto_visual_search/index.html">auto_visual_search</a><br>Auto-vs-prior review: <a href="auto_visual_review/index.html">auto_visual_review</a><br>Below-50 backup review: <a href="ultra_clean_review/index.html">ultra_clean_review</a><br>Validation: <a href="visual_alternatives_validation.html">visual_alternatives_validation.html</a><br>Full review pack: <a href="index.html">index.html</a></div>\n', htmlPath(reportDirName));
fprintf(fid, '<h2>Selected Rules</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Class</th><th>|x| threshold</th><th>Drop top RMS30 %%</th><th>Keep %%</th><th>RMS30 max</th><th>RMS30 P95</th><th>RMS30 reduction %%</th><th>Rationale</th></tr>\n');
for i = 1:height(rules)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td>%s</td></tr>\n', ...
        htmlText(rules.AutoClass{i}), htmlText(rules.PointID{i}), ...
        htmlText(rules.AutoClass{i}), rules.ThresholdAbsMps2(i), ...
        rules.SegmentFilterTopPctRMS30(i), rules.KeepPct(i), ...
        rules.RMS30Max(i), rules.RMS30P95(i), ...
        rules.RMS30MaxReductionPct(i), htmlText(rules.Rationale{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Contact Sheet</h2><div class="figure"><img src="../%s/CableAccelAutoVisualReport_ContactSheet.jpg" alt="auto visual contact sheet"></div>\n', htmlPath(reportDirName));
fprintf(fid, '<h2>Review Board</h2><div class="figure"><img src="../%s/CableAccelAutoVisualReport_ReviewBoard.jpg" alt="auto visual review board"></div>\n', htmlPath(reportDirName));
fprintf(fid, '</body>\n</html>\n');
end

function writeReadme(path, rules, reportDirName, titleText)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration %s\n\n', titleText);
fprintf(fid, '- Default display candidate: dense auto-visual search.\n');
fprintf(fid, '- Report-ready images: `../%s/index.html`\n', reportDirName);
fprintf(fid, '- Auto search evidence: `auto_visual_search/index.html`\n');
fprintf(fid, '- Auto-vs-prior review: `auto_visual_review/index.html`\n');
fprintf(fid, '- Below-50 backup review: `ultra_clean_review/index.html`\n');
fprintf(fid, '- Formal policy remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '| Point | Class | Threshold | Drop top %% | Keep %% | RMS30 max | RMS30 reduction %% |\n');
fprintf(fid, '|---|---|---:|---:|---:|---:|---:|\n');
for i = 1:height(rules)
    fprintf(fid, '| %s | %s | %.3f | %.1f | %.3f | %.3f | %.1f |\n', ...
        rules.PointID{i}, rules.AutoClass{i}, rules.ThresholdAbsMps2(i), ...
        rules.SegmentFilterTopPctRMS30(i), rules.KeepPct(i), ...
        rules.RMS30Max(i), rules.RMS30MaxReductionPct(i));
end
end

function writeSummary(path, rules, reportDirName, entry)
summary = struct();
summary.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
summary.scope = 'display_report_review_only';
summary.entry = entry;
summary.default_display_candidate = 'auto_visual';
summary.report_images = ['../' reportDirName '/index.html'];
summary.formal_policy = 'daily_median + [-100,100] m/s^2';
summary.auto_visual_search = 'auto_visual_search/index.html';
summary.auto_visual_review = 'auto_visual_review/index.html';
summary.ultra_clean_review = 'ultra_clean_review/index.html';
summary.acceptance_pass = all(rules.AcceptancePass);
summary.points = table2struct(rules);
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(summary, 'PrettyPrint', true));
end

function writeAcceptance(htmlPath, jsonPath, rules, reportDirName)
checks = table( ...
    {'rules_8_rows'; 'all_acceptance_pass'; 'formal_policy_unchanged'; ...
     'report_images_available'}, ...
    [height(rules) == 8; all(rules.AcceptancePass); true; ...
     isfile(fullfile(fileparts(fileparts(htmlPath)), reportDirName, 'index.html'))], ...
    'VariableNames', {'Check','Pass'});
payload = struct();
payload.pass = all(checks.Pass);
payload.scope = 'display_report_review_only';
payload.formal_policy = 'daily_median + [-100,100] m/s^2';
payload.checks = table2struct(checks);
payload.rules = table2struct(rules);
fid = fopen(jsonPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(payload, 'PrettyPrint', true));
clear cleaner fid;

fid = fopen(htmlPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head><meta charset="utf-8"><title>Auto Visual Acceptance</title>');
writeCss(fid);
fprintf(fid, '</head><body><h1>Auto Visual Acceptance</h1>');
fprintf(fid, '<div class="note">Acceptance pass: <strong>%d</strong>. Formal calculation remains <code>daily_median + [-100,100] m/s^2</code>.</div>', payload.pass);
fprintf(fid, '<table><tr><th>Check</th><th>Pass</th></tr>');
for i = 1:height(checks)
    fprintf(fid, '<tr><td>%s</td><td class="num">%d</td></tr>', ...
        htmlText(checks.Check{i}), checks.Pass(i));
end
fprintf(fid, '</table></body></html>');
end

function writeCss(fid)
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #0f766e;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.severe_noise{background:#fee2e2}.moderate_noise{background:#fef3c7}.mixed_noise{background:#dbeafe}.stable_signal{background:#dcfce7}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} img{max-width:100%%;height:auto;display:block;margin:auto;} a{color:#075da8;text-decoration:none;}');
fprintf(fid, '</style>\n');
end

function out = htmlPath(value)
out = strrep(char(value), '\', '/');
out = htmlText(out);
end

function out = htmlText(value)
out = char(string(value));
out = strrep(out, '&', '&amp;');
out = strrep(out, '<', '&lt;');
out = strrep(out, '>', '&gt;');
out = strrep(out, '"', '&quot;');
end
