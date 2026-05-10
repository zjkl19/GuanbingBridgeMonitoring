function analyze_cable_accel_spectrum_points(root_dir,start_date,end_date,point_ids,...
                                       excel_file,subfolder,target_freqs, ...
                                       tolerance,use_parallel,cfg)
% analyze_cable_accel_spectrum_points
%   对给定测点在 [start_date,end_date] 范围内每日 05:30-05:40 的加速度信号
%   计算 Welch PSD，提取 target_freqs±tolerance Hz 的峰值频率与幅值。
%   使用 load_timeseries_range 统一读取与清洗。

    if nargin<1||isempty(root_dir),  root_dir = pwd; end
    if nargin<2||isempty(start_date), error('必须指定 start_date'); end
    if nargin<3||isempty(end_date),   error('必须指定 end_date');   end
    if nargin<10||isempty(cfg),        cfg = load_config();          end
    if nargin<4||isempty(point_ids)
        point_ids = get_points(cfg, 'cable_accel_spectrum', []);
        if isempty(point_ids)
            point_ids = get_points(cfg, 'cable_accel', []);
        end
        if isempty(point_ids)
            point_ids = get_points(cfg, 'cable_force', []);
        end
        if isempty(point_ids)
            point_ids = {'GB-VIB-G04-001-01','GB-VIB-G05-001-01',...
                         'GB-VIB-G05-002-01','GB-VIB-G05-003-01',...
                         'GB-VIB-G06-001-01','GB-VIB-G06-002-01',...
                         'GB-VIB-G06-003-01','GB-VIB-G07-001-01'};
        end
    end
    if nargin<5||isempty(excel_file),  excel_file = 'cable_accel_spec_stats.xlsx'; end
    excel_file = resolve_data_output_path(root_dir, excel_file, 'stats');
    if nargin<6||isempty(subfolder)
        cfg_tmp = load_config();
        if isfield(cfg_tmp,'subfolders') && isfield(cfg_tmp.subfolders,'cable_accel_raw')
            subfolder = cfg_tmp.subfolders.cable_accel_raw;
        elseif isfield(cfg_tmp,'subfolders') && isfield(cfg_tmp.subfolders,'cable_accel')
            subfolder = cfg_tmp.subfolders.cable_accel;
        else
            subfolder  = '索力加速度';
        end
    end
    if nargin<7||isempty(target_freqs)
        target_freqs = get_cable_spec_param(cfg, 'target_freqs', [1.150 1.480 2.310]);
    end
    if nargin<8||isempty(tolerance)
        tolerance  = get_cable_spec_param(cfg, 'tolerance', 0.15);
    end
    if nargin<9,  use_parallel = false;                                    end

    style = get_style(cfg, 'cable_accel_spectrum');

    outDirFig = fullfile(root_dir,'频谱峰值曲线_索力加速度');
    bms.core.PathResolver.ensureDir(outDirFig);

    outDirForce = fullfile(root_dir,'索力时程图');
    bms.core.PathResolver.ensureDir(outDirForce);

    outDirForceGroup = fullfile(root_dir,'索力时程图_组图');
    bms.core.PathResolver.ensureDir(outDirForceGroup);

    psdRoot = fullfile(root_dir,'PSD_备查_索力加速度');
    bms.core.PathResolver.ensureDir(psdRoot);

    dates_all = (datetime(start_date):days(1):datetime(end_date)).';
    Nday      = numel(dates_all);


    nPts  = numel(point_ids);
    [theor_freqs, theor_labels] = get_cable_spec_theor(cfg);
    force_groups = get_groups(cfg, 'cable_force');
    force_series_all = cell(nPts, 1);
    force_valid_all = false(nPts, 1);

    if use_parallel
        p = gcp('nocreate'); if isempty(p), parpool('local'); end
    end

    for ii = 1:nPts
        pid = point_ids{ii};
        fprintf('\n---- 测点 %s ----\n', pid);

        [pt_target_freqs, pt_tol] = get_point_spec_params(cfg, pid, target_freqs, tolerance);
        nFreqPt = numel(pt_target_freqs);
        ampDay  = NaN(Nday,nFreqPt);
        freqDay = NaN(Nday,nFreqPt);

        if use_parallel
            parfor di = 1:Nday
                [ampDay(di,:), freqDay(di,:)] = process_one_day( ...
                    dates_all(di), pid, root_dir, subfolder, pt_target_freqs, pt_tol, psdRoot, style, cfg);
            end
        else
            for di = 1:Nday
                [ampDay(di,:), freqDay(di,:)] = process_one_day( ...
                    dates_all(di), pid, root_dir, subfolder, pt_target_freqs, pt_tol, psdRoot, style, cfg);
            end
        end

        [rho, L, force_decimals, has_params] = bms.analyzer.CableForceService.params(cfg, pid);
        force_ylim = bms.analyzer.CableForceService.resolveYLim(cfg, pid, style);
        forceSeries = bms.analyzer.CableForceService.compute(freqDay(:,1), rho, L, force_decimals);
        force_warn_lines = bms.analyzer.CableForceService.warnLines(cfg, pid, style, '');
        force_series_all{ii} = forceSeries;
        force_valid_all(ii) = any(isfinite(forceSeries));
        if ~has_params
            warning('测点 %s 未配置 rho/L，索力将为 NaN', pid);
        end

        % 写 Excel（每个测点一个 Sheet）
        dateCol = dates_all(:);
        freqTbl = array2table(freqDay, ...
                   'VariableNames', compose('Freq_%0.3fHz',pt_target_freqs));
        ampTbl  = array2table(ampDay, ...
                   'VariableNames', compose('Amp_%0.3fHz', pt_target_freqs));
        forceTbl = table(forceSeries, 'VariableNames',{'CableForce_kN'});
        T = [table(dateCol,'VariableNames',{'Date'}) , freqTbl , ampTbl , forceTbl];
        bms.io.StatsWriter.writeModuleTableChecked(T, excel_file, 'cable_accel_spectrum', 'Sheet', point_ids{ii});

        % 绘制峰值频率时程与索力时程
        plot_freq_timeseries(dates_all, freqDay, pid, pt_target_freqs, outDirFig, style, theor_freqs, theor_labels, cfg);
        plot_force_timeseries({dates_all}, {forceSeries}, {pid}, pid, outDirForce, style, force_ylim, {force_warn_lines}, cfg);
    end

    group_names = fieldnames(force_groups);
    for gi = 1:numel(group_names)
        group_name = group_names{gi};
        pid_list = normalize_points(force_groups.(group_name));
        if isempty(pid_list)
            continue;
        end

        force_list = {};
        labels = {};
        for pi = 1:numel(pid_list)
            idx = find(strcmp(point_ids, pid_list{pi}), 1, 'first');
            if isempty(idx) || ~force_valid_all(idx)
                continue;
            end
            force_list{end+1,1} = force_series_all{idx}; %#ok<AGROW>
            labels{end+1,1} = pid_list{pi}; %#ok<AGROW>
        end
        if isempty(labels)
            continue;
        end

        warn_line_sets = cell(numel(labels), 1);
        for pi = 1:numel(labels)
            warn_line_sets{pi} = bms.analyzer.CableForceService.warnLines(cfg, labels{pi}, style, labels{pi});
        end
        group_display_name = build_group_display_name(group_name, labels);
        plot_force_timeseries(repmat({dates_all}, numel(labels), 1), force_list, labels, group_display_name, outDirForceGroup, style, [], warn_line_sets, cfg);
    end

    fprintf('✓ 已输出 Excel -> %s\n', excel_file);
end

function pts = get_points(cfg, key, fallback)
    pts = bms.data.PointResolver.fromConfig(cfg, key, fallback);
end

function groups_cfg = get_groups(cfg, key)
    groups_cfg = struct();
    if ~isfield(cfg,'groups') || ~isfield(cfg.groups, key)
        return;
    end
    val = cfg.groups.(key);
    if isstruct(val)
        groups_cfg = val;
    elseif iscell(val)
        for i = 1:numel(val)
            groups_cfg.(sprintf('G%d', i)) = val{i};
        end
    end
end

function style = get_style(cfg, key)
    defaults = struct();
    defaults.psd_ylabel        = 'PSD (dB)';
    defaults.psd_title_prefix  = 'PSD';
    defaults.psd_color         = [0 0 0];
    defaults.freq_ylabel       = '峰值频率 (Hz)';
    defaults.freq_title_prefix = '峰值频率时程';
    defaults.colors            = {[0 0 1],[1 0 0],[0 0.7 0],[0.5 0 0.7]};
    defaults.force_ylabel       = '索力 (kN)';
    defaults.force_title_prefix = '索力时程';
    defaults.force_color         = [0 0.447 0.741];
    defaults.force_ylim          = [];
    defaults.force_alarm_colors  = [0.929 0.694 0.125; 0.85 0.1 0.1];
    style = bms.config.ConfigReader.getPlotStyle(cfg, key, defaults);
end

function val = get_cable_spec_param(cfg, field, defaultVal)
    val = defaultVal;
    if isfield(cfg, 'cable_accel_spectrum_params') && isstruct(cfg.cable_accel_spectrum_params)
        ps = cfg.cable_accel_spectrum_params;
        if isfield(ps, field) && ~isempty(ps.(field))
            val = ps.(field);
        end
    end
end

function [freqs, labels] = get_cable_spec_theor(cfg)
    freqs = [];
    labels = {};
    if isfield(cfg, 'cable_accel_spectrum_params') && isstruct(cfg.cable_accel_spectrum_params)
        ps = cfg.cable_accel_spectrum_params;
        if isfield(ps, 'theor_freqs'), freqs = ps.theor_freqs; end
        if isfield(ps, 'theor_labels'), labels = ps.theor_labels; end
    end
end

function [pt_target_freqs, pt_tol] = get_point_spec_params(cfg, pid, target_freqs, tolerance)
    pt_target_freqs = target_freqs;
    pt_tol = tolerance;
    if isempty(pt_target_freqs)
        pt_target_freqs = get_cable_spec_param(cfg, 'target_freqs', [1.150 1.480 2.310]);
    end
    if isempty(pt_tol)
        pt_tol = get_cable_spec_param(cfg, 'tolerance', 0.15);
    end

    if isfield(cfg,'per_point') && isfield(cfg.per_point,'cable_accel')
        safe_id = strrep(pid, '-', '_');
        if isfield(cfg.per_point.cable_accel, safe_id)
            pt = cfg.per_point.cable_accel.(safe_id);
            if isfield(pt,'target_freqs') && ~isempty(pt.target_freqs)
                pt_target_freqs = pt.target_freqs;
            end
            if isfield(pt,'tolerance') && ~isempty(pt.tolerance)
                pt_tol = pt.tolerance;
            end
        end
    end
end

% =========================================================================
function [ampRow, freqRow] = process_one_day(day, pid, root_dir, subfolder, target_freqs, tolerance, psdRoot, style, cfg)
    [ampRow, freqRow] = bms.analyzer.SpectrumPeakService.processOneDay( ...
        day, pid, root_dir, subfolder, 'cable_accel', target_freqs, tolerance, psdRoot, style, cfg);
end

% =========================================================================
function plot_freq_timeseries(dates_all, freqDay, pid, target_freqs, outDirFig, style, theor_freqs, theor_labels, cfg)
    if nargin < 9
        cfg = struct();
    end
    fig = figure('Visible','off','Position',[100 100 1000 470]);
    hold on;
    colors = normalize_colors(style.colors);
    h = gobjects(numel(target_freqs),1);
    hasLine = false(numel(target_freqs),1);
    for k = 1:numel(target_freqs)
        [dates_plot, freq_plot] = prepare_plot_series(dates_all, freqDay(:,k));
        if isempty(dates_plot) || isempty(freq_plot) || ~any(isfinite(freq_plot))
            continue;
        end
        if k <= numel(colors)
            h(k) = plot(dates_plot, freq_plot, 'LineWidth', 1.2, 'Color', colors{k});
        else
            h(k) = plot(dates_plot, freq_plot, 'LineWidth', 1.2);
        end
        hasLine(k) = isgraphics(h(k));
    end
    grid on; xtickformat('yyyy-MM-dd');
    xlabel('日期'); ylabel(style.freq_ylabel);
    labels = arrayfun(@(k,f)sprintf('峰%d (%.3fHz)',k,f), (1:numel(target_freqs)).', target_freqs(:), 'UniformOutput', false);
    if any(hasLine)
        legend(h(hasLine), labels(hasLine), 'Location', 'eastoutside');
    end
    title(sprintf('%s %s', style.freq_title_prefix, pid));

    if nargin < 7 || isempty(theor_freqs)
        theor_freqs = [];
    end
    if nargin < 8 || isempty(theor_labels)
        theor_labels = arrayfun(@(f) sprintf('理论频率 %.3fHz', f), theor_freqs, 'UniformOutput', false);
    end

    dataMin = min(freqDay,[],'all','omitnan');
    dataMax = max(freqDay,[],'all','omitnan');
    if ~isempty(dataMin) && ~isempty(dataMax) && isfinite(dataMin) && isfinite(dataMax)
        vals_min = dataMin;
        vals_max = dataMax;
        if ~isempty(theor_freqs)
            vals_min = min([vals_min; theor_freqs(:)]);
            vals_max = max([vals_max; theor_freqs(:)]);
        end
        ymin = vals_min; ymax = vals_max;
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

    for k = 1:numel(theor_freqs)
        c = [0 0 0];
        if k <= numel(h) && isgraphics(h(k))
            c = get(h(k),'Color');
        end
        yline(theor_freqs(k), '--', 'Color', c, 'LineWidth', 1, 'HandleVisibility','off');
        text(xleft + xoff, theor_freqs(k) + yoff, theor_labels{k}, ...
            'Color', c, 'FontSize', 9, 'VerticalAlignment','bottom');
    end
    hold off;

    fname = fullfile(outDirFig, ...
             sprintf('SpecFreq_%s_%s_%s', pid, ...
             datestr(dates_all(1),'yyyymmdd'), ...
             datestr(dates_all(end),'yyyymmdd')));
    [freq_dir, freq_name] = fileparts(fname);
    bms.plot.PlotService.saveModuleBundle(fig, freq_dir, freq_name, cfg);
end


function plot_force_timeseries(times_list, force_list, labels, name_tag, out_dir, style, force_ylim, warn_line_sets, cfg)
    if nargin < 9
        cfg = struct();
    end
    valid = false(numel(force_list), 1);
    for i = 1:numel(force_list)
        valid(i) = ~isempty(force_list{i}) && any(isfinite(force_list{i}));
    end
    if ~any(valid)
        warning('测点/组 %s 索力全为 NaN，跳过绘图', name_tag);
        return;
    end

    fig = figure('Visible','off','Position',[100 100 1000 470]);
    hold on;
    colors = normalize_colors(style.colors);
    h = gobjects(numel(force_list),1);
    for i = 1:numel(force_list)
        if ~valid(i)
            continue;
        end
        if isscalar(force_list)
            c = style.force_color;
        elseif i <= numel(colors)
            c = colors{i};
        else
            cmap = lines(numel(force_list));
            c = cmap(i,:);
        end
        [times_plot, force_plot] = prepare_plot_series(times_list{i}, force_list{i});
        if isempty(times_plot) || isempty(force_plot) || ~any(isfinite(force_plot))
            continue;
        end
        h(i) = plot(times_plot, force_plot, 'LineWidth', 1.2, 'Color', c);
    end
    grid on; xtickformat('yyyy-MM-dd');
    xlabel('日期'); ylabel(style.force_ylabel);
    title(sprintf('%s %s', style.force_title_prefix, name_tag));

    good_lines = h(isgraphics(h));
    if numel(good_lines) > 1
        legend(good_lines, labels(valid), 'Location', 'eastoutside');
    end

    all_warn_lines = {};
    if nargin >= 8 && ~isempty(warn_line_sets)
        for i = 1:numel(warn_line_sets)
            warn_lines_i = warn_line_sets{i};
            if isempty(warn_lines_i)
                continue;
            end
            for k = 1:numel(warn_lines_i)
                wl = warn_lines_i{k};
                if ~isstruct(wl) || ~isfield(wl,'y') || ~isnumeric(wl.y) || ~isfinite(wl.y)
                    continue;
                end
                yl = yline(wl.y, '--', bms.analyzer.CableForceService.warnLabel(wl), 'LabelHorizontalAlignment', 'left');
                if isfield(wl,'color') && isnumeric(wl.color) && numel(wl.color)==3
                    yl.Color = reshape(wl.color,1,3);
                end
                yl.LineWidth = 1.0;
                all_warn_lines{end+1,1} = wl; %#ok<AGROW>
            end
        end
    end

    if nargin >= 7 && ~isempty(force_ylim)
        ylim(force_ylim);
    else
        dataMin = NaN;
        dataMax = NaN;
        for i = 1:numel(force_list)
            if ~valid(i)
                continue;
            end
            dataMin = min([dataMin; min(force_list{i},[],'all','omitnan')],[],'omitnan');
            dataMax = max([dataMax; max(force_list{i},[],'all','omitnan')],[],'omitnan');
        end
        warn_vals = cellfun(@(x) x.y, all_warn_lines(cellfun(@(x)isstruct(x)&&isfield(x,'y')&&isnumeric(x.y)&&isfinite(x.y), all_warn_lines)));
        if ~isempty(warn_vals)
            dataMin = min([dataMin; warn_vals(:)], [], 'omitnan');
            dataMax = max([dataMax; warn_vals(:)], [], 'omitnan');
        end
        if isfinite(dataMin) && isfinite(dataMax)
            pad  = max(0.02, 0.05*(dataMax - dataMin));
            ylim([dataMin - 0.5*pad, dataMax + 1.5*pad]);
        end
    end

    first_idx = find(valid, 1, 'first');
    dt0 = times_list{first_idx}(1);
    dt1 = times_list{first_idx}(end);
    fname = fullfile(out_dir, ...
        sprintf('CableForce_%s_%s_%s', sanitize_filename(name_tag), ...
        datestr(dt0,'yyyymmdd'), ...
        datestr(dt1,'yyyymmdd')));
    [force_dir, force_name] = fileparts(fname);
    bms.plot.PlotService.saveModuleBundle(fig, force_dir, force_name, cfg);
end

function pts = normalize_points(v)
    pts = bms.data.PointResolver.normalize(v);
end

function out = sanitize_filename(s)
    out = regexprep(char(string(s)), '[\\/:*?"<>| ]', '_');
end

function name = build_group_display_name(group_name, labels)
    labels = labels(~cellfun(@isempty, labels));
    if isempty(labels)
        name = group_name;
        return;
    end
    if numel(labels) <= 4
        name = strjoin(labels(:).', '-');
    else
        name = group_name;
    end
end

function ccell = normalize_colors(c)
    ccell = bms.plot.PlotService.normalizeColors(c, {});
end
