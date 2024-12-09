ax = gca; % 获取当前坐标轴

% 清除默认的标签
ax.XTickLabel = {};

% 添加旋转的标签
for i = 1:length(labels)
    text(xt(i), yt - 0.1 * range(ax.YLim), labels{i}, ...
        'HorizontalAlignment', 'right', ... % 右对齐
        'VerticalAlignment', 'top', ...     % 顶部对齐
        'Rotation', 45, ...                 % 旋转角度 45°
        'FontSize', 10);                    % 字体大小
end