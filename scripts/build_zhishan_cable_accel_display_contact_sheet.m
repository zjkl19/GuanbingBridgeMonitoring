function result = build_zhishan_cable_accel_display_contact_sheet()
%BUILD_ZHISHAN_CABLE_ACCEL_DISPLAY_CONTACT_SHEET Compact visual review board.
%   Uses existing report-ready per-point figures and creates a compact 2x4
%   contact sheet for quick manual review. No data cleaning is recomputed.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
reportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' char([25512 33616 23637 31034])];
outputDir = fullfile(dataRoot, reportDirName);
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);

fig = figure('Visible', 'off', 'Position', [100 100 2600 1250], 'Color', 'w');
tiledlayout(fig, 2, 4, 'Padding', 'compact', 'TileSpacing', 'compact');

missing = {};
for i = 1:numel(points)
    pointId = points{i};
    imagePath = fullfile(outputDir, sprintf( ...
        'CableAccelRecommendationDisplay_%s_20260301_20260331.jpg', pointId));
    ax = nexttile;
    if isfile(imagePath)
        image(ax, imread(imagePath));
        axis(ax, 'image');
        axis(ax, 'off');
        title(ax, pointId, 'Interpreter', 'none', 'FontWeight', 'bold');
    else
        missing{end+1} = pointId; %#ok<AGROW>
        axis(ax, 'off');
        text(ax, 0.5, 0.5, sprintf('%s missing', pointId), ...
            'HorizontalAlignment', 'center', 'Interpreter', 'none');
    end
end

contactSheetPath = fullfile(outputDir, 'CableAccelRecommendationDisplay_ContactSheet.jpg');
exportgraphics(fig, contactSheetPath, 'Resolution', 150);
close(fig);

result = struct();
result.contact_sheet = contactSheetPath;
result.missing_points = missing;
result.pass = isempty(missing);

fprintf('contact sheet %s\n', contactSheetPath);
fprintf('pass %d\n', result.pass);
if ~isempty(missing)
    fprintf('missing %s\n', strjoin(missing, ', '));
end
end
