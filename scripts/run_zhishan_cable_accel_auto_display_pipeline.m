function result = run_zhishan_cable_accel_auto_display_pipeline(mode)
%RUN_ZHISHAN_CABLE_ACCEL_AUTO_DISPLAY_PIPELINE One-command display pipeline.
%   RUN_ZHISHAN_CABLE_ACCEL_AUTO_DISPLAY_PIPELINE() refreshes the review,
%   final/default entry, and validation from existing auto-visual search
%   artifacts. Use mode='full' to rerun the dense search first.
%
%   Display/report-review only. Formal cable acceleration spectrum/force
%   calculation remains daily_median + [-100,100] m/s^2.

if nargin < 1 || isempty(mode)
    mode = 'reuse';
end
mode = validatestring(mode, {'reuse','full'});

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
autoVisualDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([33258 21160 35270 35273 25512 33616 23637 31034])]);
autoManifest = fullfile(autoVisualDir, 'CableAccelAutoVisualReport_manifest.csv');
scoreMatrix = fullfile(stableDir, 'auto_visual_search', ...
    'CableAccelAutoVisualSearch_score_matrix.csv');

result = struct();
result.mode = mode;
result.started_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
result.formal_policy = 'daily_median + [-100,100] m/s^2';

if strcmp(mode, 'full') || ~isfile(autoManifest) || ~isfile(scoreMatrix)
    fprintf('step 1/7 rerun dense auto-visual search\n');
    result.auto_visual_search = optimize_zhishan_cable_accel_auto_visual_search();
else
    fprintf('step 1/7 reuse dense auto-visual search artifacts\n');
    result.auto_visual_search = struct( ...
        'report_html', fullfile(autoVisualDir, 'index.html'), ...
        'manifest_csv', autoManifest, ...
        'score_matrix_csv', scoreMatrix);
end

fprintf('step 2/7 refresh auto-visual comparison review\n');
result.auto_visual_review = compare_zhishan_cable_accel_auto_visual_review();

fprintf('step 3/7 refresh below-50 ultra-clean backup review\n');
result.ultra_clean_review = build_zhishan_cable_accel_ultra_clean_review();

fprintf('step 4/7 build strict report candidate\n');
result.strict_report_candidate = build_zhishan_cable_accel_strict_report_candidate();

fprintf('step 5/7 export report-ready strict images and publish final entries\n');
result.final_pack = publish_zhishan_cable_accel_strict_final_pack();

fprintf('step 6/7 refresh stable review pack\n');
result.review_pack = publish_zhishan_cable_accel_display_review_pack();

fprintf('step 7/7 validate all display alternatives and final entry\n');
result.validation = validate_zhishan_cable_accel_visual_alternatives();

result.completed_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
result.pass = result.final_pack.acceptance_pass && ...
    result.review_pack.acceptance_pass && result.validation.pass;
result.final_index = result.final_pack.final_index;
result.current_best_index = result.final_pack.current_index;
result.report_images = result.final_pack.report_images;
result.validation_html = result.validation.html;

writePipelineSummary(result, stableDir);

fprintf('auto display pipeline pass %d\n', result.pass);
fprintf('final index %s\n', result.final_index);
fprintf('report images %s\n', result.report_images);
fprintf('validation %s\n', result.validation_html);

if ~result.pass
    error('Zhishan cable acceleration auto display pipeline failed validation.');
end
end

function writePipelineSummary(result, stableDir)
summaryPath = fullfile(stableDir, 'CableAccelAutoDisplayPipeline_summary.json');
readmePath = fullfile(stableDir, 'AUTO_DISPLAY_PIPELINE_README.md');

payload = struct();
payload.mode = result.mode;
payload.started_at = result.started_at;
payload.completed_at = result.completed_at;
payload.pass = result.pass;
payload.formal_policy = result.formal_policy;
payload.final_index = result.final_index;
payload.current_best_index = result.current_best_index;
payload.report_images = result.report_images;
payload.validation_html = result.validation_html;
payload.auto_visual_review = result.auto_visual_review.html;
payload.ultra_clean_review = result.ultra_clean_review.html;
payload.strict_report_candidate = result.strict_report_candidate.html;

fid = fopen(summaryPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(payload, 'PrettyPrint', true));
clear cleaner fid;

fid = fopen(readmePath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Auto Display Pipeline\n\n');
fprintf(fid, '- Pass: `%d`\n', result.pass);
fprintf(fid, '- Mode: `%s`\n', result.mode);
fprintf(fid, '- Formal policy remains: `%s`\n', result.formal_policy);
fprintf(fid, '- Final/default entry: `%s`\n', result.final_index);
fprintf(fid, '- Report images: `%s`\n', result.report_images);
fprintf(fid, '- Validation: `%s`\n', result.validation_html);
fprintf(fid, '- Auto visual review: `%s`\n', result.auto_visual_review.html);
fprintf(fid, '- Below-50 backup review: `%s`\n\n', result.ultra_clean_review.html);
fprintf(fid, '- Strict report candidate: `%s`\n\n', result.strict_report_candidate.html);
fprintf(fid, 'Run from MATLAB:\n\n');
fprintf(fid, '```matlab\n');
fprintf(fid, 'cd(''D:\\MatlabProjects\\Guanbing'');\n');
fprintf(fid, 'addpath(genpath(pwd));\n');
fprintf(fid, 'run_zhishan_cable_accel_auto_display_pipeline(''reuse''); %% fast refresh\n');
fprintf(fid, 'run_zhishan_cable_accel_auto_display_pipeline(''full'');  %% rerun dense search\n');
fprintf(fid, '```\n');
end
