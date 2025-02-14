function plot_temperature_timeseries()
    % 设置文件目录和文件名模式
    data_dir = '温度'; % 温度数据所在目录
    file_pattern = fullfile(data_dir, '*.csv'); % CSV文件的模式
    files = dir(file_pattern); % 获取目录中所有CSV文件信息

    % 计算总数据量（用于估算时间）
    total_file_size = sum([files.bytes]) / 1e6; % 总文件大小（MB）
    estimated_time = round(total_file_size * 0.1, 1); % 粗略估计每MB需要0.1秒的处理时间，具体值可根据性能调整

    % 如果预计时间超过3分钟，给出警告
    if estimated_time > 180
        disp(['预计处理时间为 ', num2str(estimated_time / 60, '%.1f'), ' 分钟，超过3分钟。']);
        user_response = input('是否继续？(y/n): ', 's');
        if lower(user_response) ~= 'y'
            disp('操作已取消。');
            return;
        end
    else
        disp(['预计处理时间为 ', num2str(estimated_time / 60, '%.1f'), ' 分钟，开始运行。']);
    end

    % 初始化数据存储
    all_data = []; % 存放所有数据
    all_time = []; % 存放所有时间戳

    % 遍历每个文件，读取数据
    for i = 1:length(files)
        file_path = fullfile(files(i).folder, files(i).name);
        % 读取CSV文件
        try
            % 使用 textscan 读取数据
            fid = fopen(file_path);
            header_lines = detect_header_lines(file_path); % 自动检测HeaderLines
            %disp(header_lines)
            % 读取数据部分
            data = textscan(fid, '%s %f', 'Delimiter', ',', 'HeaderLines', header_lines);
            fclose(fid);

            % 提取时间戳和温度数据
            time_data = data{1}; % 时间戳
            temp_data = data{2}; % 温度数据
            
            % 将数据合并到总体数据中
            all_time = [all_time; datetime(time_data, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS')]; % 转换为 datetime 格式
            all_data = [all_data; temp_data];
        catch ME
            disp(['Error reading file: ', file_path, '. Skipping.']);
            disp(ME.message);
        end
    end

    % 将所有时间按升序排序
    [all_time, sort_idx] = sort(all_time);
    all_data = all_data(sort_idx); % 排序后的温度数据

    % 绘制时程曲线
    figure;
    plot(all_time, all_data, '-o');
    title('温度时程曲线');
    xlabel('时间');
    ylabel('温度 (°C)');
    grid on;

    % 设置Y轴小数点位数
    ytickformat('%.0f');  

    % 计算平均值
    avg_value = mean(all_data);

    % 绘制平均值的虚线
    yline(avg_value, '--r', sprintf('平均值: %.2f °C', avg_value), 'LabelHorizontalAlignment', 'center', 'LabelVerticalAlignment', 'bottom', 'LineWidth', 2);

    % 保存图像
    timestamp = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
    output_dir = '时程曲线结果';
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    saveas(gcf, fullfile(output_dir, ['temperature_timeseries_' timestamp '.jpg']));
    saveas(gcf, fullfile(output_dir, ['temperature_timeseries_' timestamp '.emf']));
    savefig(gcf, fullfile(output_dir, ['temperature_timeseries_' timestamp '.fig']), 'compact');

    disp('时程曲线已生成并保存。');
end
