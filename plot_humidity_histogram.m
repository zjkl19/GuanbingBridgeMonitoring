function plot_humidity_histogram()
    % 设置文件目录和文件名模式
    data_dir = '湿度'; % 湿度数据所在目录
    file_pattern = fullfile(data_dir, '*.csv'); % CSV文件的模式
    files = dir(file_pattern); % 获取目录中所有CSV文件信息

    % 初始化数据存储
    all_data = struct(); % 使用结构体存储每个测点的数据
    expr = 'GB-RHS-G\d{2}-\d{3}-\d{2}'; % 用于提取测点编号的正则表达式

    % 遍历每个文件，读取湿度数据
    for i = 1:length(files)
        file_path = fullfile(files(i).folder, files(i).name);
        
        % 提取测点编号
        [~, file_name, ~] = fileparts(files(i).name); % 获取文件名
        point_id = regexp(file_name, expr, 'match'); % 使用正则表达式提取测点编号
        % 将非法字符（如 '-'）替换为合法字符（如 '_'）
        point_id = strrep(point_id, '-', '_'); % 替换所有 '-' 为 '_'

        if isempty(point_id)
            disp(['文件 ', files(i).name, ' 不符合测点编号格式，跳过该文件。']);
            continue;
        end
        point_id = point_id{1}; % 提取到的测点编号

        % 读取CSV文件
        try
            % 使用 textscan 读取数据
            fid = fopen(file_path);
            header_lines = detect_header_lines(file_path); % 自动检测HeaderLines
            % 读取数据部分
            data = textscan(fid, '%s %f', 'Delimiter', ',', 'HeaderLines', header_lines);
            fclose(fid);

            % 提取湿度数据
            humidity_data = data{2}; % 湿度数据

            % 将数据存入对应测点的结构体字段
            if ~isfield(all_data, point_id)
                all_data.(point_id) = []; % 如果该测点数据不存在，则初始化
            end
            all_data.(point_id) = [all_data.(point_id); humidity_data]; % 合并数据
        catch ME
            disp(['Error reading file: ', file_path, '. Skipping.']);
            disp(ME.message);
        end
    end

    % 遍历每个测点进行频次统计和绘制柱状图
    for point_id = fieldnames(all_data)'
        point_id = point_id{1}; % 获取测点编号

        humidity_data = all_data.(point_id); % 获取该测点的数据

        % 定义湿度区间
        bins = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]; % 左开右闭的区间
        bin_labels = {'0-10', '10-20', '20-30', '30-40', '40-50', '50-60', '60-70', '70-80', '80-90', '90-100'};

        % 统计每个区间内的湿度频次
        [counts, edges] = histcounts(humidity_data, bins);

        % 计算百分比
        total_count = sum(counts);
        percentages = (counts / total_count) * 100;

        % 绘制柱状图
        figure;
        bar(1:length(counts), percentages, 'FaceColor', 'b', 'EdgeColor', 'k');
        xticks(1:length(counts));
        xticklabels(bin_labels);
        ylabel('百分比 (%)');
        xlabel('湿度区间 (%)');
        title(['湿度频次分布图 - 测点: ', point_id]);
        grid on;

        % 在每个柱上添加百分比标注
        for k = 1:length(counts)
            text(k, percentages(k) + 0.5, sprintf('%.2f%%', percentages(k)), 'HorizontalAlignment', 'center');
        end

        % 保存图像
        timestamp = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
        output_dir = '湿度结果';
        if ~exist(output_dir, 'dir')
            mkdir(output_dir);
        end
        saveas(gcf, fullfile(output_dir, [point_id '_humidity_histogram_' timestamp '.jpg']));
        saveas(gcf, fullfile(output_dir, [point_id '_humidity_histogram_' timestamp '.emf']));
        savefig(gcf, fullfile(output_dir, [point_id '_humidity_histogram_' timestamp '.fig']), 'compact');

        disp(['湿度频次分布图已生成并保存 - ', point_id]);
    end
end
