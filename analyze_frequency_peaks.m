function analyze_frequency_peaks(freq, amplitude, target_freqs, tolerance)
    % 自动识别指定频率附近的峰值并标注
    % freq: 频率数组
    % amplitude: 幅值数组
    % target_freqs: 指定的目标频率数组（如 [1.150, 1.480, 2.310]）
    % tolerance: 容差范围（如 0.05 Hz）

    % 初始化结果存储
    detected_freqs = [];
    detected_pks = [];

    % 遍历目标频率
    for i = 1:length(target_freqs)
        % 目标频率范围
        target_range = [target_freqs(i) - tolerance, target_freqs(i) + tolerance];

        % 限制频率范围
        range_mask = freq >= target_range(1) & freq <= target_range(2);
        freq_range = freq(range_mask);
        amp_range = amplitude(range_mask);

        % 在该范围内查找峰值
        if ~isempty(amp_range)
            [pks, locs] = findpeaks(amp_range, freq_range, ...
                                    'SortStr', 'descend'); % 按峰值排序

            % 取范围内最显著的峰
            if ~isempty(pks)
                detected_freqs = [detected_freqs; locs(1)];
                detected_pks = [detected_pks; pks(1)];
            end
        end
    end

    % 绘制标注
    hold on;
    for i = 1:length(detected_freqs)
        text(detected_freqs(i), detected_pks(i), sprintf('X=%.3f', detected_freqs(i)), ...
             'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'center', ...
             'BackgroundColor', 'white', 'EdgeColor', 'black');
    end
    hold off;

    % 输出结果表格
    results = table(detected_freqs, detected_pks, 'VariableNames', {'Frequency_Hz', 'Amplitude'});
    disp('检测到的目标频率附近的峰值:');
    disp(results);
end
