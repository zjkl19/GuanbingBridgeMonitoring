% 示例数据
data = randn(100, 4); % 生成 4 组随机数据
labels = {'第一组', '第二组', '第三组', '第四组'}; % 自定义标签

% 绘制箱线图，使用 LabelOrientation 参数
figure;
boxplot(data, 'Labels', labels, 'LabelOrientation', 'inline'); % 设置标签为倾斜
title('Boxplot 示例：使用 LabelOrientation 设置标签方向');
xlabel('组别');
ylabel('值');
