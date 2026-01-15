clc
clear all

% 用户自定义参数
targetFileName = 'GB-VIB-G06-002-01'; % 要处理的文件名称模式
startTime = datetime('2025-05-12 00:30:27.039', 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');        % 开始时间
endTime =datetime('2025-05-12 00:40:27.129', 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');           % 结束时间


sampling_rate = 100; % 采样频率为 100 Hz
target_freqs = [1.150, 1.480, 2.310]; % 目标频率
tolerance = 0.15; % 容差范围

% 输出文件夹路径
outputFolder = 'F:\Guanbing\频谱分析结果';
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end


% 获取所有包含CSV文件的文件夹
rootFolder = uigetdir('', '选择包含CSV文件夹的根目录');
folders = dir(rootFolder);
folders = folders([folders.isdir] & ~ismember({folders.name}, {'.', '..'}));

% 初始化结果存储
allPeakFreqs = [];
allDates = {};
allFileNames = {};

% 遍历所有文件夹
for folderIdx = 1:length(folders)
    currentFolder = fullfile(folders(folderIdx).folder, folders(folderIdx).name);
    
    % 查找目标CSV文件
    filePattern = fullfile(currentFolder, [targetFileName '*.csv']);
    csvFiles = dir(filePattern);
    
    % 处理每个匹配的CSV文件
    for fileIdx = 1:length(csvFiles)
        csvFile = fullfile(csvFiles(fileIdx).folder, csvFiles(fileIdx).name);
        [~, fileName, ~] = fileparts(csvFile);
        
        % 读取CSV文件
        % opts = detectImportOptions(csvFile);
        % opts.DataLines = [skipRows+1 Inf]; % 可以指定跳过前几行
        data = read_csv_with_header(csvFile);
       
        % 获取起止日期
       [start_date, end_date] = get_start_and_end_date_large_file(csvFile);
        % 显示结果
        disp(['起始日期: ', start_date]);
        disp(['结束日期: ', end_date]);
        
        % 参数设置
        start_time = startTime + caldays(fileIdx-1); % 日期递增
        end_time = endTime + caldays(fileIdx-1);
        
        mark_peaks = true; % 是否标注峰值
        
        % 读取CSV文件
        data = read_csv_with_header(csvFile);
        %注：对 FFT 结果进行平滑处理
        analyze_frequency_spectrum(data, start_time, end_time, sampling_rate, target_freqs, tolerance, mark_peaks);    %标注峰值

        
        % % 标记峰值
        % if ~isempty(pks)
        %     hold on;
        %     plot(locs, pks, 'ro');
        %     text(locs, pks, cellstr(num2str(locs')), 'VerticalAlignment', 'bottom');
        %     hold off;
        % 
        %     % 存储峰值频率
        %     peakFreqs = sort(locs(1:min(3, length(locs)))); % 确保按频率排序
        %     peakFreqs = [peakFreqs; zeros(3-length(peakFreqs), 1)]; % 填充不足3个的情况
        % 
        %     % 记录结果
        %     allPeakFreqs = [allPeakFreqs; peakFreqs'];
        %     allDates = [allDates; datestr(data.DateTime(1), 'yyyy/mm/dd')];
        %     allFileNames = [allFileNames; fileName];
        % else
        %     warning('未找到峰值: %s', csvFile);
        %     peakFreqs = zeros(3, 1);
        %     allPeakFreqs = [allPeakFreqs; peakFreqs'];
        %     allDates = [allDates; datestr(data.DateTime(1), 'yyyy/mm/dd')];
        %     allFileNames = [allFileNames; fileName];
        % end
        
    end
end

% 创建并保存峰值频率Excel表格

 


% 创建并保存峰值频率Excel表格
if ~isempty(allPeakFreqs)
    peakTable = table(allFileNames, allDates, ...
        allPeakFreqs(:,1), allPeakFreqs(:,2), allPeakFreqs(:,3), ...
        'VariableNames', {'FileName', 'Date', 'Peak1_Hz', 'Peak2_Hz', 'Peak3_Hz'});
    writetable(peakTable, fullfile(outputFolder, '时间峰值频率.xlsx'));
    
    % 绘制时间频谱图
    fig2 = figure('Visible', 'off');
    dates = datetime(allDates, 'InputFormat', 'yyyy/mm/dd');
    [sortedDates, sortIdx] = sort(dates);
    
    hold on;
    plot(sortedDates, allPeakFreqs(sortIdx,1), 'ro-', 'DisplayName', '第一阶峰值');
    plot(sortedDates, allPeakFreqs(sortIdx,2), 'go-', 'DisplayName', '第二阶峰值');
    plot(sortedDates, allPeakFreqs(sortIdx,3), 'bo-', 'DisplayName', '第三阶峰值');
    hold off;
    
    xlabel('日期');
    ylabel('频率 (Hz)');
    title('时间频谱图');
    legend('Location', 'best');
    grid on;
    datetick('x', 'yyyy/mm/dd', 'KeepLimits', 'KeepTicks');
    
    % 保存时间频谱图
    saveas(fig2, fullfile(outputFolder, '时间频谱图.emf'));
    close(fig2);
end

disp('处理完成！');





