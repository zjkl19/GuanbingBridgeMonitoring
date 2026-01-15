function [start_date, end_date] = get_start_and_end_date(file_path)
    % 获取CSV文件中起止日期（假定每个文件日期按升序排列）
    % file_path: CSV文件路径
    % 返回值:
    %   start_date: 起始日期
    %   end_date: 结束日期

    try
        % 打开文件
        fid = fopen(file_path, 'r');
        if fid == -1
            error('无法打开文件：%s', file_path);
        end

        % 读取首行数据，跳过空行
        first_line = '';
        while isempty(first_line) && ~feof(fid)
            first_line = fgetl(fid);
        end

        % 检查首行有效性
        if isempty(first_line)
            error('文件没有有效数据：%s', file_path);
        end
        first_row = strsplit(first_line, ','); % 假设以逗号分隔
        start_date = first_row{1}; % 获取第一列（假定为日期）

        % 读取最后一行数据
        last_line = '';
        while ~feof(fid)
            line = fgetl(fid);
            if ischar(line) && ~isempty(strtrim(line)) % 确保最后一行不是空行
                last_line = line;
            end
        end
        fclose(fid);

        % 解析最后一行的日期
        if isempty(last_line)
            error('文件没有有效数据行：%s', file_path);
        end
        last_row = strsplit(last_line, ',');
        end_date = last_row{1}; % 获取第一列（假定为日期）

    catch ME
        if exist('fid', 'var') && fid ~= -1
            fclose(fid);
        end
        rethrow(ME);
    end
end
