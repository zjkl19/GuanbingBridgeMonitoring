function analyze_frequency_spectrum(data, start_time, end_time, sampling_rate)
    % 分析指定时间段的数据频谱
    % data: 数据表，包含时间和加速度
    % start_time: 指定的起始时间 (字符串格式 'yyyy-MM-dd HH:mm:ss.SSS')
    % end_time: 指定的结束时间 (字符串格式 'yyyy-MM-dd HH:mm:ss.SSS')
    % sampling_rate: 采样频率 (Hz)
    
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

    % 检查是否有足够的数据点
    if isempty(selected_data)
        error('指定时间段内没有数据。');
    end

    % 计算频谱
    N = length(selected_data); % 数据点数
    fft_result = fft(selected_data); % 快速傅里叶变换
    freq = (0:N-1) * (sampling_rate / N); % 频率轴

    % 取幅值并归一化
    amplitude = abs(fft_result) / N;
    
    % 只取正频率部分
    half_N = floor(N/2) + 1;
    freq = freq(1:half_N);
    amplitude = amplitude(1:half_N);

    % 绘制频谱
    figure;
    plot(freq, amplitude);
    xlabel('Frequency (Hz)');
    ylabel('Amplitude');
    title('Frequency Spectrum');
    grid on;

    disp('频谱分析完成！');
end
