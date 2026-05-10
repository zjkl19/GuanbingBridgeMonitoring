function analyze_deflection_points(root_dir, start_date, end_date, excel_file, subfolder, cfg)
% analyze_deflection_points
% 批量绘制主梁挠度时程（原始+中值滤波）并统计。
%
% 输入:
%   root_dir   根目录，如 'F:/桥梁监测数据/'
%   start_date, end_date  'yyyy-MM-dd'
%   excel_file 输出统计 Excel
%   subfolder  数据子目录，默认配置里的 deflection 子目录
%   cfg        load_config() 返回的配置结构

    if nargin<1||isempty(root_dir),    root_dir = pwd; end
    if nargin<2||isempty(start_date),  start_date = input('开始日期(yyyy-MM-dd): ','s'); end
    if nargin<3||isempty(end_date),    end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
    if nargin<4||isempty(excel_file),  excel_file = 'deflection_stats.xlsx'; end
    excel_file = resolve_data_output_path(root_dir, excel_file, 'stats');
    if nargin<5||isempty(subfolder)
        cfg_tmp = load_config();
        if isfield(cfg_tmp,'subfolders') && isfield(cfg_tmp.subfolders,'deflection')
            subfolder = cfg_tmp.subfolders.deflection;
        else
            subfolder = '特征值_重采样';
        end
    end
    if nargin<6||isempty(cfg),         cfg = load_config(); end

    groups = get_groups(cfg, 'deflection', {});
    style = get_style(cfg, 'deflection');
    stats = cell(0,7);
    row = 1;

    if ~has_groups(cfg, 'deflection')
        groups = {};
    end

    collect_per_point_stats = is_jiulongjiang(cfg) && isempty(groups);
    if is_jiulongjiang(cfg)
        points = get_points(cfg, 'deflection', groups);
        for i = 1:numel(points)
            pid = points{i};
            fprintf('Per-point deflection: %s ...\n', pid);
            [times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'deflection');
            if isempty(vals)
                warning('Point %s has no data, skip', pid);
                continue;
            end
            vals_f = bms.analyzer.StructuralSeriesService.movingMedian10Min(times, vals);
            vals_f = apply_threshold_rules(vals_f, times, ...
                resolve_post_filter_thresholds(cfg, 'deflection', pid));
            if collect_per_point_stats
                stats(row, :) = bms.analyzer.StructuralSeriesService.filteredStatsRow( ...
                    pid, vals, vals_f, 1);
                row = row + 1;
            end
            plot_deflection_curve({times}, {vals}, {pid}, root_dir, start_date, end_date, pid, style, 'Orig', cfg);
            plot_deflection_curve({times}, {vals_f}, {pid}, root_dir, start_date, end_date, pid, style, 'Filt', cfg);
        end
    end

    if ~isempty(groups)
    for g = 1:numel(groups)
        pid_list = groups{g};
        fprintf('处理组 %d: %s\n', g, strjoin(pid_list, ', '));
        N = numel(pid_list);
        orig_times = cell(N,1); orig_vals = cell(N,1);
        filt_times = cell(N,1); filt_vals = cell(N,1);

        for i = 1:N
            pid = pid_list{i};
            [times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'deflection');
            if isempty(vals)
                warning('测点 %s 无数据，跳过', pid);
                continue;
            end

            % 中值滤波窗口（约 10 min）
            vals_f = bms.analyzer.StructuralSeriesService.movingMedian10Min(times, vals);
            vals_f = apply_threshold_rules(vals_f, times, ...
                resolve_post_filter_thresholds(cfg, 'deflection', pid));

            orig_times{i} = times;  orig_vals{i} = vals;
            filt_times{i} = times;  filt_vals{i} = vals_f;
            stats(row, :) = bms.analyzer.StructuralSeriesService.filteredStatsRow( ...
                pid, vals, vals_f, 1);
            row = row + 1;
        end

        % 绘制原始&滤波曲线
        plot_deflection_curve(orig_times, orig_vals, pid_list, root_dir, start_date, end_date, g, style, 'Orig', cfg);
        plot_deflection_curve(filt_times, filt_vals, pid_list, root_dir, start_date, end_date, g, style, 'Filt', cfg);
    end
    end

    % 写入 Excel
    T = bms.analyzer.StructuralSeriesService.filteredStatsTable(stats);
    bms.io.StatsWriter.writeModuleTableChecked(T, excel_file, 'deflection');
    fprintf('挠度统计已保存至 %s\n', excel_file);
end

function plot_deflection_curve(times_list, vals_list, pid_list, root_dir, start_date, end_date, group_idx, style, suffix, cfg)
if nargin < 10
    cfg = struct();
end
N = numel(pid_list);
valid = ~cellfun(@isempty, vals_list);
if ~any(valid), return; end

[dt0, dt1] = bms.analyzer.StructuralTimeSeriesPlotService.dateRange(start_date, end_date);
prefix = get_style_field(style,'title_prefix','挠度时程');
if nargin < 9 || isempty(suffix)
    suffix = '';
else
    suffix = [' ' suffix];
end
if isnumeric(group_idx)
    name_tag = sprintf('G%d', group_idx);
    title_str = sprintf('%s 组%d%s', prefix, group_idx, suffix);
else
    name_tag = char(group_idx);
    title_str = sprintf('%s %s%s', prefix, group_idx, suffix);
end
warn_lines = get_style_field(style,'warn_lines', {});
pid = '';
if numel(pid_list) == 1
    pid = pid_list{1};
end
opts = struct();
opts.style = style;
opts.ylabel = get_style_field(style,'ylabel','挠度 (mm)');
opts.titleText = title_str;
opts.outputDir = '时程曲线_挠度';
opts.baseName = sprintf('Defl_%s_%s_%s_%s_%s', name_tag, make_file_suffix_tag(suffix), ...
    datestr(dt0,'yyyymmdd'), datestr(dt1,'yyyymmdd'), datestr(now,'yyyymmdd_HHMMSS'));
opts.warnLines = warn_lines;
opts.ylimRange = bms.analyzer.StructuralTimeSeriesPlotService.resolveStyleYLim(style, pid);
if N == 2
    opts.colorField = 'colors_2';
    opts.defaultColors = [0 0 1; 0 0.7 0];
elseif N == 3
    opts.colorField = 'colors_3';
    opts.defaultColors = [0.5 0 0.7; 0 0 1; 0 0.7 0];
end
bms.analyzer.StructuralTimeSeriesPlotService.plotCells( ...
    root_dir, times_list, vals_list, pid_list, start_date, end_date, opts, cfg);
end

function tag = make_file_suffix_tag(suffix)
    tag = char(string(suffix));
    if strcmpi(tag, 'Filt') || strcmpi(tag, 'Filtered')
        tag = 'Filt';
    elseif strcmpi(tag, 'Orig') || strcmpi(tag, 'Raw')
        tag = 'Orig';
    elseif isempty(strtrim(tag))
        tag = 'Series';
    else
        tag = regexprep(tag, '[^\w-]', '');
        if isempty(tag)
            tag = 'Series';
        end
    end
end

function pts = get_points(cfg, key, groups)
    pts = bms.analyzer.StructuralPlotConfigService.getPointsOrFlattenFallback(cfg, key, groups);
end

function pts = flatten_groups(groups)
    pts = bms.analyzer.StructuralPlotConfigService.flattenGroups(groups);
end

function tf = is_jiulongjiang(cfg)
    tf = bms.analyzer.StructuralPlotConfigService.isJiulongjiang(cfg);
end

function tf = has_groups(cfg, key)
    groups = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, key, []);
    tf = bms.analyzer.StructuralPlotConfigService.hasGroups(groups);
end

function groups = get_groups(cfg, key, fallback)
    groups = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, key, fallback);
    if ~iscell(groups)
        groups = fallback;
    end
end

function style = get_style(cfg, key)
    style = bms.analyzer.StructuralPlotConfigService.getStyle(cfg, key);
end

function val = get_style_field(style, field, default)
    val = bms.analyzer.StructuralPlotConfigService.getStyleField(style, field, default);
end
