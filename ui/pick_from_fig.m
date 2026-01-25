function rows = pick_from_fig(parentFig)
% pick_from_fig
% 从 FIG 文件中通过矩形框选生成 per_point 阈值行（稳定版 V1.1）
%
% 返回 rows: N x 8 cell
% {'point_id','min','max','t_range_start','t_range_end', ...
%  'zero_to_nan','outlier_window_sec','outlier_threshold_factor'}

rows = {};

%% 选择 FIG 文件
[fname,fpath] = uigetfile('*.fig','选择 FIG 文件');
if isequal(fname,0)
    return;
end
figPath = fullfile(fpath,fname);

figSrc = [];
selFig = [];

try
    %% 打开 FIG 并选择坐标轴
    figSrc = openfig(figPath,'invisible');
    axList = findobj(figSrc,'Type','axes');
    if isempty(axList)
        error('FIG 中未找到坐标轴');
    end

    axSel = axList(1);
    if numel(axList) > 1
        axNames = arrayfun(@(a) string(a.Title.String), axList);
        axNames(axNames=="") = "Axes";
        idx = listdlg( ...
            'PromptString','选择坐标轴', ...
            'SelectionMode','single', ...
            'ListString',axNames);
        if isempty(idx)
            close(figSrc);
            return;
        end
        axSel = axList(idx);
    end

    %% 创建交互窗口
    selFig = uifigure( ...
        'Name','从 FIG 框选阈值（稳定版）', ...
        'Position',[200 200 1000 650], ...
        'WindowStyle','modal');

    %% 使用普通 axes（非 uiaxes）
    uiAx = axes( ...
        'Parent',selFig, ...
        'Position',[0.08 0.22 0.88 0.68]);

    %% 重绘曲线
    srcLines = findobj(axSel,'Type','line');
    hold(uiAx,'on');
    for k = numel(srcLines):-1:1
        plot(uiAx, ...
            srcLines(k).XData, ...
            srcLines(k).YData, ...
            'DisplayName',srcLines(k).DisplayName, ...
            'LineWidth',srcLines(k).LineWidth);
    end
    hold(uiAx,'off');

    %% 轴属性
    uiAx.XLim = axSel.XLim;
    uiAx.YLim = axSel.YLim;
    uiAx.XLabel.String = axSel.XLabel.String;
    uiAx.YLabel.String = axSel.YLabel.String;
    title(uiAx,'拖动矩形框选（时间 × 数值）');
    legend(uiAx,'show','Location','best');

    origYLim = uiAx.YLim;

    %% YLim 控件
    uilabel(selFig,'Text','Y 下限','Position',[50 80 50 22]);
    yMinEdit = uieditfield(selFig,'numeric', ...
        'Position',[100 80 80 22], ...
        'Value',origYLim(1));

    uilabel(selFig,'Text','Y 上限','Position',[190 80 50 22]);
    yMaxEdit = uieditfield(selFig,'numeric', ...
        'Position',[240 80 80 22], ...
        'Value',origYLim(2));

    uibutton(selFig,'Text','应用 YLim', ...
        'Position',[340 80 80 24], ...
        'ButtonPushedFcn',@(~,~) set(uiAx,'YLim',[yMinEdit.Value,yMaxEdit.Value]));

    uibutton(selFig,'Text','自动', ...
        'Position',[430 80 60 24], ...
        'ButtonPushedFcn',@(~,~) autoY());

    %% 框选按钮
    uibutton(selFig,'Text','框选并确认', ...
        'Position',[820 80 120 28], ...
        'ButtonPushedFcn',@addRange);

    %% 等待
    uiwait(selFig);

catch ME
    if ~isempty(selFig) && isvalid(selFig), delete(selFig); end
    if ~isempty(figSrc) && isvalid(figSrc), close(figSrc); end
    if nargin>0 && ishghandle(parentFig)
        uialert(parentFig,ME.message,'错误');
    else
        errordlg(ME.message,'错误','modal');
    end
    return;
end

if ~isempty(figSrc) && isvalid(figSrc)
    close(figSrc);
end

%% ================= 内部函数 =================

    function autoY()
        uiAx.YLimMode = 'auto';
        yMinEdit.Value = uiAx.YLim(1);
        yMaxEdit.Value = uiAx.YLim(2);
    end

function addRange(~,~)
    % ===== 最终稳定方案：overlay axes + ROI =====

    % --- 1. 取原始 datetime 范围 ---
    xl_dt = uiAx.XLim;
    yl = uiAx.YLim;

    % --- 2. 创建覆盖用 axes（不可见，数值轴） ---
    overlayAx = axes( ...
        'Parent', selFig, ...
        'Position', uiAx.Position, ...
        'XLim', datenum(xl_dt), ...
        'YLim', yl, ...
        'Visible', 'off', ...
        'HitTest', 'on');

    % --- 3. 把曲线“复制”为 datenum 版本 ---
    srcLines = findobj(uiAx,'Type','line');
    hold(overlayAx,'on');
    for i = 1:numel(srcLines)
        xd = srcLines(i).XData;
        if isa(xd,'datetime')
            xd = datenum(xd);
        end
        plot(overlayAx, xd, srcLines(i).YData, ...
            'DisplayName', srcLines(i).DisplayName);
    end
    hold(overlayAx,'off');

    % --- 4. 在 overlayAx 上安全画 ROI ---
    roi = drawrectangle(overlayAx,'StripeColor','r');
    if isempty(roi) || ~isvalid(roi)
        delete(overlayAx);
        return;
    end

    pos = roi.Position;   % 全是 double（datenum 坐标）

    % --- 5. 立刻清理 overlay axes ---
    delete(overlayAx);

    % --- 6. 还原为 datetime 时间 ---
    t0 = datetime(pos(1),'ConvertFrom','datenum');
    t1 = datetime(pos(1)+pos(3),'ConvertFrom','datenum');
    if t1 < t0, [t0,t1] = deal(t1,t0); end

    % --- 7. Y 范围 ---
    y0 = pos(2);
    y1 = pos(2) + pos(4);
    if y1 < y0, [y0,y1] = deal(y1,y0); end

    % --- 8. 命中测点（基于原 uiAx 的数据） ---
    hitPids = {};
    lines = findobj(uiAx,'Type','line');
    for i = 1:numel(lines)
        xd = lines(i).XData;
        yd = lines(i).YData;

        maskX = xd>=t0 & xd<=t1;
        if any(maskX & yd>=y0 & yd<=y1)
            pid = string(lines(i).DisplayName);
            if pid ~= ""
                hitPids{end+1} = char(pid); %#ok<AGROW>
            end
        end
    end

    if isempty(hitPids)
        uialert(selFig,'框选区域内未命中任何测点','提示');
        return;
    end

    % --- 9. 确认窗口（保持你原有逻辑） ---
    preview = uifigure( ...
        'Name','确认阈值', ...
        'Position',[300 300 620 260], ...
        'WindowStyle','modal');

    data = cell(numel(hitPids),5);
    for k = 1:numel(hitPids)
        data(k,:) = { ...
            hitPids{k}, y0, y1, ...
            datestr(t0,'yyyy-mm-dd HH:MM:ss'), ...
            datestr(t1,'yyyy-mm-dd HH:MM:ss')};
    end

    tbl = uitable(preview, ...
        'Data',data, ...
        'ColumnName',{'point_id','min','max','t_range_start','t_range_end'}, ...
        'ColumnEditable',true(1,5), ...
        'Position',[20 60 580 170]);

    uibutton(preview,'Text','确认追加', ...
        'Position',[350 20 100 26], ...
        'ButtonPushedFcn',@confirmAdd);

    uibutton(preview,'Text','取消', ...
        'Position',[470 20 80 26], ...
        'ButtonPushedFcn',@(~,~) close(preview));

    function confirmAdd()
        d = tbl.Data;
        rows = cell(size(d,1),8);
        for ii = 1:size(d,1)
            rows(ii,:) = { ...
                strtrim(string(d{ii,1})), ...
                d{ii,2}, d{ii,3}, ...
                char(string(d{ii,4})), char(string(d{ii,5})), ...
                false, [], []};
        end
        close(preview);
        uiresume(selFig);
        delete(selFig);
    end
end

end

