function split_csv_file(file_path, num_parts, header_lines)
    % 分割大型CSV文件，支持跳过表头并保留列名信息
    % file_path: CSV文件路径
    % num_parts: 平均分割的份数
    % header_lines: 跳过的表头行数

    try
        % 打开文件
        fid = fopen(file_path, 'r');
        if fid == -1
            error('无法打开文件：%s', file_path);
        end

        % 跳过表头行
        for i = 1:header_lines
            fgetl(fid);
        end

        % 获取列名信息
        column_header = fgetl(fid);
        column_header = strtrim(column_header); % 清理换行符和多余空格

        % 统计数据行数
        disp('正在统计数据行数...');
        line_count = 0;
        while ~feof(fid)
            fgetl(fid);
            line_count = line_count + 1;
        end

        % 计算每份行数
        rows_per_part = ceil(line_count / num_parts);

        % 返回文件开头并跳过表头行
        fclose(fid);
        fid = fopen(file_path, 'r');
        for i = 1:(header_lines + 1) % 跳过表头和列名行
            fgetl(fid);
        end

        % 分割文件
        disp('正在分割文件...');
        for part = 1:num_parts
            output_file = sprintf('%s_part%d.csv', file_path(1:end-4), part);
            output_fid = fopen(output_file, 'w');
            if output_fid == -1
                error('无法创建输出文件：%s', output_file);
            end

            % 写入列名
            fprintf(output_fid, '%s\n', column_header);

            % 写入数据
            for row = 1:rows_per_part
                if feof(fid)
                    break;
                end
                line = fgetl(fid);
                fprintf(output_fid, '%s\n', line);
            end

            fclose(output_fid);
            fprintf('已创建文件：%s\n', output_file);
        end

        fclose(fid);
        disp('文件分割完成。');
    catch ME
        if exist('fid', 'var') && fid ~= -1
            fclose(fid);
        end
        rethrow(ME);
    end
end
