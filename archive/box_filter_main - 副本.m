% 动应变高通滤波与箱线图分析主程序

whisker_value=300;  %该值越大，包进去的离群值越多
% 设置文件目录和文件名模式
data_dir = '动应变'; % 数据文件所在目录
file_pattern = fullfile(data_dir, '*.csv'); % CSV文件的模式
files = dir(file_pattern); % 获取目录中所有CSV文件信息
% 选择处理文件的范围
selected_files = 1:length(files); % 默认处理所有文件，可手动指定索引，如：[1, 3, 5]

% 手动指定处理文件名（如果需要）
selected_filenames = {'GB-RSG-G05-00101.csv', 'GB-RSG-G05-00102.csv'}; % 指定文件名列表，若为空则处理 selected_files

% 查找指定文件名在文件列表中的索引（若提供了文件名列表）
if ~isempty(selected_filenames)
    selected_files = find(ismember({files.name}, selected_filenames));
end

% 计算总数据量（用于估算时间）
total_file_size = sum([files(selected_files).bytes]) / 1e6; % 总文件大小（MB）
estimated_time = round(total_file_size * 0.1, 1); % 针对选择的文件计算处理时间 % 粗略估计每MB需要0.1秒的处理时间，保留到1位小数，具体值可根据性能调整

% 估算高通滤波的额外耗时
filter_time_per_mb = 0.2; % 假设每MB数据需要额外0.2秒进行滤波
estimated_filter_time = total_file_size * filter_time_per_mb; % 针对选择的文件计算滤波时间
estimated_total_time = estimated_time + estimated_filter_time; % 总预计处理时间

% 显示选中的文件名
disp('选中的文件名：');
for i = selected_files
    disp(files(i).name);
end % 总预计处理时间

% 给出预计处理时间并警告如果超过3分钟
if estimated_total_time > 180
    disp(['预计处理时间为 ', num2str(estimated_total_time / 60, '%.1f'), ' 分钟，超过3分钟。']);
    user_response = input('是否继续？(y/n): ', 's');
    if lower(user_response) ~= 'y'
        disp('操作已取消。');
        return;
    end
else
    disp(['预计处理时间为 ', num2str(estimated_total_time / 60, '%.1f'), ' 分钟，开始运行。']);
end

start_time = tic;

% 初始化数据存储
all_data = []; % 存放所有测点的应变数据
labels = {};   % 存放对应的测点标签

% 选择移除离群值的方法
method_choice = 2; % 手动指定上下限

% 高通滤波参数
fs = 100; % 采样频率 (假设为100 Hz)
fc = 0.1; % 截止频率 (0.1 Hz)
[b, a] = butter(1, fc / (fs / 2), 'high'); % 设计一阶高通滤波器

% 遍历每个文件，读取数据

for i = selected_files
    file_path = fullfile(files(i).folder, files(i).name);
    % 读取CSV文件
    try
        % 使用textscan逐行读取数据
        fid = fopen(file_path);
        % 跳过前5行的非数据部分
        for k = 1:5
            fgetl(fid);
        end
        % 读取数据部分
        data = textscan(fid, '%s %f', 'Delimiter', ',', 'HeaderLines', 1);
        fclose(fid);
        
        % 获取应变值列
        strain_data = data{2};
        
        % 移除离群值
        if method_choice == 1
            % 自动检测离群值
            Q1 = quantile(strain_data, 0.25);
            Q3 = quantile(strain_data, 0.75);
            IQR = Q3 - Q1;
            lower_bound = Q1 - 1.5 * IQR;
            upper_bound = Q3 + 1.5 * IQR;
        elseif method_choice == 2
            % 手动指定上下限
            lower_bound = -150; % 手动指定下限值
            upper_bound = 150; % 手动指定上限值
        else
            disp('无效的选择，跳过该文件。');
            continue;
        end

        % 将超出合理范围的数据改为NaN
        strain_data(strain_data < lower_bound | strain_data > upper_bound) = NaN;
        
        % 高通滤波处理，将NaN替换为零以进行滤波（滤波后再替换为NaN）
        strain_data_no_nan = strain_data;
        strain_data_no_nan(isnan(strain_data_no_nan)) = 0;
        filtered_data = filtfilt(b, a, strain_data_no_nan);
        filtered_data(isnan(strain_data)) = NaN; % 恢复原始NaN位置
        
        all_data = [all_data, filtered_data]; % 合并所有文件的应变数据
        labels{end+1} = files(i).name; % 使用文件名作为标签
    catch ME
        disp(['Error reading file: ', file_path, '. Skipping.']);
        disp(ME.message);
    end
end

elapsed_time = toc(start_time);
disp(['实际处理时间为 ', num2str(elapsed_time, '%.2f'), ' 秒。']);

% 绘制箱线图
figure;
show_outliers = false; % 设置是否显示离群值
x_label_rotation = 45; % 设置x轴标签旋转角度（度）

if ~show_outliers
    boxplot(all_data, 'Labels', labels, 'LabelOrientation', 'inline', 'Symbol', '', 'Whisker', whisker_value);
else
    boxplot(all_data, 'Labels', labels, 'LabelOrientation', 'inline', 'Whisker', whisker_value);
end
% 设置Y轴范围，手动指定或自动设置
ylim_manual = true; % 设置是否手动指定Y轴范围
if ylim_manual
    ylim([-30, 30]); % 手动指定Y轴范围
else
    ylim auto; % 自动设置Y轴范围
end


set(gca, 'XTickLabelRotation', x_label_rotation);
title('测点应变数据箱线图比较（高通滤波后）');
xlabel('测点');
ylabel('应变（με）');

% 保存图像
output_dir = '箱线图结果_高通滤波';
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

saveas(gcf, fullfile(output_dir, 'boxplot_filtered_comparison.jpg'));
saveas(gcf, fullfile(output_dir, 'boxplot_filtered_comparison.emf'));
%savefig(gcf, fullfile(output_dir, 'boxplot_filtered_comparison.fig'), 'compact');



disp('高通滤波后的箱线图已生成并保存。');
