%% 1. 生成模拟数据（含异常值）
rng(42); % 固定随机种子以便复现
data_normal = randn(1, 100)*2 + 10;      % 正常数据（均值=10，标准差=2）
data_outliers = [30, -5, 15, 40, -8];    % 人工插入的异常值
data = [data_normal(1:45), data_outliers, data_normal(46:end)]; % 合并数据
time = 1:length(data);

%% 2. 定义不同异常值检测方法
% 方法1：3σ准则（正态分布假设）
mean_val = mean(data);
std_val = std(data);
TF_std = (data > mean_val + 3*std_val) | (data < mean_val - 3*std_val);

% 方法2：IQR箱线图法（非参数方法）
Q1 = quantile(data, 0.25);
Q3 = quantile(data, 0.75);
IQR = Q3 - Q1;
TF_iqr = (data < Q1 - 1.5*IQR) | (data > Q3 + 1.5*IQR);

% 方法3：Hampel标识符（基于MAD）
median_val = median(data);
mad_val = mad(data, 1); % MAD = 1.4826 * median(|x - median|)
TF_hampel = abs(data - median_val) > 3 * mad_val;

% 方法4：滑动窗口局部检测（适合时间序列）
window_size = 10;
TF_window = false(size(data));
for i = 1:length(data)
    window_start = max(1, i - floor(window_size/2));
    window_end = min(length(data), i + floor(window_size/2));
    window_data = data(window_start:window_end);
    local_median = median(window_data);
    local_mad = mad(window_data, 1);
    TF_window(i) = abs(data(i) - local_median) > 3 * local_mad;
end

% 方法5：DBSCAN聚类（需Statistics and Machine Learning Toolbox）
% 假设数据为二维（仅作示例，需调整参数）
try
    data_2d = [time' data']; % 将时间序列转为二维数据
    TF_dbscan = dbscan(data_2d, 5, 3); % 邻域半径=5，最小点数=3
    TF_dbscan = (TF_dbscan == -1); % -1表示异常点
catch
    warning('DBSCAN需要Statistics and Machine Learning Toolbox');
    TF_dbscan = false(size(data));
end

%% 3. 可视化对比结果
figure('Position', [100, 100, 900, 600]);
subplot(2,1,1);
plot(time, data, 'b-', 'LineWidth', 1.5, 'DisplayName', '原始数据'); hold on;
plot(time(TF_std), data(TF_std), 'ro', 'MarkerSize', 8, 'DisplayName', '3σ法');
plot(time(TF_iqr), data(TF_iqr), 'g*', 'MarkerSize', 8, 'DisplayName', 'IQR法');
plot(time(TF_hampel), data(TF_hampel), 'ms', 'MarkerSize', 8, 'DisplayName', 'Hampel');
plot(time(TF_window), data(TF_window), 'cd', 'MarkerSize', 8, 'DisplayName', '滑动窗口');
if any(TF_dbscan)
    plot(time(TF_dbscan), data(TF_dbscan), 'kv', 'MarkerSize', 8, 'DisplayName', 'DBSCAN');
end
title('异常值检测方法对比', 'FontSize', 14);
xlabel('时间点', 'FontSize', 12);
ylabel('数据值', 'FontSize', 12);
legend('Location', 'northwest', 'FontSize', 10);
grid on;

% 标记人工插入的异常值（真实值）
true_outliers_idx = ismember(data, data_outliers);
plot(time(true_outliers_idx), data(true_outliers_idx), 'yx', 'MarkerSize', 12, 'LineWidth', 2, 'DisplayName', '真实异常值');

%% 4. 统计检测结果
methods = {'3σ法', 'IQR法', 'Hampel', '滑动窗口', 'DBSCAN'};
TF_all = [TF_std; TF_iqr; TF_hampel; TF_window; TF_dbscan];
detection_rate = sum(TF_all, 2) / length(data_outliers) * 100; % 检测率
false_positive = (sum(TF_all, 2) - sum(TF_all & true_outliers_idx, 2)) / length(data) * 100; % 误报率

% 显示统计表格
result_table = table(methods', detection_rate, false_positive, ...
    'VariableNames', {'方法', '检测率(%)', '误报率(%)'});
disp('=== 异常值检测性能对比 ===');
disp(result_table);