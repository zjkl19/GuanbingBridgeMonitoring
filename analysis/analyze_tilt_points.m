function analyze_tilt_points(root_dir, start_date, end_date, excel_file, subfolder, cfg)
% analyze_tilt_points Plot tilt time series and export stats.

    if nargin < 1 || isempty(root_dir), root_dir = pwd; end
    if nargin < 2 || isempty(start_date), error('start_date is required'); end
    if nargin < 3 || isempty(end_date), error('end_date is required'); end
    if nargin < 4 || isempty(excel_file), excel_file = 'tilt_stats.xlsx'; end
    excel_file = resolve_data_output_path(root_dir, excel_file, 'stats');
    if nargin < 6 || isempty(cfg), cfg = load_config(); end

    if nargin < 5 || isempty(subfolder)
        if isfield(cfg, 'subfolders') && isfield(cfg.subfolders, 'tilt')
            subfolder = cfg.subfolders.tilt;
        else
            subfolder = '波形_重采样';
        end
    end

    style = get_style(cfg, 'tilt');

    points_cfg = get_points(cfg, 'tilt', {});
    groups_cfg = get_groups(cfg, 'tilt');
    explicit_points = ~isempty(points_cfg);
    explicit_groups = has_groups(groups_cfg);

    % Preserve legacy behavior when no tilt points or groups are configured.
    if ~explicit_points && ~explicit_groups
        groups_cfg = legacy_tilt_groups();
        explicit_groups = true;
        points_cfg = flatten_groups(groups_cfg);
    end

    per_point_stats = cell(0, 4);
    if explicit_points || is_jiulongjiang(cfg)
        for i = 1:numel(points_cfg)
            pid = points_cfg{i};
            fprintf('Per-point tilt: %s ...\n', pid);
            data_one = bms.analyzer.StructuralSeriesService.loadPoint( ...
                root_dir, subfolder, pid, start_date, end_date, cfg, 'tilt');
            if isempty(data_one.vals)
                warning('Tilt point %s has no data, skip', pid);
                continue;
            end

            per_point_stats(end+1, :) = bms.analyzer.StructuralSeriesService.basicStatsRow( ...
                pid, data_one.vals, 3); %#ok<AGROW>

            warn_lines = resolve_warn_lines(style, cfg, pid);
            plot_tilt_curve(root_dir, data_one, start_date, end_date, pid, style, warn_lines, cfg);
        end
    end

    group_stats = {};
    group_names = {};
    if explicit_groups
        groups_map = normalize_group_map(groups_cfg);
        names = fieldnames(groups_map);
        for i = 1:numel(names)
            group_name = names{i};
            [stats, data_list] = process_group(root_dir, subfolder, groups_map.(group_name), start_date, end_date, cfg);
            if ~isempty(stats)
                group_names{end+1, 1} = group_name; %#ok<AGROW>
                group_stats{end+1, 1} = stats; %#ok<AGROW>
            end
            if has_plot_data(data_list)
                group_warn = resolve_warn_lines(style, cfg, '');
                plot_tilt_curve(root_dir, data_list, start_date, end_date, group_name, style, group_warn, cfg);
            end
        end
    end

    if ~isempty(per_point_stats)
        T = bms.analyzer.StructuralSeriesService.basicStatsTable(per_point_stats);
        bms.io.StatsWriter.writeModuleTableChecked(T, excel_file, 'tilt', 'Sheet', 'Tilt');
    end
    for i = 1:numel(group_stats)
        T = bms.analyzer.StructuralSeriesService.basicStatsTable(group_stats{i});
        bms.io.StatsWriter.writeModuleTableChecked(T, excel_file, 'tilt', 'Sheet', make_sheet_name(group_names{i}));
    end

    fprintf('Tilt stats saved to %s\n', excel_file);
end

function [stats, data_list] = process_group(root_dir, subfolder, pids, start_date, end_date, cfg)
    [data_list, stats] = bms.analyzer.StructuralSeriesService.collectPoints( ...
        root_dir, subfolder, pids, start_date, end_date, cfg, 'tilt', 3, 'Tilt point');
end

function plot_tilt_curve(root_dir, data_list, start_date, end_date, suffix, style, warn_lines, cfg)
    if nargin < 8
        cfg = struct();
    end
    if isempty(data_list) || ~has_plot_data(data_list)
        return;
    end

    fig = figure('Position', [100 100 1000 469]);
    hold on;

    dt0 = datetime(start_date, 'InputFormat', 'yyyy-MM-dd');
    dt1 = datetime(end_date, 'InputFormat', 'yyyy-MM-dd');
    if dt1 <= dt0
        dt1 = dt0 + days(1);
    end

    colors_3 = normalize_colors(get_style_field(style, 'colors_3', [0 0 0; 1 0 0; 0 0 1]));
    h_lines = gobjects(numel(data_list), 1);
    for i = 1:numel(data_list)
        d = data_list(i);
        if isempty(d.vals)
            continue;
        end
        if numel(data_list) == 3 && i <= numel(colors_3)
            [times_plot, vals_plot] = prepare_plot_series(d.times, d.vals);
            h_lines(i) = plot(times_plot, vals_plot, 'LineWidth', 1.0, 'Color', colors_3{i});
        else
            [times_plot, vals_plot] = prepare_plot_series(d.times, d.vals);
            h_lines(i) = plot(times_plot, vals_plot, 'LineWidth', 1.0);
        end
    end

    valid = isgraphics(h_lines);
    if any(valid)
        labels = {data_list(valid).pid};
        lg = legend(h_lines(valid), labels, 'Location', 'northeast', 'Box', 'off');
        lg.AutoUpdate = 'off';
    end

    ticks = dt0 + (dt1 - dt0) * (0:4) / 4;
    ax = gca;
    ax.XLim = [dt0 dt1];
    ax.XTick = ticks;
    xtickformat('yyyy-MM-dd');

    xlabel('时间');
    ylabel(get_style_field(style, 'ylabel', '倾角 (°)'));
    title(sprintf('%s %s', get_style_field(style, 'title_prefix', '倾角时程'), char(string(suffix))));

    warn_lines = normalize_warn_lines(warn_lines);
    for k = 1:numel(warn_lines)
        wl = warn_lines{k};
        if ~isstruct(wl) || ~isfield(wl, 'y') || ~isnumeric(wl.y) || ~isscalar(wl.y) || ~isfinite(wl.y)
            continue;
        end
        yl = yline(wl.y, '--', get_warn_label(wl), 'LabelHorizontalAlignment', 'left');
        if isfield(wl, 'color') && isnumeric(wl.color) && numel(wl.color) == 3
            yl.Color = wl.color;
        end
    end

    ylim_auto = get_style_field(style, 'ylim_auto', false);
    if (islogical(ylim_auto) && ylim_auto) || (isnumeric(ylim_auto) && ylim_auto ~= 0)
        ylim auto;
    else
        ylim_val = get_style_field(style, 'ylim', []);
        pid = '';
        if numel(data_list) == 1 && isfield(data_list, 'pid')
            pid = data_list(1).pid;
        end
        ylim_override = get_ylim_for_pid(style, pid, ylim_val);
        if is_valid_ylim(ylim_override)
            ylim(ylim_override);
        else
            ylim auto;
        end
    end

    grid on;
    grid minor;

    ts = datestr(now, 'yyyymmdd_HHMMSS');
    out_dir = char(string(get_style_field(style, 'output_dir', '时程曲线_倾角')));
    out_dir = fullfile(root_dir, out_dir);
    bms.core.PathResolver.ensureDir(out_dir);
    fname = sanitize_filename(sprintf('Tilt_%s_%s_%s', char(string(suffix)), datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd')));
    bms.plot.PlotService.saveModuleBundle(fig, out_dir, [fname '_' ts], cfg);
end

function warn_lines = resolve_warn_lines(style, cfg, pid)
    warn_lines = bms.analyzer.StructuralPlotConfigService.resolveWarnLines(style, cfg, 'tilt', pid);
end

function ccell = normalize_warn_lines(v)
    ccell = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(v);
end

function lbl = get_warn_label(wl)
    lbl = bms.analyzer.StructuralPlotConfigService.warnLabel(wl);
end

function groups = get_groups(cfg, key)
    groups = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, key, []);
end

function groups = normalize_group_map(groups_cfg)
    groups = bms.analyzer.StructuralPlotConfigService.normalizeGroupMap(groups_cfg);
end

function tf = has_groups(groups_cfg)
    tf = bms.analyzer.StructuralPlotConfigService.hasGroups(groups_cfg);
end

function groups = legacy_tilt_groups()
    groups = struct( ...
        'X', {{'GB-DIS-P04-001-01-X', 'GB-DIS-P05-001-01-X', 'GB-DIS-P06-001-01-X'}}, ...
        'Y', {{'GB-DIS-P04-001-01-Y', 'GB-DIS-P05-001-01-Y', 'GB-DIS-P06-001-01-Y'}});
end

function pts = get_points(cfg, key, fallback)
    pts = bms.analyzer.StructuralPlotConfigService.getPoints(cfg, key, fallback);
end

function pts = flatten_groups(groups)
    pts = bms.analyzer.StructuralPlotConfigService.flattenGroups(groups);
end

function pts = normalize_points(v)
    pts = bms.analyzer.StructuralPlotConfigService.normalizePoints(v);
end

function tf = is_jiulongjiang(cfg)
    tf = bms.analyzer.StructuralPlotConfigService.isJiulongjiang(cfg);
end

function style = get_style(cfg, key)
    style = bms.analyzer.StructuralPlotConfigService.getStyle(cfg, key);
end

function val = get_style_field(style, field, default)
    val = bms.analyzer.StructuralPlotConfigService.getStyleField(style, field, default);
end

function y = get_ylim_for_pid(style, pid, default)
    y = bms.analyzer.StructuralPlotConfigService.resolveNamedYLim(style, pid, default);
end

function ok = is_valid_ylim(v)
    ok = bms.analyzer.StructuralPlotConfigService.isValidYLim(v);
end

function ccell = normalize_colors(c)
    ccell = bms.analyzer.StructuralPlotConfigService.normalizeColors(c, {});
end

function tf = has_plot_data(data_list)
    tf = bms.analyzer.StructuralPlotConfigService.hasPlotData(data_list);
end

function sheet = make_sheet_name(name)
    sheet = bms.analyzer.StructuralPlotConfigService.sheetName(name, 'Tilt_');
end

function out = sanitize_filename(name)
    out = bms.analyzer.StructuralPlotConfigService.sanitizeFilename(name);
end
