% 文件路径
file_path = '加速度/GB-VIB-G06-00201.csv';
tic;
% 获取起止日期
[start_date, end_date] = get_start_and_end_date_large_file(file_path);
toc;
% 显示结果
disp(['起始日期: ', start_date]);
disp(['结束日期: ', end_date]);
