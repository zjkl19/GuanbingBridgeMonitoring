function result = publish_zhishan_cable_accel_current_best_pack()
%PUBLISH_ZHISHAN_CABLE_ACCEL_CURRENT_BEST_PACK Publish current best display.
%   Uses the accepted auto-knee candidate as the current best display-only
%   recommendation. Formal spectrum/force calculation remains unchanged.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
autoKneeDir = fullfile(stableDir, 'auto_knee_display_pick');
reportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([24403 21069 26368 20339 25512 33616 23637 31034])];
cleanerReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26356 24178 20928 20248 20808 23637 31034])];
cleanest70ReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26368 24178 20928 33258 21160 23637 31034])];

manifestPath = fullfile(autoKneeDir, 'CableAccelAutoKnee_manifest.csv');
acceptancePath = fullfile(autoKneeDir, 'CableAccelAutoKnee_acceptance.json');
manifest = readtable(manifestPath, 'Encoding', 'UTF-8');
acceptance = readJson(acceptancePath);
rules = buildRulesTable(manifest);

indexPath = fullfile(stableDir, 'current_best_index.html');
readmePath = fullfile(stableDir, 'CURRENT_BEST_README.md');
summaryPath = fullfile(stableDir, 'CableAccelCurrentBestDisplay_summary.json');
rulesXlsx = fullfile(stableDir, 'CableAccelCurrentBestDisplay_rules.xlsx');
rulesCsv = fullfile(stableDir, 'CableAccelCurrentBestDisplay_rules.csv');

writetable(rules, rulesXlsx, 'Sheet', 'rules');
writetable(rules, rulesCsv, 'Encoding', 'UTF-8');
writeIndex(indexPath, rules, acceptance, reportDirName, cleanerReportDirName, cleanest70ReportDirName);
writeReadme(readmePath, rules, acceptance, reportDirName, cleanerReportDirName, cleanest70ReportDirName);
writeSummary(summaryPath, rules, acceptance, reportDirName, cleanerReportDirName, cleanest70ReportDirName);

result = struct();
result.index = indexPath;
result.readme = readmePath;
result.summary = summaryPath;
result.rules_xlsx = rulesXlsx;
result.rules_csv = rulesCsv;
result.acceptance_pass = acceptance.pass;

fprintf('current-best index %s\n', indexPath);
fprintf('current-best rules %s\n', rulesXlsx);
fprintf('current-best acceptance pass %d\n', acceptance.pass);
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

function rules = buildRulesTable(manifest)
rows = {};
for i = 1:height(manifest)
    rows(end+1, :) = {manifest.PointID{i}, manifest.SelectedSource{i}, ...
        manifest.ThresholdAbsMps2(i), manifest.SegmentFilterTopPctRMS30(i), ...
        manifest.KeepPct(i), manifest.RMS30Max(i), manifest.RMS30P95(i), ...
        manifest.KeepDeltaVsFinalPct(i), manifest.RMS30MaxDeltaVsFinalPct(i), ...
        logical(manifest.AcceptancePass(i)), manifest.Strategy{i}, ...
        manifest.Rationale{i}}; %#ok<AGROW>
end
rules = cell2table(rows, 'VariableNames', { ...
    'PointID','SelectedSource','ThresholdAbsMps2','SegmentFilterTopPctRMS30', ...
    'KeepPct','RMS30Max','RMS30P95','KeepDeltaVsBalancedPct', ...
    'RMS30MaxImprovementPct','AcceptancePass','Strategy','Rationale'});
end

function writeIndex(path, rules, acceptance, reportDirName, cleanerReportDirName, cleanest70ReportDirName)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
satisfactionAutoReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([28385 24847 24230 33258 21160 25512 33616 23637 31034])];
lowKeepAutoReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([20302 20445 30041 29575 33258 21160 25512 33616 23637 31034])];
extremeFallbackReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26497 38480 24178 20928 22791 36873 23637 31034])];
autoKneeCount = nnz(strcmp(rules.SelectedSource, 'auto_knee'));
balancedCount = nnz(strcmp(rules.SelectedSource, 'balanced_final'));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Current Best Display</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.meta,.note{line-height:1.7;color:#4b5563;} .note{background:white;border-left:4px solid #067a46;padding:10px 12px;margin:14px 0 20px;}');
fprintf(fid, '.pass{color:#067a46;font-weight:700;} table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;}');
fprintf(fid, 'th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.auto_knee{background:#f4edff}.balanced_final{background:#eaf7f2}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;}');
fprintf(fid, 'img{max-width:100%%;height:auto;display:block;margin:auto;} a{color:#075da8;text-decoration:none;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230;&#24403;&#21069;&#26368;&#20339;&#23637;&#31034; / Current Best Display</h1>\n');
fprintf(fid, '<div class="meta">Acceptance pass: <span class="pass">%d</span><br>Current-best acceptance: <a href="current_best_acceptance.html">current_best_acceptance.html</a><br>Rules: <a href="CableAccelCurrentBestDisplay_rules.xlsx">CableAccelCurrentBestDisplay_rules.xlsx</a><br>Auto-knee acceptance: <a href="auto_knee_display_pick/acceptance.html">auto-knee acceptance</a><br>Side-by-side review: <a href="balanced_vs_auto_knee_review/index.html">balanced vs auto-knee</a><br>Satisfaction review: <a href="satisfaction_review/index.html">current-best / cleaner-priority / cleanest70</a><br>Three-level tradeoff: <a href="three_level_tradeoff_review/index.html">current-best / aggressive / target80</a><br>Retention tradeoff summary: <a href="retention_tradeoff_summary/index.html">retention tradeoff summary</a><br>Visual-best mixed pick: <a href="visual_best_display_export/index.html">visual-best display export</a><br>Cleaner-priority pick: <a href="decisive_visual_display_export/index.html">decisive visual display export</a><br>Cleanest70 auto pick: <a href="cleanest70_display_export/index.html">cleanest70 display export</a><br>Cleaner tradeoff review: <a href="current_best_vs_aggressive_review/index.html">current-best vs aggressive</a><br>Target80 export: <a href="target80_display_export/index.html">target80 display export</a><br>Target70 export: <a href="target70_display_export/index.html">target70 display export</a><br>Report-ready images: <a href="../%s/index.html">current-best report-ready images</a><br>Cleaner-priority report images: <a href="../%s/index.html">cleaner-priority report-ready images</a><br>Cleanest70 report images: <a href="../%s/index.html">cleanest70 report-ready images</a><br>Satisfaction auto report images: <a href="../%s/index.html">satisfaction-auto report-ready images</a><br>Full review pack: <a href="index.html">index.html</a></div>\n', ...
    acceptance.pass, htmlPath(reportDirName), htmlPath(cleanerReportDirName), ...
    htmlPath(cleanest70ReportDirName), htmlPath(satisfactionAutoReportDirName));
fprintf(fid, '<div class="note">&#24403;&#21069;&#25512;&#33616;&#20351;&#29992; auto-knee &#20505;&#36873;&#65306;%d &#20010;&#27979;&#28857;&#20351;&#29992; auto-knee&#65292;%d &#20010;&#27979;&#28857;&#20445;&#25345; balanced final&#12290;&#27491;&#24335;&#39057;&#35889;/&#32034;&#21147;&#35745;&#31639;&#19981;&#21464;: <code>daily_median + [-100,100] m/s^2</code>. &#26412;&#39029;&#20165;&#29992;&#20110;&#23637;&#31034;/&#23457;&#22270;&#21644;&#25253;&#21578;&#21462;&#22270;&#20915;&#31574;&#12290;</div>\n', ...
    autoKneeCount, balancedCount);
fprintf(fid, '<div class="note">If current-best is still visually too wide, review <a href="current_best_vs_aggressive_review/index.html">current-best vs aggressive</a> first. The aggressive tier is cleaner but usually keeps about 85%%-87%% of finite data. The <a href="target80_display_export/index.html">target80 export</a> is a more aggressive reference, not the default recommendation.</div>\n');
fprintf(fid, '<div class="note">For a single no-pick stricter chart package, open <a href="visual_best_display_export/index.html">visual-best display export</a>. It mixes aggressive and target80 according to the three-level tradeoff suggestions.</div>\n');
fprintf(fid, '<div class="note">For the cleanest no-pick backup, open <a href="decisive_visual_display_export/index.html">decisive visual display export</a>. It uses target75 for CF-1/CF-2/CF-5 and visual-best for the other points, so it should be reviewed only if chart cleanliness is more important than retention.</div>\n');
fprintf(fid, '<div class="note">For the automatic cleanest backup with a 70%% keep floor, open <a href="cleanest70_display_export/index.html">cleanest70 display export</a>. It selects the lowest RMS30 max candidate per point among all generated tiers, so it is stricter than decisive visual and should be used only after review.</div>\n');
fprintf(fid, '<div class="note">For the fastest satisfaction check, open <a href="satisfaction_review/index.html">satisfaction review</a>. It compares current-best, cleaner-priority, and cleanest70 side by side for each point and gives an automatic review recommendation.</div>\n');
fprintf(fid, '<div class="note">For a single report-facing image set based on that automatic recommendation, open <a href="../%s/index.html">satisfaction-auto report-ready images</a>.</div>\n', htmlPath(satisfactionAutoReportDirName));
fprintf(fid, '<div class="note">If the satisfaction-auto package is still not clean enough, open <a href="low_keep_tradeoff_review/index.html">low-keep tradeoff review</a>. It compares satisfaction-auto, cleanest60, and cleanest50 without changing formal calculation.</div>\n');
fprintf(fid, '<div class="note">For a single report-facing image set based on the low-keep tradeoff recommendation, open <a href="../%s/index.html">low-keep auto report-ready images</a>.</div>\n', htmlPath(lowKeepAutoReportDirName));
fprintf(fid, '<div class="note">For the strictest report-facing fallback, open <a href="../%s/index.html">extreme fallback report-ready images</a>. It uses cleanest50 only where the low-keep review explicitly marked an extreme fallback.</div>\n', htmlPath(extremeFallbackReportDirName));
fprintf(fid, '<h2>&#31574;&#30053;&#34920; / Strategy Table</h2>\n<table>\n');
fprintf(fid, '<tr><th>Point</th><th>Selected</th><th>|x| threshold</th><th>RMS30 top %%</th><th>Keep %%</th><th>RMS30 max</th><th>Improve %%</th><th>Pass</th><th>Rationale</th></tr>\n');
for i = 1:height(rules)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%d</td><td>%s</td></tr>\n', ...
        htmlText(rules.SelectedSource{i}), htmlText(rules.PointID{i}), ...
        htmlText(rules.SelectedSource{i}), rules.ThresholdAbsMps2(i), ...
        rules.SegmentFilterTopPctRMS30(i), rules.KeepPct(i), rules.RMS30Max(i), ...
        rules.RMS30MaxImprovementPct(i), rules.AcceptancePass(i), ...
        htmlText(rules.Rationale{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Auto-knee Contact Sheet</h2>\n');
fprintf(fid, '<div class="figure"><img src="auto_knee_display_pick/CableAccelAutoKnee_ContactSheet.jpg" alt="auto-knee contact sheet"></div>\n');
fprintf(fid, '<h2>Acceptance Evidence</h2>\n');
fprintf(fid, '<div class="figure"><img src="auto_knee_display_pick/CableAccelAutoKnee_ContactSheet.jpg" alt="acceptance evidence"></div>\n');
fprintf(fid, '</body>\n</html>\n');
end

function writeReadme(path, rules, acceptance, reportDirName, cleanerReportDirName, cleanest70ReportDirName)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
satisfactionAutoReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([28385 24847 24230 33258 21160 25512 33616 23637 31034])];
lowKeepAutoReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([20302 20445 30041 29575 33258 21160 25512 33616 23637 31034])];
extremeFallbackReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26497 38480 24178 20928 22791 36873 23637 31034])];
fprintf(fid, '# Zhishan Cable Acceleration Current Best Display\n\n');
fprintf(fid, '- Entry: `current_best_index.html`\n');
fprintf(fid, '- Acceptance pass: `%d`\n', acceptance.pass);
fprintf(fid, '- Current-best acceptance: `current_best_acceptance.html`\n');
fprintf(fid, '- Rules: `CableAccelCurrentBestDisplay_rules.xlsx`\n');
fprintf(fid, '- Auto-knee acceptance: `auto_knee_display_pick/acceptance.html`\n');
fprintf(fid, '- Side-by-side review: `balanced_vs_auto_knee_review/index.html`\n');
fprintf(fid, '- Satisfaction review: `satisfaction_review/index.html`\n');
fprintf(fid, '- Low-keep tradeoff review: `low_keep_tradeoff_review/index.html`\n');
fprintf(fid, '- Three-level tradeoff review: `three_level_tradeoff_review/index.html`\n');
fprintf(fid, '- Retention tradeoff summary: `retention_tradeoff_summary/index.html`\n');
fprintf(fid, '- Visual-best mixed pick: `visual_best_display_export/index.html`\n');
fprintf(fid, '- Cleaner-priority mixed pick: `decisive_visual_display_export/index.html`\n');
fprintf(fid, '- Cleanest70 auto pick: `cleanest70_display_export/index.html`\n');
fprintf(fid, '- Current-best vs aggressive review: `current_best_vs_aggressive_review/index.html`\n');
fprintf(fid, '- Target80 display export: `target80_display_export/index.html`\n');
fprintf(fid, '- Target70 display export: `target70_display_export/index.html`\n');
fprintf(fid, '- Current-best report-ready images: `../%s/index.html`\n', reportDirName);
fprintf(fid, '- Cleaner-priority report-ready images: `../%s/index.html`\n', cleanerReportDirName);
fprintf(fid, '- Cleanest70 report-ready images: `../%s/index.html`\n', cleanest70ReportDirName);
fprintf(fid, '- Satisfaction-auto report-ready images: `../%s/index.html`\n\n', satisfactionAutoReportDirName);
fprintf(fid, '- Low-keep auto report-ready images: `../%s/index.html`\n\n', lowKeepAutoReportDirName);
fprintf(fid, '- Extreme fallback report-ready images: `../%s/index.html`\n\n', extremeFallbackReportDirName);
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '| Point | Selected | |x| threshold | RMS30 top %% | Keep %% | RMS30 max | Improve %% | Pass |\n');
fprintf(fid, '|---|---|---:|---:|---:|---:|---:|---:|\n');
for i = 1:height(rules)
    fprintf(fid, '| %s | %s | %.3f | %.1f | %.3f | %.3f | %.1f | %d |\n', ...
        rules.PointID{i}, rules.SelectedSource{i}, rules.ThresholdAbsMps2(i), ...
        rules.SegmentFilterTopPctRMS30(i), rules.KeepPct(i), rules.RMS30Max(i), ...
        rules.RMS30MaxImprovementPct(i), rules.AcceptancePass(i));
end
end

function writeSummary(path, rules, acceptance, reportDirName, cleanerReportDirName, cleanest70ReportDirName)
summary = struct();
satisfactionAutoReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([28385 24847 24230 33258 21160 25512 33616 23637 31034])];
lowKeepAutoReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([20302 20445 30041 29575 33258 21160 25512 33616 23637 31034])];
extremeFallbackReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26497 38480 24178 20928 22791 36873 23637 31034])];
summary.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
summary.scope = 'display_only';
summary.current_best_policy = 'Accepted auto-knee candidate';
summary.formal_policy = 'Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.';
summary.acceptance_pass = acceptance.pass;
summary.entry = 'current_best_index.html';
summary.current_best_acceptance = 'current_best_acceptance.html';
summary.rules = 'CableAccelCurrentBestDisplay_rules.xlsx';
summary.rules_csv = 'CableAccelCurrentBestDisplay_rules.csv';
summary.auto_knee_acceptance = 'auto_knee_display_pick/acceptance.html';
summary.side_by_side_review = 'balanced_vs_auto_knee_review/index.html';
summary.satisfaction_review = 'satisfaction_review/index.html';
summary.low_keep_tradeoff_review = 'low_keep_tradeoff_review/index.html';
summary.three_level_tradeoff_review = 'three_level_tradeoff_review/index.html';
summary.retention_tradeoff_summary = 'retention_tradeoff_summary/index.html';
summary.visual_best_display_export = 'visual_best_display_export/index.html';
summary.decisive_visual_display_export = 'decisive_visual_display_export/index.html';
summary.cleanest70_display_export = 'cleanest70_display_export/index.html';
summary.current_best_vs_aggressive_review = 'current_best_vs_aggressive_review/index.html';
summary.target80_display_export = 'target80_display_export/index.html';
summary.target70_display_export = 'target70_display_export/index.html';
summary.report_ready_images = ['../' reportDirName '/index.html'];
summary.cleaner_priority_report_images = ['../' cleanerReportDirName '/index.html'];
summary.cleanest70_report_images = ['../' cleanest70ReportDirName '/index.html'];
summary.satisfaction_auto_report_images = ['../' satisfactionAutoReportDirName '/index.html'];
summary.low_keep_auto_report_images = ['../' lowKeepAutoReportDirName '/index.html'];
summary.extreme_fallback_report_images = ['../' extremeFallbackReportDirName '/index.html'];
summary.points = struct();
for i = 1:height(rules)
    field = matlab.lang.makeValidName(strrep(rules.PointID{i}, '-', '_'));
    summary.points.(field) = struct( ...
        'point_id', rules.PointID{i}, ...
        'selected_source', rules.SelectedSource{i}, ...
        'threshold_abs_mps2', rules.ThresholdAbsMps2(i), ...
        'segment_filter_top_pct_rms30', rules.SegmentFilterTopPctRMS30(i), ...
        'keep_pct', rules.KeepPct(i), ...
        'rms30_max', rules.RMS30Max(i), ...
        'rms30_max_improvement_pct', rules.RMS30MaxImprovementPct(i), ...
        'acceptance_pass', rules.AcceptancePass(i));
end
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(summary));
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
