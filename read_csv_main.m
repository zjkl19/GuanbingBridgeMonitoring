% 设置CSV文件路径
file_path = '动应变/GB-RSG-G05-00101.csv';

tic;
% 读取CSV文件
data = read_csv_to_memory(file_path);
toc;