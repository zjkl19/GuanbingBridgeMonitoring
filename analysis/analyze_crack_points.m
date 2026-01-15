function analyze_crack_points(root_dir, start_date, end_date, excel_file, subfolder, cfg)
% analyze_crack_points 批量绘制并统计裂缝宽度与温度时程
%   root_dir   : 根目录
%   start_date,end_date: 'yyyy-MM-dd'
%   excel_file : 输出 Excel
%   subfolder  : 数据子目录（默认配置里的 crack）
%   cfg        : load_config() 结果

    if nargin<1||isempty(root_dir),  root_dir = pwd;               end
    if nargin<2||isempty(start_date), start_date = input('开始日期(yyyy-MM-dd): ','s'); end
    if nargin<3||isempty(end_date),   end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
    if nargin<4||isempty(excel_file), excel_file = 'crack_stats.xlsx';end
    if nargin<5||isempty(subfolder)
        cfg_tmp = load_config();
        if isfield(cfg_tmp,'subfolders') && isfield(cfg_tmp.subfolders,'crack')
            subfolder = cfg_tmp.subfolders.crack;
        else
            subfolder  = '特征值';
        end
    end
    if nargin<6||isempty(cfg),        cfg = load_config();         end

    groups_cfg = get_groups(cfg,'crack');
    if isempty(groups_cfg)
        groups_cfg = struct('G05',{{'GB-CRK-G05-001-01','GB-CRK-G05-001-02','GB-CRK-G05-001-03','GB-CRK-G05-001-04'}}, ...
                            'G06',{{'GB-CRK-G06-001-01','GB-CRK-G06-001-02','GB-CRK-G06-001-03','GB-CRK-G06-001-04'}} );
    end
    style = get_style(cfg,'crack');

    stats = {};
    row = 1;
    grp_names = fieldnames(groups_cfg);
    for gi = 1:numel(grp_names)
        pid_list = groups_cfg.(grp_names{gi});
        N = numel(pid_list);
        crack_times = cell(N,1);
        crack_vals  = cell(N,1);
        temp_times  = cell(N,1);
        temp_vals   = cell(N,1);
        for i = 1:N
            pid = pid_list{i};
            [tc, vc] = load_timeseries_range(root_dir, subfolder, pid,   start_date, end_date, cfg, 'crack');
            [tt, vt] = load_timeseries_range(root_dir, subfolder, [pid '-t'], start_date, end_date, cfg, 'crack_temp');
            crack_times{i} = tc;  crack_vals{i} = vc;
            temp_times{i}  = tt;  temp_vals{i}  = vt;
            stats(row,:) = {
                pid, ...
                round(min(vc),3), round(max(vc),3), round(mean(vc),3), ...
                round(min(vt),3), round(max(vt),3), round(mean(vt),3)};
            row = row + 1;
        end
        ylim_group = get_ylim(style, grp_names{gi});
        plot_group_curve(crack_times, crack_vals, pid_list, '裂缝宽度 (mm)', ...
            fullfile(root_dir,'时程曲线_裂缝宽度 (mm)'), gi, start_date, end_date, ylim_group, style);
        plot_group_curve(temp_times, temp_vals, pid_list, '裂缝温度 (°C)', ...
            fullfile(root_dir,'时程曲线_裂缝温度 (°C)'), gi, start_date, end_date, ylim_group, style);
    end
    T = cell2table(stats, 'VariableNames',{'PointID','CrkMin','CrkMax','CrkMean','TmpMin','TmpMax','TmpMean'});
    writetable(T, excel_file);
    fprintf('统计结果已保存至 %s\n', excel_file);
end

function plot_group_curve(times_cell, vals_cell, labels, ylabel_str, out_dir, group_idx, start_date, end_date, ylim_range, style)

if ~exist(out_dir,'dir'), mkdir(out_dir); end
fig = figure('Position',[100 100 1000 469]); hold on;
N = numel(labels);
colors_4 = normalize_colors(get_style_field(style,'colors_4', {
    [0 0 0],
    [1 0 0],
    [0 0 1],
    [0 0.7 0]
    }));
for i = 1:N
    if N == 4
        plot(times_cell{i}, vals_cell{i}, 'LineWidth', 1.0, 'Color', colors_4{i});
    else
        plot(times_cell{i}, vals_cell{i}, 'LineWidth', 1.0);
    end
end

legend(labels,'Location','northeast','Box','off');
xlabel('时间'); ylabel(ylabel_str);
dt0 = datetime(start_date,'InputFormat','yyyy-MM-dd');
dt1 = datetime(end_date,  'InputFormat','yyyy-MM-dd');
ticks = dt0 + (dt1 - dt0) * (0:4)/4;
ax = gca; ax.XLim = [dt0 dt1]; ax.XTick = ticks;
xtickformat('yyyy-MM-dd'); grid on; grid minor;
if ~isempty(ylim_range)
    ylim(ylim_range);
else
    ylim auto;
end
ts = datestr(now,'yyyymmdd_HHMMSS');
fname = sprintf('%s_G%d_%s_%s', ylabel_str, group_idx, datestr(dt0,'yyyymmdd'), datestr(dt1,'yyyymmdd'));
saveas(fig, fullfile(out_dir, [fname '_' ts '.jpg']));
saveas(fig, fullfile(out_dir, [fname '_' ts '.emf']));
savefig(fig,fullfile(out_dir,[fname '_' ts '.fig']),'compact');
close(fig);
end

% helpers
function g = get_groups(cfg, key)
    g = [];
    if isfield(cfg,'groups') && isfield(cfg.groups, key)
        g = cfg.groups.(key);
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

function ylim_val = get_ylim(style, grp_name)
    ylim_val = [];
    if isstruct(style) && isfield(style,'ylims') && isfield(style.ylims, grp_name)
        ylim_val = style.ylims.(grp_name);
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
