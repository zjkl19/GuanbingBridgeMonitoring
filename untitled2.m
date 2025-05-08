function analyze_deflection_points1(root_dir, point_ids, start_date, end_date, excel_file, subfolder, cleaners)
% analyze_deflection_points 批量绘制挠度时程曲线并统计指标，支持可组合异常值清洗策略
%   root_dir: 根目录，例如 'F:/...'
%   point_ids: 测点编号 cell 数组
%   start_date,end_date: 'yyyy-MM-dd'
%   excel_file: 输出统计 Excel，如 'deflection_stats.xlsx'
%   subfolder: 数据所在子文件夹，默认为 '特征值'
%   cleaners: 清洗策略列表，每项结构体含 .fun 和 .params

if nargin<1||isempty(root_dir),  root_dir=pwd; end
if nargin<2||isempty(point_ids), error('请提供 point_ids cell 数组'); end
if nargin<3||isempty(start_date), start_date=input('开始日期 (yyyy-MM-dd): ','s'); end
if nargin<4||isempty(end_date),   end_date  =input('结束日期 (yyyy-MM-dd): ','s'); end
if nargin<5||isempty(excel_file), excel_file='deflection_stats.xlsx'; end
if nargin<6||isempty(subfolder),  subfolder='特征值'; end
if nargin<7,                     cleaners={}; end

% 统计表格初始化
stats = cell(numel(point_ids),4);

% 逐测点处理
for i=1:numel(point_ids)
    pid = point_ids{i}; fprintf('处理测点 %s ...\n',pid);
    % 提取原始数据
    [times, vals] = extract_deflection_data(root_dir, subfolder, pid, start_date, end_date);
    if isempty(vals)
        warning('无 %s 数据',pid); continue;
    end
    % 应用清洗策略
    for k=1:numel(cleaners)
        clean_fun = cleaners{k}.fun;
        params    = cleaners{k}.params;
        vals = clean_fun(vals, times, params);
    end
    % 绘图
    plot_deflection_point(root_dir, subfolder, pid, times, vals, start_date, end_date);
    % 统计指标（取整）
    mn = round(min(vals)); mx = round(max(vals)); av = round(mean(vals));
    stats{i,1}=pid; stats{i,2}=mn; stats{i,3}=mx; stats{i,4}=av;
end

% 写入 Excel
T = cell2table(stats,'VariableNames',{'PointID','Min','Max','Mean'});
writetable(T,excel_file);
fprintf('统计结果已保存至 %s\n',excel_file);
end

%% Subfunctions
function [all_t, all_v] = extract_deflection_data(root_dir, subfolder, pid, start_date,end_date)
% 同前，自动检测头部并读取
all_t=[]; all_v=[];
dn0=datenum(start_date,'yyyy-mm-dd'); dn1=datenum(end_date,'yyyy-mm-dd');
dinfo=dir(fullfile(root_dir,'20??-??-??')); folders={dinfo([dinfo.isdir]).name};
dates=folders(datenum(folders,'yyyy-mm-dd')>=dn0 & datenum(folders,'yyyy-mm-dd')<=dn1);
for j=1:numel(dates)
    dirp=fullfile(root_dir,dates{j},subfolder);
    if exist(dirp,'dir')
        files=dir(fullfile(dirp,'*.csv'));
        idx=find(arrayfun(@(f)contains(f.name,pid),files),1);
        if ~isempty(idx)
            fp=fullfile(files(idx).folder,files(idx).name);
            fid=fopen(fp,'rt'); h=0;
            while h<50 && ~feof(fid)
                ln=fgetl(fid); h=h+1;
                if contains(ln,'[绝对时间]'), break; end
            end; fclose(fid);
            T=readtable(fp,'Delimiter',',','HeaderLines',h,'Format','%{yyyy-MM-dd HH:mm:ss.SSS}D%f');
            all_t=[all_t;T{:,1}]; all_v=[all_v;T{:,2}];
        end
    end
end
[all_t,ix]=sort(all_t); all_v=all_v(ix);
end

function plot_deflection_point(root_dir, subfolder, pid, times, vals, sd, ed)
% 仅做简单时程绘图，可根据需求自定义
fig=figure('Position',[100 100 1000 469]);
plot(times,vals,'LineWidth',1); grid on; grid minor;
% 时间刻度4等分
dn0=datenum(sd,'yyyy-mm-dd'); dn1=datenum(ed,'yyyy-mm-dd');
ticks=datetime(linspace(dn0,dn1,5),'ConvertFrom','datenum');
ax=gca; ax.XLim=[ticks(1) ticks(end)]; ax.XTick=ticks; xtickformat('yyyy-MM-dd');
xlabel('时间'); ylabel('主梁位移 (mm)'); title(sprintf('测点 %s 挠度时程',pid));
% 保存
ts=datestr(now,'yyyyMMdd_HHMMSS'); out=fullfile(root_dir,'时程曲线_挠度'); if ~exist(out,'dir'), mkdir(out); end
fname=sprintf('%s_%s_%s',pid,datestr(dn0,'yyyMMdd'),datestr(dn1,'yyyMMdd'));
saveas(fig,fullfile(out,[fname '_' ts '.jpg'])); saveas(fig,fullfile(out,[fname '_' ts '.emf'])); savefig(fig,fullfile(out,[fname '_' ts '.fig']),'compact'); close(fig);
end

%% 示例清洗策略
function v=clean_threshold(v,~,params)
% 将 v 超出 [min,max] 置 NaN
v(v<params.min|v>params.max)=NaN;
end

function v=clean_zero(v,~,params)
% 将 v 等于 0 的项目置 NaN
v(v==0)=NaN;
end
