% main.m 文件

folder_path = '加速度';
file_name = 'GB-VIB-G06-00201.csv';
full_file_path = fullfile(folder_path, file_name);

% 参数设置
num_parts = 10;        % 分割为num_parts份
header_lines = 3;       % 表头信息占3行

% 开始计时
tic;
try
    disp('开始分割文件...');
    split_csv_file(full_file_path, num_parts, header_lines);
    disp('文件分割完成。');
catch ME
    disp('文件分割失败：');
    disp(ME.message);
end
% 结束计时
toc;
