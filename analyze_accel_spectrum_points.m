function analyze_accel_spectrum_points(root_dir,start_date,end_date,point_ids,...
                                       excel_file,subfolder,target_freqs, ...
                                       tolerance,use_parallel)
% analyze_accel_spectrum_points
% ────────────────────────────────────────────────────────────────────────
%   在 [start_date,end_date] 每天 00:30–00:40 段，对给定测点的加速度信号
%   做 Welch PSD，提取 target_freqs±tolerance Hz 带内峰值（幅度 dB & 频率）
%   并保存峰值时程曲线和 Excel。
% ------------------------------------------------------------------------
if nargin<1||isempty(root_dir),  root_dir = pwd; end
if nargin<2||isempty(start_date), error('必须指定 start_date'); end
if nargin<3||isempty(end_date),   error('必须指定 end_date');   end
if nargin<4||isempty(point_ids)
    point_ids = {'GB-VIB-G04-001-01','GB-VIB-G05-001-01',...
                 'GB-VIB-G05-002-01','GB-VIB-G05-003-01',...
                 'GB-VIB-G06-001-01','GB-VIB-G06-002-01',...
                 'GB-VIB-G06-003-01','GB-VIB-G07-001-01'};
end
if nargin<5||isempty(excel_file),  excel_file = 'accel_spec_stats.xlsx'; end
if nargin<6||isempty(subfolder),   subfolder  = '波形';          end
if nargin<7||isempty(target_freqs),target_freqs=[1.150 1.480 2.310];   end
if nargin<8||isempty(tolerance),   tolerance  = 0.15;                  end
if nargin<9,  use_parallel = false;                                    end

outDirFig = fullfile(root_dir,'谱峰值曲线_加速度');
if ~exist(outDirFig,'dir'), mkdir(outDirFig); end

psdRoot = fullfile(root_dir,'PSD_备查');
if ~exist(psdRoot,'dir'), mkdir(psdRoot); end

dates_all = (datetime(start_date):days(1):datetime(end_date)).';
Nday      = numel(dates_all);

if use_parallel
    p = gcp('nocreate'); if isempty(p), parpool('local'); end
end

nPts  = numel(point_ids);
nFreq = numel(target_freqs);

peakAmpMat   = NaN(Nday,nFreq,nPts);   % 峰值幅度 (dB)
peakFreqMat  = NaN(Nday,nFreq,nPts);   % 峰值频率 (Hz)

%% ---------- 主循环 ----------
for ii = 1:nPts
    processPoint(point_ids{ii}, ii);
end

%% ---------- 写 Excel ----------
for pi = 1:nPts
    dateCol = dates_all(:);
    freqTbl = array2table( peakFreqMat(:,:,pi), ...
               'VariableNames', compose('Freq_%0.3fHz',target_freqs));
    ampTbl  = array2table( peakAmpMat(:,:,pi), ...
               'VariableNames', compose('Amp_%0.3fHz', target_freqs));
    T = [table(dateCol,'VariableNames',{'Date'}) , freqTbl , ampTbl];
    writetable(T, excel_file,'Sheet',point_ids{pi});
end
fprintf('★ 已输出 Excel -> %s\n', excel_file);

%% ================= 内部函数 =================
    function processPoint(pid, idxPt)
        fprintf('\n─► 测点 %s\n', pid);
        ampDay  = NaN(Nday,nFreq);
        freqDay = NaN(Nday,nFreq);

        for di = 1:Nday
            day    = dates_all(di);
            dayStr = datestr(day,'yyyy-mm-dd');
            [ts,val] = extract_accel_data(root_dir,subfolder,pid,dayStr,dayStr);
            if isempty(ts),  continue; end

            t0 = day + duration(0,30,0);
            t1 = day + duration(0,40,0);
            
            winIdx = ts>=t0 & ts<=t1;
            if ~any(winIdx), continue; end

            % --- 估计采样频率 & 初始 Welch 参数 -----------------
            fs      = 1/median(seconds(diff(ts(winIdx))));
            win_sec = 20;                              % 20 s 窗
            wlen    = round(win_sec*fs);
            if mod(wlen,2)==1, wlen = wlen+1; end
            overlap = round(0.5*wlen);
            nfft    = 2^nextpow2(max(wlen,8192));

            % --- 去掉 NaN，防止 pwelch 报错 --------------------
            x_raw = val(winIdx);
            good  = ~isnan(x_raw) & isfinite(x_raw);
            if nnz(good) < 3          % 有效点太少
                continue;
            end
            x = detrend(x_raw(good));

            % 若有效样本 < 当前窗口，重新缩小 wlen / nfft --------
            if numel(x) < wlen
                wlen    = numel(x);
                overlap = round(0.5*wlen);
                nfft    = 2^nextpow2(max(wlen,512));
            end

            [Pxx,f] = pwelch(x, hamming(wlen), overlap, nfft, fs,'onesided');
            Pdb = 10*log10(Pxx);

            % -------- 备查 PSD 图/fig --------
            psdDir = fullfile(psdRoot,pid);
            if ~exist(psdDir,'dir'), mkdir(psdDir); end

            figPSD = figure('Visible','off','Position',[100 100 900 420]);
            plot(f,Pdb,'k','LineWidth',1); grid on;
            hold on;
            xline(target_freqs,'--r');
            hold off;
            xlabel('频率 (Hz)'); ylabel('PSD (dB)');
            title(sprintf('PSD %s  %s  (00:30–00:40)',pid,dayStr));
            fnamePSD = fullfile(psdDir,sprintf('PSD_%s_%s',pid,dayStr));
            saveas(figPSD,[fnamePSD '.jpg']);
            savefig(figPSD,[fnamePSD '.fig'],'compact');
            close(figPSD);

            % 提峰
            for fi = 1:nFreq
                f0 = target_freqs(fi);
                idxBand = f>=f0-tolerance & f<=f0+tolerance;
                if ~any(idxBand), continue; end

                [pk, idxRel] = max(Pdb(idxBand));
                bandF        = f(idxBand);

                ampDay (di,fi) = pk;
                freqDay(di,fi) = bandF(idxRel);
            end
        end

        peakAmpMat(:,:, idxPt)  = ampDay;
        peakFreqMat(:,:,idxPt)  = freqDay;


        % 绘图：峰值“频率”时程
        fig = figure('Visible','off','Position',[100 100 1000 470]);
        plot(dates_all, freqDay,'LineWidth',1.2);
        grid on; xtickformat('yyyy-MM-dd');
        xlabel('日期'); ylabel('峰值频率 (Hz)');
        
        legend({'一阶','二阶','三阶'},'Location','best');
        title(sprintf('峰值频率时程 %s  (00:30–00:40)', pid));

        fname = fullfile(outDirFig, ...
                 sprintf('SpecFreq_%s_%s_%s', pid, ...
                 datestr(dates_all(1),'yyyymmdd'), ...
                 datestr(dates_all(end),'yyyymmdd')));
        saveas(fig, [fname '.jpg']);
        saveas(fig, [fname '.emf']);
        savefig(fig,[fname '.fig'],'compact');
        close(fig);
    end
end


function [all_time, all_val] = extract_accel_data(root_dir, subfolder, point_id, start_date, end_date)
% 提取加速度数据
all_time=[]; all_val=[];
dn0 = datenum(start_date,'yyyy-mm-dd'); dn1 = datenum(end_date,'yyyy-mm-dd');
dinfo = dir(fullfile(root_dir,'20??-??-??')); folders={dinfo([dinfo.isdir]).name};
dates = folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
for j=1:numel(dates)
    day = dates{j};
    dirp = fullfile(root_dir, day, subfolder);
    if ~exist(dirp,'dir'), continue; end
    files = dir(fullfile(dirp,'*.csv'));
    idx = find(arrayfun(@(f) contains(f.name, point_id), files),1);
    if isempty(idx), continue; end
    fp = fullfile(dirp, files(idx).name);
    % 头部检测
    fid = fopen(fp,'rt');
    h = 0;
    found = false;               % ← 初始化 found
    for k=1:50
        if feof(fid), break; end
        ln = fgetl(fid); h=h+1;
        if contains(ln,'[绝对时间]')
            found = true; 
            break;
        end
    end
    if ~found
       warning('提示：文件 %s 未检测到头部标记 “[绝对时间]”，使用 h=0 读取全部作为数据', fp);
       h = 0;                  % ← 避免把所有行当成 header 跳过
    end
    fclose(fid);

    % ==== 缓存机制开始 =========================
    cacheDir = fullfile(dirp,'cache');
    if ~exist(cacheDir,'dir'), mkdir(cacheDir); end

    [~,name,~] = fileparts(fp);
    cacheFile  = fullfile(cacheDir,[name '.mat']);
    useCache   = false;

    if exist(cacheFile,'file')
        infoCSV = dir(fp);
        infoMAT = dir(cacheFile);
        % 仅当 MAT 更新且较新才使用
        if datenum(infoMAT.date) > datenum(infoCSV.date)
            tmp      = load(cacheFile,'times','vals');
            times    = tmp.times;
            vals     = tmp.vals;
            useCache = true;
        end
    end

    if ~useCache
        % 从 CSV 读取并写缓存
        T = readtable(fp, ...
            'Delimiter',',', ...
            'HeaderLines',h, ...
            'Format','%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
        times = T{:,1};
        vals  = T{:,2};
        save(cacheFile,'times','vals');
    end
    % ==== 缓存机制结束 =========================================

    % === 基础清洗 ===
        % 示例：针对特殊测点额外清洗
        % if strcmp(point_id, 'GB-DIS-G05-001-02Y')
        %     vals = clean_threshold(vals, times, struct('min', -20, 'max', 20, 't_range', [datetime('2025-02-28 20:00:00'), datetime('2025-02-28 23:00:00')]));
        % end
         if strcmp(point_id, 'GB-VIB-G06-002-01')
            vals = clean_threshold(vals, times, struct('min', -500, 'max', 400, 't_range', []));
         end
         if strcmp(point_id, 'GB-VIB-G04-001-01')
            vals = clean_threshold(vals, times, struct('min', -500, 'max', 500, 't_range', [datetime('2025-05-12 20:00:00'), datetime('2025-05-15 22:00:00')]));
         end
         if strcmp(point_id, 'GB-VIB-G05-003-01')
            vals = clean_threshold(vals, times, struct('min', -500, 'max', 300, 't_range', [datetime('2025-04-26 20:00:00'), datetime('2025-05-18 22:00:00')]));
         end
         if strcmp(point_id, 'GB-VIB-G05-002-01')
            vals = clean_threshold(vals, times, struct('min', -500, 'max', 500, 't_range', [datetime('2025-05-12 20:00:00'), datetime('2025-05-15 22:00:00')]));
         end
          if strcmp(point_id, 'GB-VIB-G06-001-01')
            vals = clean_threshold(vals, times, struct('min', -500, 'max', 500, 't_range', [datetime('2025-05-12 20:00:00'), datetime('2025-05-15 22:00:00')]));
          end
          if strcmp(point_id, 'GB-VIB-G06-003-01')
            vals = clean_threshold(vals, times, struct('min', -500, 'max', 500, 't_range', [datetime('2025-05-12 20:00:00'), datetime('2025-05-15 22:00:00')]));
          end 
        if strcmp(point_id, 'GB-VIB-G07-001-01')
            vals = clean_threshold(vals, times, struct('min', -500, 'max', 420, 't_range', []));
        end
        % =====================
    all_time = [all_time; times];
    all_val  = [all_val;  vals];

end
[all_time,ix]=sort(all_time); all_val=all_val(ix);
end