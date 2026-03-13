function rule = pick_threshold_lines_from_fig(parentFig, figPath)
% pick_threshold_lines_from_fig  Select one curve from a FIG and define a
% threshold band with two draggable horizontal line segments.
%
% Returns:
%   struct('point_id',..., 'min',..., 'max',..., 't_range_start',..., 't_range_end',...)
%   or [] when cancelled.

    rule = [];

    if nargin < 1
        parentFig = [];
    end
    if nargin < 2
        figPath = '';
    end

    if isempty(figPath)
        [fname, fpath] = uigetfile('*.fig', '选择 FIG 文件');
        if isequal(fname, 0), return; end
        figPath = fullfile(fpath, fname);
    elseif isstring(figPath)
        figPath = char(figPath);
    end

    figSrc = [];
    dlg = [];
    try
        if ~isfile(figPath)
            error('FIG 文件不存在: %s', figPath);
        end

        figSrc = openfig(figPath, 'invisible');
        axSel = choose_axis(figSrc);
        if isempty(axSel)
            close(figSrc);
            return;
        end

        [lineObj, pointId, xNum, yData] = choose_curve(figSrc, axSel);
        if isempty(lineObj)
            close(figSrc);
            return;
        end

        close(figSrc);
        figSrc = [];

        [xNum, yData] = sanitize_curve_data(xNum, yData);
        if numel(xNum) < 2
            error('所选曲线有效点不足，无法设置阈值。');
        end

        pointId = ensure_point_id(pointId, parentFig);
        if isempty(pointId)
            return;
        end

        xMin = min(xNum);
        xMax = max(xNum);
        yFinite = yData(isfinite(yData));
        if isempty(yFinite)
            error('所选曲线没有有效数值。');
        end
        yMin = min(yFinite);
        yMax = max(yFinite);
        if yMin == yMax
            pad = max(abs(yMin) * 0.1, 1);
            yMin = yMin - pad;
            yMax = yMax + pad;
        else
            pad = 0.1 * (yMax - yMin);
            yMin = yMin - pad;
            yMax = yMax + pad;
        end

        q1 = quantile(yFinite, 0.25);
        q3 = quantile(yFinite, 0.75);
        if ~isfinite(q1), q1 = mean(yFinite); end
        if ~isfinite(q3), q3 = mean(yFinite); end
        lowerInit = min(q1, q3);
        upperInit = max(q1, q3);
        if lowerInit == upperInit
            lowerInit = yMin + 0.3 * (yMax - yMin);
            upperInit = yMin + 0.7 * (yMax - yMin);
        end

        result = struct('ok', false, 'rule', []);
        syncGuard = false;
        xRange = [xMin, xMax];

        dlg = uifigure( ...
            'Name', 'FIG 拖线设阈', ...
            'Position', [160 120 1100 700], ...
            'WindowStyle', 'modal', ...
            'CloseRequestFcn', @onCancel);

        outer = uigridlayout(dlg, [3 1]);
        outer.RowHeight = {34, '1x', 70};
        outer.ColumnWidth = {'1x'};
        outer.Padding = [8 8 8 8];
        outer.RowSpacing = 8;

        infoGrid = uigridlayout(outer, [1 8]);
        infoGrid.Layout.Row = 1;
        infoGrid.ColumnWidth = {70, '1x', 60, 90, 60, 90, 80, '1x'};
        infoGrid.RowHeight = {24};
        infoGrid.Padding = [0 0 0 0];
        infoGrid.ColumnSpacing = 8;
        uilabel(infoGrid, 'Text', '点号:');
        pointLbl = uilabel(infoGrid, 'Text', pointId, 'FontWeight', 'bold');
        pointLbl.Layout.Column = 2;
        uilabel(infoGrid, 'Text', '上限:'); uilabel(infoGrid, 'Text', '');
        upperLbl = uilabel(infoGrid, 'Text', '');
        upperLbl.Layout.Column = 4;
        uilabel(infoGrid, 'Text', '下限:'); uilabel(infoGrid, 'Text', '');
        lowerLbl = uilabel(infoGrid, 'Text', '');
        lowerLbl.Layout.Column = 6;
        timeLbl = uilabel(infoGrid, 'Text', '');
        timeLbl.Layout.Column = [7 8];

        ax = axes('Parent', outer);
        ax.Layout.Row = 2;
        plot(ax, xNum, yData, 'LineWidth', 1.0, 'Color', [0 0.447 0.741], ...
            'DisplayName', pointId);
        grid(ax, 'on');
        grid(ax, 'minor');
        ax.XLim = [xMin, xMax];
        ax.YLim = [yMin, yMax];
        datetick(ax, 'x', 'yyyy-mm-dd HH:MM', 'keeplimits');
        ax.XTickLabelRotation = 20;
        xlabel(ax, get_axis_label(axSel, 'x', '时间'));
        ylabel(ax, get_axis_label(axSel, 'y', '数值'));
        title(ax, sprintf('拖动上下限线段并调整时间窗 - %s', pointId));

        lowerLine = drawline(ax, ...
            'Position', [xRange(1), lowerInit; xRange(2), lowerInit], ...
            'Color', [0.929 0.694 0.125], ...
            'LineWidth', 1.5, ...
            'Label', '下限');
        upperLine = drawline(ax, ...
            'Position', [xRange(1), upperInit; xRange(2), upperInit], ...
            'Color', [0.85 0.1 0.1], ...
            'LineWidth', 1.5, ...
            'Label', '上限');
        lowerLine.Deletable = false;
        upperLine.Deletable = false;

        addlistener(lowerLine, 'MovingROI', @(src,evt) sync_band(src, evt.CurrentPosition, false));
        addlistener(lowerLine, 'ROIMoved', @(src,evt) sync_band(src, evt.CurrentPosition, false));
        addlistener(upperLine, 'MovingROI', @(src,evt) sync_band(src, evt.CurrentPosition, true));
        addlistener(upperLine, 'ROIMoved', @(src,evt) sync_band(src, evt.CurrentPosition, true));

        btnGrid = uigridlayout(outer, [1 4]);
        btnGrid.Layout.Row = 3;
        btnGrid.ColumnWidth = {'1x', 90, 90, 90};
        btnGrid.RowHeight = {32};
        btnGrid.Padding = [0 0 0 0];
        btnGrid.ColumnSpacing = 8;
        uilabel(btnGrid, 'Text', '拖动端点调整时间窗，拖动整条线调整阈值。');
        autoBtn = uibutton(btnGrid, 'Text', '自动Y', 'ButtonPushedFcn', @onAutoY);
        autoBtn.Layout.Column = 2;
        okBtn = uibutton(btnGrid, 'Text', '确认', 'ButtonPushedFcn', @onConfirm); %#ok<NASGU>
        okBtn.Layout.Column = 3;
        cancelBtn = uibutton(btnGrid, 'Text', '取消', 'ButtonPushedFcn', @onCancel); %#ok<NASGU>
        cancelBtn.Layout.Column = 4;

        refresh_summary();
        waitfor(dlg);
        if result.ok
            rule = result.rule;
        end

    catch ME
        if ~isempty(figSrc) && isvalid(figSrc)
            close(figSrc);
        end
        if ~isempty(dlg) && isvalid(dlg)
            delete(dlg);
        end
        if nargin > 0 && ishghandle(parentFig)
            uialert(parentFig, ME.message, '错误');
        else
            errordlg(ME.message, '错误', 'modal');
        end
    end

    function sync_band(src, pos, isUpper)
        if syncGuard || isempty(dlg) || ~isvalid(dlg)
            return;
        end
        syncGuard = true;
        pos = constrain_horizontal(pos, ax.XLim, ax.YLim);
        xRange = [min(pos(:,1)), max(pos(:,1))];
        src.Position = [xRange(1), mean(pos(:,2)); xRange(2), mean(pos(:,2))];
        if isUpper
            otherY = mean(lowerLine.Position(:,2));
            lowerLine.Position = [xRange(1), otherY; xRange(2), otherY];
        else
            otherY = mean(upperLine.Position(:,2));
            upperLine.Position = [xRange(1), otherY; xRange(2), otherY];
        end
        refresh_summary();
        syncGuard = false;
    end

    function refresh_summary()
        lowerY = mean(lowerLine.Position(:,2));
        upperY = mean(upperLine.Position(:,2));
        yPair = sort([lowerY, upperY]);
        lowerLbl.Text = sprintf('%.6g', yPair(1));
        upperLbl.Text = sprintf('%.6g', yPair(2));
        t0 = datetime(xRange(1), 'ConvertFrom', 'datenum');
        t1 = datetime(xRange(2), 'ConvertFrom', 'datenum');
        timeLbl.Text = sprintf('%s ~ %s', ...
            char(string(t0, 'yyyy-MM-dd HH:mm:ss')), ...
            char(string(t1, 'yyyy-MM-dd HH:mm:ss')));
    end

    function onAutoY(~, ~)
        ax.YLimMode = 'auto';
        yl = ax.YLim;
        if yl(1) == yl(2)
            yl = yl + [-1 1];
        end
        ax.YLim = yl;
        sync_band(lowerLine, lowerLine.Position, false);
        sync_band(upperLine, upperLine.Position, true);
    end

    function onConfirm(~, ~)
        lowerY = mean(lowerLine.Position(:,2));
        upperY = mean(upperLine.Position(:,2));
        yPair = sort([lowerY, upperY]);
        t0 = datetime(xRange(1), 'ConvertFrom', 'datenum');
        t1 = datetime(xRange(2), 'ConvertFrom', 'datenum');
        result.rule = struct( ...
            'point_id', pointId, ...
            'min', yPair(1), ...
            'max', yPair(2), ...
            't_range_start', char(string(t0, 'yyyy-MM-dd HH:mm:ss')), ...
            't_range_end',   char(string(t1, 'yyyy-MM-dd HH:mm:ss')));
        result.ok = true;
        delete(dlg);
    end

    function onCancel(~, ~)
        result.ok = false;
        if ~isempty(dlg) && isvalid(dlg)
            delete(dlg);
        end
    end
end

function axSel = choose_axis(figSrc)
    axSel = [];
    axList = findobj(figSrc, 'Type', 'axes');
    axList = axList(:);
    hasLines = arrayfun(@(a) ~isempty(findobj(a, 'Type', 'line')), axList);
    hasLines = logical(hasLines(:));
    if numel(hasLines) ~= numel(axList)
        hasLines = hasLines(1:min(numel(hasLines), numel(axList)));
        axList = axList(1:numel(hasLines));
    end
    axList = axList(hasLines);
    if isempty(axList)
        error('FIG 中未找到包含曲线的坐标轴。');
    end

    if numel(axList) == 1
        axSel = axList(1);
        return;
    end

    axNames = cell(numel(axList), 1);
    for i = 1:numel(axList)
        ttl = axList(i).Title.String;
        if iscell(ttl), ttl = strjoin(ttl, ' '); end
        ttl = strtrim(char(string(ttl)));
        if isempty(ttl)
            ttl = sprintf('Axes %d', i);
        end
        axNames{i} = ttl;
    end

    idx = listdlg( ...
        'PromptString', '选择坐标轴', ...
        'SelectionMode', 'single', ...
        'ListString', axNames);
    if ~isempty(idx)
        axSel = axList(idx);
    end
end

function [lineObj, pointId, xNum, yData] = choose_curve(figSrc, axSel)
    lineObj = [];
    pointId = '';
    xNum = [];
    yData = [];

    lines = findobj(axSel, 'Type', 'line');
    lines = flipud(lines(:));
    labels = build_line_labels(figSrc, axSel, lines);
    labels = reshape(labels, [], 1);

    nLines = numel(lines);
    if numel(labels) < nLines
        for i = numel(labels)+1:nLines
            labels{i, 1} = sprintf('Curve%d', i); %#ok<AGROW>
        end
    elseif numel(labels) > nLines
        labels = labels(1:nLines);
    end

    valid = false(nLines, 1);
    xDataCell = cell(nLines, 1);
    yDataCell = cell(nLines, 1);
    for i = 1:nLines
        [xCandidate, yCandidate, ok] = extract_time_series(lines(i));
        valid(i) = ok;
        if ok
            xDataCell{i,1} = xCandidate;
            yDataCell{i,1} = yCandidate;
        end
    end

    keepIdx = find(valid);
    lines = lines(keepIdx);
    labels = labels(keepIdx);
    xDataCell = xDataCell(keepIdx);
    yDataCell = yDataCell(keepIdx);

    if isempty(lines)
        error('所选坐标轴中没有可用曲线。');
    end

    if numel(lines) == 1
        idx = 1;
    else
        idx = listdlg( ...
            'PromptString', '选择目标曲线（只编辑一条）', ...
            'SelectionMode', 'single', ...
            'ListString', labels);
        if isempty(idx)
            return;
        end
    end

    lineObj = lines(idx);
    pointId = labels{idx};
    xNum = xDataCell{idx};
    yData = yDataCell{idx};
end

function labels = build_line_labels(figSrc, axSel, lines)
    labels = cell(numel(lines), 1);
    legendStrings = {};
    lg = findobj(figSrc, 'Type', 'legend');
    if ~isempty(lg)
        try
            legendStrings = cellstr(string(lg(1).String));
        catch
            legendStrings = {};
        end
    end

    generated = 0;
    for i = 1:numel(lines)
        lbl = strtrim(char(string(lines(i).DisplayName)));
        if isempty(lbl) && numel(legendStrings) == numel(lines)
            lbl = strtrim(char(string(legendStrings{i})));
        end
        if isempty(lbl)
            generated = generated + 1;
            lbl = sprintf('Curve%d', generated);
        end
        labels{i} = lbl;
    end
end

function [xNum, yData, ok] = extract_time_series(lineObj)
    ok = false;
    xNum = [];
    yData = [];
    xData = lineObj.XData;
    yData = lineObj.YData;
    if isempty(xData) || isempty(yData)
        return;
    end
    if isa(xData, 'datetime')
        xNum = datenum(xData(:));
    elseif isnumeric(xData)
        xNum = xData(:);
        try
            dt = datetime(xNum, 'ConvertFrom', 'datenum');
            yrs = year(dt);
            if any(yrs < 1900 | yrs > 2100)
                return;
            end
        catch
            return;
        end
    else
        return;
    end
    yData = yData(:);
    if numel(xNum) ~= numel(yData)
        return;
    end
    mask = isfinite(xNum) & isfinite(yData);
    xNum = xNum(mask);
    yData = yData(mask);
    ok = numel(xNum) >= 2;
end

function [xNum, yData] = sanitize_curve_data(xNum, yData)
    [xNum, idx] = sort(xNum(:));
    yData = yData(idx);
end

function pointId = ensure_point_id(pointId, parentFig)
    if ~isempty(pointId) && ~startsWith(pointId, 'Curve')
        return;
    end
    answer = inputdlg('未识别点号，请输入 point_id', '点号确认', 1, {''});
    if isempty(answer)
        pointId = '';
        return;
    end
    pointId = strtrim(answer{1});
    if isempty(pointId)
        if nargin > 1 && ishghandle(parentFig)
            uialert(parentFig, 'point_id 不能为空。', '提示');
        end
        pointId = '';
    end
end

function pos = constrain_horizontal(pos, xLim, yLim)
    x1 = min(max(pos(1,1), xLim(1)), xLim(2));
    x2 = min(max(pos(2,1), xLim(1)), xLim(2));
    if x1 == x2
        delta = max(diff(xLim) * 0.01, eps(max(abs(xLim))));
        x2 = min(xLim(2), x1 + delta);
        x1 = max(xLim(1), x2 - delta);
    end
    y = mean(pos(:,2), 'omitnan');
    if ~isfinite(y)
        y = mean(yLim);
    end
    y = min(max(y, yLim(1)), yLim(2));
    pos = [x1, y; x2, y];
end

function txt = get_axis_label(axSel, axisName, fallback)
    txt = fallback;
    try
        if strcmpi(axisName, 'x')
            raw = axSel.XLabel.String;
        else
            raw = axSel.YLabel.String;
        end
        if iscell(raw)
            raw = strjoin(raw, ' ');
        end
        raw = strtrim(char(string(raw)));
        if ~isempty(raw)
            txt = raw;
        end
    catch
    end
end
