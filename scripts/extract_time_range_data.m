function data = extract_time_range_data(file_path, start_time, end_time)
    % 提取指定时间段内的数据，逐行读取文件
    % file_path: CSV 文件路径
    % start_time: 起始时间
    % end_time: 结束时间
    % 返回:
    %   data: 指定时间段内的加速度数据向量

    data = []; % 初始化返回数据
    start_time = datetime(start_time, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
    end_time = datetime(end_time, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');

    % 打开文件
    fid = fopen(file_path, 'r');
    if fid == -1
        error('无法打开文件：%s', file_path);
    end

    try
        % 跳过空行
        first_line = '';
        while isempty(first_line) && ~feof(fid)
            first_line = fgetl(fid);
        end

        % 逐行读取有效数据
        while ~feof(fid)
            line = fgetl(fid);
            if isempty(line) || ~ischar(line)
                continue;
            end

            % 按逗号分割行
            row = strsplit(line, ',');
            timestamp = datetime(row{1}, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
            if timestamp >= start_time && timestamp <= end_time
                data = [data; str2double(row{2})]; %#ok<AGROW>
            end
        end
    catch ME
        fclose(fid);
        rethrow(ME);
    end

    fclose(fid);
end