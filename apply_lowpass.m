function v_filtered = apply_lowpass(times, vals)
    % APPLY_LOWPASS   对 vals 做零相位低通滤波
    %   times: datetime 数组
    %   vals:  数值向量（含 NaN）
    
    v_filtered = vals;  % 默认不变
    if numel(times) < 2
        return;
    end

    % 计算采样频率
    dt = seconds(times(2) - times(1));  
    fs = 1 / dt;  % Hz
    
    % 用户可调参数
    fc    = fs/50;  % 截止频率 (Hz)
    order = 4;  % 滤波器阶数

    % 计算归一化截止频率
    Wn = fc / (fs/2);
    if Wn <= 0 || Wn >= 1
        warning('低通滤波：fc=%.2f Hz 不合法 (fs=%.2f Hz)，跳过滤波。', fc, fs);
        return;
    end

    % 设计并应用四/六阶 Butterworth 零相位滤波
    [b,a]     = butter(order, Wn);
    % 保留 NaN 段：先把 NaN 替为 0，滤波后再还原
    nan_mask = isnan(vals);
    temp     = vals;
    temp(nan_mask) = 0;
    y        = filtfilt(b, a, temp);
    y(nan_mask)= NaN;

    v_filtered = y;
end
