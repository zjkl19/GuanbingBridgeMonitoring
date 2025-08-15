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
% 新增：
%   - 生成两组（G05/G06）高通滤波后的“时程曲线图”，并保存 JPG/EMF/FIG。
%
% 输出：
%   - 箱线图（G05 一张，G06 一张）：JPG/EMF/FIG
%   - 统计 TXT + Excel（Min/Q1/Median/Q3/Max/Mean/Std/Count）
%   - 时程曲线（G05 一张，G06 一张）：JPG/EMF/FIG
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
outdir_ts  = fullfile(root_dir, '时程曲线_动应变_高通滤波');
if ~exist(outdir_ts,'dir'), mkdir(outdir_ts); end

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
[dataG05, labelsG05, tsG05] = collect_group_data(groupG05);
make_boxplot_and_stats(dataG05, labelsG05, 'G05', outdir);
plot_timeseries_group(tsG05, labelsG05, 'G05', outdir_ts, dt0, dt1, ylim_manual, ylim_rng, tag, ts);

fprintf('\n== 处理 G06 ==\n');
[dataG06, labelsG06, tsG06] = collect_group_data(groupG06);
make_boxplot_and_stats(dataG06, labelsG06, 'G06', outdir);
plot_timeseries_group(tsG06, labelsG06, 'G06', outdir_ts, dt0, dt1, ylim_manual, ylim_rng, tag, ts);

fprintf('\n全部完成。\n');

%% ================= 内部函数 =================

    function [dataMat, labels, tsList] = collect_group_data(pid_list)
        % 对一组 6 个测点，逐个测点汇总“处理后的总体样本” + 收集时程用于绘图
        N = numel(pid_list);
        colData = cell(N,1);
        labels  = pid_list(:).';
        tsList  = struct('pid',cell(N,1),'times',[],'vals',[]);
        for ii = 1:N
            pid = pid_list{ii};
            fprintf('  ▸ 汇总测点 %s ...\n', pid);
            [vals_all, times_all] = process_one_pid(pid);   % ← 返回值+时
            colData{ii} = vals_all(:);                      % 列向量
            tsList(ii).pid   = pid;
            tsList(ii).times = times_all(:);
            tsList(ii).vals  = vals_all(:);
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

    function [vals_all, times_all] = process_one_pid(pid)
        % 遍历日期 -> 定位文件 -> 读缓存/CSV -> 去异常 -> 滤波 -> 修剪 -> 拼接
        dn0 = datenum(start_date,'yyyy-mm-dd');
        dn1 = datenum(end_date,  'yyyy-mm-dd');
        dinfo = dir(fullfile(root_dir,'20??-??-??'));
        folders = {dinfo([dinfo.isdir]).name};
        dates = folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);

        vals_all  = [];
        times_all = [];
        trimN     = round(trim_sec * fs);

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
                v2    = v2(trimN+1:end-trimN);
                times = times(trimN+1:end-trimN);
            end

            % 拼接
            vals_all  = [vals_all;  v2(:)];
            times_all = [times_all; times(:)];
        end

        % 时间最终按时间排序一次，确保递增
        if ~isempty(times_all)
            [times_all, ix] = sort(times_all);
            vals_all = vals_all(ix);
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

    function plot_timeseries_group(tsList, labels, groupName, outdir_ts_, dt0_, dt1_, yl_manual, yl_rng, tag_, ts_)
        % 绘制高通滤波后的“时程曲线”（一张图/组）
        f = figure('Position',[100 100 1100 520]); hold on;

        % 专用配色（6条）
        colors_6 = {
            [0 0 0],         % 黑
            [0 0 1],         % 蓝
            [0 0.7 0],       % 绿
            [1 0.4 0.8],     % 粉
            [1 0.6 0],       % 橙
            [1 0 0]          % 红
        };

        % 逐条曲线
        n = numel(tsList);
        hLines = gobjects(n,1);
        for i = 1:n
            t = tsList(i).times;
            v = tsList(i).vals;
            if isempty(t) || isempty(v), continue; end
            c = colors_6{ min(i, numel(colors_6)) };
            hLines(i) = plot(t, v, 'LineWidth', 1.0, 'Color', c);
        end

        % 轴/网格/标题
        xlabel('时间'); ylabel('应变 (με)');
        title(sprintf('动应变时程（高通滤波后）%s  [%s]', groupName, tag_));
        grid on; grid minor;

        % X 轴范围与刻度（从实际数据确定）
        all_t = vertcat(tsList.times);
        if ~isempty(all_t)
            xmin = min(all_t); xmax = max(all_t);
        else
            xmin = dt0_; xmax = dt1_;
        end
        if xmin == xmax
            xmin = xmin - minutes(1);
            xmax = xmax + minutes(1);
        end
        ax = gca; ax.XLim = [xmin xmax];

        % 5 等分刻度（严格递增检测）
        ticks = datetime(linspace(datenum(xmin), datenum(xmax), 5), 'ConvertFrom','datenum');
        ticks = unique(ticks,'stable');
        if numel(ticks) >= 2 && all(diff(ticks) > duration(0,0,0))
            ax.XTick = ticks;
        else
            ax.XTickMode = 'auto';
        end
        if days(xmax - xmin) >= 1
            xtickformat('yyyy-MM-dd');
        else
            xtickformat('MM-dd HH:mm');
        end

        % Y 轴范围
        if yl_manual
            ylim(yl_rng);
        else
            ylim auto;
        end

        % 图例
        legend(hLines, labels, 'Location','northeast','Box','off');

        % 保存
        base = sprintf('dynstrain_hp_%s_%s', groupName, tag_);
        saveas(f, fullfile(outdir_ts_, [base '_' ts_ '.jpg']));
        saveas(f, fullfile(outdir_ts_, [base '_' ts_ '.emf']));
        savefig(f, fullfile(outdir_ts_, [base '_' ts_ '.fig']), 'compact');
        close(f);
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
