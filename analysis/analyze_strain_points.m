function analyze_strain_points(root_dir, start_date, end_date, excel_file, subfolder, cfg)
% analyze_strain_points 批量绘制主梁应变时程并统计
%   root_dir: 根目录
%   start_date,end_date: 'yyyy-MM-dd'
%   excel_file: 输出 Excel
%   subfolder: 数据子目录（默认配置里的 strain）
%   cfg: load_config() 结果

    if nargin<1||isempty(root_dir),    root_dir = pwd; end
    if nargin<2||isempty(start_date),  start_date = input('开始日期(yyyy-MM-dd): ','s'); end
    if nargin<3||isempty(end_date),    end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
    if nargin<4||isempty(excel_file),  excel_file = 'strain_stats.xlsx'; end
    if nargin<5||isempty(subfolder)
        cfg_tmp = load_config();
        if isfield(cfg_tmp,'subfolders') && isfield(cfg_tmp.subfolders,'strain')
            subfolder = cfg_tmp.subfolders.strain;
        else
            subfolder  = '特征值';
        end
    end
    if nargin<6||isempty(cfg),         cfg = load_config(); end

    groups_cfg = get_groups(cfg,'strain');
    if isempty(groups_cfg)
        groups_cfg = struct('G05',{{'GB-RSG-G05-001-01','GB-RSG-G05-001-02','GB-RSG-G05-001-03','GB-RSG-G05-001-04','GB-RSG-G05-001-05','GB-RSG-G05-001-06'}}, ...
                            'G06',{{'GB-RSG-G06-001-01','GB-RSG-G06-001-02','GB-RSG-G06-001-03','GB-RSG-G06-001-04','GB-RSG-G06-001-05','GB-RSG-G06-001-06'}} );
    end
    style = get_style(cfg,'strain');
    colors_6 = normalize_colors(get_style_field(style,'colors_6', {
        [0 0 0],
        [0 0 1],
        [0 0.7 0],
        [1 0.4 0.8],
        [1 0.6 0],
        [1 0 0]
    }));

    stats = {};
    row = 1;
    dt0 = datetime(start_date,'InputFormat','yyyy-MM-dd');
    dt1 = datetime(end_date,  'InputFormat','yyyy-MM-dd');
    ticks = dt0 + (dt1 - dt0) * (0:4)/4;

    grp_names = fieldnames(groups_cfg);
    for gi = 1:numel(grp_names)
        pid_list = groups_cfg.(grp_names{gi});
        fig=figure('Position',[100 100 1000 469]); hold on;
        N = numel(pid_list);
        for i = 1:N
            pid = pid_list{i};
            [t, v] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'strain');
            if isempty(v)
                warning('无%s 数据', pid);
                continue;
            end
            stats(row,:) = {pid, round(min(v)), round(max(v)), round(mean(v))};
            row = row + 1;
            c = colors_6{ min(i, numel(colors_6)) };
            plot(t, v, 'LineWidth', 1.0, 'Color', c);
        end

        legend(pid_list,'Location','northeast','Box','off');
        xlabel('时间'); ylabel('主梁应变 (με)');
        ylims_cfg = get_style_field(style,'ylims', struct());
        if isfield(ylims_cfg, grp_names{gi})
            ylim(ylims_cfg.(grp_names{gi}));
        else
            ylim auto;
        end
        ax=gca; ax.XLim=[ticks(1) ticks(end)]; ax.XTick=ticks; xtickformat('yyyy-MM-dd');
        grid on; grid minor;
        title(sprintf('应变时程曲线 组%d',gi));
        ts=datestr(now,'yyyymmdd_HHMMSS'); out=fullfile(root_dir,'时程曲线_应变'); if ~exist(out,'dir'), mkdir(out); end
        fname=sprintf('StrainG%d_%s_%s',gi,datestr(dt0,'yyyyMMdd'),datestr(dt1,'yyyyMMdd'));
        saveas(fig,fullfile(out,[fname '_' ts '.jpg']));
        saveas(fig,fullfile(out,[fname '_' ts '.emf']));
        savefig(fig,fullfile(out,[fname '_' ts '.fig']), 'compact'); close(fig);
    end

    T = cell2table(stats, 'VariableNames', {'PointID','Min','Max','Mean'});
    writetable(T, excel_file);
    fprintf('应变统计已保存至 %s\n', excel_file);
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

function ccell = normalize_colors(c)
    if isnumeric(c)
        ccell = mat2cell(c, ones(size(c,1),1), size(c,2));
    elseif iscell(c)
        ccell = c;
    else
        ccell = {};
    end
end
