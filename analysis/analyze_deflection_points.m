function analyze_deflection_points(root_dir, start_date, end_date, excel_file, subfolder, cfg)
% analyze_deflection_points
%   批量绘制主梁位移（挠度）时程曲线并统计（原始+中值滤波）
%
% 输入：
%   root_dir   根目录，例 'F:/桥梁监测数据/'
%   start_date, end_date  'yyyy-MM-dd'
%   excel_file 输出统计 Excel
%   subfolder  数据子目录，默认配置里的 deflection 子目录
%   cfg        load_config() 返回的配置结构

    if nargin<1||isempty(root_dir),    root_dir = pwd; end
    if nargin<2||isempty(start_date),  start_date = input('开始日期(yyyy-MM-dd): ','s'); end
    if nargin<3||isempty(end_date),    end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
    if nargin<4||isempty(excel_file),  excel_file = 'deflection_stats.xlsx'; end
    if nargin<5||isempty(subfolder)
        cfg_tmp = load_config();
        if isfield(cfg_tmp,'subfolders') && isfield(cfg_tmp.subfolders,'deflection')
            subfolder = cfg_tmp.subfolders.deflection;
        else
            subfolder = '特征值_重采样';
        end
    end
    if nargin<6||isempty(cfg),         cfg = load_config(); end

    % 定义测点分组（Y通道）
    groups = { ...
        {'GB-DIS-G05-001-01Y','GB-DIS-G05-001-02Y'}, ...
        {'GB-DIS-G05-002-01Y','GB-DIS-G05-002-02Y','GB-DIS-G05-002-03Y'}, ...
        {'GB-DIS-G05-003-01Y','GB-DIS-G05-003-02Y'}, ...
        {'GB-DIS-G06-001-01Y','GB-DIS-G06-001-02Y'}, ...
        {'GB-DIS-G06-002-01Y','GB-DIS-G06-002-02Y','GB-DIS-G06-002-03Y'}, ...
        {'GB-DIS-G06-003-01Y','GB-DIS-G06-003-02Y'} ...
        };

    stats = {};
    row = 1;
    for g = 1:numel(groups)
        pid_list = groups{g};
        fprintf('处理组 %d: %s\n', g, strjoin(pid_list, ', '));
        N = numel(pid_list);
        orig_times = cell(N,1);
        orig_vals  = cell(N,1);
        filt_times = cell(N,1);
        filt_vals  = cell(N,1);

        for i = 1:N
            pid = pid_list{i};
            [times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'deflection');
            if isempty(vals)
                warning('测点 %s 无数据，跳过', pid);
                continue;
            end

            % 动态计算中值滤波窗口（10 min）
            if numel(times) >= 2
                dts = seconds(diff(times));
                fs = 1/median(dts);
                window_sec = 10*60;
                win_len = round(window_sec * fs);
                if mod(win_len,2)==0, win_len = win_len + 1; end
            else
                win_len = 201;
            end
            vals_f = movmedian(vals, win_len, 'omitnan');

            orig_times{i} = times;    orig_vals{i} = vals;
            filt_times{i} = times;    filt_vals{i} = vals_f;
            stats(row, :) = {
                pid, ...
                round(min(vals),1), round(max(vals),1), round(mean(vals,  'omitnan'), 1), ...
                round(min(vals_f),1), round(max(vals_f),1), round(mean(vals_f,  'omitnan'), 1)};
            row = row + 1;
        end

        % 绘制原始&滤波曲线
        plot_deflection_curve(orig_times, orig_vals, pid_list, root_dir, start_date, end_date, g);
        plot_deflection_curve(filt_times, filt_vals, pid_list, root_dir, start_date, end_date, g);

        clear orig_times orig_vals filt_times filt_vals
    end

    % 写入 Excel
    T = cell2table(stats, 'VariableNames', ...
        {'PointID','OrigMin_mm','OrigMax_mm','OrigMean_mm','FiltMin_mm','FiltMax_mm','FiltMean_mm'});
    writetable(T, excel_file);
    fprintf('挠度统计已保存至 %s\n', excel_file);
end

function plot_deflection_curve(times_list, vals_list, pid_list,  root_dir, start_date, end_date, group_idx)
% plot_deflection_curve 绘制一组挠度时程曲线
fig = figure('Position',[100 100 1000 469]); hold on;
dn0 = datenum(start_date,'yyyy-mm-dd'); dn1 = datenum(end_date,'yyyy-mm-dd');
% 绘制多条曲线并生成图例
h = gobjects(numel(pid_list),1);

N = numel(pid_list);

% 2条线：蓝、绿；3条线：紫、蓝、绿
colors_2 = {[0 0 1], [0 0.7 0]};                  % 蓝，绿
colors_3 = {[0.5 0 0.7], [0 0 1], [0 0.7 0]};     % 紫，蓝，绿

for i = 1:N
    if N == 2
        c = colors_2{i};
    elseif N == 3
        c = colors_3{i};
    else
        cmap = lines(N);   % 默认Matlab配色
        c = cmap(i,:);
    end
    plot(times_list{i}, vals_list{i}, 'LineWidth', 1.0, 'Color', c);
end

lg=legend(pid_list,'Location','northeast','Box','off');
lg.AutoUpdate = 'off';

% X 刻度
numDiv = 4;
ticks = datetime(linspace(dn0, dn1, numDiv+1), 'ConvertFrom','datenum');
ax = gca; ax.XLim = ticks([1 end]); ax.XTick = ticks; xtickformat('yyyy-MM-dd');
xlabel('时间'); ylabel('主梁位移 (mm)');
title(sprintf('挠度时程曲线 组%d', group_idx));

% 预警线
yline(-21.0, '--', '二级报警值-21.0', 'LabelHorizontalAlignment','left', 'Color',[0.9290 0.6940 0.1250]);
yline( 33.4, '--', '二级报警值3.4',  'LabelHorizontalAlignment','left', 'Color',[0.9290 0.6940 0.1250]);
yline(-26.3, '--', '三级报警值-26.3', 'LabelHorizontalAlignment','left', 'Color',[1 0 0]);
yline( 41.7, '--', '三级报警值1.7',  'LabelHorizontalAlignment','left', 'Color',[1 0 0]);

% Y轴范围
tmp_manual = true;
if tmp_manual
    ylim([-40, 50]);
else
    ylim auto;
end
grid on; grid minor;

% 保存 JPG, EMF, FIG
ts = datestr(now,'yyyymmdd_HHMMSS');
out = fullfile(root_dir, '时程曲线_挠度'); if ~exist(out,'dir'), mkdir(out); end
fname = sprintf('Defl_G%d_%s_%s', group_idx, datestr(dn0,'yyyymmdd'), datestr(dn1,'yyyymmdd'));
saveas(fig, fullfile(out, [fname '_' ts '.jpg']));
saveas(fig, fullfile(out, [fname '_' ts '.emf']));
savefig(fig, fullfile(out, [fname '_' ts '.fig']), 'compact');
close(fig);
end
