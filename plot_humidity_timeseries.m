function plot_humidity_timeseries()
    % 设置文件目录和文件名模式
    data_dir = '湿度'; % 湿度数据所在目录
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
    all_data = struct(); % 按测点编号分组数据
    all_time = struct(); % 按测点编号分组的时间戳

    % 遍历每个文件，读取数据
    for i = 1:length(files)
        file_path = fullfile(files(i).folder, files(i).name);
        
        % 提取文件名中的测点编号（通过正则表达式）
        point_id = extract_point_id(files(i).name);
        
        % 将非法字符（如 '-'）替换为合法字符（如 '_'）
        point_id = strrep(point_id, '-', '_'); % 替换所有 '-' 为 '_'
        
        % 读取CSV文件
        try
            % 使用 textscan 读取数据
            fid = fopen(file_path);
            header_lines = detect_header_lines(file_path); % 自动检测HeaderLines
            %disp(header_lines)
            % 读取数据部分
            data = textscan(fid, '%s %f', 'Delimiter', ',', 'HeaderLines', header_lines);
            fclose(fid);

            % 提取时间戳和湿度数据
            time_data = data{1}; % 时间戳
            humidity_data = data{2}; % 湿度数据
            
            % 将数据合并到对应测点的结构中
            if ~isfield(all_data, point_id)
                all_data.(point_id) = [];
                all_time.(point_id) = [];
            end
            all_time.(point_id) = [all_time.(point_id); datetime(time_data, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS')]; % 转换为 datetime 格式
            all_data.(point_id) = [all_data.(point_id); humidity_data];
        catch ME
            disp(['Error reading file: ', file_path, '. Skipping.']);
            disp(ME.message);
        end
    end

    % 绘制每个测点的时程曲线并保存
    output_dir = '湿度结果';
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end

    for point_id = fieldnames(all_data)'
        point_id = point_id{1}; % 获取测点编号
        data = all_data.(point_id);
        time = all_time.(point_id);
        
        % 将所有时间按升序排序
        [time, sort_idx] = sort(time);
        data = data(sort_idx); % 排序后的湿度数据

        % 绘制时程曲线
        figure;
        plot(time, data, '-o');
        title([point_id, ' 湿度时程曲线']);
        xlabel('时间');
        ylabel('湿度 (%)');
        grid on;

        % 设置Y轴小数点位数
        ytickformat('%.0f');  

        % 计算平均值
        avg_value = mean(data);

        % 绘制平均值的虚线
        yline(avg_value, '--r', sprintf('平均值: %.2f %%', avg_value), 'LabelHorizontalAlignment', 'center', 'LabelVerticalAlignment', 'bottom', 'LineWidth', 2);

        % 保存图像
        timestamp = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
        saveas(gcf, fullfile(output_dir, [point_id '_humidity_timeseries_' timestamp '.jpg']));
        saveas(gcf, fullfile(output_dir, [point_id '_humidity_timeseries_' timestamp '.emf']));
        savefig(gcf, fullfile(output_dir, [point_id '_humidity_timeseries_' timestamp '.fig']), 'compact');

        % 保存统计数据
        save_statistics_to_txt(point_id, data, output_dir);
    end

    disp('湿度时程曲线已生成并保存。');
end

function point_id = extract_point_id(filename)
    % 使用正则表达式从文件名中提取测点编号（例如：GB-RTS-G05-001-01）
    expr = 'GB-RHS-G\d{2}-\d{3}-\d{2}';
    matches = regexp(filename, expr, 'match');
    if ~isempty(matches)
        point_id = matches{1};
    else
        error('未能从文件名中提取测点编号');
    end
end

function save_statistics_to_txt(point_id, data, output_dir)
    % 计算每个测点的统计数据：最大值、最小值、平均值
    min_val = min(data);
    max_val = max(data);
    avg_val = mean(data);

    % 创建新的输出文件，文件名包含时间戳
    timestamp = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
    output_file = fullfile(output_dir, ['humidity_statistics_' point_id '_' timestamp '.txt']);
    fileID = fopen(output_file, 'w'); % 新建文件

    % 写入统计数据
    fprintf(fileID, '测点: %s\n', point_id);
    fprintf(fileID, '最小值: %.2f\n', min_val);
    fprintf(fileID, '最大值: %.2f\n', max_val);
    fprintf(fileID, '平均值: %.2f\n', avg_val);
    fclose(fileID);
    
    disp(['统计数据已保存至 ' output_file]);
end
