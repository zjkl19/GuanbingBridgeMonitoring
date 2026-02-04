function analyze_tilt_points(root_dir, start_date, end_date, excel_file, subfolder, cfg)
% analyze_tilt_points  倾角时程与统计（按 X/Y 分组）。
%
% root_dir   : 根目录
% start_date : 'yyyy-MM-dd'
% end_date   : 'yyyy-MM-dd'
% excel_file : 输出 Excel 文件名
% subfolder  : 数据子目录（默认 cfg.subfolders.tilt 或 '波形_重采样'）
% cfg        : load_config() 结果

    if nargin<1||isempty(root_dir),   root_dir  = pwd; end
    if nargin<2||isempty(start_date), start_date = input('开始日期 (yyyy-MM-dd): ','s'); end
    if nargin<3||isempty(end_date),   end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
    if nargin<4||isempty(excel_file), excel_file = 'tilt_stats.xlsx'; end
    if nargin<5||isempty(subfolder)
        cfg_tmp = load_config();
        if isfield(cfg_tmp,'subfolders') && isfield(cfg_tmp.subfolders,'tilt')
            subfolder = cfg_tmp.subfolders.tilt;
        else
            subfolder  = '波形_重采样';
        end
    end
    if nargin<6||isempty(cfg), cfg = load_config(); end

    groups_cfg = get_groups(cfg,'tilt');
    if isempty(groups_cfg)
        groups_cfg = struct('X',{{'GB-DIS-P04-001-01-X','GB-DIS-P05-001-01-X','GB-DIS-P06-001-01-X'}}, ...
                            'Y',{{'GB-DIS-P04-001-01-Y','GB-DIS-P05-001-01-Y','GB-DIS-P06-001-01-Y'}} );
    end
    style = get_style(cfg,'tilt');

    if is_jiulongjiang(cfg)
        points = get_points(cfg, 'tilt', groups_cfg);
        for i = 1:numel(points)
            pid = points{i};
            fprintf('Per-point tilt: %s ...\n', pid);
            [times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'tilt');
            if isempty(vals)
                warning('Point %s has no data, skip', pid);
                continue;
            end
            dataOne = struct('pid', pid, 'times', times, 'vals', vals);
            plot_tilt_curve(root_dir, dataOne, start_date, end_date, pid, style);
        end
    end

    [statsX, dataX] = process_group(root_dir, subfolder, groups_cfg.X, start_date, end_date, 'X', cfg);
    plot_tilt_curve(root_dir, dataX, start_date, end_date, 'X', style);

    [statsY, dataY] = process_group(root_dir, subfolder, groups_cfg.Y, start_date, end_date, 'Y', cfg);
    plot_tilt_curve(root_dir, dataY, start_date, end_date, 'Y', style);

    T_X = cell2table(statsX, 'VariableNames', {'PointID','Min','Max','Mean'});
    T_Y = cell2table(statsY, 'VariableNames', {'PointID','Min','Max','Mean'});
    writetable(T_X, excel_file, 'Sheet','Tilt_X');
    writetable(T_Y, excel_file, 'Sheet','Tilt_Y');
    fprintf('倾角统计已保存至 %s\n', excel_file);
end

function [stats, dataList] = process_group(root, subfolder, pids, t0, t1, suffix, cfg)
    n = numel(pids);
    stats    = cell(n,4);
    dataList = struct('pid',cell(n,1),'times',[],'vals',[]);
    for i = 1:n
        pid = pids{i};
        fprintf('提取 %s ...\n', pid);
        [times, vals] = load_timeseries_range(root, subfolder, pid, t0, t1, cfg, 'tilt');
        if isempty(vals)
            warning('测点 %s 无数据，跳过', pid);
            stats(i,:) = {pid, NaN, NaN, NaN};
            continue;
        end
        stats(i,:) = {pid, round(min(vals),3), round(max(vals),3), round(mean(vals),3)};
        dataList(i).pid   = pid;
        dataList(i).times = times;
        dataList(i).vals  = vals;
    end
end

function plot_tilt_curve(root_dir, dataList, t0, t1, suffix, style)
    fig = figure('Position',[100 100 1000 469]); hold on;

    dt0 = datetime(t0,'InputFormat','yyyy-MM-dd'); dt1 = datetime(t1,'InputFormat','yyyy-MM-dd');
    colors_3 = normalize_colors(get_style_field(style,'colors_3', {[0 0 0], [1 0 0], [0 0 1]}));

    hLines = gobjects(numel(dataList),1);
    for i = 1:numel(dataList)
        d = dataList(i);
        if isempty(d.vals), continue; end
        if numel(dataList) == 3 && i <= numel(colors_3)
            hLines(i) = plot(d.times, d.vals, 'LineWidth', 1.0, 'Color', colors_3{i});
        else
            hLines(i) = plot(d.times, d.vals, 'LineWidth', 1.0);
        end
    end
    goodLines = hLines(isgraphics(hLines));
    lg =legend(goodLines, {dataList.pid}, 'Location','northeast','Box','off');
    lg.AutoUpdate = 'off';
    numDiv = 4;
    ticks = dt0 + (dt1 - dt0) * (0:numDiv)/numDiv;
    ax = gca; ax.XLim = [dt0 dt1]; ax.XTick = ticks;
    xtickformat('yyyy-MM-dd');
    xlabel('时间');
    ylabel(get_style_field(style,'ylabel','倾角 (°)'));
    title(sprintf('%s %s', get_style_field(style,'title_prefix','倾角时程'), suffix));

    warn_lines = get_style_field(style,'warn_lines',{});
    if isstruct(warn_lines) && ~iscell(warn_lines)
        warn_lines = num2cell(warn_lines);
    end
    if iscell(warn_lines)
        for k = 1:numel(warn_lines)
            wl = warn_lines{k};
            if isstruct(wl) && isfield(wl,'y')
                yl = yline(wl.y, '--');
                if isfield(wl,'color'), yl.Color = wl.color; end
                if isfield(wl,'label'), yl.Label = wl.label; end
                yl.LabelHorizontalAlignment = 'left';
            end
        end
    end

    ylim_auto = get_style_field(style,'ylim_auto', false);
    if islogical(ylim_auto) && ylim_auto
        ylim auto;
    else
        ylim_val = get_style_field(style,'ylim', []);
        pid = '';
        if numel(dataList)==1 && isfield(dataList,'pid')
            pid = dataList(1).pid;
        end
        ylim_override = get_ylim_for_pid(style, pid, ylim_val);
        if ~isempty(ylim_override), ylim(ylim_override); else, ylim auto; end
    end

    grid on; grid minor;

    ts = datestr(now,'yyyymmdd_HHMMSS');
    out=fullfile(root_dir,'时程曲线_倾角'); if ~exist(out,'dir'), mkdir(out); end
    fname = sprintf('Tilt_%s_%s_%s', suffix, datestr(dt0,'yyyymmdd'), datestr(dt1,'yyyymmdd'));
    saveas(fig, fullfile(out, [fname '_' ts '.jpg']));
    saveas(fig, fullfile(out, [fname '_' ts '.emf']));
    savefig(fig, fullfile(out, [fname '_' ts '.fig']), 'compact');
    close(fig);
end

% helpers
function g = get_groups(cfg, key)
    g = [];
    if isfield(cfg,'groups') && isfield(cfg.groups, key)
        g = cfg.groups.(key);
    end
end

function pts = get_points(cfg, key, groups_cfg)
    pts = {};
    if isfield(cfg,'points') && isfield(cfg.points, key)
        pts = cfg.points.(key);
    elseif ~isempty(groups_cfg)
        pts = flatten_groups(groups_cfg);
    end
end

function pts = flatten_groups(groups_cfg)
    pts = {};
    if isstruct(groups_cfg)
        fn = fieldnames(groups_cfg);
        for i = 1:numel(fn)
            v = groups_cfg.(fn{i});
            if iscell(v)
                pts = [pts, v(:)'];
            end
        end
    end
    if ~isempty(pts)
        pts = unique(pts, 'stable');
    end
end

function tf = is_jiulongjiang(cfg)
    tf = isfield(cfg,'vendor') && strcmpi(cfg.vendor,'jiulongjiang');
end

function y = get_ylim_for_pid(style, pid, default)
    y = default;
    if isempty(pid) || ~isstruct(style) || ~isfield(style,'ylims')
        return;
    end
    ylims = style.ylims;
    if isa(ylims,'containers.Map')
        if isKey(ylims, pid)
            y = ylims(pid);
        end
        return;
    end
    if isstruct(ylims)
        if isfield(ylims, pid)
            y = ylims.(pid);
            return;
        end
        if isfield(ylims,'name') && isfield(ylims,'ylim')
            for i = 1:numel(ylims)
                if strcmp(ylims(i).name, pid)
                    y = ylims(i).ylim;
                    return;
                end
            end
        end
    end
    if iscell(ylims)
        for i = 1:numel(ylims)
            item = ylims{i};
            if isstruct(item) && isfield(item,'name') && strcmp(item.name, pid) && isfield(item,'ylim')
                y = item.ylim;
                return;
            end
        end
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

function ccell = normalize_colors(c)
    if isnumeric(c)
        ccell = mat2cell(c, ones(size(c,1),1), size(c,2));
    elseif iscell(c)
        ccell = c;
    else
        ccell = {};
    end
end
