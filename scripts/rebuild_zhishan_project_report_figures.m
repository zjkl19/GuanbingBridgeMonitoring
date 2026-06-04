function summary = rebuild_zhishan_project_report_figures(summaryFile)
%REBUILD_ZHISHAN_PROJECT_REPORT_FIGURES Re-run Zhishan report figure modules.
%   This is a thin project entry point for report regeneration. It calls the
%   normal run_all pipeline, then builds only a contact sheet from the formal
%   cable-acceleration envelope figures produced by that pipeline.

if nargin < 1
    summaryFile = '';
end

scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(scriptDir);
addpath(projectRoot);
addpath(fullfile(projectRoot, 'pipeline'));
addpath(fullfile(projectRoot, 'config'));
addpath(fullfile(projectRoot, 'analysis'));
addpath(fullfile(projectRoot, 'scripts'));

dataRoot = ['D:' filesep '芝山大桥数据' filesep '2026年3月'];
cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));

opts = struct( ...
    'doStrain', true, ...
    'doBearingDisplacement', true, ...
    'doAccel', true, ...
    'doCableAccel', true, ...
    'doAccelSpectrum', true, ...
    'doCableAccelSpectrum', true);

summary = run_all(dataRoot, '2026-03-01', '2026-03-31', opts, cfg);
rebuild_zhishan_cable_accel_envelope_sheet(dataRoot, cfg);

if ~isempty(summaryFile)
    save(summaryFile, 'summary');
end
end
