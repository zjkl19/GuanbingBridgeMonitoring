function analyze_accel_spectrum_points(root_dir,start_date,end_date,point_ids,...
                                       excel_file,subfolder,target_freqs, ...
                                       tolerance,use_parallel,cfg)
% analyze_accel_spectrum_points
%   对给定测点在 [start_date,end_date] 范围内每�?05:30-05:40 的加速度信号
%   计算 Welch PSD，提�?target_freqs±tolerance Hz 的峰值频率与幅值�?
%   使用 load_timeseries_range 统一读取与清洗�?

    if nargin<1||isempty(root_dir),  root_dir = pwd; end
    if nargin<2||isempty(start_date), error('必须指定 start_date'); end
    if nargin<3||isempty(end_date),   error('必须指定 end_date');   end
    if nargin<10||isempty(cfg),        cfg = load_config();          end
    if nargin<4||isempty(point_ids)
        point_ids = get_points(cfg, 'accel_spectrum', []);
        if isempty(point_ids)
            point_ids = get_points(cfg, 'acceleration', ...
                {'GB-VIB-G04-001-01','GB-VIB-G05-001-01',...
                 'GB-VIB-G05-002-01','GB-VIB-G05-003-01',...
                 'GB-VIB-G06-001-01','GB-VIB-G06-002-01',...
                 'GB-VIB-G06-003-01','GB-VIB-G07-001-01'});
        end
    end
    if nargin<5||isempty(excel_file),  excel_file = 'accel_spec_stats.xlsx'; end
    if nargin<6||isempty(subfolder)
        cfg_tmp = load_config();
        if isfield(cfg_tmp,'subfolders') && isfield(cfg_tmp.subfolders,'acceleration_raw')
            subfolder = cfg_tmp.subfolders.acceleration_raw;
        else
            subfolder  = '波形';
        end
    end
    if nargin<7||isempty(target_freqs),target_freqs=[1.150 1.480 2.310];   end
    if nargin<8||isempty(tolerance),   tolerance  = 0.15;                  end
    if nargin<9,  use_parallel = false;                                    end

    style = get_style(cfg, 'accel_spectrum');

    outDirFig = fullfile(root_dir,'频谱峰值曲线_加速度');
    if ~exist(outDirFig,'dir'), mkdir(outDirFig); end

    psdRoot = fullfile(root_dir,'PSD_备查');
    if ~exist(psdRoot,'dir'), mkdir(psdRoot); end

    dates_all = (datetime(start_date):days(1):datetime(end_date)).';
    Nday      = numel(dates_all);

    nPts  = numel(point_ids);
    nFreq = numel(target_freqs);

    peakAmpMat   = NaN(Nday,nFreq,nPts);
    peakFreqMat  = NaN(Nday,nFreq,nPts);

    if use_parallel
        p = gcp('nocreate'); if isempty(p), parpool('local'); end
    end

    for ii = 1:nPts
        pid = point_ids{ii};
        fprintf('\n---- 测点 %s ----\n', pid);
        ampDay  = NaN(Nday,nFreq);
        freqDay = NaN(Nday,nFreq);

        if use_parallel
            parfor di = 1:Nday
                [ampDay(di,:), freqDay(di,:)] = process_one_day(dates_all(di), pid, root_dir, subfolder, target_freqs, tolerance, psdRoot, style, cfg);
            end
        else
            for di = 1:Nday
                [ampDay(di,:), freqDay(di,:)] = process_one_day(dates_all(di), pid, root_dir, subfolder, target_freqs, tolerance, psdRoot, style, cfg);
            end
        end

        peakAmpMat(:,:, ii)  = ampDay;
        peakFreqMat(:,:,ii)  = freqDay;

        % 写 Excel（每个测点一个 Sheet）
        dateCol = dates_all(:);
        freqTbl = array2table( peakFreqMat(:,:,ii), ...
                   'VariableNames', compose('Freq_%0.3fHz',target_freqs));
        ampTbl  = array2table( peakAmpMat(:,:,ii), ...
                   'VariableNames', compose('Amp_%0.3fHz', target_freqs));
        T = [table(dateCol,'VariableNames',{'Date'}) , freqTbl , ampTbl];
        writetable(T, excel_file,'Sheet',point_ids{ii});

        % 绘制峰值频率时程
        plot_freq_timeseries(dates_all, freqDay, pid, target_freqs, outDirFig, style);
    end
    fprintf('✓ 已输出 Excel -> %s\n', excel_file);
end

function pts = get_points(cfg, key, fallback)
    pts = fallback;
    if isfield(cfg,'points') && isfield(cfg.points, key)
        val = cfg.points.(key);
        if iscellstr(val) || (iscell(val) && all(cellfun(@ischar,val)))
            pts = val;
        end
    end
end

function style = get_style(cfg, key)
    % 标量默认样式，避免因颜色矩阵/元胞自动扩展�?struct 数组
    style = struct();
    style.psd_ylabel        = 'PSD (dB)';
    style.psd_title_prefix  = 'PSD';
    style.psd_color         = [0 0 0];
    style.freq_ylabel       = '峰值频率 (Hz)';
    style.freq_title_prefix = '峰值频率时程';
    style.colors            = {[0 0 1],[1 0 0],[0 0.7 0],[0.5 0 0.7]};

    if isfield(cfg,'plot_styles') && isfield(cfg.plot_styles,key)
        ps_all = cfg.plot_styles.(key);
        ps = ps_all(1); % 强制标量
        if isfield(ps,'psd_ylabel'),        style.psd_ylabel = ps.psd_ylabel; end
        if isfield(ps,'psd_title_prefix'),  style.psd_title_prefix = ps.psd_title_prefix; end
        if isfield(ps,'psd_color'),         style.psd_color = ps.psd_color; end
        if isfield(ps,'freq_ylabel'),       style.freq_ylabel = ps.freq_ylabel; end
        if isfield(ps,'freq_title_prefix'), style.freq_title_prefix = ps.freq_title_prefix; end
        if isfield(ps,'colors')
            c = ps.colors;
            if isnumeric(c) && size(c,2)==3
                style.colors = mat2cell(c, ones(size(c,1),1), 3);
            elseif iscell(c)
                style.colors = c;
            end
        end
    end
end

% =========================================================================
function [ampRow, freqRow] = process_one_day(day, pid, root_dir, subfolder, target_freqs, tolerance, psdRoot, style, cfg)
    ampRow  = NaN(1, numel(target_freqs));
    freqRow = NaN(1, numel(target_freqs));

    dayStr = datestr(day,'yyyy-mm-dd');
    [ts,val] = load_timeseries_range(root_dir, subfolder, pid, dayStr, dayStr, cfg, 'acceleration');
    if isempty(ts),  return; end

    t0 = day + duration(5,30,0);
    t1 = day + duration(5,40,0);
    winIdx = ts>=t0 & ts<=t1;
    if ~any(winIdx), return; end

    fs      = 1/median(seconds(diff(ts(winIdx))));
    win_sec = 20;
    wlen    = round(win_sec*fs);
    if mod(wlen,2)==1, wlen = wlen+1; end
    overlap = round(0.5*wlen);
    nfft    = 2^nextpow2(max(wlen,8192));

    x_raw = val(winIdx);
    good  = ~isnan(x_raw) & isfinite(x_raw);
    if nnz(good) < 3
        return;
    end
    x = detrend(x_raw(good));
    if numel(x) < wlen
        wlen    = numel(x);
        overlap = round(0.5*wlen);
        nfft    = 2^nextpow2(max(wlen,512));
    end

    [Pxx,f] = pwelch(x, hamming(wlen), overlap, nfft, fs,'onesided');
    Pdb = 10*log10(Pxx);

    % 备查 PSD
    psdDir = fullfile(psdRoot,pid);
    if ~exist(psdDir,'dir'), mkdir(psdDir); end
    figPSD = figure('Visible','off','Position',[100 100 900 420]);
    plot(f,Pdb,'Color',style.psd_color,'LineWidth',1); grid on; hold on;
    xline(target_freqs,'--r');
    xlabel('频率 (Hz)'); ylabel(style.psd_ylabel);
    title(sprintf('%s %s  %s',style.psd_title_prefix,pid,dayStr));
    fnamePSD = fullfile(psdDir,sprintf('PSD_%s_%s',pid,dayStr));
    saveas(figPSD,[fnamePSD '.jpg']);
    savefig(figPSD,[fnamePSD '.fig'],'compact');
    close(figPSD);

    for fi = 1:numel(target_freqs)
        f0 = target_freqs(fi);
        idxBand = f>=f0-tolerance & f<=f0+tolerance;
        if ~any(idxBand), continue; end

        [pk, idxRel] = max(Pdb(idxBand));
        bandF        = f(idxBand);

        ampRow(fi)  = pk;
        freqRow(fi) = bandF(idxRel);
    end
end

% =========================================================================
function plot_freq_timeseries(dates_all, freqDay, pid, target_freqs, outDirFig, style)
    fig = figure('Visible','off','Position',[100 100 1000 470]);
    hold on;
    colors = normalize_colors(style.colors);
    h = gobjects(numel(target_freqs),1);
    for k = 1:numel(target_freqs)
        if k <= numel(colors)
            h(k) = plot(dates_all, freqDay(:,k), 'LineWidth', 1.2, 'Color', colors{k});
        else
            h(k) = plot(dates_all, freqDay(:,k), 'LineWidth', 1.2);
        end
    end
    grid on; xtickformat('yyyy-MM-dd');
    xlabel('日期'); ylabel(style.freq_ylabel);
    legend(h, compose('峰%d (%.3fHz)', 1:numel(target_freqs), target_freqs), 'Location', 'eastoutside');
    title(sprintf('%s %s', style.freq_title_prefix, pid));

    theor = [0.975, 1.243, 1.528];
    tlabels = { ...
        '理论竖向一阶自振频率 0.975Hz', ...
        '理论竖向二阶自振频率 1.243Hz', ...
        '理论竖向三阶自振频率 1.528Hz' };

    dataMin = min(freqDay,[],'all','omitnan');
    dataMax = max(freqDay,[],'all','omitnan');
    if ~isempty(dataMin) && ~isempty(dataMax) && isfinite(dataMin) && isfinite(dataMax)
        ymin = min([dataMin, theor]);
        ymax = max([dataMax, theor]);
        pad  = max(0.02, 0.05*(ymax - ymin));
        ylim([ymin - 0.5*pad, ymax + 1.5*pad]);
    end

    ax = gca;
    if numel(dates_all) >= 2
        xoff = (dates_all(end) - dates_all(1)) * 0.01;
    else
        xoff = days(1);
    end
    yoff = diff(ylim(ax)) * 0.02;
    xleft = dates_all(1);

    for k = 1:numel(theor)
        c = [0 0 0];
        if k <= numel(h) && isgraphics(h(k))
            c = get(h(k),'Color');
        end
        yline(theor(k), '--', 'Color', c, 'LineWidth', 1, 'HandleVisibility','off');
        text(xleft + xoff, theor(k) + yoff, tlabels{k}, ...
            'Color', c, 'FontSize', 9, 'VerticalAlignment','bottom');
    end
    hold off;

    fname = fullfile(outDirFig, ...
             sprintf('SpecFreq_%s_%s_%s', pid, ...
             datestr(dates_all(1),'yyyymmdd'), ...
             datestr(dates_all(end),'yyyymmdd')));
    saveas(fig, [fname '.jpg']);
    saveas(fig, [fname '.emf']);
    savefig(fig,[fname '.fig'],'compact');
    close(fig);
end

function ccell = normalize_colors(c)
    if isnumeric(c) && size(c,2)==3
        ccell = mat2cell(c, ones(size(c,1),1), 3);
    elseif iscell(c)
        tmp = {};
        for i = 1:numel(c)
            ci = c{i};
            if isnumeric(ci) && numel(ci)==3
                tmp{end+1} = reshape(ci,1,3); %#ok<AGROW>
            end
        end
        ccell = tmp;
    else
        ccell = {};
    end
    if isempty(ccell)
        co = lines( max(1, size(c,1)) );
        ccell = mat2cell(co, ones(size(co,1),1), 3);
    end
end
