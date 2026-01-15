function analyze_dynamic_strain_boxplot(root_dir, start_date, end_date, varargin)
% analyze_dynamic_strain_boxplot
% ────────────────────────────────────────────────────────────────────────
% 读取 <root>\YYYY-MM-DD\特征值\*.csv 的动应变数据（两组：G05/G06），
% 对每个测点在 start_date~end_date 范围内的全部文件逐个执行：
%   1) 去异常（越界置 NaN）
%   2) 高通滤波（filtfilt，支持NaN掩码回填）
%   3) 边界修剪（可选，默认首尾各 5 s）
% 将所有文件处理后的数据拼接为“该测点的总体样本”，用于箱线图与统计。
%
% 输出：
%   - 箱线图（G05 一张，G06 一张）：JPG/EMF/FIG
%   - 统计 TXT + Excel（Min/Q1/Median/Q3/Max/Mean/Std/Count）
%   - CSV/MAT 读取使用“每文件缓存”：<同目录>\cache\<同名>.mat，仅缓存 times/vals
%
% 用法示例：
%   analyze_dynamic_strain_boxplot('F:\管柄数据\管柄7月数据', '2025-07-01','2025-07-07');
%
% 可选参数（Name-Value）：
%   'Subfolder'        (char)   默认 '特征值'
%   'OutputDir'        (char)   默认 '箱线图结果_高通滤波'
%   'Fs'               (double) 默认 20          % 采样频率
%   'Fc'               (double) 默认 0.1         % 高通截止频率
%   'Whisker'          (double) 默认 300         % 箱线图胡须参数
%   'ShowOutliers'     (logical)默认 false       % 是否显示离群值
%   'YLimManual'       (logical)默认 true
%   'YLimRange'        (1x2 double) 默认 [-30 30]
%   'LowerBound'       (double) 默认 -150        % 去异常阈值
%   'UpperBound'       (double) 默认  150
%   'EdgeTrimSec'      (double) 默认 5           % 每文件滤波后首尾修剪秒数
%
% 作者：ChatGPT  2025-08-15
% ────────────────────────────────────────────────────────────────────────

%% 参数
p = inputParser;
addRequired(p, 'root_dir',   @(s)ischar(s)||isstring(s));
addRequired(p, 'start_date', @(s)ischar(s)||isstring(s));
addRequired(p, 'end_date',   @(s)ischar(s)||isstring(s));
addParameter(p,'Subfolder',   '特征值',         @(s)ischar(s)||isstring(s));
addParameter(p,'OutputDir',   '箱线图结果_高通滤波', @(s)ischar(s)||isstring(s));
addParameter(p,'Fs',          20,               @(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'Fc',          0.1,              @(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'Whisker',     300,              @(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'ShowOutliers',false,            @(x)islogical(x)||ismember(x,[0 1]));
addParameter(p,'YLimManual',  true,             @(x)islogical(x)||ismember(x,[0 1]));
addParameter(p,'YLimRange',   [-30 30],         @(v)isnumeric(v)&&numel(v)==2);
addParameter(p,'LowerBound',  -150,             @(x)isnumeric(x)&&isscalar(x));
addParameter(p,'UpperBound',   150,             @(x)isnumeric(x)&&isscalar(x));
addParameter(p,'EdgeTrimSec',   5,              @(x)isnumeric(x)&&isscalar(x)&&x>=0);

parse(p, root_dir, start_date, end_date, varargin{:});
opt = p.Results;

root_dir   = char(opt.root_dir);
subfolder  = char(opt.Subfolder);
outdir     = fullfile(root_dir, char(opt.OutputDir));
if ~exist(outdir,'dir'), mkdir(outdir); end

fs         = opt.Fs;
fc         = opt.Fc;
whisker    = opt.Whisker;
showOut    = opt.ShowOutliers;
ylim_manual= opt.YLimManual;
ylim_rng   = opt.YLimRange;
lo_bd      = opt.LowerBound;
hi_bd      = opt.UpperBound;
trim_sec   = opt.EdgeTrimSec;

% 两组固定测点
groupG05 = {'GB-RSG-G05-001-01','GB-RSG-G05-001-02','GB-RSG-G05-001-03', ...
            'GB-RSG-G05-001-04','GB-RSG-G05-001-05','GB-RSG-G05-001-06'};
groupG06 = {'GB-RSG-G06-001-01','GB-RSG-G06-001-02','GB-RSG-G06-001-03', ...
            'GB-RSG-G06-001-04','GB-RSG-G06-001-05','GB-RSG-G06-001-06'};

dt0 = datetime(start_date,'InputFormat','yyyy-MM-dd');
dt1 = datetime(end_date,  'InputFormat','yyyy-MM-dd');
tag = [datestr(dt0,'yyyymmdd') '-' datestr(dt1,'yyyymmdd')];
ts  = datestr(now,'yyyy-mm-dd_HH-MM-SS');

% 设计高通滤波器
[b,a] = butter(1, fc/(fs/2), 'high');

fprintf('日期范围：%s ~ %s，目录：%s\\YYYY-MM-DD\\%s\n', start_date, end_date, root_dir, subfolder);
fprintf('Fs=%.3f Hz, Fc=%.3f Hz，高通一阶（filtfilt），边界修剪 %.1f s\n', fs, fc, trim_sec);

%% 处理两组
fprintf('\n== 处理 G05 ==\n');
[dataG05, labelsG05] = collect_group_data(groupG05);
make_boxplot_and_stats(dataG05, labelsG05, 'G05', outdir);

fprintf('\n== 处理 G06 ==\n');
[dataG06, labelsG06] = collect_group_data(groupG06);
make_boxplot_and_stats(dataG06, labelsG06, 'G06', outdir);

fprintf('\n全部完成。\n');

%% ================= 内部函数 =================

    function [dataMat, labels] = collect_group_data(pid_list)
        % 对一组 6 个测点，逐个测点汇总“处理后的总体样本”
        N = numel(pid_list);
        colData = cell(N,1);
        labels  = pid_list(:).';
        for ii = 1:N
            pid = pid_list{ii};
            fprintf('  ▸ 汇总测点 %s ...\n', pid);
            vals_all = process_one_pid(pid);
            colData{ii} = vals_all(:);    % 列向量
            fprintf('    总样本数（非 NaN）：%d\n', nnz(~isnan(vals_all)));
        end
        % 填充为 NaN 对齐的矩阵（箱线图可接受 NaN）
        Lmax = max(cellfun(@numel, colData));
        dataMat = NaN(Lmax, N);
        for ii = 1:N
            v = colData{ii};
            dataMat(1:numel(v), ii) = v;
        end
    end

    function vals_all = process_one_pid(pid)
        % 遍历日期 -> 定位文件 -> 读缓存/CSV -> 去异常 -> 滤波 -> 修剪 -> 拼接
        dn0 = datenum(start_date,'yyyy-mm-dd');
        dn1 = datenum(end_date,  'yyyy-mm-dd');
        dinfo = dir(fullfile(root_dir,'20??-??-??'));
        folders = {dinfo([dinfo.isdir]).name};
        dates = folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);

        vals_all = [];
        trimN    = round(trim_sec * fs);

        for jj = 1:numel(dates)
            day = dates{jj};
            dirp = fullfile(root_dir, day, subfolder);
            if ~exist(dirp,'dir'), continue; end

            files = dir(fullfile(dirp,'*.csv'));
            idx   = find(arrayfun(@(f) contains(f.name, pid), files), 1);
            if isempty(idx), continue; end

            fp = fullfile(files(idx).folder, files(idx).name);
            [times, vals] = read_csv_with_cache(fp);

            if isempty(vals), continue; end

            % 去异常（越界置 NaN）
            vals(vals<lo_bd | vals>hi_bd) = NaN;

            % 高通滤波（NaN→0，再回填 NaN）
            v2 = vals;
            maskNaN = isnan(v2) | ~isfinite(v2);
            v2(maskNaN) = 0;
            v2 = filtfilt(b,a,v2);
            v2(maskNaN) = NaN;

            % 边界修剪：首尾各 trimN 样本（若足够长）
            if trimN>0 && numel(v2)>2*trimN
                v2 = v2(trimN+1:end-trimN);
            end

            % 拼接
            vals_all = [vals_all; v2(:)];
        end
    end

    function make_boxplot_and_stats(dataMat, labels, groupName, outdir_)
        % 绘制箱线图
        f = figure('Position',[100 100 1100 520]);
        if showOut
            gf = boxplot(dataMat, 'Labels', labels, ...
                'LabelOrientation', 'horizontal', 'Whisker', whisker);
        else
            gf = boxplot(dataMat, 'Labels', labels, ...
                'LabelOrientation', 'horizontal', 'Whisker', whisker, 'Symbol','');
        end
        xlabel('测点'); ylabel('应变 (με)');
        title(sprintf('动应变箱线图（高通滤波后）%s  [%s]', groupName, tag));
        xtickangle(45);
        grid on; grid minor;
        if ylim_manual
            ylim(ylim_rng);
        else
            ylim auto;
        end

        % 保存图像
        base = sprintf('boxplot_%s_%s', groupName, tag);
        saveas(f, fullfile(outdir_, [base '_' ts '.jpg']));
        saveas(f, fullfile(outdir_, [base '_' ts '.emf']));
        savefig(f, fullfile(outdir_, [base '_' ts '.fig']), 'compact');
        close(f);

        % 统计并保存
        statsTbl = calc_stats_table(dataMat, labels);
        % TXT
        txtPath = fullfile(outdir_, sprintf('boxplot_stats_%s_%s.txt', groupName, tag));
        write_stats_txt(txtPath, statsTbl);
        % 追加到 Excel（每组一个 Sheet）
        xlsxPath = fullfile(outdir_, sprintf('boxplot_stats_%s.xlsx', tag));
        writetable(statsTbl, xlsxPath, 'Sheet', groupName);
        fprintf('  ▸ %s 统计写入：\n    %s（TXT）\n    %s（Excel Sheet=%s）\n', ...
            groupName, txtPath, xlsxPath, groupName);
    end

    function T = calc_stats_table(dataMat, labels)
        % dataMat: L x N（NaN 允许）
        N = numel(labels);
        mins  = NaN(N,1); q1s = NaN(N,1); meds = NaN(N,1); q3s = NaN(N,1);
        maxs  = NaN(N,1); means=NaN(N,1); stds=NaN(N,1); cnts=NaN(N,1);
        for k = 1:N
            v = dataMat(:,k);
            v = v(~isnan(v) & isfinite(v));
            if isempty(v), continue; end
            mins(k)  = min(v);
            q1s(k)   = quantile(v,0.25);
            meds(k)  = quantile(v,0.50);
            q3s(k)   = quantile(v,0.75);
            maxs(k)  = max(v);
            means(k) = mean(v);
            stds(k)  = std(v);
            cnts(k)  = numel(v);
        end
        T = table(labels(:), mins, q1s, meds, q3s, maxs, means, stds, cnts, ...
            'VariableNames', {'PointID','Min','Q1','Median','Q3','Max','Mean','Std','Count'});
    end

    function write_stats_txt(path, T)
        fid = fopen(path,'wt');
        fprintf(fid, '动应变箱线图统计（高通滤波后）  日期范围：%s ~ %s\n', start_date, end_date);
        fprintf(fid, '列：PointID, Min, Q1, Median, Q3, Max, Mean, Std, Count\n\n');
        for i = 1:height(T)
            fprintf(fid, '%s\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%d\n', ...
                T.PointID{i}, T.Min(i), T.Q1(i), T.Median(i), T.Q3(i), ...
                T.Max(i), T.Mean(i), T.Std(i), T.Count(i));
        end
        fclose(fid);
    end

    function [times, vals] = read_csv_with_cache(fp)
        % 与 analyze_strain_points 相同的缓存策略：仅缓存原始 times/vals
        % 头部检测 up to 50 行，找 '[绝对时间]'，未找到则 HeaderLines=0
        times = []; vals = [];

        % 缓存文件路径
        cacheDir = fullfile(fileparts(fp), 'cache');
        if ~exist(cacheDir,'dir'), mkdir(cacheDir); end
        [~, name, ~] = fileparts(fp);
        cacheFile = fullfile(cacheDir, [name '.mat']);
        useCache  = false;

        if exist(cacheFile,'file')
            infoCSV = dir(fp);
            infoMAT = dir(cacheFile);
            if datenum(infoMAT.date) > datenum(infoCSV.date)
                tmp   = load(cacheFile,'times','vals');
                times = tmp.times;
                vals  = tmp.vals;
                useCache = true;
            end
        end

        if ~useCache
            % 检测 HeaderLines
            fid = fopen(fp,'rt');
            h = 0; found=false; k=0;
            while k<50 && ~feof(fid)
                ln = fgetl(fid); k=k+1; h=h+1;
                if contains(ln,'[绝对时间]'), found=true; break; end
            end
            fclose(fid);
            if ~found
                warning('提示：文件 %s 未检测到头部标记“[绝对时间]”，使用 HeaderLines=0 读取。', fp);
                h = 0;
            end
            % 读取 CSV
            T = readtable(fp, 'Delimiter', ',', 'HeaderLines', h, ...
                'Format','%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
            times = T{:,1};
            vals  = T{:,2};
            % 写缓存（只存原始）
            save(cacheFile,'times','vals');
        end
    end

end
