
% 设置输出目录
output_dir = '时程曲线结果';
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

% 调用绘制温度时程曲线的函数
plot_temperature_timeseries();

