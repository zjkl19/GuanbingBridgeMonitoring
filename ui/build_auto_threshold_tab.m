function at = build_auto_threshold_tab(tabAuto, f, cfgCache, cfgPath, cfgEdit, rootEdit, startPicker, endPicker, addLog, primaryBlue)
% build_auto_threshold_tab  Draft automatic cleaning-threshold suggestions.

    if nargin < 9 || isempty(addLog)
        addLog = @(~) [];
    end
    if nargin < 10 || isempty(primaryBlue)
        primaryBlue = [0 94 172] / 255;
    end

    main = uigridlayout(tabAuto, [1 2]);
    main.ColumnWidth = {'1.08x', '1x'};
    main.RowHeight = {'1x'};
    main.Padding = [8 8 8 8];
    main.ColumnSpacing = 8;

    left = uipanel(main, 'BorderType', 'none');
    left.Layout.Row = 1;
    left.Layout.Column = 1;
    right = uipanel(main, 'BorderType', 'none');
    right.Layout.Row = 1;
    right.Layout.Column = 2;

    grid = uigridlayout(left, [10 6]);
    grid.RowHeight = {28, 120, 32, 32, 32, 32, 32, '1x', 32, 54};
    grid.ColumnWidth = {120, 95, 95, 110, 95, '1x'};
    grid.Padding = [4 4 4 4];
    grid.RowSpacing = 6;
    grid.ColumnSpacing = 8;

    titleLbl = uilabel(grid, 'Text', '自动清洗建议：生成草稿，人工复核后再写入配置');
    titleLbl.Layout.Row = 1;
    titleLbl.Layout.Column = [1 4];
    reloadBtn = uibutton(grid, 'Text', '重新加载配置', 'ButtonPushedFcn', @(~,~) onReloadCfg());
    reloadBtn.Layout.Row = 1;
    reloadBtn.Layout.Column = 5;
    helpBtn = uibutton(grid, 'Text', '说明', 'ButtonPushedFcn', @(~,~) showHelp());
    helpBtn.Layout.Row = 1;
    helpBtn.Layout.Column = 6;

    moduleTable = uitable(grid, 'ColumnName', {'使用', '模块', '说明'}, ...
        'ColumnEditable', [true false false], 'RowName', {});
    moduleTable.Layout.Row = 2;
    moduleTable.Layout.Column = [1 6];
    moduleTable.ColumnWidth = {54, 150, 260};

    cbAutoCut = uicheckbox(grid, 'Text', '智能切线', 'Value', true);
    cbAutoCut.Layout.Row = 3; cbAutoCut.Layout.Column = 1;
    autoCutMode = uidropdown(grid, 'Items', {'标准', '保守', '激进'}, 'Value', '标准');
    autoCutMode.Layout.Row = 3; autoCutMode.Layout.Column = 2;
    autoCutHint = uilabel(grid, 'Text', '自动判断单边切线，一刀切不了就分段', 'FontColor', [0.35 0.35 0.35]);
    autoCutHint.Layout.Row = 3; autoCutHint.Layout.Column = [3 6];

    cbQuantile = uicheckbox(grid, 'Text', '分位数', 'Value', false);
    cbQuantile.Layout.Row = 4; cbQuantile.Layout.Column = 1;
    qLow = uieditfield(grid, 'numeric', 'Value', 0.5, 'Limits', [0 50], 'ValueDisplayFormat', '%.3g');
    qLow.Layout.Row = 4; qLow.Layout.Column = 2;
    qHigh = uieditfield(grid, 'numeric', 'Value', 99.5, 'Limits', [50 100], 'ValueDisplayFormat', '%.3g');
    qHigh.Layout.Row = 4; qHigh.Layout.Column = 3;
    padFactor = uieditfield(grid, 'numeric', 'Value', 0.05, 'Limits', [0 10], 'ValueDisplayFormat', '%.3g');
    padFactor.Layout.Row = 4; padFactor.Layout.Column = 4;
    qHint = uilabel(grid, 'Text', '低/高/外扩', 'FontColor', [0.35 0.35 0.35]);
    qHint.Layout.Row = 4; qHint.Layout.Column = [5 6];

    cbMad = uicheckbox(grid, 'Text', 'MAD', 'Value', false);
    cbMad.Layout.Row = 5; cbMad.Layout.Column = 1;
    madFactor = uieditfield(grid, 'numeric', 'Value', 6, 'Limits', [0.1 100], 'ValueDisplayFormat', '%.3g');
    madFactor.Layout.Row = 5; madFactor.Layout.Column = 2;
    cbIqr = uicheckbox(grid, 'Text', 'IQR', 'Value', false);
    cbIqr.Layout.Row = 5; cbIqr.Layout.Column = 3;
    iqrFactor = uieditfield(grid, 'numeric', 'Value', 3, 'Limits', [0.1 100], 'ValueDisplayFormat', '%.3g');
    iqrFactor.Layout.Row = 5; iqrFactor.Layout.Column = 4;
    cbZeroFlat = uicheckbox(grid, 'Text', '零值/固定值提示', 'Value', true);
    cbZeroFlat.Layout.Row = 5; cbZeroFlat.Layout.Column = [5 6];

    cbWindow = uicheckbox(grid, 'Text', '局部尖峰时间窗', 'Value', false);
    cbWindow.Layout.Row = 6; cbWindow.Layout.Column = 1;
    spikeFactor = uieditfield(grid, 'numeric', 'Value', 8, 'Limits', [0.1 100], 'ValueDisplayFormat', '%.3g');
    spikeFactor.Layout.Row = 6; spikeFactor.Layout.Column = 2;
    minWindowPoints = uieditfield(grid, 'numeric', 'Value', 3, 'Limits', [1 Inf], 'RoundFractionalValues', 'on');
    minWindowPoints.Layout.Row = 6; minWindowPoints.Layout.Column = 3;
    maxWindowRows = uieditfield(grid, 'numeric', 'Value', 3, 'Limits', [1 Inf], 'RoundFractionalValues', 'on');
    maxWindowRows.Layout.Row = 6; maxWindowRows.Layout.Column = 4;
    wHint = uilabel(grid, 'Text', '系数/点数/最多窗', 'FontColor', [0.35 0.35 0.35]);
    wHint.Layout.Row = 6; wHint.Layout.Column = [5 6];

    minValidLbl = uilabel(grid, 'Text', '最少有效点', 'HorizontalAlignment', 'right');
    minValidLbl.Layout.Row = 7; minValidLbl.Layout.Column = 1;
    minValid = uieditfield(grid, 'numeric', 'Value', 30, 'Limits', [1 Inf], 'RoundFractionalValues', 'on');
    minValid.Layout.Row = 7; minValid.Layout.Column = 2;
    maxRemovedLbl = uilabel(grid, 'Text', '最大剔除比例', 'HorizontalAlignment', 'right');
    maxRemovedLbl.Layout.Row = 7; maxRemovedLbl.Layout.Column = 3;
    maxRemovedRatio = uieditfield(grid, 'numeric', 'Value', 0.20, 'Limits', [0 1], 'ValueDisplayFormat', '%.3g');
    maxRemovedRatio.Layout.Row = 7; maxRemovedRatio.Layout.Column = 4;
    ignoreExisting = uicheckbox(grid, 'Text', '生成时忽略现有清洗阈值', 'Value', true);
    ignoreExisting.Layout.Row = 7; ignoreExisting.Layout.Column = [5 6];

    cbAutoCut.Tooltip = '主算法：自动找单边清洗切线。能一刀切就给全时段阈值，一刀不安全就输出少量局部时间窗。';
    autoCutMode.Tooltip = '保守更少误切，标准用于日常复核，激进会接受更小的正常/异常间隙。';
    cbQuantile.Tooltip = '按全时段低/高分位数估计建议上下限，适合先剔除极端尾部值。';
    qLow.Tooltip = '低分位百分比，例如 0.5 表示取最小的 0.5% 之外作为下限。';
    qHigh.Tooltip = '高分位百分比，例如 99.5 表示取最大的 0.5% 之外作为上限。';
    padFactor.Tooltip = '在分位数范围两侧继续放宽的比例，0.05 表示放宽 5%。';
    cbMad.Tooltip = '以中位数和 MAD 估计稳健范围，对少量异常点不敏感。';
    madFactor.Tooltip = 'MAD 系数越大，建议范围越宽，误删风险越低。';
    cbIqr.Tooltip = '以 25/75 分位和四分位距估计范围，适合主体稳定但分布偏斜的数据。';
    iqrFactor.Tooltip = 'IQR 系数越大，建议范围越宽。';
    cbZeroFlat.Tooltip = '当 0 值或固定值比例异常高时给出人工复核提示。';
    cbWindow.Tooltip = '识别短时尖峰并输出局部时间窗，不把阈值扩展到全时段。';
    spikeFactor.Tooltip = '局部尖峰敏感系数，越小越敏感。';
    minWindowPoints.Tooltip = '一个时间窗内至少包含多少个异常点才生成建议。';
    maxWindowRows.Tooltip = '每个测点按尖峰强度最多输出多少个局部时间窗建议。';
    minValid.Tooltip = '有效样本数低于该值时跳过，避免小样本误判。';
    maxRemovedRatio.Tooltip = '建议剔除比例超过该值时丢弃，避免把整段正常数据当异常。';
    ignoreExisting.Tooltip = '生成建议时直接分析原始曲线，避免旧阈值先过滤异常点。';

    proposalTable = uitable(grid, 'ColumnName', bms.config.AutoThresholdProposalService.tableColumns(), ...
        'ColumnEditable', [true false false false false true true true true false false false false true], ...
        'RowName', {}, 'CellSelectionCallback', @(tbl,evt) onProposalSelection(evt), ...
        'CellEditCallback', @(tbl,evt) onProposalEdited(evt));
    proposalTable.Layout.Row = 8;
    proposalTable.Layout.Column = [1 6];
    proposalTable.ColumnWidth = {58, 120, 190, 95, 95, 80, 80, 155, 155, 85, 85, 85, 70, 260};

    genBtn = uibutton(grid, 'Text', '生成建议', 'BackgroundColor', primaryBlue, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~,~) onGenerate());
    genBtn.Layout.Row = 9; genBtn.Layout.Column = [1 2];
    applyBtn = uibutton(grid, 'Text', '应用勾选到配置', 'ButtonPushedFcn', @(~,~) onApply());
    applyBtn.Layout.Row = 9; applyBtn.Layout.Column = [3 4];
    exportBtn = uibutton(grid, 'Text', '导出建议', 'ButtonPushedFcn', @(~,~) onExport());
    exportBtn.Layout.Row = 9; exportBtn.Layout.Column = 5;
    clearBtn = uibutton(grid, 'Text', '清空', 'ButtonPushedFcn', @(~,~) clearProposals());
    clearBtn.Layout.Row = 9; clearBtn.Layout.Column = 6;

    msg = uitextarea(grid, 'Editable', 'off', 'Value', {'准备就绪。'});
    msg.Layout.Row = 10;
    msg.Layout.Column = [1 6];

    rgrid = uigridlayout(right, [3 1]);
    rgrid.RowHeight = {30, '1x', 92};
    rgrid.ColumnWidth = {'1x'};
    rgrid.Padding = [4 4 4 4];
    rgrid.RowSpacing = 6;

    previewBar = uigridlayout(rgrid, [1 2]);
    previewBar.Layout.Row = 1;
    previewBar.Layout.Column = 1;
    previewBar.ColumnWidth = {'1x', 110};
    previewBar.RowHeight = {'1x'};
    previewBar.Padding = [0 0 0 0];
    previewTitle = uilabel(previewBar, 'Text', '预览', 'FontWeight', 'bold');
    previewTitle.Layout.Row = 1;
    previewTitle.Layout.Column = 1;
    popupBtn = uibutton(previewBar, 'Text', '弹出预览', 'ButtonPushedFcn', @(~,~) openPreviewWindow());
    popupBtn.Layout.Row = 1;
    popupBtn.Layout.Column = 2;

    ax = uiaxes(rgrid);
    ax.Layout.Row = 2;
    ax.Layout.Column = 1;
    ax.XGrid = 'on';
    ax.YGrid = 'on';
    try
        ax.PlotBoxAspectRatio = [1.65 1 1];
    catch
    end
    info = uitextarea(rgrid, 'Editable', 'off', 'Value', {'选择一条建议后显示曲线预览。'});
    info.Layout.Row = 3;
    info.Layout.Column = 1;

    lastResult = [];
    selectedRow = [];
    previewMaxPoints = 20000;
    previewCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    refreshModules();

    function refreshModules()
        defaultKeys = bms.config.AutoThresholdProposalService.defaultModuleKeys();
        try
            configured = bms.gui.ConfigEditorService.editableModuleKeys(cfgCache, 'threshold');
            configured = configured(ismember(configured, defaultKeys));
            keys = [configured(:); defaultKeys(:)];
            keys = unique(keys, 'stable');
        catch
            keys = defaultKeys;
        end
        labels = bms.config.AutoThresholdProposalService.moduleLabels(keys);
        data = cell(numel(keys), 3);
        for i = 1:numel(keys)
            data{i, 1} = true;
            data{i, 2} = keys{i};
            data{i, 3} = labels{i};
        end
        moduleTable.Data = data;
    end

    function opts = readOptions()
        opts = bms.config.AutoThresholdProposalService.defaultOptions();
        mdata = moduleTable.Data;
        keys = {};
        for i = 1:size(mdata, 1)
            if logical(mdata{i, 1})
                keys{end+1, 1} = char(string(mdata{i, 2})); %#ok<AGROW>
            end
        end
        opts.module_keys = keys;
        opts.use_auto_cut = logical(cbAutoCut.Value);
        opts.auto_cut_mode = modeValue(autoCutMode.Value);
        opts.auto_cut_max_proposals_per_point = maxWindowRows.Value;
        opts.auto_cut_min_removed_count = minWindowPoints.Value;
        opts.use_quantile = logical(cbQuantile.Value);
        opts.quantile_low = qLow.Value;
        opts.quantile_high = qHigh.Value;
        opts.padding_factor = padFactor.Value;
        opts.use_mad = logical(cbMad.Value);
        opts.mad_factor = madFactor.Value;
        opts.use_iqr = logical(cbIqr.Value);
        opts.iqr_factor = iqrFactor.Value;
        opts.use_spike_window = logical(cbWindow.Value);
        opts.spike_mad_factor = spikeFactor.Value;
        opts.min_window_points = minWindowPoints.Value;
        opts.max_window_proposals_per_point = maxWindowRows.Value;
        opts.use_zero_or_flat = logical(cbZeroFlat.Value);
        opts.min_valid_count = minValid.Value;
        opts.max_removed_ratio = maxRemovedRatio.Value;
        opts.load_without_existing_cleaning = logical(ignoreExisting.Value);
        opts.capture_preview_series = true;
        opts.preview_sample_count = previewMaxPoints;
    end

    function value = modeValue(label)
        switch char(string(label))
            case '保守'
                value = 'conservative';
            case '激进'
                value = 'aggressive';
            otherwise
                value = 'standard';
        end
    end

    function onGenerate()
        try
            cfgCache = bms.gui.ConfigEditorService.load(cfgEdit.Value);
            cfgPath = cfgEdit.Value;
            opts = readOptions();
            if isempty(opts.module_keys)
                msg.Value = {'请至少勾选一个模块。'};
                return;
            end
            msg.Value = {'正在生成自动清洗建议...'};
            drawnow;
            lastResult = bms.config.AutoThresholdProposalService.generate( ...
                cfgCache, rootEdit.Value, startPicker.Value, endPicker.Value, opts);
            resetPreviewCache();
            seedPreviewCache(lastResult);
            proposalTable.Data = bms.config.AutoThresholdProposalService.proposalsToCell(lastResult.proposals);
            reportText = sprintf('生成完成：%d 条建议。', lastResult.summary.proposal_count);
            msg.Value = [{reportText}; moduleReportLines(lastResult.summary.module_reports)];
            addLog(reportText);
            plotFirstProposal();
        catch ME
            msg.Value = {['生成失败: ' ME.message]};
            uialert(f, ME.message, '自动清洗建议生成失败');
        end
    end

    function onApply()
        try
            data = proposalTable.Data;
            if isempty(data)
                msg.Value = {'没有可应用的建议。'};
                return;
            end
            proposals = bms.config.AutoThresholdProposalService.cellToProposals(data);
            selected = false(numel(proposals), 1);
            for i = 1:numel(proposals)
                selected(i) = logical(proposals(i).selected) && any(strcmp(proposals(i).kind, {'range', 'window_range'}));
            end
            if ~any(selected)
                msg.Value = {'没有勾选可写入配置的阈值建议。'};
                return;
            end
            cfgNew = bms.config.AutoThresholdProposalService.applyAccepted(cfgCache, proposals(selected));
            validate_config(cfgNew, false);
            [cfgCache, saveReport] = bms.gui.ConfigEditorService.saveAndReload(cfgNew, cfgEdit.Value, true);
            cfgPath = cfgEdit.Value;
            txt = sprintf('已写入 %d 条建议到配置，变更 %d 项。', sum(selected), saveReport.changed_count);
            msg.Value = {txt; '建议重新运行对应模块，检查曲线和统计结果。'};
            addLog(txt);
        catch ME
            msg.Value = {['写入失败: ' ME.message]};
            uialert(f, ME.message, '自动清洗建议写入失败');
        end
    end

    function onExport()
        try
            if isempty(lastResult)
                lastResult = struct();
                lastResult.schema_version = 1;
                lastResult.proposal_type = 'auto_threshold_proposals';
                lastResult.created_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
                lastResult.root_dir = rootEdit.Value;
                lastResult.start_date = datestr(startPicker.Value, 'yyyy-mm-dd');
                lastResult.end_date = datestr(endPicker.Value, 'yyyy-mm-dd');
                lastResult.options = readOptions();
                lastResult.summary = struct();
            end
            lastResult.proposals = bms.config.AutoThresholdProposalService.cellToProposals(proposalTable.Data);
            paths = bms.config.AutoThresholdProposalService.writeArtifacts(rootEdit.Value, lastResult);
            lines = {['已导出 JSON: ' paths.json]};
            if ~isempty(paths.xlsx)
                lines{end+1,1} = ['已导出 Excel: ' paths.xlsx]; %#ok<AGROW>
            end
            msg.Value = lines;
            addLog(lines{1});
        catch ME
            msg.Value = {['导出失败: ' ME.message]};
        end
    end

    function clearProposals()
        proposalTable.Data = cell(0, numel(bms.config.AutoThresholdProposalService.tableColumns()));
        lastResult = [];
        selectedRow = [];
        resetPreviewCache();
        cla(ax);
        info.Value = {'已清空建议。'};
        msg.Value = {'已清空。'};
    end

    function onReloadCfg()
        try
            cfgCache = bms.gui.ConfigEditorService.load(cfgEdit.Value);
            cfgPath = cfgEdit.Value;
            refreshModules();
            resetPreviewCache();
            msg.Value = {['已重新加载配置: ' cfgPath]};
        catch ME
            msg.Value = {['加载配置失败: ' ME.message]};
        end
    end

    function onProposalSelection(evt)
        if isempty(evt.Indices)
            return;
        end
        selectedRow = evt.Indices(1, 1);
        previewRow(selectedRow);
    end

    function onProposalEdited(~)
        if ~isempty(selectedRow)
            previewRow(selectedRow);
        end
    end

    function plotFirstProposal()
        data = proposalTable.Data;
        if isempty(data)
            cla(ax);
            info.Value = {'没有生成可预览的建议。'};
            return;
        end
        selectedRow = 1;
        previewRow(1);
    end

    function openPreviewWindow()
        data = proposalTable.Data;
        if isempty(data)
            info.Value = {'没有可预览的建议。'};
            return;
        end
        rowIdx = selectedRow;
        if isempty(rowIdx) || rowIdx < 1 || rowIdx > size(data, 1)
            rowIdx = 1;
        end
        try
            p = proposalFromRow(rowIdx);
            dlg = uifigure('Name', '自动清洗建议预览', 'Position', [80 80 1120 640]);
            dlgLayout = uigridlayout(dlg, [2 1]);
            dlgLayout.RowHeight = {'1x', 115};
            dlgLayout.ColumnWidth = {'1x'};
            dlgLayout.Padding = [10 10 10 10];
            popupAx = uiaxes(dlgLayout);
            popupAx.Layout.Row = 1;
            popupAx.Layout.Column = 1;
            popupInfo = uitextarea(dlgLayout, 'Editable', 'off');
            popupInfo.Layout.Row = 2;
            popupInfo.Layout.Column = 1;
            try
                popupAx.PlotBoxAspectRatio = [1.9 1 1];
            catch
            end
            renderPreviewForProposal(popupAx, popupInfo, p);
        catch ME
            info.Value = {['弹出预览失败: ' ME.message]};
        end
    end

    function previewRow(rowIdx)
        data = proposalTable.Data;
        if isempty(data) || rowIdx < 1 || rowIdx > size(data, 1)
            return;
        end
        try
            p = proposalFromRow(rowIdx);
            renderPreviewForProposal(ax, info, p);
        catch ME
            info.Value = {['预览失败: ' ME.message]};
        end
    end

    function p = proposalFromRow(rowIdx)
        p = bms.config.AutoThresholdProposalService.cellToProposals(proposalTable.Data(rowIdx, :));
        p = p(1);
    end

    function resetPreviewCache()
        previewCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    end

    function seedPreviewCache(result)
        if ~isstruct(result) || ~isfield(result, 'preview_series')
            return;
        end
        rows = result.preview_series;
        for i = 1:numel(rows)
            if ~isfield(rows(i), 'times') || ~isfield(rows(i), 'values')
                continue;
            end
            key = bms.config.AutoThresholdProposalService.previewCacheKey(rows(i).module_key, rows(i).point_id);
            previewCache(key) = rows(i);
        end
    end

    function series = getPreviewSeries(p)
        key = bms.config.AutoThresholdProposalService.previewCacheKey(p.module_key, p.point_id);
        if isKey(previewCache, key)
            series = previewCache(key);
            return;
        end
        [times, values] = bms.config.AutoThresholdProposalService.loadSeriesForPreview( ...
            cfgCache, rootEdit.Value, startPicker.Value, endPicker.Value, ...
            p.module_key, p.point_id, logical(ignoreExisting.Value));
        [tp, vp] = bms.config.AutoThresholdProposalService.sampleSeries(times, values, previewMaxPoints);
        series = struct();
        series.module_key = p.module_key;
        series.point_id = p.point_id;
        series.sensor_type = '';
        series.times = tp;
        series.values = vp;
        series.sample_count = numel(vp);
        previewCache(key) = series;
    end

    function renderPreviewForProposal(targetAx, targetInfo, p)
        series = getPreviewSeries(p);
        drawPreview(targetAx, targetInfo, p, series);
    end

    function drawPreview(targetAx, targetInfo, p, series)
        cla(targetAx);
        targetAx.XGrid = 'on';
        targetAx.YGrid = 'on';
        values = series.values(:);
        times = series.times(:);
        if isempty(values)
            targetInfo.Value = {['无数据: ' p.point_id]};
            return;
        end
        if isempty(times)
            times = (1:numel(values))';
        end

        targetAx.XLimMode = 'auto';
        targetAx.YLimMode = 'auto';
        plot(targetAx, times, values, '-', 'LineWidth', 0.8, 'Color', [0.10 0.35 0.70]);
        hold(targetAx, 'on');

        finiteMask = isfinite(values);
        finiteTimes = times(finiteMask);
        if isempty(finiteTimes)
            finiteTimes = times;
        end
        if ~isempty(finiteTimes)
            [hasRange, t0, t1] = proposalTimeRange(p);
            if hasRange
                x0 = t0;
                x1 = t1;
                yl = ylim(targetAx);
                drawRangePatch(targetAx, t0, t1, yl);
            else
                x0 = finiteTimes(1);
                x1 = finiteTimes(end);
            end
            drawThresholdSegment(targetAx, x0, x1, p.min, [0.85 0.18 0.16]);
            drawThresholdSegment(targetAx, x0, x1, p.max, [0.85 0.18 0.16]);
            if hasRange
                drawRangeBoundary(targetAx, t0, [0.20 0.20 0.20]);
                drawRangeBoundary(targetAx, t1, [0.20 0.20 0.20]);
            end
        else
            hasRange = false;
            t0 = [];
            t1 = [];
        end

        hold(targetAx, 'off');
        title(targetAx, sprintf('%s | %s | %s', p.module_key, p.point_id, p.algorithm), 'Interpreter', 'none');
        ylabel(targetAx, 'value');
        xlabel(targetAx, 'time');
        targetInfo.Value = previewInfoLines(p, series, hasRange, t0, t1);
    end

    function drawRangePatch(targetAx, t0, t1, yl)
        if numel(yl) < 2 || ~all(isfinite(yl)) || yl(1) == yl(2)
            return;
        end
        try
            h = patch(targetAx, [t0 t1 t1 t0], [yl(1) yl(1) yl(2) yl(2)], ...
                [1.00 0.82 0.22], 'FaceAlpha', 0.16, 'EdgeColor', 'none');
            try
                uistack(h, 'bottom');
            catch
            end
        catch
        end
    end

    function drawThresholdSegment(targetAx, x0, x1, y, color)
        if isempty(y) || ~isnumeric(y) || ~isfinite(y)
            return;
        end
        line(targetAx, [x0 x1], [y y], 'LineStyle', '--', ...
            'Color', color, 'LineWidth', 1.1);
    end

    function drawRangeBoundary(targetAx, t, color)
        try
            yl = ylim(targetAx);
            line(targetAx, [t t], yl, 'LineStyle', ':', 'Color', color, 'LineWidth', 1.0);
        catch
        end
    end

    function [hasRange, t0, t1] = proposalTimeRange(p)
        hasRange = false;
        t0 = [];
        t1 = [];
        if ~isfield(p, 't_range_start') || ~isfield(p, 't_range_end')
            return;
        end
        s = strtrim(char(string(p.t_range_start)));
        e = strtrim(char(string(p.t_range_end)));
        if isempty(s) || isempty(e)
            return;
        end
        try
            t0 = datetime(s, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
            t1 = datetime(e, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
            if isnat(t0) || isnat(t1)
                return;
            end
            if t1 < t0
                tmp = t0;
                t0 = t1;
                t1 = tmp;
            elseif t1 == t0
                t1 = t0 + seconds(1);
            end
            hasRange = true;
        catch
            hasRange = false;
            t0 = [];
            t1 = [];
        end
    end

    function lines = previewInfoLines(p, series, hasRange, t0, t1)
        algorithmName = bms.config.AutoThresholdProposalService.algorithmDisplayName(p.algorithm);
        algorithmTip = bms.config.AutoThresholdProposalService.algorithmDescription(p.algorithm);
        if hasRange
            rangeLine = sprintf('时间范围: %s ~ %s', ...
                datestr(t0, 'yyyy-mm-dd HH:MM:SS'), datestr(t1, 'yyyy-mm-dd HH:MM:SS'));
        else
            rangeLine = '时间范围: 全时段';
        end
        sampleCount = numel(series.values);
        if isfield(series, 'sample_count') && ~isempty(series.sample_count)
            sampleCount = series.sample_count;
        end
        lines = { ...
            sprintf('模块: %s    测点: %s', p.module_key, p.point_id), ...
            sprintf('算法: %s (%s)    类型: %s', algorithmName, p.algorithm, p.kind), ...
            sprintf('建议范围: %s ~ %s    建议剔除: %g / %g (%.3g)', ...
                valueText(p.min), valueText(p.max), p.removed_count, p.valid_count, p.removed_ratio), ...
            sprintf('%s    预览点数: %d', rangeLine, sampleCount), ...
            ['原因: ' p.reason], ...
            ['说明: ' algorithmTip]};
    end

    function txt = valueText(v)
        if isnumeric(v) && isscalar(v) && isfinite(v)
            txt = sprintf('%.6g', v);
        else
            txt = '无';
        end
    end

    function lines = moduleReportLines(reports)
        lines = {};
        for i = 1:numel(reports)
            lines{end+1, 1} = sprintf('%s: 点数=%d, 建议=%d, 缺数据=%d', ... %#ok<AGROW>
                reports(i).module_key, reports(i).point_count, ...
                reports(i).proposal_count, reports(i).skipped_count);
        end
        if isempty(lines)
            lines = {'没有模块报告。'};
        end
    end

    function showHelp()
        dlg = uifigure('Name', '自动清洗建议说明', 'Position', [120 120 820 560]);
        helpLayout = uigridlayout(dlg, [1 1]);
        helpLayout.Padding = [10 10 10 10];
        helpText = uitextarea(helpLayout, 'Editable', 'off', ...
            'Value', bms.config.AutoThresholdProposalService.helpLines());
        helpText.Layout.Row = 1;
        helpText.Layout.Column = 1;
    end

    function onShow()
        if exist(cfgEdit.Value, 'file')
            try
                cfgCache = bms.gui.ConfigEditorService.load(cfgEdit.Value);
                cfgPath = cfgEdit.Value;
                refreshModules();
            catch
            end
        end
    end

    at = struct('onShow', @onShow);
end
