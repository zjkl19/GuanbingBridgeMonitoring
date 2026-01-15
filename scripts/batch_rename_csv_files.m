% 设置文件夹路径
folderPath = 'F:\管柄数据\管柄6月数据\动应变';

% 获取文件夹中的所有CSV文件
fileList = dir(fullfile(folderPath, '*.csv'));

% 遍历文件列表
for i = 1:length(fileList)
    % 获取当前文件名
    oldName = fileList(i).name;
    
    % 提取文件的前缀部分和数字编号部分
    tokens = regexp(oldName, '(GB-RSG-[A-Z0-9]+)-(\d+)(.*)', 'tokens');
    
    % 确保提取到符合格式的内容
    if ~isempty(tokens)
        prefix = tokens{1}{1};  % 获取前缀部分
        numberPart = tokens{1}{2};  % 获取数字部分
        
        % 将数字部分转换为指定格式：例如将'00101'转换为'001-01'
        numberFormatted = [numberPart(1:3), '-', numberPart(4:end)];
        
        % 构造新的文件名
        newName = [prefix, '-', numberFormatted, '.csv'];
        
        % 获取完整的文件路径
        oldFilePath = fullfile(folderPath, oldName);
        newFilePath = fullfile(folderPath, newName);
        
        % 重命名文件
        movefile(oldFilePath, newFilePath);
        
        % 输出重命名信息
        disp(['Renamed: ', oldName, ' -> ', newName]);
    else
        disp(['Skipping file: ', oldName]);
    end
end
