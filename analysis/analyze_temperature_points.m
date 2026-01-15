function analyze_temperature_points(root_dir, point_ids, start_date, end_date, excel_file, subfolder, cfg)
% analyze_temperature_points 批量绘制多个测点温度时程并统计

    if nargin<1||isempty(root_dir),    root_dir = pwd; end
    if nargin<2||isempty(point_ids),    error('请提供 point_ids cell 数组'); end
    if nargin<3||isempty(start_date),   start_date = input('开始日期(yyyy-MM-dd): ','s'); end
    if nargin<4||isempty(end_date),     end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
    if nargin<5||isempty(excel_file),   excel_file = 'temperature_stats.xlsx'; end
    if nargin<6||isempty(subfolder)
        cfg_tmp = load_config();
        if isfield(cfg_tmp,'subfolders') && isfield(cfg_tmp.subfolders,'temperature')
            subfolder = cfg_tmp.subfolders.temperature;
        else
            subfolder = '特征值';
        end
    end
    if nargin<7||isempty(cfg),          cfg = load_config(); end

    nPts = numel(point_ids);
    stats = cell(nPts,4);

    dn0 = datenum(start_date,'yyyy-mm-dd');
    dn1 = datenum(end_date,  'yyyy-mm-dd');
    timestamp = datestr(now,'yyyymmdd_HHMMSS');
    outDir = fullfile(root_dir,'时程曲线_温度');
    if ~exist(outDir,'dir'), mkdir(outDir); end

    for i = 1:nPts
        pid = point_ids{i};
        fprintf('Processing %s...\n', pid);
        [all_time, all_val] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'temperature');
        if isempty(all_val)
            warning('测点 %s 无数据 跳过', pid);
            continue;
        end
        fig = figure('Position',[100 100 1000 469]); hold on;
        plot(all_time, all_val,'LineWidth',1);
        avg_val = round(mean(all_val),1);
        yline(avg_val,'--r',sprintf('平均值 %.1f',avg_val),...
            'LabelHorizontalAlignment','center','LabelVerticalAlignment','bottom');
        numDiv = 4;
        tk = linspace(dn0,dn1,numDiv+1);
        xt = datetime(tk,'ConvertFrom','datenum');
        ax = gca;
        ax.XLim = [xt(1) xt(end)];
        ax.XTick = xt;
        xtickformat('yyyy-MM-dd');
        xlabel('时间'); ylabel('环境温度 (℃)');
        tmp_manual = true;
        if tmp_manual, ylim([0,40]); else, ylim auto; end
        grid on; grid minor;
        title(sprintf('测点 %s 温度时程曲线', pid));
        base = sprintf('%s_%s_%s', pid, datestr(dn0,'yyyymmdd'), datestr(dn1,'yyyymmdd'));
        saveas(fig, fullfile(outDir,[base '_' timestamp '.jpg']));
        saveas(fig, fullfile(outDir,[base '_' timestamp '.emf']));
        savefig(fig, fullfile(outDir,[base '_' timestamp '.fig']), 'compact');
        close(fig);
        mn = min(all_val);
        mx = max(all_val);
        stats{i,1} = pid;
        stats{i,2} = mn;
        stats{i,3} = mx;
        stats{i,4} = avg_val;
    end
    T = cell2table(stats,'VariableNames',{'PointID','Min','Max','Mean'});
    writetable(T,excel_file);
    fprintf('统计结果已保存至 %s\n',excel_file);
end
