function analyze_gnss_points(root_dir, point_ids, start_date, end_date, excel_file, subfolder, cfg)
% analyze_gnss_points 批量绘制 GNSS 位移时程并导出统计结果

    if nargin < 1 || isempty(root_dir),  root_dir = pwd; end
    if nargin < 2 || isempty(point_ids), error('请提供 GNSS point_ids'); end
    if nargin < 3 || isempty(start_date), error('start_date is required'); end
    if nargin < 4 || isempty(end_date),   error('end_date is required'); end
    if nargin < 5 || isempty(excel_file), excel_file = 'gnss_stats.xlsx'; end
    excel_file = resolve_data_output_path(root_dir, excel_file, 'stats');
    if nargin < 7 || isempty(cfg), cfg = load_config(); end

    if nargin < 6 || isempty(subfolder)
        if isfield(cfg, 'subfolders') && isfield(cfg.subfolders, 'gnss')
            subfolder = cfg.subfolders.gnss;
        else
            subfolder = '波形';
        end
    end

    style = get_style(cfg, 'gnss');
    out_dir = fullfile(root_dir, char(string(get_style_field(style, 'output_dir', '时程曲线_GNSS'))));
    bms.core.PathResolver.ensureDir(out_dir);

    dt0 = datetime(start_date, 'InputFormat', 'yyyy-MM-dd');
    dt1 = datetime(end_date, 'InputFormat', 'yyyy-MM-dd');
    if dt1 <= dt0
        dt1 = dt0 + days(1);
    end
    ticks = dt0 + (dt1 - dt0) * (0:4) / 4;

    comp_defs = { ...
        struct('suffix', 'X', 'sensor_type', 'gnss_x', 'label', 'X向位移'), ...
        struct('suffix', 'Y', 'sensor_type', 'gnss_y', 'label', 'Y向位移'), ...
        struct('suffix', 'Z', 'sensor_type', 'gnss_z', 'label', 'Z向位移')};
    colors = normalize_colors(get_style_field(style, 'colors', [0 0.447 0.741; 0.85 0.325 0.098; 0.466 0.674 0.188]));

    stats = cell(0, 10);
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    for i = 1:numel(point_ids)
        pid = point_ids{i};
        fprintf('GNSS point %s ...\n', pid);

        series = struct('label', {}, 'times', {}, 'vals', {});
        for j = 1:numel(comp_defs)
            comp = comp_defs{j};
            [times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, comp.sensor_type);
            if isempty(times) || isempty(vals)
                continue;
            end
            [times, vals] = bms.analyzer.StructuralSeriesService.validSeries(times, vals);
            if isempty(vals)
                continue;
            end

            series(end+1) = struct('label', comp.label, 'times', times, 'vals', vals); %#ok<AGROW>
            stats(end+1, :) = bms.analyzer.StructuralSeriesService.componentStatsRow( ...
                pid, comp.suffix, comp.label, times, vals, 3); %#ok<AGROW>
        end

        if isempty(series)
            warning('GNSS 测点 %s 无有效数据，跳过', pid);
            continue;
        end

        fig = figure('Position', [100 100 1000 469]);
        hold on;
        h_lines = gobjects(numel(series), 1);
        for j = 1:numel(series)
            [times_plot, vals_plot] = prepare_plot_series(series(j).times, series(j).vals);
            color_idx = min(j, size(colors, 1));
            h_lines(j) = plot(times_plot, vals_plot, 'LineWidth', 1.0, 'Color', colors(color_idx, :));
        end

        lg = legend(h_lines, {series.label}, 'Location', 'northeast', 'Box', 'off');
        lg.AutoUpdate = 'off';
        ax = gca;
        ax.XLim = [dt0 dt1];
        ax.XTick = ticks;
        xtickformat('yyyy-MM-dd');
        xlabel('时间');
        ylabel(get_style_field(style, 'ylabel', 'GNSS位移 (mm)'));
        title(sprintf('%s %s', get_style_field(style, 'title_prefix', 'GNSS位移时程'), pid));

        ylim_auto = get_style_field(style, 'ylim_auto', true);
        if is_truthy(ylim_auto)
            ylim auto;
        else
            yl = get_style_field(style, 'ylim', []);
            if is_valid_ylim(yl)
                ylim(yl);
            else
                ylim auto;
            end
        end

        grid on;
        grid minor;

        fname = sanitize_filename(sprintf('GNSS_%s_%s_%s', pid, datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd')));
        bms.plot.PlotService.saveModuleBundle(fig, out_dir, [fname '_' ts], cfg);
    end

    T = bms.analyzer.StructuralSeriesService.componentStatsTable(stats);
    bms.io.StatsWriter.writeModuleTableChecked(T, excel_file, 'gnss');
    fprintf('GNSS stats saved to %s\n', excel_file);
end

function style = get_style(cfg, key)
    style = bms.config.ConfigReader.getPlotStyle(cfg, key);
end

function val = get_style_field(style, field, default)
    val = bms.config.ConfigReader.getField(style, field, default);
end

function colors = normalize_colors(raw)
    default_colors = [0 0.447 0.741; 0.85 0.325 0.098; 0.466 0.674 0.188];
    colors = bms.plot.PlotService.normalizeColors(raw, default_colors);
end

function tf = is_truthy(v)
    tf = bms.config.ConfigReader.boolValue(v, false);
end

function ok = is_valid_ylim(v)
    ok = bms.plot.PlotService.isValidYLim(v);
end

function out = sanitize_filename(in)
    out = regexprep(char(string(in)), '[<>:\"/\\\\|?*]+', '_');
    out = regexprep(out, '\s+', '_');
end
