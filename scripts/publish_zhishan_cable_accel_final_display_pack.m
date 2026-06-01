function result = publish_zhishan_cable_accel_final_display_pack()
%PUBLISH_ZHISHAN_CABLE_ACCEL_FINAL_DISPLAY_PACK Create final user entry.
%   Publishes a concise final entry for the automatic balanced display pick.
%   The full review pack remains available from index.html.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
balancedDir = fullfile(stableDir, 'balanced_display_pick');
autoKneeDir = fullfile(stableDir, 'auto_knee_display_pick');

balancedAcceptance = readJson(fullfile(balancedDir, 'CableAccelBalancedDisplay_acceptance.json'));
autoKneeAcceptance = readJson(fullfile(autoKneeDir, 'CableAccelAutoKnee_acceptance.json'));
rules = buildCurrentBestRulesTable(fullfile(autoKneeDir, 'CableAccelAutoKnee_manifest.csv'));

finalIndex = fullfile(stableDir, 'final_index.html');
finalReadme = fullfile(stableDir, 'FINAL_README.md');
finalSummary = fullfile(stableDir, 'CableAccelFinalDisplay_summary.json');
finalRulesXlsx = fullfile(stableDir, 'CableAccelFinalDisplay_rules.xlsx');
finalRulesCsv = fullfile(stableDir, 'CableAccelFinalDisplay_rules.csv');
currentBestRel = 'current_best_index.html';
currentBestRulesRel = 'CableAccelCurrentBestDisplay_rules.xlsx';
currentBestAcceptanceRel = 'current_best_acceptance.html';
currentBestExists = exist(fullfile(stableDir, currentBestRel), 'file') == 2;
currentBestAcceptanceExists = exist(fullfile(stableDir, currentBestAcceptanceRel), 'file') == 2;
finalReportImageDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26368 32456 25512 33616 23637 31034])];
finalReportImageIndex = fullfile(dataRoot, finalReportImageDirName, 'index.html');
finalReportImageManifest = fullfile(dataRoot, finalReportImageDirName, ...
    'CableAccelFinalDisplay_manifest.xlsx');
finalReportImageRel = ['../' finalReportImageDirName '/index.html'];
finalReportManifestRel = ['../' finalReportImageDirName '/CableAccelFinalDisplay_manifest.xlsx'];
finalReportImagesExist = exist(finalReportImageIndex, 'file') == 2;
polishedRel = 'polished_min90_display_pick/index.html';
polishedManifestRel = 'polished_min90_display_pick/CableAccelPolishedMin90_manifest.xlsx';
polishedExists = exist(fullfile(stableDir, polishedRel), 'file') == 2;
keepLadderRel = 'keep_ladder_review/index.html';
keepLadderManifestRel = 'keep_ladder_review/CableAccelKeepLadder_manifest.xlsx';
keepLadderExists = exist(fullfile(stableDir, keepLadderRel), 'file') == 2;
tradeoffRel = 'tradeoff_dashboard/index.html';
tradeoffManifestRel = 'tradeoff_dashboard/CableAccelTradeoffDashboard_suggestions.xlsx';
tradeoffExists = exist(fullfile(stableDir, tradeoffRel), 'file') == 2;
autoKneeRel = 'auto_knee_display_pick/index.html';
autoKneeManifestRel = 'auto_knee_display_pick/CableAccelAutoKnee_manifest.xlsx';
autoKneeExists = exist(fullfile(stableDir, autoKneeRel), 'file') == 2;
autoKneeAcceptanceRel = 'auto_knee_display_pick/acceptance.html';
autoKneeAcceptanceJsonRel = 'auto_knee_display_pick/CableAccelAutoKnee_acceptance.json';
autoKneeAcceptanceExists = exist(fullfile(stableDir, autoKneeAcceptanceRel), 'file') == 2;
autoKneeReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_auto_knee_' ...
    char([25512 33616 23637 31034])];
autoKneeReportRel = ['../' autoKneeReportDirName '/index.html'];
autoKneeReportManifestRel = ['../' autoKneeReportDirName '/CableAccelAutoKneeReport_manifest.xlsx'];
autoKneeReportExists = exist(fullfile(dataRoot, autoKneeReportDirName, 'index.html'), 'file') == 2;
balancedVsAutoKneeRel = 'balanced_vs_auto_knee_review/index.html';
balancedVsAutoKneeManifestRel = 'balanced_vs_auto_knee_review/CableAccelBalancedVsAutoKnee_manifest.xlsx';
balancedVsAutoKneeExists = exist(fullfile(stableDir, balancedVsAutoKneeRel), 'file') == 2;

writetable(rules, finalRulesXlsx, 'Sheet', 'rules');
writetable(rules, finalRulesCsv, 'Encoding', 'UTF-8');
writeFinalIndex(finalIndex, rules, finalReportImageRel, ...
    finalReportManifestRel, finalReportImagesExist, polishedRel, ...
    polishedManifestRel, polishedExists, keepLadderRel, ...
    keepLadderManifestRel, keepLadderExists, tradeoffRel, ...
    tradeoffManifestRel, tradeoffExists, autoKneeRel, ...
    autoKneeManifestRel, autoKneeExists, autoKneeReportRel, ...
    autoKneeReportManifestRel, autoKneeReportExists, ...
    balancedVsAutoKneeRel, balancedVsAutoKneeManifestRel, ...
    balancedVsAutoKneeExists, autoKneeAcceptanceRel, ...
    autoKneeAcceptanceJsonRel, autoKneeAcceptanceExists, ...
    currentBestRel, currentBestRulesRel, currentBestExists, ...
    currentBestAcceptanceRel, currentBestAcceptanceExists, ...
    balancedAcceptance, autoKneeAcceptance);
writeFinalReadme(finalReadme, rules, balancedAcceptance, autoKneeAcceptance, finalReportImageRel, ...
    finalReportManifestRel, finalReportImagesExist, polishedRel, ...
    polishedManifestRel, polishedExists, keepLadderRel, ...
    keepLadderManifestRel, keepLadderExists, tradeoffRel, ...
    tradeoffManifestRel, tradeoffExists, autoKneeRel, ...
    autoKneeManifestRel, autoKneeExists, autoKneeReportRel, ...
    autoKneeReportManifestRel, autoKneeReportExists, ...
    balancedVsAutoKneeRel, balancedVsAutoKneeManifestRel, ...
    balancedVsAutoKneeExists, autoKneeAcceptanceRel, ...
    autoKneeAcceptanceJsonRel, autoKneeAcceptanceExists, ...
    currentBestRel, currentBestRulesRel, currentBestExists, ...
    currentBestAcceptanceRel, currentBestAcceptanceExists);
writeFinalSummary(finalSummary, rules, balancedAcceptance, autoKneeAcceptance, finalReportImageRel, ...
    finalReportManifestRel, finalReportImagesExist, polishedRel, ...
    polishedManifestRel, polishedExists, keepLadderRel, ...
    keepLadderManifestRel, keepLadderExists, tradeoffRel, ...
    tradeoffManifestRel, tradeoffExists, autoKneeRel, ...
    autoKneeManifestRel, autoKneeExists, autoKneeReportRel, ...
    autoKneeReportManifestRel, autoKneeReportExists, ...
    balancedVsAutoKneeRel, balancedVsAutoKneeManifestRel, ...
    balancedVsAutoKneeExists, autoKneeAcceptanceRel, ...
    autoKneeAcceptanceJsonRel, autoKneeAcceptanceExists, ...
    currentBestRel, currentBestRulesRel, currentBestExists, ...
    currentBestAcceptanceRel, currentBestAcceptanceExists);

result = struct();
result.final_index = finalIndex;
result.final_readme = finalReadme;
result.final_summary = finalSummary;
result.final_rules_xlsx = finalRulesXlsx;
result.final_rules_csv = finalRulesCsv;
result.final_report_images = finalReportImageIndex;
result.final_report_manifest = finalReportImageManifest;
result.polished_min90 = fullfile(stableDir, polishedRel);
result.keep_ladder = fullfile(stableDir, keepLadderRel);
result.tradeoff_dashboard = fullfile(stableDir, tradeoffRel);
result.auto_knee = fullfile(stableDir, autoKneeRel);
result.auto_knee_report_images = fullfile(dataRoot, autoKneeReportDirName, 'index.html');
result.balanced_vs_auto_knee = fullfile(stableDir, balancedVsAutoKneeRel);
result.acceptance_pass = autoKneeAcceptance.pass;

fprintf('final index %s\n', finalIndex);
fprintf('final readme %s\n', finalReadme);
fprintf('final summary %s\n', finalSummary);
fprintf('final rules %s\n', finalRulesXlsx);
fprintf('final report images %s\n', finalReportImageIndex);
fprintf('acceptance pass %d\n', autoKneeAcceptance.pass);
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

function rules = buildCurrentBestRulesTable(manifestPath)
manifest = readtable(manifestPath, 'Encoding', 'UTF-8');
rows = {};
for i = 1:height(manifest)
    rows(end+1, :) = {manifest.PointID{i}, manifest.SelectedSource{i}, ...
        manifest.ThresholdAbsMps2(i), manifest.SegmentFilterTopPctRMS30(i), ...
        manifest.KeepPct(i), manifest.RMS30Max(i), ...
        logical(manifest.AcceptancePass(i)), manifest.Strategy{i}, ...
        manifest.Rationale{i}}; %#ok<AGROW>
end
rules = cell2table(rows, 'VariableNames', { ...
    'PointID','SelectedSource','ThresholdAbsMps2','SegmentFilterTopPctRMS30', ...
    'KeepPct','RMS30Max','AcceptancePass','Strategy','Rationale'});
end

function writeFinalIndex(path, rules, finalReportImageRel, finalReportManifestRel, finalReportImagesExist, polishedRel, polishedManifestRel, polishedExists, keepLadderRel, keepLadderManifestRel, keepLadderExists, tradeoffRel, tradeoffManifestRel, tradeoffExists, autoKneeRel, autoKneeManifestRel, autoKneeExists, autoKneeReportRel, autoKneeReportManifestRel, autoKneeReportExists, balancedVsAutoKneeRel, balancedVsAutoKneeManifestRel, balancedVsAutoKneeExists, autoKneeAcceptanceRel, autoKneeAcceptanceJsonRel, autoKneeAcceptanceExists, currentBestRel, currentBestRulesRel, currentBestExists, currentBestAcceptanceRel, currentBestAcceptanceExists, balancedAcceptance, autoKneeAcceptance)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
imageStatus = 'ready';
if ~finalReportImagesExist
    imageStatus = 'not generated';
end
polishedStatus = 'ready';
if ~polishedExists
    polishedStatus = 'not generated';
end
keepLadderStatus = 'ready';
if ~keepLadderExists
    keepLadderStatus = 'not generated';
end
tradeoffStatus = 'ready';
if ~tradeoffExists
    tradeoffStatus = 'not generated';
end
autoKneeStatus = 'ready';
if ~autoKneeExists
    autoKneeStatus = 'not generated';
end
autoKneeAcceptanceStatus = 'ready';
if ~autoKneeAcceptanceExists
    autoKneeAcceptanceStatus = 'not generated';
end
autoKneeReportStatus = 'ready';
if ~autoKneeReportExists
    autoKneeReportStatus = 'not generated';
end
balancedVsAutoKneeStatus = 'ready';
if ~balancedVsAutoKneeExists
    balancedVsAutoKneeStatus = 'not generated';
end
currentBestStatus = 'ready';
if ~currentBestExists
    currentBestStatus = 'not generated';
end
currentBestAcceptanceStatus = 'ready';
if ~currentBestAcceptanceExists
    currentBestAcceptanceStatus = 'not generated';
end
cleanerReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26356 24178 20928 20248 20808 23637 31034])];
cleanerReportRel = ['../' cleanerReportDirName '/index.html'];
cleanerReportStatus = 'ready';
dataRoot = fileparts(fileparts(path));
if exist(fullfile(dataRoot, cleanerReportDirName, 'index.html'), 'file') ~= 2
    cleanerReportStatus = 'not generated';
end
cleanest70ReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26368 24178 20928 33258 21160 23637 31034])];
cleanest70ReportRel = ['../' cleanest70ReportDirName '/index.html'];
cleanest70ReportStatus = 'ready';
if exist(fullfile(dataRoot, cleanest70ReportDirName, 'index.html'), 'file') ~= 2
    cleanest70ReportStatus = 'not generated';
end
satisfactionAutoReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([28385 24847 24230 33258 21160 25512 33616 23637 31034])];
satisfactionAutoReportRel = ['../' satisfactionAutoReportDirName '/index.html'];
satisfactionAutoReportStatus = 'ready';
if exist(fullfile(dataRoot, satisfactionAutoReportDirName, 'index.html'), 'file') ~= 2
    satisfactionAutoReportStatus = 'not generated';
end
lowKeepAutoReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([20302 20445 30041 29575 33258 21160 25512 33616 23637 31034])];
lowKeepAutoReportRel = ['../' lowKeepAutoReportDirName '/index.html'];
lowKeepAutoReportStatus = 'ready';
if exist(fullfile(dataRoot, lowKeepAutoReportDirName, 'index.html'), 'file') ~= 2
    lowKeepAutoReportStatus = 'not generated';
end
extremeFallbackReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26497 38480 24178 20928 22791 36873 23637 31034])];
extremeFallbackReportRel = ['../' extremeFallbackReportDirName '/index.html'];
extremeFallbackReportStatus = 'ready';
if exist(fullfile(dataRoot, extremeFallbackReportDirName, 'index.html'), 'file') ~= 2
    extremeFallbackReportStatus = 'not generated';
end
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Final Display Pick</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.meta,.note{line-height:1.7;color:#4b5563;} .note{background:white;border-left:4px solid #067a46;padding:10px 12px;margin:14px 0 20px;}');
fprintf(fid, '.pass{color:#067a46;font-weight:700;} table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;}');
fprintf(fid, 'th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.cleaner{background:#eaf7f2}.current{background:#f4f6f8}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;}');
fprintf(fid, 'img{max-width:100%%;height:auto;display:block;margin:auto;} a{color:#075da8;text-decoration:none;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230;&#26368;&#32456;&#25512;&#33616;&#23637;&#31034; / Final Display Pick</h1>\n');
fprintf(fid, '<div class="meta">Current-best entry: <a href="%s">current_best_index.html</a> (%s)<br>Current-best acceptance: <a href="%s">current_best_acceptance.html</a> (%s)<br>Current-best rules: <a href="%s">CableAccelCurrentBestDisplay_rules.xlsx</a><br>Auto-knee acceptance pass: <span class="pass">%d</span><br>Balanced acceptance pass: <span class="pass">%d</span><br>Final rules: <a href="CableAccelFinalDisplay_rules.xlsx">CableAccelFinalDisplay_rules.xlsx</a><br>Auto-knee candidate: <a href="%s">auto_knee_display_pick</a> (%s)<br>Auto-knee acceptance: <a href="%s">auto-knee acceptance</a> (%s)<br>Auto-knee acceptance JSON: <a href="%s">CableAccelAutoKnee_acceptance.json</a><br>Auto-knee manifest: <a href="%s">CableAccelAutoKnee_manifest.xlsx</a><br>Auto-knee report images: <a href="%s">auto-knee report-ready images</a> (%s)<br>Auto-knee report manifest: <a href="%s">CableAccelAutoKneeReport_manifest.xlsx</a><br>Report images: <a href="%s">balanced report-ready images</a> (%s)<br>Report image manifest: <a href="%s">CableAccelFinalDisplay_manifest.xlsx</a><br>Stricter visual candidate: <a href="%s">polished min90</a> (%s)<br>Stricter candidate manifest: <a href="%s">CableAccelPolishedMin90_manifest.xlsx</a><br>Keep-rate ladder: <a href="%s">95/93/92/90/88/85 candidate matrix</a> (%s)<br>Keep-rate ladder manifest: <a href="%s">CableAccelKeepLadder_manifest.xlsx</a><br>Tradeoff dashboard: <a href="%s">auto knee suggestions</a> (%s)<br>Tradeoff suggestions: <a href="%s">CableAccelTradeoffDashboard_suggestions.xlsx</a><br>Policy: <a href="balanced_display_pick/CableAccelBalancedDisplay_policy.json">CableAccelBalancedDisplay_policy.json</a><br>Acceptance: <a href="balanced_display_pick/acceptance.html">balanced acceptance</a><br>Full review pack: <a href="index.html">index.html</a></div>\n', ...
    htmlText(currentBestRel), htmlText(currentBestStatus), ...
    htmlText(currentBestAcceptanceRel), htmlText(currentBestAcceptanceStatus), ...
    htmlText(currentBestRulesRel), ...
    autoKneeAcceptance.pass, balancedAcceptance.pass, ...
    htmlText(autoKneeRel), htmlText(autoKneeStatus), ...
    htmlText(autoKneeAcceptanceRel), htmlText(autoKneeAcceptanceStatus), ...
    htmlText(autoKneeAcceptanceJsonRel), htmlText(autoKneeManifestRel), ...
    htmlText(autoKneeReportRel), htmlText(autoKneeReportStatus), ...
    htmlText(autoKneeReportManifestRel), ...
    htmlText(finalReportImageRel), htmlText(imageStatus), ...
    htmlText(finalReportManifestRel), htmlText(polishedRel), ...
    htmlText(polishedStatus), htmlText(polishedManifestRel), ...
    htmlText(keepLadderRel), htmlText(keepLadderStatus), ...
    htmlText(keepLadderManifestRel), htmlText(tradeoffRel), ...
    htmlText(tradeoffStatus), htmlText(tradeoffManifestRel));
fprintf(fid, '<div class="note">&#24403;&#21069;&#26368;&#20540;&#24471;&#20808;&#23457;&#30340;&#20505;&#36873;&#26159; <a href="%s">current-best auto-knee</a>&#65306;&#23427;&#22312; balanced final &#30340;&#22522;&#30784;&#19978;&#21482;&#26367;&#25442; CF-3/CF-4/CF-5&#65292;&#24182;&#24050;&#36890;&#36807;&#29420;&#31435;&#39564;&#25910;&#12290;&#27491;&#24335;&#39057;&#35889;/&#32034;&#21147;&#35745;&#31639;&#19981;&#21464;: <code>daily_median + [-100,100] m/s^2</code>. &#26412;&#39029;&#20165;&#20026;&#23637;&#31034;/&#23457;&#22270;&#36755;&#20986;&#12290;</div>\n', htmlText(currentBestRel));
fprintf(fid, '<div class="note">Satisfaction review: <a href="satisfaction_review/index.html">current-best / cleaner-priority / cleanest70 &#19977;&#26723;&#24182;&#25490;</a>&#12290;&#29992;&#20110;&#19968;&#27425;&#24615;&#21028;&#26029;&#21738;&#19968;&#26723;&#26368;&#25509;&#36817;&#28385;&#24847;&#12290;</div>\n');
fprintf(fid, '<div class="note">Satisfaction-auto &#25253;&#21578;&#21462;&#22270;: <a href="%s">satisfaction-auto report-ready images</a> (%s). &#36825;&#26159;&#25353;&#28385;&#24847;&#24230;&#22797;&#26680;&#33258;&#21160;&#24314;&#35758;&#27719;&#24635;&#30340;&#21333;&#19968;&#22270;&#21253;&#12290;</div>\n', ...
    htmlText(satisfactionAutoReportRel), htmlText(satisfactionAutoReportStatus));
fprintf(fid, '<div class="note">Low-keep tradeoff: <a href="low_keep_tradeoff_review/index.html">satisfaction-auto / cleanest60 / cleanest50 &#20302;&#20445;&#30041;&#29575;&#23545;&#29031;</a>&#12290;&#22914;&#26524;&#28385;&#24847;&#24230;&#33258;&#21160;&#29256;&#20173;&#28982;&#19981;&#22815;&#24178;&#20928;&#65292;&#20808;&#30475;&#36825;&#20010;&#39029;&#38754;&#12290;</div>\n');
fprintf(fid, '<div class="note">Low-keep auto &#25253;&#21578;&#21462;&#22270;: <a href="%s">low-keep auto report-ready images</a> (%s). &#36825;&#26159;&#25353; low-keep tradeoff &#33258;&#21160;&#24314;&#35758;&#27719;&#24635;&#30340;&#21333;&#19968;&#22270;&#21253;&#12290;</div>\n', ...
    htmlText(lowKeepAutoReportRel), htmlText(lowKeepAutoReportStatus));
fprintf(fid, '<div class="note">Extreme fallback &#25253;&#21578;&#21462;&#22270;: <a href="%s">extreme fallback report-ready images</a> (%s). &#20165;&#22312; low-keep review &#26631;&#35760; cleanest50 extreme &#30340;&#27979;&#28857;&#19978;&#20351;&#29992; cleanest50&#65292;&#20316;&#26368;&#20005;&#26684;&#22791;&#36873;&#12290;</div>\n', ...
    htmlText(extremeFallbackReportRel), htmlText(extremeFallbackReportStatus));
fprintf(fid, '<div class="note">&#26368;&#24555;&#30340;&#21462;&#33293;&#39029;: <a href="three_level_tradeoff_review/index.html">current-best / aggressive / target80 &#19977;&#26723;&#24182;&#25490;</a>&#12290;&#23427;&#20250;&#30452;&#25509;&#26174;&#31034;&#27599;&#20010;&#27979;&#28857;&#30340;&#19977;&#26723;&#22270;&#21644;&#25351;&#26631;&#65292;&#29992;&#20110;&#19968;&#27425;&#24615;&#21028;&#26029;&#26159;&#21542;&#35201;&#27604; current-best &#26356;&#20005;&#26684;&#12290;</div>\n');
fprintf(fid, '<div class="note">&#38454;&#26799;&#27719;&#24635;: <a href="retention_tradeoff_summary/index.html">retention tradeoff summary</a>&#12290;&#23427;&#23558; current-best/aggressive/target80/target75/visual-best &#25918;&#21040;&#19968;&#24352;&#34920;&#65292;&#29992;&#20110;&#21028;&#26029;&#20877;&#38477;&#20302;&#20445;&#30041;&#29575;&#26159;&#21542;&#20540;&#24471;&#12290;</div>\n');
fprintf(fid, '<div class="note">&#21333;&#19968;&#28151;&#21512;&#20505;&#36873;: <a href="visual_best_display_export/index.html">visual-best display export</a>&#12290;&#36825;&#26159;&#25353;&#19977;&#26723;&#21462;&#33293;&#35268;&#21017;&#33258;&#21160;&#36873;&#20986;&#30340;&#26356;&#24178;&#20928;&#22270;&#21253;&#65292;&#30446;&#21069;&#20316;&#20026;&#35270;&#35273;&#26368;&#20248;&#22791;&#36873;&#65292;&#19981;&#26367;&#20195; current-best &#40664;&#35748;&#20505;&#36873;&#12290;</div>\n');
fprintf(fid, '<div class="note">&#26356;&#24178;&#20928;&#20248;&#20808;&#22791;&#36873;: <a href="decisive_visual_display_export/index.html">decisive visual display export</a>&#12290;&#23427;&#23545; CF-1/CF-2/CF-5 &#20351;&#29992; target75&#65292;&#22270;&#38754;&#26356;&#24178;&#20928;&#20294;&#20445;&#30041;&#29575;&#26356;&#20302;&#65292;&#20165;&#20316;&#26368;&#20005;&#26684;&#23457;&#22270;&#22791;&#36873;&#12290;</div>\n');
fprintf(fid, '<div class="note">&#26356;&#24178;&#20928;&#20248;&#20808;&#25253;&#21578;&#21462;&#22270;: <a href="%s">cleaner-priority report-ready images</a> (%s). &#36825;&#26159;&#19978;&#36848;&#26368;&#20005;&#26684;&#22791;&#36873;&#30340;&#20013;&#24615;&#30446;&#24405;&#12290;</div>\n', ...
    htmlText(cleanerReportRel), htmlText(cleanerReportStatus));
fprintf(fid, '<div class="note">Cleanest70 &#33258;&#21160;&#26497;&#38480;&#22791;&#36873;: <a href="cleanest70_display_export/index.html">cleanest70 display export</a>&#12290;&#27599;&#20010;&#27979;&#28857;&#22312;&#20445;&#30041;&#29575; &gt;=70%% &#30340;&#20505;&#36873;&#20013;&#36873; RMS30 &#26368;&#23567;&#30340;&#19968;&#20010;&#65292;&#21482;&#20316;&#23457;&#22270;&#26497;&#38480;&#21442;&#32771;&#12290;</div>\n');
fprintf(fid, '<div class="note">Cleanest70 &#25253;&#21578;&#21462;&#22270;: <a href="%s">cleanest70 report-ready images</a> (%s). &#36825;&#26159;&#26368;&#24178;&#20928;&#33258;&#21160;&#22791;&#36873;&#30340;&#20013;&#24615;&#30446;&#24405;&#12290;</div>\n', ...
    htmlText(cleanest70ReportRel), htmlText(cleanest70ReportStatus));
fprintf(fid, '<div class="note">&#22914;&#26524; current-best &#22270;&#38754;&#20173;&#28982;&#19981;&#22815;&#24178;&#20928;&#65292;&#20808;&#30475; <a href="current_best_vs_aggressive_review/index.html">current-best vs aggressive</a>&#12290;aggressive &#26356;&#24178;&#20928;&#65292;&#20294;&#22810;&#25968;&#27979;&#28857;&#20445;&#30041;&#29575;&#38477;&#21040;&#32422;85%%-87%%&#12290;<a href="target80_display_export/index.html">target80</a> &#26159;&#26356;&#28608;&#36827;&#30340;80%%&#20445;&#30041;&#29575;&#22791;&#36873;&#65292;&#19981;&#20316;&#40664;&#35748;&#25512;&#33616;&#12290;</div>\n');
fprintf(fid, '<div class="note">auto-knee &#26159;&#24403;&#21069;&#26368;&#20540;&#24471;&#23457;&#30340;&#33258;&#21160;&#25348;&#28857;&#20505;&#36873;&#65306;&#21482;&#25910;&#32039; CF-3/CF-4/CF-5&#65292;&#20854;&#20313;&#27979;&#28857;&#20445;&#25345; balanced final&#65292;&#36991;&#20813;&#20840;&#20307;&#36807;&#24230;&#21024;&#38500;&#12290;</div>\n');
fprintf(fid, '<div class="note">Balanced vs Auto-knee &#24182;&#25490;&#23545;&#29031;: <a href="%s">balanced_vs_auto_knee_review</a> (%s). &#24038;&#20391;&#26159; balanced final&#65292;&#21491;&#20391;&#26159; auto-knee&#65292;&#29992;&#20110;&#30452;&#35266;&#21028;&#26029;&#33258;&#21160;&#25348;&#28857;&#26159;&#21542;&#26356;&#21512;&#36866;&#12290; Manifest: <a href="%s">CableAccelBalancedVsAutoKnee_manifest.xlsx</a></div>\n', ...
    htmlText(balancedVsAutoKneeRel), htmlText(balancedVsAutoKneeStatus), htmlText(balancedVsAutoKneeManifestRel));
fprintf(fid, '<div class="note">polished min90 &#26159;&#26356;&#20005;&#26684;&#30340;&#35270;&#35273;&#22791;&#36873;&#29256;&#65306;&#20445;&#30041;&#29575;&#30446;&#26631; &gt;= 90%%&#65292;&#29992;&#20110;&#24403;&#26412;&#39029;&#25512;&#33616;&#29256;&#20173;&#28982;&#35273;&#24471;&#19981;&#22815;&#24178;&#20928;&#26102;&#22797;&#26680;&#12290;&#23427;&#19981;&#20250;&#35206;&#30422;&#24403;&#21069;&#26368;&#32456;&#25512;&#33616;&#12290;</div>\n');
fprintf(fid, '<div class="note">keep-rate ladder &#25552;&#20379; 95/93/92/90/88/85%% &#20445;&#30041;&#29575;&#26723;&#20301;&#30697;&#38453;&#65292;&#29992;&#20110;&#30452;&#25509;&#27604;&#36739;&#26356;&#24178;&#20928;&#19982;&#25968;&#25454;&#25439;&#22833;&#30340;&#21462;&#33293;&#12290;</div>\n');
fprintf(fid, '<div class="note">tradeoff dashboard &#25226;&#21508;&#26723;&#20301;&#30340;&#20445;&#30041;&#29575;&#21644; RMS30 &#26368;&#22823;&#20540;&#30011;&#25104;&#21462;&#33293;&#26354;&#32447;&#65292;&#24182;&#32473;&#20986;&#19981;&#27604;&#24403;&#21069;&#26368;&#32456;&#29256;&#26356;&#24046;&#30340;&#33258;&#21160;&#25348;&#28857;&#24314;&#35758;&#12290;</div>\n');

fprintf(fid, '<h2>Current-Best Strategy / &#24403;&#21069;&#26368;&#20339;&#31574;&#30053;</h2>\n<table>\n');
fprintf(fid, '<tr><th>Point</th><th>Selected</th><th>|x| threshold</th><th>RMS30 top %%</th><th>Keep %%</th><th>RMS30 max</th><th>Pass</th><th>Rationale</th></tr>\n');
for i = 1:height(rules)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%d</td><td>%s</td></tr>\n', ...
        htmlText(rules.SelectedSource{i}), htmlText(rules.PointID{i}), ...
        htmlText(rules.SelectedSource{i}), rules.ThresholdAbsMps2(i), ...
        rules.SegmentFilterTopPctRMS30(i), rules.KeepPct(i), rules.RMS30Max(i), ...
        rules.AcceptancePass(i), htmlText(rules.Rationale{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>&#32039;&#20945;&#22797;&#26680;&#22270; / Contact Sheet</h2>\n');
fprintf(fid, '<div class="figure"><img src="balanced_display_pick/CableAccelBalancedDisplay_ContactSheet.jpg" alt="balanced contact sheet"></div>\n');
fprintf(fid, '<h2>&#39564;&#25910;&#39029;&#25130;&#22270; / Acceptance Snapshot</h2>\n');
fprintf(fid, '<div class="figure"><img src="balanced_display_pick/acceptance_render.png" alt="balanced acceptance snapshot"></div>\n');
fprintf(fid, '</body>\n</html>\n');
end

function writeFinalReadme(path, rules, balancedAcceptance, autoKneeAcceptance, finalReportImageRel, finalReportManifestRel, finalReportImagesExist, polishedRel, polishedManifestRel, polishedExists, keepLadderRel, keepLadderManifestRel, keepLadderExists, tradeoffRel, tradeoffManifestRel, tradeoffExists, autoKneeRel, autoKneeManifestRel, autoKneeExists, autoKneeReportRel, autoKneeReportManifestRel, autoKneeReportExists, balancedVsAutoKneeRel, balancedVsAutoKneeManifestRel, balancedVsAutoKneeExists, autoKneeAcceptanceRel, autoKneeAcceptanceJsonRel, autoKneeAcceptanceExists, currentBestRel, currentBestRulesRel, currentBestExists, currentBestAcceptanceRel, currentBestAcceptanceExists)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Final Display Pick\n\n');
fprintf(fid, '- Final entry: `final_index.html`\n');
fprintf(fid, '- Current-best entry: `%s` (exists: `%d`)\n', currentBestRel, currentBestExists);
fprintf(fid, '- Current-best acceptance: `%s` (exists: `%d`)\n', currentBestAcceptanceRel, currentBestAcceptanceExists);
fprintf(fid, '- Current-best rules: `%s`\n', currentBestRulesRel);
fprintf(fid, '- Satisfaction review: `satisfaction_review/index.html`\n');
satisfactionAutoReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([28385 24847 24230 33258 21160 25512 33616 23637 31034])];
fprintf(fid, '- Satisfaction-auto report images: `../%s/index.html`\n', satisfactionAutoReportDirName);
fprintf(fid, '- Low-keep tradeoff review: `low_keep_tradeoff_review/index.html`\n');
lowKeepAutoReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([20302 20445 30041 29575 33258 21160 25512 33616 23637 31034])];
fprintf(fid, '- Low-keep auto report images: `../%s/index.html`\n', lowKeepAutoReportDirName);
extremeFallbackReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26497 38480 24178 20928 22791 36873 23637 31034])];
fprintf(fid, '- Extreme fallback report images: `../%s/index.html`\n', extremeFallbackReportDirName);
fprintf(fid, '- Auto-knee acceptance pass: `%d`\n', autoKneeAcceptance.pass);
fprintf(fid, '- Balanced acceptance pass: `%d`\n', balancedAcceptance.pass);
fprintf(fid, '- Final rules: `CableAccelFinalDisplay_rules.xlsx`\n');
fprintf(fid, '- Auto-knee candidate: `%s` (exists: `%d`)\n', autoKneeRel, autoKneeExists);
fprintf(fid, '- Auto-knee acceptance: `%s` (exists: `%d`)\n', autoKneeAcceptanceRel, autoKneeAcceptanceExists);
fprintf(fid, '- Auto-knee acceptance JSON: `%s`\n', autoKneeAcceptanceJsonRel);
fprintf(fid, '- Auto-knee manifest: `%s`\n', autoKneeManifestRel);
fprintf(fid, '- Auto-knee report images: `%s` (exists: `%d`)\n', autoKneeReportRel, autoKneeReportExists);
fprintf(fid, '- Auto-knee report image manifest: `%s`\n', autoKneeReportManifestRel);
fprintf(fid, '- Balanced vs auto-knee review: `%s` (exists: `%d`)\n', balancedVsAutoKneeRel, balancedVsAutoKneeExists);
fprintf(fid, '- Balanced vs auto-knee manifest: `%s`\n', balancedVsAutoKneeManifestRel);
fprintf(fid, '- Final report images: `%s` (exists: `%d`)\n', finalReportImageRel, finalReportImagesExist);
fprintf(fid, '- Final report image manifest: `%s`\n', finalReportManifestRel);
cleanerReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26356 24178 20928 20248 20808 23637 31034])];
fprintf(fid, '- Cleaner-priority report images: `../%s/index.html`\n', cleanerReportDirName);
fprintf(fid, '- Cleanest70 auto pick: `cleanest70_display_export/index.html`\n');
cleanest70ReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26368 24178 20928 33258 21160 23637 31034])];
fprintf(fid, '- Cleanest70 report images: `../%s/index.html`\n', cleanest70ReportDirName);
fprintf(fid, '- Stricter visual candidate: `%s` (exists: `%d`)\n', polishedRel, polishedExists);
fprintf(fid, '- Stricter visual candidate manifest: `%s`\n', polishedManifestRel);
fprintf(fid, '- Keep-rate ladder: `%s` (exists: `%d`)\n', keepLadderRel, keepLadderExists);
fprintf(fid, '- Keep-rate ladder manifest: `%s`\n', keepLadderManifestRel);
fprintf(fid, '- Tradeoff dashboard: `%s` (exists: `%d`)\n', tradeoffRel, tradeoffExists);
fprintf(fid, '- Tradeoff suggestions: `%s`\n', tradeoffManifestRel);
fprintf(fid, '- Balanced policy: `balanced_display_pick/CableAccelBalancedDisplay_policy.json`\n');
fprintf(fid, '- Balanced acceptance: `balanced_display_pick/acceptance.html`\n');
fprintf(fid, '- Full review pack: `index.html`\n\n');
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`. This final pick is display-only.\n\n');
fprintf(fid, '| Point | Selected | |x| threshold | RMS30 top %% | Keep %% | RMS30 max | Pass | Rationale |\n');
fprintf(fid, '|---|---|---:|---:|---:|---:|---:|---|\n');
for i = 1:height(rules)
    fprintf(fid, '| %s | %s | %.3f | %.1f | %.3f | %.3f | %d | %s |\n', ...
        rules.PointID{i}, rules.SelectedSource{i}, rules.ThresholdAbsMps2(i), ...
        rules.SegmentFilterTopPctRMS30(i), rules.KeepPct(i), rules.RMS30Max(i), ...
        rules.AcceptancePass(i), rules.Rationale{i});
end
end

function writeFinalSummary(path, rules, balancedAcceptance, autoKneeAcceptance, finalReportImageRel, finalReportManifestRel, finalReportImagesExist, polishedRel, polishedManifestRel, polishedExists, keepLadderRel, keepLadderManifestRel, keepLadderExists, tradeoffRel, tradeoffManifestRel, tradeoffExists, autoKneeRel, autoKneeManifestRel, autoKneeExists, autoKneeReportRel, autoKneeReportManifestRel, autoKneeReportExists, balancedVsAutoKneeRel, balancedVsAutoKneeManifestRel, balancedVsAutoKneeExists, autoKneeAcceptanceRel, autoKneeAcceptanceJsonRel, autoKneeAcceptanceExists, currentBestRel, currentBestRulesRel, currentBestExists, currentBestAcceptanceRel, currentBestAcceptanceExists)
summary = struct();
summary.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
summary.scope = 'display_only';
summary.formal_policy = 'Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.';
summary.acceptance_pass = autoKneeAcceptance.pass;
summary.auto_knee_acceptance_pass = autoKneeAcceptance.pass;
summary.balanced_acceptance_pass = balancedAcceptance.pass;
summary.final_index = 'final_index.html';
summary.current_best_entry = currentBestRel;
summary.current_best_acceptance = currentBestAcceptanceRel;
summary.current_best_acceptance_exists = currentBestAcceptanceExists;
summary.current_best_rules = currentBestRulesRel;
summary.current_best_exists = currentBestExists;
summary.satisfaction_review = 'satisfaction_review/index.html';
satisfactionAutoReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([28385 24847 24230 33258 21160 25512 33616 23637 31034])];
summary.satisfaction_auto_report_images = ['../' satisfactionAutoReportDirName '/index.html'];
summary.low_keep_tradeoff_review = 'low_keep_tradeoff_review/index.html';
lowKeepAutoReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([20302 20445 30041 29575 33258 21160 25512 33616 23637 31034])];
summary.low_keep_auto_report_images = ['../' lowKeepAutoReportDirName '/index.html'];
extremeFallbackReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26497 38480 24178 20928 22791 36873 23637 31034])];
summary.extreme_fallback_report_images = ['../' extremeFallbackReportDirName '/index.html'];
summary.final_rules = 'CableAccelFinalDisplay_rules.xlsx';
summary.final_rules_csv = 'CableAccelFinalDisplay_rules.csv';
summary.final_report_images = finalReportImageRel;
summary.final_report_image_manifest = finalReportManifestRel;
summary.final_report_images_exist = finalReportImagesExist;
cleanerReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26356 24178 20928 20248 20808 23637 31034])];
summary.cleaner_priority_report_images = ['../' cleanerReportDirName '/index.html'];
summary.cleanest70_display_export = 'cleanest70_display_export/index.html';
cleanest70ReportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26368 24178 20928 33258 21160 23637 31034])];
summary.cleanest70_report_images = ['../' cleanest70ReportDirName '/index.html'];
summary.polished_min90_candidate = polishedRel;
summary.polished_min90_manifest = polishedManifestRel;
summary.polished_min90_exists = polishedExists;
summary.keep_ladder_review = keepLadderRel;
summary.keep_ladder_manifest = keepLadderManifestRel;
summary.keep_ladder_exists = keepLadderExists;
summary.tradeoff_dashboard = tradeoffRel;
summary.tradeoff_suggestions = tradeoffManifestRel;
summary.tradeoff_exists = tradeoffExists;
summary.auto_knee_candidate = autoKneeRel;
summary.auto_knee_manifest = autoKneeManifestRel;
summary.auto_knee_exists = autoKneeExists;
summary.auto_knee_acceptance = autoKneeAcceptanceRel;
summary.auto_knee_acceptance_json = autoKneeAcceptanceJsonRel;
summary.auto_knee_acceptance_exists = autoKneeAcceptanceExists;
summary.auto_knee_report_images = autoKneeReportRel;
summary.auto_knee_report_manifest = autoKneeReportManifestRel;
summary.auto_knee_report_exists = autoKneeReportExists;
summary.balanced_vs_auto_knee_review = balancedVsAutoKneeRel;
summary.balanced_vs_auto_knee_manifest = balancedVsAutoKneeManifestRel;
summary.balanced_vs_auto_knee_exists = balancedVsAutoKneeExists;
summary.full_review_pack = 'index.html';
summary.balanced_policy = 'balanced_display_pick/CableAccelBalancedDisplay_policy.json';
summary.balanced_acceptance = 'balanced_display_pick/acceptance.html';
summary.points = struct();
for i = 1:height(rules)
    pointId = rules.PointID{i};
    field = matlab.lang.makeValidName(strrep(pointId, '-', '_'));
    summary.points.(field) = struct( ...
        'point_id', pointId, ...
        'selected_source', rules.SelectedSource{i}, ...
        'threshold_abs_mps2', rules.ThresholdAbsMps2(i), ...
        'segment_filter_top_pct_rms30', rules.SegmentFilterTopPctRMS30(i), ...
        'keep_pct', rules.KeepPct(i), ...
        'rms30_max', rules.RMS30Max(i), ...
        'acceptance_pass', rules.AcceptancePass(i), ...
        'rationale', rules.Rationale{i});
end
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(summary));
end

function out = htmlText(value)
out = char(string(value));
out = strrep(out, '&', '&amp;');
out = strrep(out, '<', '&lt;');
out = strrep(out, '>', '&gt;');
out = strrep(out, '"', '&quot;');
end
