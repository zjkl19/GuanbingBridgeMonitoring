function outPath = rebuild_zhishan_cable_accel_envelope_sheet(dataRoot, cfg)
%REBUILD_ZHISHAN_CABLE_ACCEL_ENVELOPE_SHEET Build a contact sheet from formal envelope plots.

if nargin < 1 || isempty(dataRoot)
    dataRoot = ['D:' filesep '芝山大桥数据' filesep '2026年1-3月'];
end
if nargin < 2 || isempty(cfg)
    projectRoot = fileparts(fileparts(mfilename('fullpath')));
    cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));
end

srcDir = fullfile(dataRoot, '时程曲线_索力加速度_包络30min');
outDir = fullfile(dataRoot, '时程曲线_索力加速度_包络30min_组图');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

points = {'CF-1','CF-2','CF-3','CF-4','CF-5','CF-6','CF-7','CF-8'};
paths = cell(size(points));
for i = 1:numel(points)
    paths{i} = latestEnvelopePath(srcDir, points{i});
    if isempty(paths{i})
        warning('Missing cable acceleration envelope figure for %s in %s', points{i}, srcDir);
    end
end

fig = figure('Visible', 'off', 'Position', [100 100 1400 1600]);
tl = tiledlayout(fig, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, '索力加速度30 min包络总览');
for i = 1:numel(points)
    ax = nexttile(tl);
    if ~isempty(paths{i}) && isfile(paths{i})
        img = imread(paths{i});
        image(ax, img);
        axis(ax, 'image');
        axis(ax, 'off');
    else
        text(ax, 0.5, 0.5, [points{i} ' image missing'], ...
            'HorizontalAlignment', 'center', 'Interpreter', 'none');
        axis(ax, 'off');
    end
    title(ax, points{i}, 'Interpreter', 'none');
end

baseName = 'CableAccelEnvelope30_CF-1-CF-8_20260301_20260331';
outPath = fullfile(outDir, [baseName '.jpg']);
bms.plot.PlotService.saveModuleBundle(fig, outDir, baseName, cfg, ...
    struct('save_fig', false, 'save_emf', false));
end

function path = latestEnvelopePath(srcDir, pointId)
path = '';
files = dir(fullfile(srcDir, sprintf('CableAccelEnvelope30_%s_*.jpg', pointId)));
if isempty(files)
    return;
end
[~, idx] = max([files.datenum]);
path = fullfile(files(idx).folder, files(idx).name);
end
