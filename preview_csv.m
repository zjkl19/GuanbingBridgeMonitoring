function preview_csv(file_path, n)
    % 预览CSV文件前n行信息
    % file_path: CSV文件路径
    % n: 需要预览的行数

    % 检查输入参数
    if nargin < 2
        n = 10; % 默认预览10行
    end

    try
        % 打开文件
        fid = fopen(file_path, 'r');
        if fid == -1
            error('无法打开文件：%s', file_path);
        end

        % 逐行读取并打印
        fprintf('文件 %s 的前 %d 行内容:\n', file_path, n);
        line_count = 0;
        while ~feof(fid) && line_count < n
            line = fgetl(fid); % 读取一行
            fprintf('%s\n', line); % 打印该行内容
            line_count = line_count + 1;
        end

        % 关闭文件
        fclose(fid);
        if line_count == 0
            fprintf('文件为空或没有有效内容。\n');
        end
    catch ME
        if exist('fid', 'var') && fid ~= -1
            fclose(fid);
        end
        fprintf('预览失败：%s\n', ME.message);
    end
end
