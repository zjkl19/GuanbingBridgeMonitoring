% 自动检测HeaderLines，限制只读取前50行
function header_lines = detect_header_lines(file_path)
    % 打开文件
    fid = fopen(file_path, 'rt');
    
    % 初始化
    header_lines = 0;
    line_count = 0;
    
    % 读取文件的前50行
    while line_count < 50 && ~feof(fid)
        line = fgetl(fid); % 逐行读取
        line_count = line_count + 1;
        %disp(line_count)
        % 查找包含"绝对时间"的行
        if contains(line, '绝对时间')
            header_lines = line_count; % 如果找到“绝对时间”，记录当前行号
            break; % 找到后跳出循环
        end
    end
    
    % 如果没有找到“绝对时间”行，返回0（表示没有头部信息）
    if header_lines == 0
        warning('未找到“绝对时间”行');
    end
    
    % 关闭文件
    fclose(fid);
end