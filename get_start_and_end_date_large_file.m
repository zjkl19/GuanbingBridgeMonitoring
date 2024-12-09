function [start_date, end_date] = get_start_and_end_date_large_file(file_path)
    % 高效获取CSV文件的起止日期，自动跳过无效表头
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

        % 跳过无关表头，读取首个有效数据行
        start_date = '';
        while ~feof(fid)
            line = fgetl(fid); % 读取一行
            if isempty(line) || ~ischar(line)
                continue; % 跳过空行
            end

            % 检查该行是否包含有效日期
            row = strsplit(line, ',');
            try
                datetime(row{1}, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
                start_date = row{1}; % 找到首个有效日期
                break;
            catch
                % 如果无法解析日期，跳过该行
                continue;
            end
        end

        if isempty(start_date)
            error('文件中没有有效的起始日期：%s', file_path);
        end

        % 从文件尾部读取最后的数据块
        block_size = 8192; % 一次读取8KB数据块
        fseek(fid, -block_size, 'eof'); % 从文件尾部偏移
        data_block = fread(fid, block_size, '*char')'; % 读取数据块
        fclose(fid);

        % 分割数据块为多行
        lines = strsplit(data_block, '\n');
        lines = lines(~cellfun('isempty', strtrim(lines))); % 移除空行

        % 找到最后一个有效日期行
        end_date = '';
        for i = numel(lines):-1:1
            line = lines{i};
            row = strsplit(line, ',');
            try
                datetime(row{1}, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
                end_date = row{1}; % 找到最后一个有效日期
                break;
            catch
                % 如果无法解析日期，跳过该行
                continue;
            end
        end

        if isempty(end_date)
            error('文件中没有有效的结束日期：%s', file_path);
        end
    catch ME
        if exist('fid', 'var') && fid ~= -1
            fclose(fid);
        end
        rethrow(ME);
    end
end
