% 生成模拟时程数据
fs = 100;                   % 采样频率 100 Hz
t = 0:1/fs:10;              % 时间向量：0～10 s
signal_clean = sin(2*pi*0.5*t);    % 0.5 Hz 正弦信号
noise = 0.2*randn(size(t));        % 高斯噪声
signal_noisy = signal_clean + noise;

% 添加脉冲噪声（尖峰）
num_spikes = 20;
for k = 1:num_spikes
    idx = randi(length(signal_noisy));
    signal_noisy(idx) = signal_noisy(idx) + (randn*5);
end

% 中值滤波
window_size = 5;            % 滤波窗口长度（奇数）
signal_filtered = medfilt1(signal_noisy, window_size);

% 绘图对比
figure;
plot(t, signal_noisy, 'b', 'DisplayName', '原始带噪信号'); hold on;
plot(t, signal_filtered, 'r', 'LineWidth',1.5, 'DisplayName', '中值滤波后信号');
legend('Location','best');
xlabel('时间 (s)');
ylabel('幅值');
title('中值滤波示例：原始信号 vs 滤波后信号');
grid on;
