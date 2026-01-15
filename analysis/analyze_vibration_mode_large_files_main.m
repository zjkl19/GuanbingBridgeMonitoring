% file_paths = {
%     '加速度/GB-VIB-G05-00101_part6.csv',
%     '加速度/GB-VIB-G05-00201_part6.csv',
%     '加速度/GB-VIB-G05-00301_part6.csv'
% };
file_paths = {
    '加速度/GB-VIB-G05-00101_part6.csv',
    '加速度/GB-VIB-G05-00201_part6.csv',
    '加速度/GB-VIB-G05-00301_part6.csv'
};
% 参数设置
start_time = '2024-10-11 00:30:27.039';
end_time = '2024-10-11 00:40:27.129';
frequency = 2.617; % Hz
sampling_rate = 100; % 假定采样频率为 100 Hz

tic;
% 分析振型
normalized_displacement = analyze_vibration_mode_large_files(file_paths, start_time, end_time, frequency, sampling_rate);
toc;

% 输出结果
disp('归一化的振型:');
disp(normalized_displacement);
