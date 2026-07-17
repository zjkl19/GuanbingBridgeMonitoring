function [rule, sourceCurve] = pick_threshold_box_from_fig(parentFig, figPath, side, options)
%PICK_THRESHOLD_BOX_FROM_FIG Select one-sided threshold from FIG samples.
%   LOWER takes the highest finite sample inside the rectangle; values
%   strictly below it are candidates for cleaning. UPPER takes the lowest
%   finite sample inside the rectangle; values strictly above it are
%   candidates for cleaning. Rectangle edges themselves are retained.

    rule = [];
    sourceCurve = bms.gui.FigCurveSelector.metadata([]);
    if nargin < 1
        parentFig = [];
    end
    if nargin < 2
        figPath = '';
    end
    if nargin < 3
        side = '';
    end
    if nargin < 4 || isempty(options)
        options = struct();
    end
    side = lower(strtrim(char(string(side))));
    if ~ismember(side, {'lower', 'upper'})
        error('BMS:FigThresholdBox:InvalidSide', ...
            'Box threshold side must be lower or upper.');
    end

    if isempty(figPath)
        [name, folder] = uigetfile('*.fig', '选择 FIG 文件');
        if isequal(name, 0)
            return;
        end
        figPath = fullfile(folder, name);
    else
        figPath = char(string(figPath));
    end

    dlg = [];
    try
        if exist(figPath, 'file') ~= 2
            error('BMS:FigThresholdBox:MissingFig', ...
                'FIG 文件不存在: %s', figPath);
        end
        if bms.gui.FigCurveSelector.scriptedCancel(options)
            return;
        end
        [curve, cancelled] = bms.gui.FigCurveSelector.selectFromFile(figPath, options);
        if cancelled
            return;
        end
        sourceCurve = bms.gui.FigCurveSelector.metadata(curve);
        pointId = sourceCurve.curve_label;
        if startsWith(pointId, 'Curve') && isfield(options, 'point_id') ...
                && ~isempty(options.point_id)
            pointId = strtrim(char(string(options.point_id)));
        end

        scripted = bms.gui.FigCurveSelector.scriptedSelection(options);
        if ~isempty(fieldnames(scripted))
            x0 = bms.gui.FigCurveSelector.scriptedTime( ...
                scripted, {'selection_start', 'x_min'}, min(curve.x));
            x1 = bms.gui.FigCurveSelector.scriptedTime( ...
                scripted, {'selection_end', 'x_max'}, max(curve.x));
            y0 = bms.gui.FigCurveSelector.scriptedNumber( ...
                scripted, {'selection_min', 'y_min'}, min(curve.y));
            y1 = bms.gui.FigCurveSelector.scriptedNumber( ...
                scripted, {'selection_max', 'y_max'}, max(curve.y));
            rule = makeRule(sort([x0 x1]), sort([y0 y1]));
            return;
        end

        xLim = [min(curve.x), max(curve.x)];
        yLim = finitePaddedLimits(curve.y);
        dlg = uifigure( ...
            'Name', sprintf('FIG 框选设为%s限', sideText(side)), ...
            'Visible', 'on', ...
            'Position', [170 130 1100 700], ...
            'WindowStyle', 'modal');
        gridLayout = uigridlayout(dlg, [3 1]);
        gridLayout.RowHeight = {48, '1x', 38};
        gridLayout.Padding = [8 8 8 8];
        instruction = uilabel(gridLayout, ...
            'Text', instructionText(side), ...
            'FontWeight', 'bold', ...
            'WordWrap', 'on');
        instruction.Layout.Row = 1;
        ax = axes('Parent', gridLayout);
        ax.Layout.Row = 2;
        plot(ax, curve.x, curve.y, 'LineWidth', 1.0, ...
            'Color', [0 0.447 0.741], 'DisplayName', pointId);
        grid(ax, 'on');
        grid(ax, 'minor');
        ax.XLim = xLim;
        ax.YLim = yLim;
        datetick(ax, 'x', 'yyyy-mm-dd HH:MM', 'keeplimits');
        ax.XTickLabelRotation = 20;
        xlabel(ax, curve.x_label);
        ylabel(ax, curve.y_label);
        title(ax, sprintf('%s - %s', instructionText(side), pointId));
        footer = uilabel(gridLayout, ...
            'Text', '按住鼠标左键拖出矩形；完成初次框选后可采用、重新框选或取消。', ...
            'HorizontalAlignment', 'center');
        footer.Layout.Row = 3;

        while isvalid(dlg)
            try
                roi = drawrectangle(ax, 'StripeColor', 'r');
            catch ME
                if isempty(dlg) || ~isvalid(dlg)
                    return;
                end
                rethrow(ME);
            end
            if isempty(roi) || ~isvalid(roi)
                return;
            end
            position = roi.Position;
            xBounds = sort([position(1), position(1) + position(3)]);
            yBounds = sort([position(2), position(2) + position(4)]);
            try
                candidate = makeRule(xBounds, yBounds);
            catch ME
                if strcmp(ME.identifier, 'BMS:FigThresholdBox:NoSamples')
                    uialert(dlg, '框选区域内没有命中有限曲线样本，请重新框选。', '未命中样本');
                    delete(roi);
                    continue;
                end
                rethrow(ME);
            end
            message = sprintf( ...
                '命中 %d 个有限样本；候选%s限 = %.15g。边界值本身保留。', ...
                candidate.selected_sample_count, sideText(side), candidate.value);
            choice = uiconfirm(dlg, message, '确认框选阈值', ...
                'Options', {'采用', '重新框选', '取消'}, ...
                'DefaultOption', 1, 'CancelOption', 3);
            if strcmp(choice, '采用')
                rule = candidate;
                delete(dlg);
                dlg = [];
                return;
            elseif strcmp(choice, '重新框选')
                delete(roi);
            else
                delete(dlg);
                dlg = [];
                return;
            end
        end
    catch ME
        closeDialog();
        if isfield(options, 'throw_errors') && ~isempty(options.throw_errors) ...
                && logical(options.throw_errors(1))
            rethrow(ME);
        elseif ~isempty(parentFig) && ishghandle(parentFig)
            uialert(parentFig, ME.message, '错误');
        else
            errordlg(ME.message, '错误', 'modal');
        end
    end

    function candidate = makeRule(xBounds, yBounds)
        mask = curve.x >= xBounds(1) & curve.x <= xBounds(2) ...
            & curve.y >= yBounds(1) & curve.y <= yBounds(2) ...
            & isfinite(curve.x) & isfinite(curve.y);
        selected = curve.y(mask);
        if isempty(selected)
            error('BMS:FigThresholdBox:NoSamples', ...
                'Selection rectangle contains no finite curve samples.');
        end
        if strcmp(side, 'lower')
            value = max(selected);
        else
            value = min(selected);
        end
        candidate = struct( ...
            'point_id', pointId, ...
            'side', side, ...
            'value', value, ...
            'selected_sample_count', numel(selected), ...
            'selection_start', bms.gui.FigCurveSelector.timeText(xBounds(1)), ...
            'selection_end', bms.gui.FigCurveSelector.timeText(xBounds(2)));
    end

    function closeDialog()
        try
            if ~isempty(dlg) && isvalid(dlg)
                delete(dlg);
            end
        catch
        end
    end
end

function text = sideText(side)
    if strcmp(side, 'lower')
        text = '下';
    else
        text = '上';
    end
end

function text = instructionText(side)
    if strcmp(side, 'lower')
        text = '下侧框选：取框内实际有限样本的最高值作为下限';
    else
        text = '上侧框选：取框内实际有限样本的最低值作为上限';
    end
end

function limits = finitePaddedLimits(values)
    finite = values(isfinite(values));
    if isempty(finite)
        error('BMS:FigThresholdBox:NoFiniteValues', ...
            'Selected curve has no finite values.');
    end
    low = min(finite);
    high = max(finite);
    if low == high
        padding = max(abs(low) * 0.1, 1);
    else
        padding = 0.1 * (high - low);
    end
    limits = [low - padding, high + padding];
end
