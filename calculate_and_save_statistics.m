function calculate_and_save_statistics(output_dir, labels, gf)
    % 创建带时间戳的输出文件名
    timestamp = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
    output_file = fullfile(output_dir, ['boxplot_statistics_' timestamp '.txt']);
    
    % 打开新文件
    fileID = fopen(output_file, 'w'); 
    
    % 写入统计时间
    current_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    fprintf(fileID, '统计时间: %s\n', current_time);

    % 获取当前图形中的 Y 数据
    ydata = get(gf, 'YData'); % 获取箱线图中的所有Y数据

    % 每个测点的行数
    num_rows_per_point = 7;

    % 循环处理每个测点
    for i = 1:length(labels)
        % 每个测点数据的索引偏移量
        offset = (i - 1) * num_rows_per_point;

        % 获取最大值和最小值
        max_val = ydata{3 + offset}(2);  % 第3行第2列是最大值
        min_val = ydata{4 + offset}(2);  % 第4行第2列是最小值

        % 写入统计结果
        fprintf(fileID, '测点: %s\n', labels{i});
        fprintf(fileID, '最大值: %.2f\n', max_val);
        fprintf(fileID, '最小值: %.2f\n', min_val);
        fprintf(fileID, '\n');
    end
    
    % 关闭文件
    fclose(fileID);

    disp('测点统计值已保存至新的 boxplot_statistics 文件。');
end
