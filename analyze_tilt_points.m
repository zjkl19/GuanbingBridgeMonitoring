function analyze_tilt_points(root_dir, start_date, end_date, excel_file, subfolder)
% analyze_tilt_points 批量绘制倾角时程曲线并统计指标
%   root_dir: 根目录，例如 'F:/管柄大桥健康监测数据/'
%   start_date,end_date: 日期范围，'yyyy-MM-dd'
%   excel_file: 输出统计 Excel，如 'tilt_stats.xlsx'
%   subfolder: 数据所在子文件夹，默认 '特征值_重采样'

if nargin<1||isempty(root_dir),  root_dir = pwd; end
if nargin<2||isempty(start_date), start_date = input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<3||isempty(end_date),   end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
if nargin<4||isempty(excel_file), excel_file = 'tilt_stats.xlsx'; end
if nargin<5||isempty(subfolder),  subfolder  = '波形_重采样'; end

% 测点分组
groupX = {'GB-DIS-P04-001-01-X','GB-DIS-P05-001-01-X','GB-DIS-P06-001-01-X'};
groupY = {'GB-DIS-P04-001-01-Y','GB-DIS-P05-001-01-Y','GB-DIS-P06-001-01-Y'};

% 提取统计并绘图
statsX = process_group(root_dir, subfolder, groupX, start_date, end_date, 'X');
statsY = process_group(root_dir, subfolder, groupY, start_date, end_date, 'Y');

% 合并写入 Excel，不同 sheet
T_X = cell2table(statsX, 'VariableNames',{'PointID','Min','Max','Mean'});
T_Y = cell2table(statsY, 'VariableNames',{'PointID','Min','Max','Mean'});
writetable(T_X, excel_file, 'Sheet','Tilt_X');
writetable(T_Y, excel_file, 'Sheet','Tilt_Y');
fprintf('倾角统计已保存至 %s\n', excel_file);
end

function stats = process_group(root_dir, subfolder, point_ids, start_date, end_date, suffix)
% process_group 处理一个分组，绘图并计算统计
num = numel(point_ids);
stats = cell(num,4);
for i=1:num
    pid = point_ids{i}; fprintf('处理 %s ...\n', pid);
    [times, vals] = extract_tilt_data(root_dir, subfolder, pid, start_date, end_date);
    if isempty(vals)
        warning('测点 %s 无数据，跳过。', pid);
        continue;
    end
    % 统计并保留3位小数
    stats{i,1} = pid;
    stats{i,2} = round(min(vals),3);
    stats{i,3} = round(max(vals),3);
    stats{i,4} = round(mean(vals),3);
end
% 绘制整组曲线
plot_tilt_curve(root_dir, subfolder, point_ids, start_date, end_date, suffix);
end

function [all_time, all_val] = extract_tilt_data(root_dir, subfolder, point_id, start_date, end_date)
% extract_tilt_data 提取倾角数据
all_time=[]; all_val=[];
dn0=datenum(start_date,'yyyy-mm-dd'); dn1=datenum(end_date,'yyyy-mm-dd');
dinfo=dir(fullfile(root_dir,'20??-??-??')); folders={dinfo([dinfo.isdir]).name};
dates=folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
for j=1:numel(dates)
    day=dates{j}; dirp=fullfile(root_dir,day,subfolder);
    if ~exist(dirp,'dir'), continue; end
    files=dir(fullfile(dirp,'*.csv'));
    idxs=arrayfun(@(f) contains(f.name, point_id), files);
    if ~any(idxs), continue; end
    fname=files(find(idxs,1)).name;
    fullpath=fullfile(dirp,fname);
    % 检测头部前50行
    fid=fopen(fullpath,'rt'); h=0;
    for k=1:50
        if feof(fid), break; end
        ln=fgetl(fid); h=h+1;
        if contains(ln,'[绝对时间]'), break; end
    end
    fclose(fid);
    T=readtable(fullpath,'Delimiter',',','HeaderLines',h,'Format','%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
    all_time=[all_time; T{:,1}]; all_val=[all_val; T{:,2}];
end
[all_time,ix]=sort(all_time); all_val=all_val(ix);
end

function plot_tilt_curve(root_dir, subfolder, point_ids, start_date, end_date, suffix)
% plot_tilt_curve 绘制一组倾角曲线并添加预警线和图例
fig=figure('Position',[100 100 1000 469]); hold on;
dn0=datenum(start_date,'yyyy-mm-dd'); dn1=datenum(end_date,'yyyy-mm-dd');
% 绘制多条曲线并收集图例句柄
hLines = gobjects(numel(point_ids),1);
for i=1:numel(point_ids)
    [t,v]=extract_tilt_data(root_dir, subfolder, point_ids{i}, start_date, end_date);
    hLines(i) = plot(t,v,'LineWidth',1);
end
% 添加图例，只显示测点曲线
lg = legend(hLines, point_ids, 'Location','northeast');
lg.AutoUpdate = 'off';

% X 轴刻度
numDiv=4; ticks=datetime(linspace(dn0,dn1,numDiv+1),'ConvertFrom','datenum');
ax=gca; ax.XLim=ticks([1 end]); ax.XTick=ticks; xtickformat('yyyy-MM-dd');
xlabel('时间'); ylabel('倾角 (°)'); title(['倾角时程曲线 ' suffix]);

% 添加报警线和 Y 轴范围
yVals = [-0.126,0.126,-0.155,0.155];
labels = {'二级报警值-0.126','二级报警值0.126','三级报警值-0.155','三级报警值0.155'};
colors = [0.9290 0.6940 0.1250;  % 黄色警告颜色
          0.9290 0.6940 0.1250;
          1      0      0;
          1      0      0];
for k=1:4
    yl = yline(yVals(k), '--');
    yl.Color = colors(k,:);
    yl.Label = labels{k};
    yl.LabelHorizontalAlignment = 'left';
end
% Y 轴范围（可切换）
tmp_manual=true;
if tmp_manual
    ylim([-0.15,0.15]);
else
    ylim auto;
end

grid on; grid minor;
% 保存 JPG, EMF, FIG
ts=datestr(now,'yyyymmdd_HHMMSS'); out=fullfile(root_dir,'时程曲线_倾角');
if ~exist(out,'dir'), mkdir(out); end
fname=sprintf('Tilt_%s_%s_%s',suffix,datestr(dn0,'yyyymmdd'),datestr(dn1,'yyyymmdd'));
saveas(fig,fullfile(out,[fname '_' ts '.jpg']));
saveas(fig,fullfile(out,[fname '_' ts '.emf']));
savefig(fig,fullfile(out,[fname '_' ts '.fig']),'compact');
close(fig);
end