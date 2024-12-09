% 设置CSV文件路径
file_path = '加速度/GB-VIB-G06-00201.csv';

% 获取起止日期
[start_date, end_date] = get_start_and_end_date_large_file(file_path);
toc;
% 显示结果
disp(['起始日期: ', start_date]);
disp(['结束日期: ', end_date]);

% 参数设置
start_time = '2024-11-25 00:30:27.039';
end_time = '2024-11-25 00:40:27.129';
sampling_rate = 100; % 假设采样频率为 100 Hz
target_freqs = [1.150, 1.480, 2.310]; % 目标频率
tolerance = 0.15; % 容差范围
mark_peaks = true; % 是否标注峰值

tic;
% 读取CSV文件
data = read_csv_with_header(file_path);
toc;
%注：对 FFT 结果进行平滑处理
analyze_frequency_spectrum(data, start_time, end_time, sampling_rate, target_freqs, tolerance, mark_peaks);    %标注峰值
