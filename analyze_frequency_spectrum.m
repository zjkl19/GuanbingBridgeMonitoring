function analyze_frequency_spectrum(data, start_time, end_time, sampling_rate, target_freqs, tolerance, mark_peaks)
    % 分析指定时间段的数据频谱，可选是否标注峰值
    % data: 数据表，包含时间和加速度
    % start_time: 指定的起始时间 (字符串格式 'yyyy-MM-dd HH:mm:ss.SSS')
    % end_time: 指定的结束时间 (字符串格式 'yyyy-MM-dd HH:mm:ss.SSS')
    % sampling_rate: 采样频率 (Hz)
    % num_peaks: 需要标注的峰值数量
    % tolerance: 容差范围（如 0.05 Hz）
    % mark_peaks: 是否标注峰值（布尔值）

    % 检查输入格式
    if ~istable(data)
        error('输入数据必须为table格式。');
    end

    % 确保时间列是datetime格式
    if ~isdatetime(data{:, 1})
        data{:, 1} = datetime(data{:, 1}, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
    end

    % 提取时间段的数据
    mask = data{:, 1} >= datetime(start_time, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS') & ...
           data{:, 1} <= datetime(end_time, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
    selected_data = data{mask, 2}; % 提取加速度列

    if isempty(selected_data)
        error('指定时间段内没有数据。');
    end

    % 计算频谱
    N = length(selected_data); % 数据点数
    fft_result = fft(selected_data); % 快速傅里叶变换
    freq = (0:N-1) * (sampling_rate / N); % 频率轴

    % 取幅值并归一化
    amplitude = abs(fft_result) / N;

    % 平滑处理
    window_size = 5; % 平滑窗口大小
    amplitude_smoothed = smooth(amplitude, window_size);

    % 只取正频率部分
    half_N = floor(N/2) + 1;
    freq = freq(1:half_N);
    amplitude_smoothed = amplitude_smoothed(1:half_N);

    % 绘制频谱
    figure;
    plot(freq, amplitude_smoothed);
    xlim([0,10])
    xlabel('频率 (Hz)');
    ylabel('幅值');
    title('平滑后的频谱图');
    grid on;


    % 是否标注峰值
    if mark_peaks
        % 调用辅助函数标注目标频率附近的峰值
        analyze_frequency_peaks(freq, amplitude_smoothed, target_freqs, tolerance);
    end

    % 保存图像
    save_spectrum_plot();

    disp('频谱分析完成！');
end

function save_spectrum_plot()
    % 获取当前时间戳
    timestamp = datetime('now', 'Format', 'yyyyMMdd_HHmmss');  % 使用 datetime 获取时间戳
    timestamp_str = char(timestamp);  % 转为字符型字符串
    
    % 删除非法字符（如冒号和空格）
    timestamp_str = strrep(timestamp_str, ':', '-');  % 替换冒号为破折号
    timestamp_str = strrep(timestamp_str, ' ', '_');  % 替换空格为下划线

    % 确保结果存储文件夹存在
    folder_name = '频谱分析结果';
    if ~exist(folder_name, 'dir')
        mkdir(folder_name);
    end

    % 文件名
    file_base_name = fullfile(folder_name, ['spectrum_plot_' timestamp_str]);

    % 保存为不同格式
    saveas(gcf, [file_base_name, '.fig']);  % 保存为 MATLAB .fig 文件
    saveas(gcf, [file_base_name, '.jpg']);  % 保存为 JPG 文件
    saveas(gcf, [file_base_name, '.emf']);  % 保存为 EMF 文件

    disp(['频谱图已保存至: ' folder_name]);
end

