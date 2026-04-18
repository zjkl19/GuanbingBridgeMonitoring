function analyze_rainfall_points(root_dir, point_ids, start_date, end_date, excel_file, subfolder, cfg)
% analyze_rainfall_points 批量绘制雨量计时程并统计降雨强度/累计降雨量
    if nargin<1||isempty(root_dir),    root_dir = pwd; end
    if nargin<2||isempty(point_ids),    error('请提供 point_ids cell 数组'); end
    if nargin<3||isempty(start_date),   start_date = input('开始日期(yyyy-MM-dd): ','s'); end
    if nargin<4||isempty(end_date),     end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
    if nargin<5||isempty(excel_file),   excel_file = 'rainfall_stats.xlsx'; end
    excel_file = resolve_data_output_path(root_dir, excel_file, 'stats');
    if nargin<6||isempty(subfolder)
        cfg_tmp = load_config();
        if isfield(cfg_tmp,'subfolders') && isfield(cfg_tmp.subfolders,'rainfall')
            subfolder = cfg_tmp.subfolders.rainfall;
        else
            subfolder = '特征值';
        end
    end
    if nargin<7||isempty(cfg),          cfg = load_config(); end

    style = get_style(cfg, 'rainfall');
    nPts = numel(point_ids);
    stats = cell(nPts, 7);

    dn0 = datenum(start_date, 'yyyy-mm-dd');
    dn1 = datenum(end_date,   'yyyy-mm-dd');
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    outDir = fullfile(root_dir, get_style_field(style, 'output_dir', '时程曲线_雨量'));
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    for i = 1:nPts
        pid = point_ids{i};
        fprintf('Processing rainfall %s...\n', pid);
        [all_time, all_val] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'rainfall');
        if isempty(all_val) || isempty(all_time)
            warning('雨量测点 %s 无有效数据，跳过', pid);
            stats{i,1} = pid;
            continue;
        end
        valid = isfinite(all_val) & ~isnat(all_time);
        if ~any(valid)
            warning('雨量测点 %s 无有效数据，跳过', pid);
            stats{i,1} = pid;
            continue;
        end

        t_valid = all_time(valid);
        v_valid = all_val(valid);
        total_mm = calc_total_rainfall_mm(t_valid, v_valid);
        max_val = max(v_valid);
        mean_val = mean(v_valid);

        fig = figure('Position', [100 100 1000 469]); hold on;
        [time_plot, val_plot] = prepare_plot_series(all_time, all_val);
        plot(time_plot, val_plot, 'LineWidth', 1, 'Color', get_color(style, 1));
        avg_val = round(mean_val, 2);
        yline(avg_val, '--r', sprintf('平均降雨强度 %.2f mm/h', avg_val), ...
            'LabelHorizontalAlignment', 'center', 'LabelVerticalAlignment', 'bottom');

        numDiv = 4;
        tk = linspace(dn0, dn1, numDiv+1);
        xt = datetime(tk, 'ConvertFrom', 'datenum');
        ax = gca;
        ax.XLim = [xt(1) xt(end)];
        ax.XTick = xt;
        xtickformat('yyyy-MM-dd');
        xlabel('时间');
        ylabel(get_style_field(style, 'ylabel', '降雨强度 (mm/h)'));
        apply_ylim(style, pid);
        grid on; grid minor;
        title(sprintf('%s %s', get_style_field(style, 'title_prefix', '降雨强度时程'), pid));

        base = sprintf('Rainfall_%s_%s_%s', pid, datestr(dn0,'yyyymmdd'), datestr(dn1,'yyyymmdd'));
        save_plot_bundle(fig, outDir, [base '_' timestamp]);

        stats{i,1} = pid;
        stats{i,2} = format_time(min(t_valid));
        stats{i,3} = format_time(max(t_valid));
        stats{i,4} = sum(valid);
        stats{i,5} = max_val;
        stats{i,6} = mean_val;
        stats{i,7} = total_mm;
    end

    T = cell2table(stats, 'VariableNames', ...
        {'PointID','StartTime','EndTime','ValidCount','Max_mm_h','Mean_mm_h','Total_mm'});
    writetable(T, excel_file);
    fprintf('雨量统计结果已保存至 %s\n', excel_file);
end

function total_mm = calc_total_rainfall_mm(t, v)
    total_mm = NaN;
    if isempty(t) || isempty(v)
        return;
    end
    [t, order] = sort(t(:));
    v = v(order);
    valid = ~isnat(t) & isfinite(v);
    t = t(valid);
    v = v(valid);
    if numel(v) < 2
        total_mm = 0;
        return;
    end
    dt_hours = hours(diff(t));
    good = isfinite(dt_hours) & dt_hours >= 0;
    if ~any(good)
        total_mm = 0;
        return;
    end
    vv = (v(1:end-1) + v(2:end)) / 2;
    total_mm = sum(vv(good) .* dt_hours(good));
end

function apply_ylim(style, pid)
    yl = resolve_named_ylim(get_style_field(style,'ylims', []), pid, get_style_field(style,'ylim', []));
    if is_truthy(get_style_field(style,'ylim_auto', true))
        ylim auto;
    elseif is_valid_ylim(yl)
        ylim(yl);
    elseif ~isempty(get_style_field(style,'ylim', []))
        ylim(get_style_field(style,'ylim', []));
    else
        ylim auto;
    end
end

function style = get_style(cfg, key)
    style = struct();
    if isfield(cfg,'plot_styles') && isfield(cfg.plot_styles, key)
        style = cfg.plot_styles.(key);
    end
end

function val = get_style_field(style, field, default)
    if isstruct(style) && isfield(style, field)
        val = style.(field);
    else
        val = default;
    end
end

function c = get_color(style, idx)
    c = [];
    if isfield(style,'colors') && isnumeric(style.colors)
        if size(style.colors,1) >= idx
            c = style.colors(idx,:);
        end
    end
    if isempty(c)
        cmap = lines(3);
        c = cmap(idx,:);
    end
end

function yl = resolve_named_ylim(ylims, name, default_ylim)
    yl = default_ylim;
    if isempty(ylims) || isempty(name)
        return;
    end
    safe_name = strrep(name, '-', '_');
    if isstruct(ylims)
        if isfield(ylims, name)
            yl = ylims.(name);
            return;
        end
        if isfield(ylims, safe_name)
            yl = ylims.(safe_name);
            return;
        end
        if isfield(ylims, 'name') && isfield(ylims, 'ylim')
            for i = 1:numel(ylims)
                if strcmp(to_char(ylims(i).name), name)
                    yl = ylims(i).ylim;
                    return;
                end
            end
        end
    elseif iscell(ylims)
        for i = 1:numel(ylims)
            item = ylims{i};
            if isstruct(item) && isfield(item, 'name') && isfield(item, 'ylim') && strcmp(to_char(item.name), name)
                yl = item.ylim;
                return;
            end
        end
    end
end

function ok = is_valid_ylim(v)
    ok = isnumeric(v) && numel(v) == 2 && all(isfinite(v)) && v(2) > v(1);
end

function tf = is_truthy(v)
    tf = (islogical(v) && isscalar(v) && v) || ...
        (isnumeric(v) && isscalar(v) && ~isnan(v) && v ~= 0);
end

function txt = to_char(v)
    if isstring(v)
        txt = char(v);
    elseif ischar(v)
        txt = v;
    else
        txt = char(string(v));
    end
end

function s = format_time(t)
    if isempty(t) || isnat(t)
        s = '';
    else
        s = datestr(t, 'yyyy-mm-dd HH:MM:SS');
    end
end
