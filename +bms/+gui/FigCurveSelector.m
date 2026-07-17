classdef FigCurveSelector
    %FIGCURVESELECTOR Read one time-series line from a trusted MATLAB FIG.
    %   Interactive callers choose an axes and a line. Automated tests may
    %   provide options.scripted_selection.axis_index/curve_index. The
    %   returned structure contains plain numeric/text data only and remains
    %   valid after the source figure is closed.

    methods (Static)
        function [curve, cancelled] = selectFromFile(figPath, options)
            if nargin < 2 || isempty(options)
                options = struct();
            end
            figPath = char(string(figPath));
            if exist(figPath, 'file') ~= 2
                error('BMS:FigCurveSelector:MissingFig', ...
                    'FIG file does not exist: %s', figPath);
            end

            fig = openfig(figPath, 'invisible');
            closeFig = onCleanup(@() bms.gui.FigCurveSelector.closeIfValid(fig)); %#ok<NASGU>
            [curve, cancelled] = bms.gui.FigCurveSelector.selectFromFigure(fig, options);
        end

        function [curve, cancelled] = selectFromFigure(fig, options)
            if nargin < 2 || isempty(options)
                options = struct();
            end
            curve = bms.gui.FigCurveSelector.emptyCurve();
            cancelled = false;

            axesList = findobj(fig, 'Type', 'axes');
            axesList = flipud(axesList(:));
            keep = false(size(axesList));
            for i = 1:numel(axesList)
                keep(i) = ~isempty( ...
                    bms.gui.FigCurveSelector.candidateLines(axesList(i)));
            end
            axesList = axesList(keep);
            if isempty(axesList)
                error('BMS:FigCurveSelector:NoAxes', ...
                    'FIG contains no axes with selectable time-series curves.');
            end

            scripted = bms.gui.FigCurveSelector.scriptedSelection(options);
            [axisIndex, cancelled] = bms.gui.FigCurveSelector.chooseIndex( ...
                scripted, 'axis_index', axesList, ...
                @(item, index) bms.gui.FigCurveSelector.axisTitle(item, index), ...
                '选择坐标轴');
            if cancelled
                return;
            end
            selectedAxes = axesList(axisIndex);

            [lines, xValues, yValues] = ...
                bms.gui.FigCurveSelector.candidateLines(selectedAxes);
            if isempty(lines)
                error('BMS:FigCurveSelector:NoLines', ...
                    'Selected axes contains no selectable time-series curves.');
            end
            [curveIndex, cancelled] = bms.gui.FigCurveSelector.chooseIndex( ...
                scripted, 'curve_index', lines, ...
                @(item, index) bms.gui.FigCurveSelector.curveLabel(item, index), ...
                '选择目标曲线（只编辑一条）');
            if cancelled
                return;
            end

            line = lines(curveIndex);
            x = xValues{curveIndex};
            y = yValues{curveIndex};
            [x, order] = sort(x(:));
            y = y(order);
            curve = struct( ...
                'x', x, ...
                'y', y, ...
                'axis_title', bms.gui.FigCurveSelector.axisTitle(selectedAxes, axisIndex), ...
                'curve_label', bms.gui.FigCurveSelector.curveLabel(line, curveIndex), ...
                'sample_count', numel(y), ...
                'x_label', bms.gui.FigCurveSelector.axisLabel(selectedAxes, 'x', '时间'), ...
                'y_label', bms.gui.FigCurveSelector.axisLabel(selectedAxes, 'y', '数值'));
        end

        function metadata = metadata(curve)
            if nargin < 1 || isempty(curve)
                curve = bms.gui.FigCurveSelector.emptyCurve();
            end
            metadata = struct( ...
                'axis_title', char(string(curve.axis_title)), ...
                'curve_label', char(string(curve.curve_label)), ...
                'sample_count', double(curve.sample_count));
        end

        function scripted = scriptedSelection(options)
            scripted = struct();
            if isstruct(options) && isfield(options, 'scripted_selection') ...
                    && isstruct(options.scripted_selection)
                scripted = options.scripted_selection;
            end
        end

        function tf = scriptedCancel(options)
            scripted = bms.gui.FigCurveSelector.scriptedSelection(options);
            tf = isfield(scripted, 'cancel') && ...
                logical(scripted.cancel(1));
        end

        function value = scriptedNumber(scripted, names, fallback)
            value = fallback;
            if ischar(names) || isstring(names)
                names = cellstr(names);
            end
            for i = 1:numel(names)
                field = char(string(names{i}));
                if isfield(scripted, field) && ~isempty(scripted.(field))
                    candidate = double(scripted.(field));
                    if ~isscalar(candidate) || ~isfinite(candidate)
                        error('BMS:FigCurveSelector:InvalidScriptedNumber', ...
                            'scripted_selection.%s must be one finite number.', field);
                    end
                    value = candidate;
                    return;
                end
            end
        end

        function value = scriptedTime(scripted, names, fallback)
            value = fallback;
            if ischar(names) || isstring(names)
                names = cellstr(names);
            end
            for i = 1:numel(names)
                field = char(string(names{i}));
                if ~isfield(scripted, field) || isempty(scripted.(field))
                    continue;
                end
                raw = scripted.(field);
                if isnumeric(raw) && isscalar(raw) && isfinite(raw)
                    value = double(raw);
                    return;
                end
                try
                    value = datenum(datetime(char(string(raw)), ...
                        'InputFormat', 'yyyy-MM-dd HH:mm:ss'));
                catch
                    try
                        value = datenum(datetime(char(string(raw))));
                    catch ME
                        error('BMS:FigCurveSelector:InvalidScriptedTime', ...
                            'scripted_selection.%s is not a valid time: %s', ...
                            field, ME.message);
                    end
                end
                return;
            end
        end

        function text = timeText(value)
            text = char(string(datetime(value, 'ConvertFrom', 'datenum'), ...
                'yyyy-MM-dd HH:mm:ss'));
        end
    end

    methods (Static, Access = private)
        function [lines, xValues, yValues] = candidateLines(ax)
            rawLines = findobj(ax, 'Type', 'line');
            rawLines = flipud(rawLines(:));
            lines = rawLines([]);
            xValues = cell(0, 1);
            yValues = cell(0, 1);
            for i = 1:numel(rawLines)
                try
                    [x, y] = bms.gui.FigCurveSelector.extractTimeSeries(rawLines(i));
                    % A two-endpoint approximately horizontal line is the
                    % conventional representation of an existing
                    % threshold/reference line. Two-point sloped time series
                    % are valid historical data and must remain selectable.
                    if max(x) <= min(x) || ...
                            bms.gui.FigCurveSelector.isLikelyReferenceLine(rawLines(i), y)
                        continue;
                    end
                    lines(end + 1, 1) = rawLines(i); %#ok<AGROW>
                    xValues{end + 1, 1} = x; %#ok<AGROW>
                    yValues{end + 1, 1} = y; %#ok<AGROW>
                catch
                    % Ordinary numeric-index plots, complex/non-numeric
                    % lines and malformed graphics remain visible in the
                    % source FIG but are deliberately absent from the picker.
                end
            end
        end

        function [index, cancelled] = chooseIndex(scripted, field, objects, labelFcn, prompt)
            cancelled = false;
            if isfield(scripted, field) && ~isempty(scripted.(field))
                index = double(scripted.(field));
                if ~isscalar(index) || ~isfinite(index) || index ~= fix(index) ...
                        || index < 1 || index > numel(objects)
                    error('BMS:FigCurveSelector:InvalidScriptedIndex', ...
                        'scripted_selection.%s is outside 1..%d.', field, numel(objects));
                end
                return;
            end
            if numel(objects) == 1
                index = 1;
                return;
            end
            labels = cell(numel(objects), 1);
            for i = 1:numel(objects)
                labels{i} = labelFcn(objects(i), i);
            end
            index = listdlg('PromptString', prompt, 'SelectionMode', 'single', ...
                'ListString', labels);
            if isempty(index)
                index = [];
                cancelled = true;
            end
        end

        function [x, y] = extractTimeSeries(line)
            xData = line.XData;
            yData = line.YData;
            if isempty(xData) || isempty(yData) || ~isnumeric(yData) || ~isreal(yData)
                error('BMS:FigCurveSelector:InvalidCurve', ...
                    'Selected line does not contain a real numeric time series.');
            end
            if isa(xData, 'datetime')
                x = datenum(xData(:));
            elseif isnumeric(xData) && isreal(xData)
                x = double(xData(:));
                try
                    years = year(datetime(x, 'ConvertFrom', 'datenum'));
                catch ME
                    error('BMS:FigCurveSelector:InvalidTimeAxis', ...
                        'Selected line XData is not a MATLAB datenum time axis: %s', ME.message);
                end
                if any(years < 1900 | years > 2100)
                    error('BMS:FigCurveSelector:InvalidTimeAxis', ...
                        'Selected line XData is outside the supported years 1900..2100.');
                end
            else
                error('BMS:FigCurveSelector:InvalidTimeAxis', ...
                    'Selected line XData must be datetime or MATLAB datenum values.');
            end
            y = double(yData(:));
            if numel(x) ~= numel(y)
                error('BMS:FigCurveSelector:LengthMismatch', ...
                    'Selected line XData and YData lengths differ.');
            end
            keep = isfinite(x) & isfinite(y);
            x = x(keep);
            y = y(keep);
            if numel(x) < 2
                error('BMS:FigCurveSelector:TooFewSamples', ...
                    'Selected line has fewer than two finite time-series samples.');
            end
        end

        function text = axisTitle(ax, index)
            text = bms.gui.FigCurveSelector.graphicsText(ax.Title.String);
            if isempty(text)
                text = sprintf('Axes %d', index);
            end
        end

        function text = curveLabel(line, index)
            text = strtrim(char(string(line.DisplayName)));
            if isempty(text)
                text = bms.gui.FigCurveSelector.legendCurveLabel(line, index);
            end
            if isempty(text)
                text = sprintf('Curve%d', index);
            end
        end

        function text = legendCurveLabel(line, index)
            % Historical FIG files sometimes store series names only in the
            % legend String property and leave every line DisplayName empty.
            % Preserve the legacy selector's positional fallback whenever a
            % legend contains exactly one label per selectable curve.
            text = '';
            try
                ax = ancestor(line, 'axes');
                fig = ancestor(ax, 'figure');
                legends = findobj(fig, 'Type', 'legend');
                legends = flipud(legends(:));
                [selectableLines, ~, ~] = ...
                    bms.gui.FigCurveSelector.candidateLines(ax);
                lineCount = numel(selectableLines);
                if index < 1 || index > lineCount
                    return;
                end

                % Prefer the legend owned by the selected axes when MATLAB
                % exposes that relationship. Fall back to the legacy
                % figure-level exact-count match for older saved FIG files.
                ordered = legends([]);
                remaining = legends([]);
                for i = 1:numel(legends)
                    belongsToAxes = false;
                    try
                        belongsToAxes = isequal(legends(i).Axes, ax);
                    catch
                    end
                    if belongsToAxes
                        ordered(end + 1, 1) = legends(i); %#ok<AGROW>
                    else
                        remaining(end + 1, 1) = legends(i); %#ok<AGROW>
                    end
                end
                ordered = [ordered; remaining];

                for i = 1:numel(ordered)
                    labels = cellstr(string(ordered(i).String));
                    if numel(labels) ~= lineCount
                        continue;
                    end
                    candidate = strtrim(char(string(labels{index})));
                    if ~isempty(candidate)
                        text = candidate;
                        return;
                    end
                end
            catch
                text = '';
            end
        end

        function tf = isLikelyReferenceLine(line, y)
            tf = false;
            if numel(y) ~= 2
                return;
            end
            y = double(y(:));
            scale = max(1, max(abs(y)));
            tolerance = max(1e-12, 64 * eps(scale));
            if abs(y(2) - y(1)) > tolerance
                return;
            end

            % Two-sample constant data is legitimate historical data.  Do
            % not discard it solely because it is horizontal; require the
            % usual threshold/reference semantics or a non-solid line style.
            label = "";
            tag = "";
            style = "";
            try
                label = lower(strtrim(string(line.DisplayName)));
            catch
            end
            try
                tag = lower(strtrim(string(line.Tag)));
            catch
            end
            try
                style = strtrim(string(line.LineStyle));
            catch
            end
            semanticText = label + " " + tag;
            semanticClues = [ ...
                "threshold", "reference", "limit", "lower", "upper", ...
                "alarm", "warning", "min", "max", ...
                "阈值", "参考线", "限值", "下限", "上限", "报警", "预警"];
            tf = any(contains(semanticText, semanticClues)) || ...
                (strlength(style) > 0 && style ~= "-");
        end

        function text = axisLabel(ax, name, fallback)
            text = fallback;
            try
                if strcmpi(name, 'x')
                    raw = ax.XLabel.String;
                else
                    raw = ax.YLabel.String;
                end
                candidate = bms.gui.FigCurveSelector.graphicsText(raw);
                if ~isempty(candidate)
                    text = candidate;
                end
            catch
            end
        end

        function text = graphicsText(raw)
            if iscell(raw)
                raw = strjoin(cellstr(string(raw)), ' ');
            end
            text = strtrim(char(string(raw)));
        end

        function curve = emptyCurve()
            curve = struct('x', [], 'y', [], 'axis_title', '', ...
                'curve_label', '', 'sample_count', 0, ...
                'x_label', '时间', 'y_label', '数值');
        end

        function closeIfValid(fig)
            try
                if ~isempty(fig) && isgraphics(fig)
                    close(fig);
                end
            catch
            end
        end
    end
end
