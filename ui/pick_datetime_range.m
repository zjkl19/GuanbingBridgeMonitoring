function [tStart, tEnd, ok] = pick_datetime_range(parentFig, initStart, initEnd)
% pick_datetime_range  Modal date-time range picker with optional endpoints.

    if nargin < 1
        parentFig = [];
    end
    if nargin < 2, initStart = ''; end
    if nargin < 3, initEnd = ''; end

    [startEnabled, startDt] = parse_init_time(initStart);
    [endEnabled, endDt] = parse_init_time(initEnd);
    if ~startEnabled && ~endEnabled
        baseDt = datetime('now');
    elseif startEnabled
        baseDt = startDt;
    else
        baseDt = endDt;
    end
    if ~startEnabled, startDt = baseDt; end
    if ~endEnabled, endDt = baseDt; end

    result = struct('ok', false, 'tStart', '', 'tEnd', '');

    dlg = uifigure( ...
        'Name', '选择时间窗', ...
        'Position', [300 300 430 250], ...
        'WindowStyle', 'modal', ...
        'CloseRequestFcn', @onCancel);

    grid = uigridlayout(dlg, [4 5]);
    grid.RowHeight = {32, 32, 32, 40};
    grid.ColumnWidth = {90, 110, 55, 55, 55};
    grid.Padding = [10 10 10 10];
    grid.RowSpacing = 8;
    grid.ColumnSpacing = 8;

    startChk = uicheckbox(grid, 'Text', '开始时间', 'Value', startEnabled);
    startChk.Layout.Row = 1; startChk.Layout.Column = 1;
    startDate = uidatepicker(grid, 'Value', startDt, 'DisplayFormat', 'yyyy-MM-dd');
    startDate.Layout.Row = 1; startDate.Layout.Column = 2;
    startH = uispinner(grid, 'Limits', [0 23], 'RoundFractionalValues', true, 'Value', hour(startDt));
    startH.Layout.Row = 1; startH.Layout.Column = 3;
    startM = uispinner(grid, 'Limits', [0 59], 'RoundFractionalValues', true, 'Value', minute(startDt));
    startM.Layout.Row = 1; startM.Layout.Column = 4;
    startS = uispinner(grid, 'Limits', [0 59], 'RoundFractionalValues', true, 'Value', second(startDt));
    startS.Layout.Row = 1; startS.Layout.Column = 5;

    endChk = uicheckbox(grid, 'Text', '结束时间', 'Value', endEnabled);
    endChk.Layout.Row = 2; endChk.Layout.Column = 1;
    endDate = uidatepicker(grid, 'Value', endDt, 'DisplayFormat', 'yyyy-MM-dd');
    endDate.Layout.Row = 2; endDate.Layout.Column = 2;
    endH = uispinner(grid, 'Limits', [0 23], 'RoundFractionalValues', true, 'Value', hour(endDt));
    endH.Layout.Row = 2; endH.Layout.Column = 3;
    endM = uispinner(grid, 'Limits', [0 59], 'RoundFractionalValues', true, 'Value', minute(endDt));
    endM.Layout.Row = 2; endM.Layout.Column = 4;
    endS = uispinner(grid, 'Limits', [0 59], 'RoundFractionalValues', true, 'Value', second(endDt));
    endS.Layout.Row = 2; endS.Layout.Column = 5;

    hint = uilabel(grid, 'Text', '未勾选的端点将保存为空。时间格式：yyyy-MM-dd HH:mm:ss');
    hint.Layout.Row = 3; hint.Layout.Column = [1 5];

    btnGrid = uigridlayout(grid, [1 2]);
    btnGrid.Layout.Row = 4; btnGrid.Layout.Column = [4 5];
    btnGrid.RowHeight = {'1x'};
    btnGrid.ColumnWidth = {'1x', '1x'};
    btnGrid.Padding = [0 0 0 0];
    btnGrid.ColumnSpacing = 8;

    okBtn = uibutton(btnGrid, 'Text', '确定', 'ButtonPushedFcn', @onConfirm); %#ok<NASGU>
    cancelBtn = uibutton(btnGrid, 'Text', '取消', 'ButtonPushedFcn', @onCancel); %#ok<NASGU>

    startChk.ValueChangedFcn = @(src,~) toggle_row(src.Value, startDate, startH, startM, startS);
    endChk.ValueChangedFcn = @(src,~) toggle_row(src.Value, endDate, endH, endM, endS);

    toggle_row(startEnabled, startDate, startH, startM, startS);
    toggle_row(endEnabled, endDate, endH, endM, endS);

    if ~isempty(parentFig) && isvalid(parentFig)
        dlg.Icon = parentFig.Icon;
    end

    uiwait(dlg);

    ok = result.ok;
    tStart = result.tStart;
    tEnd = result.tEnd;

    function onConfirm(~, ~)
        result.ok = true;
        if startChk.Value
            result.tStart = build_time_string(startDate.Value, startH.Value, startM.Value, startS.Value);
        end
        if endChk.Value
            result.tEnd = build_time_string(endDate.Value, endH.Value, endM.Value, endS.Value);
        end
        delete(dlg);
    end

    function onCancel(~, ~)
        result.ok = false;
        if isvalid(dlg)
            delete(dlg);
        end
    end
end

function [enabled, dt] = parse_init_time(raw)
    enabled = false;
    dt = datetime('now');
    if isstring(raw)
        raw = char(raw);
    end
    if ~(ischar(raw) && ~isempty(strtrim(raw)))
        return;
    end
    try
        dt = datetime(raw, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
        enabled = true;
    catch
    end
end

function toggle_row(tf, dateCtrl, hourCtrl, minCtrl, secCtrl)
    state = matlab.lang.OnOffSwitchState(tf);
    dateCtrl.Enable = state;
    hourCtrl.Enable = state;
    minCtrl.Enable = state;
    secCtrl.Enable = state;
end

function out = build_time_string(dt, hh, mm, ss)
    dt = datetime(year(dt), month(dt), day(dt), hh, mm, floor(ss));
    out = char(string(dt, 'yyyy-MM-dd HH:mm:ss'));
end
