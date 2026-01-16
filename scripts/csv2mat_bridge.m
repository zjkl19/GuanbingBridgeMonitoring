function csv2mat_bridge(csvRoot, matRoot)
% csv2mat_bridge
% --------------
% BridgeCSV\YYYY-MM-DD\*.csv  → BridgeMat\YYYY-MM-DD\*.mat
% 并生成 PNG 预览、JSON 描述、convert_log.txt
%
% 默认:
%   csvRoot = 'BridgeCSV'
%   matRoot = 'BridgeMat'
%
% 用法:
%   csv2mat_bridge
%   csv2mat_bridge('E:\BridgeCSV','E:\BridgeMat')

% ---------- 可调 ----------
pngDPI = 150;    % PNG 分辨率
% --------------------------

if nargin<1 || isempty(csvRoot), csvRoot = 'BridgeCSV'; end
if nargin<2 || isempty(matRoot), matRoot = 'BridgeMat'; end
assert(isfolder(csvRoot), 'CSV 根目录 %s 不存在！', csvRoot);
if ~exist(matRoot,'dir'), mkdir(matRoot); end

dateDirs = dir(fullfile(csvRoot,'????-??-??'));
dateDirs = dateDirs([dateDirs.isdir]);
if isempty(dateDirs)
    warning('CSV 根目录下无日期文件夹'); return;
end

for d = dateDirs'
    dateStr = d.name;
    inDir   = fullfile(d.folder,d.name);
    outDir  = fullfile(matRoot,dateStr);
    if ~exist(outDir,'dir'), mkdir(outDir); end

    csvFiles = dir(fullfile(inDir,'*.csv'));
    if isempty(csvFiles)
        fprintf('[%s] 无 CSV，跳过\n',dateStr); continue;
    end

    logPath = fullfile(outDir,'convert_log.txt');
    logFid  = fopen(logPath,'w');
    if logFid==-1, warning('无法创建日志 %s，仅屏幕输出',logPath); end
    if logFid~=-1, cleaner=onCleanup(@()fclose(logFid)); else, cleaner=onCleanup(@()[]); end %#ok<NASGU>

    fprintf('\n=== %s  (%d 个 CSV) ===\n',dateStr,numel(csvFiles));

    for f = csvFiles'
        csvPath = fullfile(f.folder,f.name);
        [sensor,~] = strtok(f.name,'_');           % 'A10_143.csv'→'A10'

        outMat  = fullfile(outDir,[sensor '.mat']);
        outPng  = fullfile(outDir,[sensor '.png']);
        outJson = fullfile(outDir,[sensor '.info.json']);

        try
            %% -------- 读取两列 (自动兼容版本) -------------------------
            try
                % 新 API (R2020b+) -----------
                opts = detectImportOptions(csvPath,'Delimiter',',', ...
                    'FileEncoding','UTF-16LE','ReadVariableNames',false);
                opts.VariableTypes = {'datetime','double'};
                opts = setvaropts(opts,1, ...
                    'InputFormat','yyyy-MM-dd HH:mm:ss.SSS', ...
                    'Format','yyyy-MM-dd HH:mm:ss.SSS');
                T = readtable(csvPath,opts);
                Time  = T.Var1;
                Value = T.Var2;
            catch
                % 旧版本回退 -------------
                fid = fopen(csvPath,'r','n','UTF-16LE');
                if fid==-1, error('无法打开文件'); end
                C = textscan(fid,'%s %f','Delimiter',',','CollectOutput',true);
                fclose(fid);
                Time  = datetime(C{1}, ...
                    'InputFormat','yyyy-MM-dd HH:mm:ss.SSS', ...
                    'Format','yyyy-MM-dd HH:mm:ss.SSS');
                Value = C{2};
            end

            % ===== 新增：空文件判断 =======================================
            if isempty(Time) || isempty(Value)
                msgEmpty = sprintf('[EMPTY] %s (文件无数据，跳过)\n', f.name);
                if logFid ~= -1, fprintf(logFid, msgEmpty); end
                fprintf(msgEmpty);
                continue      % 直接处理下一个 CSV
            end
            % =============================================================

            %% -------- 保存 MAT (无压缩) -------------------------------
            save(outMat,'Time','Value','-v7.3','-nocompression');

            %% -------- PNG 预览 ---------------------------------------
            fig = figure('Visible','off','Position',[100 100 720 360]);
            plot(Time,Value,'b-','LineWidth',1);
            grid on; xlabel('时间'); ylabel('数值');
            title([sensor '  ' dateStr],'Interpreter','none');
            print(fig,outPng,'-dpng',['-r' num2str(pngDPI)]);
            close(fig);

            %% -------- JSON 描述 -------------------------------------
            meta = struct('sensor',sensor,'rows',numel(Time), ...
                'date',dateStr,'csvFile',f.name,'matFile',[sensor '.mat']);
            fidJ = fopen(outJson,'w');
            fwrite(fidJ,jsonencode(meta),'char');
            fclose(fidJ);

            msgOK = sprintf('[OK ] %s → %s\n',f.name,[sensor '.mat']);
            if logFid~=-1, fprintf(logFid,msgOK); end
            fprintf(msgOK);
        catch ME
            msgERR = sprintf('[ERR] %s : %s  (可能为空文件或格式异常)\n', ...
                f.name, ME.message);
            if logFid~=-1, fprintf(logFid,msgERR); end
            fprintf(2,msgERR);
        end
    end
    fprintf('完成 %s，日志见 %s\n',dateStr,fullfile(outDir,'convert_log.txt'));
end
fprintf('\n全部日期处理完毕！结果保存在 %s\n',matRoot);
end
