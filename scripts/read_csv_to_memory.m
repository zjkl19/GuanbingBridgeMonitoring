function data = read_csv_to_memory(file_path)
    % 读取CSV文件到内存
    % file_path: CSV文件的完整路径
    % 返回值:
    %   data: 读取的表格数据

    % 检查文件是否存在
    if ~isfile(file_path)
        error('文件不存在：%s', file_path);
    end

    try
        disp(['正在读取文件：', file_path]);
        % 使用 readtable 读取数据为表格
        data = readtable(file_path);
        disp('文件读取完成。');
    catch ME
        error('读取文件失败：%s\n错误信息：%s', file_path, ME.message);
    end
end