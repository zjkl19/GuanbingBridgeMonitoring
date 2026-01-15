function normalized_displacement = analyze_vibration_mode_large_files(file_paths, start_time, end_time, frequency, sampling_rate)
    % 分析大文件中的振型，逐行读取数据
    % file_paths: 包含每个测点的分割文件路径 cell 数组
    % start_time: 起始时间 (字符串 'yyyy-MM-dd HH:mm:ss.SSS')
    % end_time: 结束时间 (字符串 'yyyy-MM-dd HH:mm:ss.SSS')
    % frequency: 目标频率 (Hz)
    % sampling_rate: 数据采样频率 (Hz)
    % 返回:
    %   normalized_displacement: 归一化的振型数组

    num_points = numel(file_paths); % 测点数量
    if num_points < 2
        error('测点数量必须大于或等于2');
    end

    % 初始化存储振型幅值
    amplitudes = zeros(num_points, 1);

    % 带通滤波器设计
    filter_bandwidth = 0.1; % 滤波器带宽 (Hz)
    [b, a] = butter(4, [(frequency - filter_bandwidth) / (sampling_rate / 2), ...
                        (frequency + filter_bandwidth) / (sampling_rate / 2)], 'bandpass');

    for i = 1:num_points
        % 当前测点文件路径
        file_path = file_paths{i};

        % 调用逐行读取函数获取指定时间段的数据
        filtered_data = extract_time_range_data(file_path, start_time, end_time);

        if isempty(filtered_data)
            error('测点 %d 在指定时间段内无有效数据', i);
        end

        % 滤波处理
        filtered_signal = filtfilt(b, a, filtered_data);

        % 计算振型幅值（目标频率的幅值）
        amplitudes(i) = rms(filtered_signal); % 或 max(abs(filtered_signal))
    end

    % 归一化处理
    normalized_displacement = amplitudes / max(amplitudes);
end