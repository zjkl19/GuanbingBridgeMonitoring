function analyze_tilt_points(root_dir, start_date, end_date, excel_file, subfolder, cfg)
% analyze_tilt_points 批量绘制倾角时程并统计
%   root_dir: 根目录
%   start_date: 开始日期 'yyyy-MM-dd'
%   end_date: 结束日期 'yyyy-MM-dd'
%   excel_file: 输出 Excel
%   subfolder: 数据子目录（默认配置里的 tilt）
%   cfg: load_config() 结果

    if nargin<1||isempty(root_dir),    root_dir  = pwd;           end
    if nargin<2||isempty(start_date),  start_date = input('开始日期: ','s'); end
    if nargin<3||isempty(end_date),    end_date   = input('结束日期: ','s'); end
    if nargin<4||isempty(excel_file),  excel_file = 'tilt_stats.xlsx';end
    if nargin<5||isempty(subfolder)
        cfg_tmp = load_config();
        if isfield(cfg_tmp,'subfolders') && isfield(cfg_tmp.subfolders,'tilt')
            subfolder = cfg_tmp.subfolders.tilt;
        else
            subfolder  = '波形_重采样';
        end
    end
    if nargin<6||isempty(cfg),         cfg = load_config(); end

    groupX = {'GB-DIS-P04-001-01-X','GB-DIS-P05-001-01-X','GB-DIS-P06-001-01-X'};
    groupY = {'GB-DIS-P04-001-01-Y','GB-DIS-P05-001-01-Y','GB-DIS-P06-001-01-Y'};

    [statsX, dataX] = process_group(root_dir, subfolder, groupX, start_date, end_date, 'X', cfg);
    plot_tilt_curve(root_dir,dataX, start_date, end_date, 'X');
    clear dataX;

    [statsY, dataY] = process_group(root_dir, subfolder, groupY, start_date, end_date, 'Y', cfg);
    plot_tilt_curve(root_dir,dataY, start_date, end_date, 'Y');
    clear dataY;

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
            continue;
        end
        stats(i,:) = {pid, round(min(vals),3), round(max(vals),3), round(mean(vals),3)};
        dataList(i).pid   = pid;
        dataList(i).times = times;
        dataList(i).vals  = vals;
    end
end

function plot_tilt_curve(root_dir,dataList, t0, t1, suffix)
fig = figure('Position',[100 100 1000 469]); hold on;

dn0 = datenum(t0,'yyyy-mm-dd'); dn1 = datenum(t1,'yyyy-mm-dd');

hLines = gobjects(numel(dataList),1);
N = numel(dataList);
colors_3 = {[0 0 0], [1 0 0], [0 0 1]};  % 黑、红、蓝

for i = 1:N
    d = dataList(i);
    if isempty(d.vals), continue; end
    if N == 3
        c = colors_3{i};
        hLines(i) = plot(d.times, d.vals, 'LineWidth', 1.0, 'Color', c);
    else
        hLines(i) = plot(d.times, d.vals, 'LineWidth', 1.0);
    end
end
legend(hLines, {dataList.pid}, 'Location','northeast','Box','off');
lg = legend; lg.AutoUpdate = 'off';

numDiv = 4;
ticks = datetime(linspace(dn0,dn1,numDiv+1),'ConvertFrom','datenum');
ax = gca; ax.XLim = ticks([1 end]); ax.XTick = ticks;
xtickformat('yyyy-MM-dd');
xlabel('时间'); ylabel('倾角 (°)');
title(['倾角时程曲线 ' suffix]);

yVals = [-0.126,0.126,-0.155,0.155];
labels = {'二级报警值-0.126','二级报警值0.126','三级报警值-0.155','三级报警值0.155'};
colors = [0.9290 0.6940 0.1250;0.9290 0.6940 0.1250;1 0 0;1 0 0];
for k = 1:4
    yl = yline(yVals(k), '--');
    yl.Color = colors(k,:);
    yl.Label = labels{k};
    yl.LabelHorizontalAlignment = 'left';
end

tmp_manual = true;
if tmp_manual, ylim([-0.17,0.17]); else, ylim auto; end

grid on; grid minor;

ts = datestr(now,'yyyymmdd_HHMMSS');
out=fullfile(root_dir,'时程曲线_倾角'); if ~exist(out,'dir'), mkdir(out); end
fname = sprintf('Tilt_%s_%s_%s', suffix, datestr(dn0,'yyyymmdd'), datestr(dn1,'yyyymmdd'));
saveas(fig, fullfile(out, [fname '_' ts '.jpg']));
saveas(fig, fullfile(out, [fname '_' ts '.emf']));
savefig(fig, fullfile(out, [fname '_' ts '.fig']), 'compact');
close(fig);
end
