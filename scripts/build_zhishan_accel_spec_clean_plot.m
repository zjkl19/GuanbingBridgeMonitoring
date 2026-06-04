function build_zhishan_accel_spec_clean_plot()
% Build a report-ready acceleration spectrum peak-frequency figure.
% This does not change the formal statistics workbook.

dataRoot = 'D:\芝山大桥数据\2026年3月';
statsFile = fullfile(dataRoot, 'stats', 'accel_spec_stats.xlsx');
outDir = fullfile(dataRoot, 'report_assets_v3', 'accel_spec');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

set(0, 'DefaultAxesFontName', 'Microsoft YaHei');
set(0, 'DefaultTextFontName', 'Microsoft YaHei');

points = {'AZ-1', 'AZ-2', 'AZ-3', 'AZ-4', 'AZ-5'};
targetFreq = [0.610, 0.623, 0.620, 0.620, 0.640];
theoryFreq = 0.385;

fig = figure('Visible', 'off', 'Position', [80, 80, 1500, 760], 'Color', 'w');
ax = axes(fig);
hold(ax, 'on');

for i = 1:numel(points)
    T = readtable(statsFile, 'Sheet', points{i}, 'VariableNamingRule', 'preserve');
    dates = T{:, 1};
    if ~isdatetime(dates)
        dates = datetime(dates);
    end
    freq = T{:, 2};
    plot(ax, dates, freq, '-o', 'LineWidth', 1.0, 'MarkerSize', 3.5, ...
        'DisplayName', sprintf('%s 峰值频率(%.3fHz附近)', points{i}, targetFreq(i)));
end

yline(ax, theoryFreq, '--', sprintf('理论竖向一阶频率 %.3fHz', theoryFreq), ...
    'Color', [0.15 0.15 0.15], 'LineWidth', 1.1, 'LabelHorizontalAlignment', 'left', ...
    'HandleVisibility', 'off');

grid(ax, 'on');
xlim(ax, [datetime(2026, 3, 1), datetime(2026, 3, 31, 23, 59, 59)]);
ylim(ax, [0.30, 0.72]);
xtickformat(ax, 'MM-dd');
xlabel(ax, '日期');
ylabel(ax, '峰值频率 (Hz)');
title(ax, '主梁结构加速度峰值频率时程');
legend(ax, 'Location', 'southoutside', 'NumColumns', 2);

exportgraphics(fig, fullfile(outDir, 'SpecFreq_AZ_ReportClean_20260301_20260331.jpg'), 'Resolution', 220);
close(fig);

fprintf('Wrote %s\n', fullfile(outDir, 'SpecFreq_AZ_ReportClean_20260301_20260331.jpg'));
end
