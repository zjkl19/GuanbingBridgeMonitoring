function data = read_csv_with_header(file_path)
    % 从包含无效表头的CSV文件中读取有效数据
    % file_path: CSV文件的完整路径
    % 返回值:
    %   data: 读取的表格数据

    % 检查文件是否存在
    if ~isfile(file_path)
        error('文件不存在：%s', file_path);
    end

    try
        fid = fopen(file_path, 'r');
        if fid == -1
            error('无法打开文件：%s', file_path);
        end

        % 检测有效数据行（假定列名包含时间关键字 "[绝对时间]" 或其他标志）
        valid_line_found = false;
        line_num = 0;
        while ~feof(fid)
            line = fgetl(fid);
            line_num = line_num + 1;
            if contains(line, '[绝对时间]')
                valid_line_found = true;
                break;
            end
        end

        % 如果未找到有效行，抛出错误
        if ~valid_line_found
            error('未找到有效数据行，请检查文件格式：%s', file_path);
        end

        fclose(fid);

        % 使用 readtable 从有效数据行开始读取
        opts = detectImportOptions(file_path, 'NumHeaderLines', line_num - 1);
        data = readtable(file_path, opts);
    catch ME
        if exist('fid', 'var') && fid ~= -1
            fclose(fid);
        end
        error('读取文件失败：%s\n错误信息：%s', file_path, ME.message);
    end
end
