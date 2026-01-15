function calculate_and_save_statistics_to_excel(output_dir, labels, gf)
    % 创建带时间戳的输出文件名
    timestamp = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
    output_file = fullfile(output_dir, ['boxplot_statistics_' timestamp '.xlsx']);
    
    % 获取当前图形中的 Y 数据
    ydata = get(gf, 'YData'); % 获取箱线图中的所有Y数据

    % 每个测点的行数
    num_rows_per_point = 7;

    % 创建一个存储统计结果的单元格数组
    result_data = {};
    result_data{1, 1} = '统计时间';
    result_data{1, 2} = datestr(now, 'yyyy-mm-dd HH:MM:SS');

    % 添加标题行
    result_data{2, 1} = '测点';
    result_data{2, 2} = '最大值';
    result_data{2, 3} = '最小值';

    % 循环处理每个测点并将数据添加到结果数组中
    for i = 1:length(labels)
        % 每个测点数据的索引偏移量
        offset = (i - 1) * num_rows_per_point;

        % 获取最大值和最小值
        max_val = ydata{3 + offset}(2);  % 第3行第2列是最大值
        min_val = ydata{4 + offset}(2);  % 第4行第2列是最小值

        % 保留2位小数
        max_val = round(max_val, 2);
        min_val = round(min_val, 2);

        % 将数据添加到结果数组
        result_data{2 + i, 1} = labels{i};
        result_data{2 + i, 2} = max_val;
        result_data{2 + i, 3} = min_val;
    end

    % 将结果保存到Excel文件中
    writetable(cell2table(result_data), output_file, 'WriteVariableNames', false);

    disp(['测点统计值已保存至新的 Excel 文件：' output_file]);
end
