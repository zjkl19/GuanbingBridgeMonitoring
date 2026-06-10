function psTab = build_plot_settings_tab(tabCfg, f, cfgCache, cfgPath, cfgEdit, addLog, primaryBlue)
% build_plot_settings_tab Build controlled plot/style/spectrum editors.

    if nargin < 6 || isempty(addLog)
        addLog = @(~) [];
    end

    moduleDefs = plot_module_defs();
    moduleValues = arrayfun(@(x)x.value, moduleDefs, 'UniformOutput', false);
    moduleLabels = arrayfun(@(x)x.label, moduleDefs, 'UniformOutput', false);

    draftCfg = cfgCache;
    currentModule = moduleValues{1};
    currentWarnField = 'warn_lines';
    warnExpanded = false;
    selectedYlimRows = [];
    selectedAlarmRows = [];
    selectedWarnRows = [];
    selectedPeakRows = [];
    warnTableDerivedPreview = false;
    updating = false;

    grid = uigridlayout(tabCfg, [5 4]);
    grid.RowHeight = {150, 32, '1x', 36, 64};
    grid.ColumnWidth = {'1x', '1x', '1x', 160};
    grid.Padding = [8 8 8 8];
    grid.RowSpacing = 8;
    grid.ColumnSpacing = 8;

    globalPanel = uipanel(grid, 'Title', '全局绘图保存设置');
    globalPanel.Layout.Row = 1; globalPanel.Layout.Column = [1 4];
    globalGrid = uigridlayout(globalPanel, [4 4]);
    globalGrid.RowHeight = {28, 28, 28, 28};
    globalGrid.ColumnWidth = {'1x', '1x', 160, '1x'};

    cbSaveFig = uicheckbox(globalGrid, 'Text', '保存 .fig', ...
        'ValueChangedFcn', @(~,~) onGlobalChanged());
    cbSaveFig.Layout.Row = 1; cbSaveFig.Layout.Column = 1;

    cbLightFig = uicheckbox(globalGrid, 'Text', '轻量 .fig', ...
        'ValueChangedFcn', @(~,~) onGlobalChanged());
    cbLightFig.Layout.Row = 1; cbLightFig.Layout.Column = 2;

    figMaxLabel = uilabel(globalGrid, 'Text', 'fig_max_points', 'HorizontalAlignment', 'right', ...
        'Tooltip', '单条曲线点数超过此阈值时，保存 .fig 前做保峰降采样。');
    figMaxLabel.Layout.Row = 1; figMaxLabel.Layout.Column = 3;
    figMaxEdit = uieditfield(globalGrid, 'numeric', 'Limits', [1000 Inf], ...
        'RoundFractionalValues', true, 'ValueDisplayFormat', '%.0f', ...
        'ValueChangedFcn', @(~,~) onGlobalChanged());
    figMaxEdit.Layout.Row = 1; figMaxEdit.Layout.Column = 4;

    cbAutoFolders = uicheckbox(globalGrid, 'Text', '自动整理结果目录视图', ...
        'ValueChangedFcn', @(~,~) onGlobalChanged());
    cbAutoFolders.Layout.Row = 2; cbAutoFolders.Layout.Column = [1 2];

    cbAppendTimestamp = uicheckbox(globalGrid, 'Text', '图片追加运行时间戳', ...
        'Tooltip', '取消后保留数据周期，不追加运行时间戳；同一周期重算会覆盖旧图片。', ...
        'ValueChangedFcn', @(~,~) onGlobalChanged());
    cbAppendTimestamp.Layout.Row = 2; cbAppendTimestamp.Layout.Column = [3 4];

    gapModeLabel = uilabel(globalGrid, 'Text', 'Gap mode', 'HorizontalAlignment', 'right', ...
        'Tooltip', 'connect: 缺口直接连线; break: 缺口留空');
    gapModeLabel.Layout.Row = 3; gapModeLabel.Layout.Column = 1;
    gapModeDrop = uidropdown(globalGrid, 'Items', {'break', 'connect'}, ...
        'ValueChangedFcn', @(~,~) onGlobalChanged());
    gapModeDrop.Layout.Row = 3; gapModeDrop.Layout.Column = 2;

    gapFactorLabel = uilabel(globalGrid, 'Text', 'Gap factor', 'HorizontalAlignment', 'right', ...
        'Tooltip', '相邻时间差超过 median(diff)*该倍数时，break 模式断线。');
    gapFactorLabel.Layout.Row = 3; gapFactorLabel.Layout.Column = 3;
    gapFactorEdit = uieditfield(globalGrid, 'numeric', 'Limits', [1.1 Inf], ...
        'ValueDisplayFormat', '%.1f', 'RoundFractionalValues', false, ...
        'ValueChangedFcn', @(~,~) onGlobalChanged());
    gapFactorEdit.Layout.Row = 3; gapFactorEdit.Layout.Column = 4;

    globalHint = uilabel(globalGrid, 'Text', ...
        '说明：ylabel 可按 MATLAB TeX 写法输入 m/s^2、cm/s^2、f_1；^ 表示上标，_ 表示下标，应变单位建议写 με。');
    globalHint.Layout.Row = 4; globalHint.Layout.Column = [1 4];

    moduleLabel = uilabel(grid, 'Text', '模块', 'HorizontalAlignment', 'right');
    moduleLabel.Layout.Row = 2; moduleLabel.Layout.Column = 1;
    moduleDrop = uidropdown(grid, 'Items', moduleLabels, 'ItemsData', moduleValues, ...
        'Value', currentModule, 'ValueChangedFcn', @(~,~) onModuleChanged());
    moduleDrop.Layout.Row = 2; moduleDrop.Layout.Column = 2;

    reloadBtn = uibutton(grid, 'Text', '重新加载配置', 'ButtonPushedFcn', @(~,~) onReloadCfg());
    reloadBtn.Layout.Row = 2; reloadBtn.Layout.Column = 4;

    detailTabs = uitabgroup(grid);
    detailTabs.Layout.Row = 3; detailTabs.Layout.Column = [1 4];
    tabBasic = uitab(detailTabs, 'Title', '基础参数');
    tabWarn = uitab(detailTabs, 'Title', '预警线');
    tabSpectrum = uitab(detailTabs, 'Title', '频谱找峰');
    tabSummary = uitab(detailTabs, 'Title', '生效总览');

    basicGrid = uigridlayout(tabBasic, [7 4]);
    basicGrid.RowHeight = {28, 28, 28, 28, 28, '1x', 32};
    basicGrid.ColumnWidth = {130, '1x', 120, '1x'};
    basicGrid.Padding = [8 8 8 8];

    ylabelLabel = uilabel(basicGrid, 'Text', 'ylabel', 'HorizontalAlignment', 'right');
    ylabelLabel.Layout.Row = 1; ylabelLabel.Layout.Column = 1;
    ylabelEdit = uieditfield(basicGrid, 'text', 'ValueChangedFcn', @(~,~) onModuleFieldChanged());
    ylabelEdit.Layout.Row = 1; ylabelEdit.Layout.Column = [2 4];

    titleLabel = uilabel(basicGrid, 'Text', 'title_prefix', 'HorizontalAlignment', 'right');
    titleLabel.Layout.Row = 2; titleLabel.Layout.Column = 1;
    titleEdit = uieditfield(basicGrid, 'text', 'ValueChangedFcn', @(~,~) onModuleFieldChanged());
    titleEdit.Layout.Row = 2; titleEdit.Layout.Column = [2 4];

    cbYlimAuto = uicheckbox(basicGrid, 'Text', 'Y轴自动', ...
        'ValueChangedFcn', @(~,~) onModuleFieldChanged());
    cbYlimAuto.Layout.Row = 3; cbYlimAuto.Layout.Column = 1;

    ylimMinLabel = uilabel(basicGrid, 'Text', 'ylim_min', 'HorizontalAlignment', 'right');
    ylimMinLabel.Layout.Row = 3; ylimMinLabel.Layout.Column = 3;
    ylimMinEdit = uieditfield(basicGrid, 'text', 'ValueChangedFcn', @(~,~) onModuleFieldChanged());
    ylimMinEdit.Layout.Row = 3; ylimMinEdit.Layout.Column = 4;

    ylimMaxLabel = uilabel(basicGrid, 'Text', 'ylim_max', 'HorizontalAlignment', 'right');
    ylimMaxLabel.Layout.Row = 4; ylimMaxLabel.Layout.Column = 3;
    ylimMaxEdit = uieditfield(basicGrid, 'text', 'ValueChangedFcn', @(~,~) onModuleFieldChanged());
    ylimMaxEdit.Layout.Row = 4; ylimMaxEdit.Layout.Column = 4;

    cbShowOutliers = uicheckbox(basicGrid, 'Text', '箱线图显示离群值', ...
        'ValueChangedFcn', @(~,~) onModuleFieldChanged());
    cbShowOutliers.Layout.Row = 4; cbShowOutliers.Layout.Column = 1;

    cbShowWarnPoint = uicheckbox(basicGrid, 'Text', '单点图显示预警线', ...
        'ValueChangedFcn', @(~,~) onModuleFieldChanged());
    cbShowWarnPoint.Layout.Row = 5; cbShowWarnPoint.Layout.Column = 1;

    cbShowWarnBox = uicheckbox(basicGrid, 'Text', '箱线图显示预警线', ...
        'ValueChangedFcn', @(~,~) onModuleFieldChanged());
    cbShowWarnBox.Layout.Row = 5; cbShowWarnBox.Layout.Column = 2;

    ylimsTable = uitable(basicGrid, ...
        'ColumnName', {'name', 'ylim_min', 'ylim_max'}, ...
        'ColumnEditable', [true true true], ...
        'CellSelectionCallback', @(~, evt) onYlimSelected(evt), ...
        'CellEditCallback', @(~,~) onModuleFieldChanged());
    ylimsTable.Layout.Row = 6; ylimsTable.Layout.Column = [1 4];

    addYlimBtn = uibutton(basicGrid, 'Text', '新增 ylims 行', 'ButtonPushedFcn', @(~,~) add_ylims_row());
    addYlimBtn.Layout.Row = 7; addYlimBtn.Layout.Column = 1;
    delYlimBtn = uibutton(basicGrid, 'Text', '删除选中 ylims', 'ButtonPushedFcn', @(~,~) delete_ylims_rows());
    delYlimBtn.Layout.Row = 7; delYlimBtn.Layout.Column = 2;

    warnOuterGrid = uigridlayout(tabWarn, [1 1]);
    warnOuterGrid.Padding = [0 0 0 0];
    warnTabs = uitabgroup(warnOuterGrid);
    warnTabs.Layout.Row = 1; warnTabs.Layout.Column = 1;
    tabAlarmBounds = uitab(warnTabs, 'Title', '测点预警值');
    tabWarnLines = uitab(warnTabs, 'Title', '图上自定义线');

    alarmGrid = uigridlayout(tabAlarmBounds, [3 4]);
    alarmGrid.RowHeight = {32, '1x', 32};
    alarmGrid.ColumnWidth = {140, '1x', 140, 140};
    alarmGrid.Padding = [8 8 8 8];
    alarmHint = uilabel(alarmGrid, 'Text', ...
        '编辑真实预警阈值：保存后写入 per_point.<模块>.<测点>.alarm_bounds；level 必须写成 level1、level2、level3。');
    alarmHint.Layout.Row = 1; alarmHint.Layout.Column = [1 4];
    alarmTable = uitable(alarmGrid, ...
        'ColumnName', {'point_id', 'level', 'lower', 'upper', 'source'}, ...
        'ColumnEditable', [true true true true false], ...
        'CellSelectionCallback', @(~, evt) onAlarmSelected(evt), ...
        'CellEditCallback', @(~,~) onAlarmTableEdited());
    alarmTable.Layout.Row = 2; alarmTable.Layout.Column = [1 4];
    addAlarmBtn = uibutton(alarmGrid, 'Text', '新增测点预警值', 'ButtonPushedFcn', @(~,~) add_alarm_row());
    addAlarmBtn.Layout.Row = 3; addAlarmBtn.Layout.Column = 1;
    delAlarmBtn = uibutton(alarmGrid, 'Text', '删除选中预警值', 'ButtonPushedFcn', @(~,~) delete_alarm_rows());
    delAlarmBtn.Layout.Row = 3; delAlarmBtn.Layout.Column = 2;

    warnGrid = uigridlayout(tabWarnLines, [4 4]);
    warnGrid.RowHeight = {32, 28, '1x', 32};
    warnGrid.ColumnWidth = {120, '1x', 120, 140};
    warnGrid.Padding = [8 8 8 8];

    warnFieldLabel = uilabel(warnGrid, 'Text', '预警线字段', 'HorizontalAlignment', 'right');
    warnFieldLabel.Layout.Row = 1; warnFieldLabel.Layout.Column = 1;
    warnFieldDrop = uidropdown(warnGrid, 'Items', {'warn_lines', 'rms_warn_lines', 'group_warn_lines'}, ...
        'Value', currentWarnField, 'ValueChangedFcn', @(~,~) onWarnFieldChanged());
    warnFieldDrop.Layout.Row = 1; warnFieldDrop.Layout.Column = 2;
    warnExpandCheck = uicheckbox(warnGrid, 'Text', '展开测点', ...
        'Value', warnExpanded, 'ValueChangedFcn', @(~,~) onWarnExpandChanged());
    warnExpandCheck.Layout.Row = 1; warnExpandCheck.Layout.Column = 3;
    warnHint = uilabel(warnGrid, 'Text', '仅编辑图上预警线；清洗阈值仍在“阈值配置/滤波后二次清洗”页。');
    warnHint.Layout.Row = 2; warnHint.Layout.Column = [1 4];

    warnTable = uitable(warnGrid, ...
        'ColumnName', {'y', 'label', 'R', 'G', 'B', 'LineStyle'}, ...
        'ColumnEditable', true(1, 6), ...
        'CellSelectionCallback', @(~, evt) onWarnSelected(evt), ...
        'CellEditCallback', @(~,~) onWarnTableEdited());
    warnTable.Layout.Row = 3; warnTable.Layout.Column = [1 4];

    addWarnBtn = uibutton(warnGrid, 'Text', '新增预警线', 'ButtonPushedFcn', @(~,~) add_warn_row());
    addWarnBtn.Layout.Row = 4; addWarnBtn.Layout.Column = 1;
    delWarnBtn = uibutton(warnGrid, 'Text', '删除选中预警线', 'ButtonPushedFcn', @(~,~) delete_warn_rows());
    delWarnBtn.Layout.Row = 4; delWarnBtn.Layout.Column = 2;

    spectrumGrid = uigridlayout(tabSpectrum, [3 5]);
    spectrumGrid.RowHeight = {44, '1x', 32};
    spectrumGrid.ColumnWidth = {'1x', 140, 140, 140, 140};
    spectrumGrid.Padding = [8 8 8 8];

    spectrumHint = uilabel(spectrumGrid, 'Text', ...
        '频谱模块保存为 peak_orders：阶次名称、找峰中心、找峰半宽、理论频率和理论标签集中在一个表内。');
    spectrumHint.Layout.Row = 1; spectrumHint.Layout.Column = [1 5];

    peakTable = uitable(spectrumGrid, ...
        'ColumnName', bms.gui.SpectrumPeakOrderEditorService.columnNames(), ...
        'ColumnEditable', [true true true true true true true true true false], ...
        'CellSelectionCallback', @(~, evt) onPeakSelected(evt), ...
        'CellEditCallback', @(~,~) onPeakTableEdited());
    peakTable.Layout.Row = 2; peakTable.Layout.Column = [1 5];

    addPeakBtn = uibutton(spectrumGrid, 'Text', '新增阶次', 'ButtonPushedFcn', @(~,~) add_peak_row());
    addPeakBtn.Layout.Row = 3; addPeakBtn.Layout.Column = 1;
    addPointPeakBtn = uibutton(spectrumGrid, 'Text', '新增测点阶次', 'ButtonPushedFcn', @(~,~) add_point_peak_row());
    addPointPeakBtn.Layout.Row = 3; addPointPeakBtn.Layout.Column = 2;
    delPeakBtn = uibutton(spectrumGrid, 'Text', '删除选中阶次', 'ButtonPushedFcn', @(~,~) delete_peak_rows());
    delPeakBtn.Layout.Row = 3; delPeakBtn.Layout.Column = 3;

    summaryGrid = uigridlayout(tabSummary, [1 1]);
    summaryGrid.Padding = [8 8 8 8];
    summaryTable = uitable(summaryGrid, ...
        'ColumnName', {'类别', '参数名', '生效值', '来源', '说明'}, ...
        'ColumnEditable', false(1, 5), ...
        'RowName', {});
    summaryTable.Layout.Row = 1; summaryTable.Layout.Column = 1;

    saveBtn = uibutton(grid, 'Text', '保存', 'BackgroundColor', primaryBlue, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~,~) onSaveCfg(false));
    saveBtn.Layout.Row = 4; saveBtn.Layout.Column = 3;
    saveAsBtn = uibutton(grid, 'Text', '另存为', 'ButtonPushedFcn', @(~,~) onSaveCfg(true));
    saveAsBtn.Layout.Row = 4; saveAsBtn.Layout.Column = 4;

    msgBox = uitextarea(grid, 'Editable', 'off', 'Value', { ...
        '本页仅编辑绘图表达、图上预警线和频谱找峰设置；不修改数据清洗阈值、零点修正或原始数据。', ...
        '频谱表保存后使用 peak_orders，避免 target_freqs/tolerance/theor_freqs 多套配置互相打架。'});
    msgBox.Layout.Row = 5; msgBox.Layout.Column = [1 4];

    refresh_all_controls();

    function onReloadCfg()
        try
            draftCfg = bms.gui.ConfigEditorService.load(cfgEdit.Value);
            cfgCache = draftCfg;
            cfgPath = cfgEdit.Value;
            currentModule = moduleDrop.Value;
            refresh_all_controls();
            msgBox.Value = {'已重新加载配置。'};
        catch ME
            msgBox.Value = {['加载失败: ' ME.message]};
        end
    end

    function onGlobalChanged()
        if updating
            return;
        end
        persist_global_to_draft();
        refresh_summary();
    end

    function onModuleChanged()
        if updating
            currentModule = moduleDrop.Value;
            return;
        end
        persist_current_module_to_draft();
        currentModule = moduleDrop.Value;
        currentWarnField = 'warn_lines';
        warnFieldDrop.Value = currentWarnField;
        refresh_module_controls();
    end

    function onModuleFieldChanged()
        if updating
            return;
        end
        persist_current_module_to_draft();
        sync_module_enable_state();
        refresh_summary();
    end

    function onWarnFieldChanged()
        if updating
            currentWarnField = warnFieldDrop.Value;
            return;
        end
        persist_warn_lines_to_draft(currentWarnField);
        currentWarnField = warnFieldDrop.Value;
        refresh_warn_controls();
        refresh_summary();
    end

    function onWarnExpandChanged()
        warnExpanded = logical(warnExpandCheck.Value);
        refresh_warn_controls();
    end

    function onWarnTableEdited()
        if updating
            return;
        end
        persist_warn_lines_to_draft(currentWarnField);
        refresh_summary();
    end

    function onAlarmTableEdited()
        if updating
            return;
        end
        try
            persist_alarm_bounds_to_draft();
            refresh_warn_controls();
            refresh_summary();
            msgBox.Value = {'测点预警值已更新到草稿；点击保存后写入配置文件。'};
        catch ME
            msgBox.Value = {['测点预警值无效: ' ME.message]};
        end
    end

    function onPeakTableEdited()
        if updating
            return;
        end
        try
            persist_peak_orders_to_draft();
            refresh_summary();
            msgBox.Value = {'频谱找峰配置已更新到草稿；scope=point 时必须填写 point_id，search_max_hz 必须大于 search_min_hz。'};
        catch ME
            msgBox.Value = {['频谱找峰配置无效: ' ME.message]};
        end
    end

    function onYlimSelected(evt)
        selectedYlimRows = selected_rows(evt);
    end

    function onWarnSelected(evt)
        selectedWarnRows = selected_rows(evt);
    end

    function onAlarmSelected(evt)
        selectedAlarmRows = selected_rows(evt);
    end

    function onPeakSelected(evt)
        selectedPeakRows = selected_rows(evt);
    end

    function add_ylims_row()
        ylimsTable.Data = append_row(ylimsTable.Data, {'', [], []});
        onModuleFieldChanged();
    end

    function delete_ylims_rows()
        ylimsTable.Data = delete_rows_by_index(ylimsTable.Data, selectedYlimRows);
        selectedYlimRows = [];
        onModuleFieldChanged();
    end

    function add_alarm_row()
        pointIds = bms.gui.AlarmBoundsEditorService.modulePointIds(draftCfg, current_def());
        if isempty(pointIds)
            pointId = '';
        else
            pointId = pointIds{1};
        end
        alarmTable.Data = append_row(alarmTable.Data, {pointId, 'level2', [], [], 'per_point'});
        selectedAlarmRows = [];
        msgBox.Value = {'已新增一行测点预警值；请填写 lower/upper 后保存。'};
    end

    function delete_alarm_rows()
        alarmTable.Data = delete_rows_by_index(alarmTable.Data, selectedAlarmRows);
        selectedAlarmRows = [];
        onAlarmTableEdited();
    end

    function add_warn_row()
        if warnTableDerivedPreview
            warnTableDerivedPreview = false;
            warnTable.Data = cell(0, 6);
            warnTable.ColumnEditable = true(1, 6);
            addWarnBtn.Text = '新增预警线';
            delWarnBtn.Enable = 'on';
            warnHint.Text = '正在编辑自定义图上预警线；保存后写入当前模块 plot_styles。';
        end
        warnTable.Data = append_row(warnTable.Data, {[], '', [], [], [], '--'});
        onWarnTableEdited();
    end

    function delete_warn_rows()
        if warnTableDerivedPreview
            return;
        end
        warnTable.Data = delete_rows_by_index(warnTable.Data, selectedWarnRows);
        selectedWarnRows = [];
        onWarnTableEdited();
    end

    function add_peak_row()
        peakTable.Data = append_row(peakTable.Data, bms.gui.SpectrumPeakOrderEditorService.defaultRow('', 'default'));
        onPeakTableEdited();
    end

    function add_default_peak_row()
        add_peak_row();
    end

    function add_point_peak_row()
        pointIds = bms.gui.SpectrumPeakOrderEditorService.modulePointIds(draftCfg, current_def());
        if isempty(pointIds)
            pointId = '';
        else
            pointId = pointIds{1};
        end
        peakTable.Data = append_row(peakTable.Data, bms.gui.SpectrumPeakOrderEditorService.defaultRow(pointId, 'point'));
        onPeakTableEdited();
    end

    function delete_peak_rows()
        peakTable.Data = delete_rows_by_index(peakTable.Data, selectedPeakRows);
        selectedPeakRows = [];
        onPeakTableEdited();
    end

    function onSaveCfg(doSaveAs)
        try
            cfgNew = applyToCfg(draftCfg);

            targetPath = cfgPath;
            if doSaveAs
                [fname, fpath] = uiputfile('*.json', '另存为', cfgPath);
                if isequal(fname, 0)
                    return;
                end
                targetPath = fullfile(fpath, fname);
            end

            [cfgCache, saveReport] = bms.gui.ConfigEditorService.saveAndReload(cfgNew, targetPath, true);
            draftCfg = cfgCache;
            cfgPath = targetPath;
            cfgEdit.Value = targetPath;
            refresh_all_controls();
            msgBox.Value = {sprintf('已保存配置到 %s（变更 %d 项）', targetPath, saveReport.changed_count)};
            addLog(sprintf('绘图参数已保存: %s（变更 %d 项）', targetPath, saveReport.changed_count));
        catch ME
            msgBox.Value = {['保存失败: ' ME.message]};
        end
    end

    function onShow()
        if exist(cfgEdit.Value, 'file')
            try
                cfgCache = bms.gui.ConfigEditorService.load(cfgEdit.Value);
                draftCfg = cfgCache;
                cfgPath = cfgEdit.Value;
            catch
            end
        end
        if ~ismember(currentModule, moduleValues)
            currentModule = moduleValues{1};
        end
        moduleDrop.Value = currentModule;
        refresh_all_controls();
    end

    function cfgOut = applyToCfg(baseCfg)
        if nargin < 1 || isempty(baseCfg)
            cfgOut = draftCfg;
        else
            cfgOut = baseCfg;
        end
        draftCfg = cfgOut;
        persist_global_to_draft();
        persist_current_module_to_draft();
        cfgOut = draftCfg;
    end

    function refresh_all_controls()
        updating = true;
        refresh_global_controls();
        refresh_module_controls();
        updating = false;
    end

    function refresh_global_controls()
        common = get_plot_common(draftCfg);
        cbSaveFig.Value = common.save_fig;
        cbLightFig.Value = common.lightweight_fig;
        figMaxEdit.Value = common.fig_max_points;
        cbAppendTimestamp.Value = common.append_timestamp;
        gapModeDrop.Value = common.gap_mode;
        gapFactorEdit.Value = common.gap_break_factor;
        cbAutoFolders.Value = get_auto_folder_setting(draftCfg);
    end

    function refresh_module_controls()
        updating = true;
        def = current_def();
        style = get_effective_style(draftCfg, def);
        [ylabelField, titleField] = label_fields(def);
        ylabelEdit.Value = to_char(getfield_default(style, ylabelField, ''));
        titleEdit.Value = to_char(getfield_default(style, titleField, ''));

        cbYlimAuto.Value = get_truthy_field(style, 'ylim_auto', false);
        [ylimMin, ylimMax] = split_ylim(getfield_default(style, 'ylim', []));
        ylimMinEdit.Value = format_num(ylimMin);
        ylimMaxEdit.Value = format_num(ylimMax);

        isStrain = any(strcmp(def.value, {'strain', 'dynamic_strain', 'dynamic_strain_lowpass'}));
        cbShowOutliers.Visible = on_off(isStrain);
        cbShowWarnPoint.Visible = on_off(isStrain);
        cbShowWarnBox.Visible = on_off(isStrain);
        if isStrain
            cbShowOutliers.Value = get_truthy_field(style, 'show_boxplot_outliers', false);
            cbShowWarnPoint.Value = get_truthy_field(style, 'show_warn_lines_point', true);
            cbShowWarnBox.Value = get_truthy_field(style, 'show_warn_lines_boxplot', true);
        else
            cbShowOutliers.Value = false;
            cbShowWarnPoint.Value = false;
            cbShowWarnBox.Value = false;
        end

        ylimsTable.Data = ylims_to_rows(getfield_default(style, 'ylims', []));
        selectedYlimRows = [];
        refresh_alarm_controls();
        refresh_warn_controls();
        refresh_peak_controls();
        sync_module_enable_state();
        refresh_summary();
        updating = false;
    end

    function refresh_warn_controls()
        def = current_def();
        style = get_effective_style(draftCfg, def);
        [rows, isPreview, hintText] = warn_rows_for_table(draftCfg, def, style, currentWarnField, warnExpanded);
        warnTable.Data = rows;
        warnTableDerivedPreview = isPreview;
        warnTable.ColumnEditable = repmat(~isPreview, 1, 6);
        warnExpandCheck.Enable = on_off(isPreview);
        addWarnBtn.Text = ternary(isPreview, '改为自定义预警线', '新增预警线');
        delWarnBtn.Enable = on_off(~isPreview);
        warnHint.Text = hintText;
        selectedWarnRows = [];
    end

    function refresh_peak_controls()
        def = current_def();
        isSpec = ~isempty(def.params_key);
        spectrumHint.Text = 'Frequency peak orders: scope=default edits module defaults; scope=point plus point_id edits one sensor. Use search_min_hz/search_max_hz as the peak search band.';
        peakTable.Enable = on_off(isSpec);
        addPeakBtn.Enable = on_off(isSpec);
        addPointPeakBtn.Enable = on_off(isSpec);
        delPeakBtn.Enable = on_off(isSpec);
        if isSpec
            peakTable.Data = bms.gui.SpectrumPeakOrderEditorService.rows(draftCfg, def);
        else
            peakTable.Data = cell(0, numel(bms.gui.SpectrumPeakOrderEditorService.columnNames()));
        end
        selectedPeakRows = [];
    end

    function sync_module_enable_state()
        manual = ~cbYlimAuto.Value;
        ylimMinEdit.Editable = manual;
        ylimMaxEdit.Editable = manual;
    end

    function refresh_summary()
        def = current_def();
        style = get_effective_style(draftCfg, def);
        summaryTable.Data = build_summary_rows(draftCfg, def, style);
    end

    function refresh_alarm_controls()
        def = current_def();
        if isfield(def, 'is_spectrum') && logical(def.is_spectrum)
            alarmTable.Data = cell(0, 5);
            alarmTable.Enable = 'off';
            addAlarmBtn.Enable = 'off';
            delAlarmBtn.Enable = 'off';
            alarmHint.Text = '频谱模块不编辑 alarm_bounds；理论频率或参考线请使用“图上自定义线/频谱找峰”。';
            selectedAlarmRows = [];
            return;
        end
        alarmTable.Enable = 'on';
        addAlarmBtn.Enable = 'on';
        delAlarmBtn.Enable = 'on';
        try
            alarmTable.Data = bms.gui.AlarmBoundsEditorService.rows(draftCfg, def);
            alarmHint.Text = '编辑真实预警阈值：保存后写入 per_point.<模块>.<测点>.alarm_bounds；level 必须写成 level1、level2、level3。';
        catch ME
            alarmTable.Data = cell(0, 5);
            alarmHint.Text = ['测点预警值读取失败: ' ME.message];
        end
        selectedAlarmRows = [];
    end

    function persist_global_to_draft()
        if ~isfield(draftCfg, 'plot_common') || ~isstruct(draftCfg.plot_common)
            draftCfg.plot_common = struct();
        end
        draftCfg.plot_common.save_fig = logical(cbSaveFig.Value);
        draftCfg.plot_common.lightweight_fig = logical(cbLightFig.Value);
        draftCfg.plot_common.fig_max_points = round(figMaxEdit.Value);
        draftCfg.plot_common.append_timestamp = logical(cbAppendTimestamp.Value);
        draftCfg.plot_common.gap_mode = char(string(gapModeDrop.Value));
        draftCfg.plot_common.gap_break_factor = double(gapFactorEdit.Value);

        if ~isfield(draftCfg, 'gui') || ~isstruct(draftCfg.gui)
            draftCfg.gui = struct();
        end
        draftCfg.gui.auto_configure_result_folders = logical(cbAutoFolders.Value);
    end

    function persist_current_module_to_draft()
        def = current_def();
        style = get_raw_style(draftCfg, def);
        [ylabelField, titleField] = label_fields(def);
        style.(ylabelField) = char(string(ylabelEdit.Value));
        style.(titleField) = char(string(titleEdit.Value));
        style.ylim_auto = logical(cbYlimAuto.Value);

        minVal = parse_optional_number(ylimMinEdit.Value);
        maxVal = parse_optional_number(ylimMaxEdit.Value);
        if isfinite(minVal) && isfinite(maxVal) && maxVal > minVal
            style.ylim = [minVal, maxVal];
        else
            style = rmfield_if_present(style, 'ylim');
        end

        ylimsValue = rows_to_ylims(ylimsTable.Data);
        if isempty(ylimsValue)
            style = rmfield_if_present(style, 'ylims');
        else
            style.ylims = ylimsValue;
        end

        if any(strcmp(def.value, {'strain', 'dynamic_strain', 'dynamic_strain_lowpass'}))
            style.show_boxplot_outliers = logical(cbShowOutliers.Value);
            style.show_warn_lines_point = logical(cbShowWarnPoint.Value);
            style.show_warn_lines_boxplot = logical(cbShowWarnBox.Value);
        end

        draftCfg = set_style(draftCfg, def, style);
        persist_alarm_bounds_to_draft();
        persist_warn_lines_to_draft(currentWarnField);
        persist_peak_orders_to_draft();
    end

    function persist_alarm_bounds_to_draft()
        def = current_def();
        if isfield(def, 'is_spectrum') && logical(def.is_spectrum)
            return;
        end
        draftCfg = bms.gui.AlarmBoundsEditorService.applyRows(draftCfg, def, alarmTable.Data);
    end

    function persist_warn_lines_to_draft(fieldName)
        if warnTableDerivedPreview
            return;
        end
        def = current_def();
        style = get_raw_style(draftCfg, def);
        lines = rows_to_warn_lines(warnTable.Data);
        if isempty(lines)
            style = rmfield_if_present(style, fieldName);
        else
            style.(fieldName) = lines;
        end
        draftCfg = set_style(draftCfg, def, style);
    end

    function persist_peak_orders_to_draft()
        def = current_def();
        if isempty(def.params_key)
            return;
        end
        draftCfg = bms.gui.SpectrumPeakOrderEditorService.applyRows(draftCfg, def, peakTable.Data);
    end

    function def = current_def()
        idx = find(strcmp(moduleValues, currentModule), 1);
        if isempty(idx)
            def = moduleDefs(1);
        else
            def = moduleDefs(idx);
        end
    end

    psTab = struct('grid', grid, ...
        'onShow', @onShow, ...
        'applyToCfg', @applyToCfg, ...
        'moduleDrop', moduleDrop, ...
        'warnTabs', warnTabs, ...
        'alarmTable', alarmTable, ...
        'warnTable', warnTable, ...
        'peakTable', peakTable, ...
        'addPointPeakBtn', addPointPeakBtn, ...
        'warnExpandCheck', warnExpandCheck, ...
        'refreshWarnControls', @refresh_warn_controls, ...
        'alarmHint', alarmHint, ...
        'warnHint', warnHint);
end

function defs = plot_module_defs()
    defs = bms.config.ModuleConfigRegistry.plotModuleDefs();
end

function common = get_plot_common(cfg)
    common = struct( ...
        'save_fig', true, ...
        'lightweight_fig', true, ...
        'fig_max_points', 50000, ...
        'append_timestamp', false, ...
        'gap_mode', 'break', ...
        'gap_break_factor', 5);
    if isstruct(cfg) && isfield(cfg, 'plot_common') && isstruct(cfg.plot_common)
        src = cfg.plot_common;
        if isfield(src, 'save_fig') && ~isempty(src.save_fig), common.save_fig = logical(src.save_fig); end
        if isfield(src, 'lightweight_fig') && ~isempty(src.lightweight_fig), common.lightweight_fig = logical(src.lightweight_fig); end
        if isfield(src, 'fig_max_points') && isnumeric(src.fig_max_points) && isscalar(src.fig_max_points) && isfinite(src.fig_max_points)
            common.fig_max_points = max(1000, round(src.fig_max_points));
        end
        if isfield(src, 'append_timestamp') && ~isempty(src.append_timestamp), common.append_timestamp = logical(src.append_timestamp); end
        if isfield(src, 'gap_mode') && ~isempty(src.gap_mode)
            mode = lower(char(string(src.gap_mode)));
            if ismember(mode, {'break', 'connect'}), common.gap_mode = mode; end
        end
        if isfield(src, 'gap_break_factor') && isnumeric(src.gap_break_factor) && isscalar(src.gap_break_factor) && isfinite(src.gap_break_factor)
            common.gap_break_factor = max(1.1, double(src.gap_break_factor));
        end
    end
end

function tf = get_auto_folder_setting(cfg)
    tf = true;
    if isstruct(cfg) && isfield(cfg, 'gui') && isstruct(cfg.gui) && ...
            isfield(cfg.gui, 'auto_configure_result_folders') && ~isempty(cfg.gui.auto_configure_result_folders)
        tf = logical(cfg.gui.auto_configure_result_folders);
    end
end

function [ylabelField, titleField] = label_fields(def)
    switch def.value
        case 'accel_spectrum'
            ylabelField = 'freq_ylabel';
            titleField = 'freq_title_prefix';
        case 'cable_accel_spectrum'
            ylabelField = 'freq_ylabel';
            titleField = 'freq_title_prefix';
        case 'crack'
            ylabelField = 'ylabel_crack';
            titleField = 'title_prefix_crack';
        case 'wind_rose'
            ylabelField = 'ylabel';
            titleField = 'title_prefix';
        otherwise
            ylabelField = 'ylabel';
            titleField = 'title_prefix';
    end
end

function style = get_effective_style(cfg, def)
    defaults = default_style(def, cfg);
    style = bms.config.ModuleConfigResolver.resolvePlotStyle(cfg, def, defaults);
end

function style = get_raw_style(cfg, def)
    style = bms.config.ModuleConfigResolver.rawPlotStyle(cfg, def);
end

function cfg = set_style(cfg, def, style)
    cfg = bms.config.ModuleConfigResolver.setPlotStyle(cfg, def, style);
end

function style = default_style(def, cfg)
    style = struct();
    try
        switch def.value
            case 'acceleration'
                spec = bms.analyzer.DynamicAccelerationPipeline.spec('acceleration');
                style = spec.defaultStyle;
            case 'cable_accel'
                spec = bms.analyzer.DynamicAccelerationPipeline.spec('cable_accel');
                style = spec.defaultStyle;
            case 'accel_spectrum'
                spec = bms.analyzer.SpectrumAnalysisPipeline.spec('accel_spectrum');
                style = spec.defaultStyle;
            case 'cable_accel_spectrum'
                spec = bms.analyzer.SpectrumAnalysisPipeline.spec('cable_accel_spectrum');
                style = spec.defaultStyle;
            case 'deflection'
                spec = bms.analyzer.StructuralFilteredSeriesPipeline.spec('deflection');
                style = struct('ylabel', spec.defaultYLabel, 'title_prefix', spec.defaultTitlePrefix);
            case 'bearing_displacement'
                spec = bms.analyzer.StructuralFilteredSeriesPipeline.spec('bearing_displacement');
                style = struct('ylabel', spec.defaultYLabel, 'title_prefix', spec.defaultTitlePrefix);
            case 'tilt'
                spec = bms.analyzer.StructuralFilteredSeriesPipeline.spec('tilt');
                style = struct('ylabel', spec.defaultYLabel, 'title_prefix', spec.defaultTitlePrefix);
            case {'wind_speed', 'wind_direction', 'wind_speed10', 'wind_rose'}
                windStyle = bms.analyzer.WindPlotService.style(cfg);
                if isfield(windStyle, def.section)
                    style = windStyle.(def.section);
                end
            otherwise
                style = hardcoded_default_style(def.value);
        end
    catch
        style = hardcoded_default_style(def.value);
    end
end

function style = hardcoded_default_style(value)
    switch value
        case 'temperature'
            style = struct('ylabel', '温度 (°C)', 'title_prefix', '温度时程');
        case 'humidity'
            style = struct('ylabel', '相对湿度 (%)', 'title_prefix', '湿度时程');
        case 'rainfall'
            style = struct('ylabel', '降雨强度 (mm/h)', 'title_prefix', '降雨强度时程');
        case 'earthquake'
            style = struct('ylabel', '地震动加速度 (m/s^2)', 'title_prefix', '地震动时程');
        case 'gnss'
            style = struct('ylabel', 'GNSS位移 (mm)', 'title_prefix', 'GNSS位移时程');
        case 'strain'
            style = struct('ylabel', '主梁应变 (με)', 'title_prefix', '应变时程曲线', 'boxplot_title_prefix', '应变箱线图');
        case 'dynamic_strain'
            style = struct('ylabel', '高通应变 (με)', 'title_prefix', '动应变高通时程');
        case 'dynamic_strain_lowpass'
            style = struct('ylabel', '低通应变 (με)', 'title_prefix', '动应变低通时程');
        case 'crack'
            style = struct('ylabel_crack', '裂缝宽度 (mm)', 'title_prefix_crack', '裂缝宽度');
        otherwise
            style = struct();
    end
end

function params = get_params(cfg, key)
    params = bms.config.ModuleConfigResolver.resolveParams(cfg, struct('value', key, 'params_key', key));
end

function rows = build_summary_rows(cfg, def, style)
    [ylabelField, titleField] = label_fields(def);
    rows = {
        '基础', ylabelField, value_to_text(getfield_default(style, ylabelField, '')), field_source(cfg, def, ylabelField), '图上 Y 轴文字；上标用 ^，下标用 _'
        '基础', titleField, value_to_text(getfield_default(style, titleField, '')), field_source(cfg, def, titleField), '图标题前缀'
        '基础', 'ylim_auto', value_to_text(getfield_default(style, 'ylim_auto', false)), field_source(cfg, def, 'ylim_auto'), 'true 时由数据自动决定 Y 轴'
        '基础', 'ylim', value_to_text(getfield_default(style, 'ylim', [])), field_source(cfg, def, 'ylim'), '当前模块默认 Y 轴范围'
        '预警线', 'warn_lines', value_to_text(getfield_default(style, 'warn_lines', [])), field_source(cfg, def, 'warn_lines'), '图上普通预警线'
        '预警线', 'rms_warn_lines', value_to_text(getfield_default(style, 'rms_warn_lines', [])), field_source(cfg, def, 'rms_warn_lines'), 'RMS 图预警线'
        };
    if ~isempty(def.params_key)
        params = get_params(cfg, def.params_key);
        rows = [rows; {
            '频谱', [def.params_key '.peak_orders'], value_to_text(getfield_default(params, 'peak_orders', [])), param_source(cfg, def.params_key, 'peak_orders'), '推荐配置：找峰中心/半宽/理论频率集中到一张表'
            '频谱', [def.params_key '.target_freqs'], value_to_text(getfield_default(params, 'target_freqs', [])), param_source(cfg, def.params_key, 'target_freqs'), '旧配置；编辑后会由 peak_orders 接管'
            '频谱', [def.params_key '.tolerance'], value_to_text(getfield_default(params, 'tolerance', [])), param_source(cfg, def.params_key, 'tolerance'), '旧配置；编辑后会由 peak_orders 接管'
            '频谱', [def.params_key '.theor_freqs'], value_to_text(getfield_default(params, 'theor_freqs', [])), param_source(cfg, def.params_key, 'theor_freqs'), '理论频率线'
            }];
    end
end

function src = field_source(cfg, def, fieldName)
    raw = get_raw_style(cfg, def);
    if isstruct(raw) && isfield(raw, fieldName)
        src = ['config plot_styles.' def.style_key];
        if ~isempty(def.section)
            src = [src '.' def.section];
        end
    else
        src = '代码默认值';
    end
end

function src = param_source(cfg, paramsKey, fieldName)
    if isstruct(cfg) && isfield(cfg, paramsKey) && isstruct(cfg.(paramsKey)) && isfield(cfg.(paramsKey), fieldName)
        src = ['config ' paramsKey];
    else
        src = '代码默认值/未配置';
    end
end

function rows = ylims_to_rows(ylims)
    rows = cell(0, 3);
    if isempty(ylims)
        return;
    end
    if isstruct(ylims)
        if numel(ylims) > 1 && isfield(ylims, 'name') && isfield(ylims, 'ylim')
            for i = 1:numel(ylims)
                [mn, mx] = split_ylim(ylims(i).ylim);
                rows(end+1, :) = {to_char(ylims(i).name), mn, mx}; %#ok<AGROW>
            end
            return;
        end
        if isfield(ylims, 'name') && isfield(ylims, 'ylim') && isscalar(ylims)
            [mn, mx] = split_ylim(ylims.ylim);
            rows(end+1, :) = {to_char(ylims.name), mn, mx}; %#ok<AGROW>
            return;
        end
        names = fieldnames(ylims);
        for i = 1:numel(names)
            [mn, mx] = split_ylim(ylims.(names{i}));
            rows(end+1, :) = {names{i}, mn, mx}; %#ok<AGROW>
        end
    elseif iscell(ylims)
        for i = 1:numel(ylims)
            item = ylims{i};
            if isstruct(item) && isfield(item, 'name') && isfield(item, 'ylim')
                [mn, mx] = split_ylim(item.ylim);
                rows(end+1, :) = {to_char(item.name), mn, mx}; %#ok<AGROW>
            end
        end
    end
end

function ylims = rows_to_ylims(rows)
    ylims = [];
    if isempty(rows)
        return;
    end
    out = struct('name', {}, 'ylim', {});
    for i = 1:size(rows, 1)
        name = strtrim(to_char(rows{i, 1}));
        mn = parse_optional_number(rows{i, 2});
        mx = parse_optional_number(rows{i, 3});
        if isempty(name) || ~isfinite(mn) || ~isfinite(mx) || mx <= mn
            continue;
        end
        out(end+1).name = name; %#ok<AGROW>
        out(end).ylim = [mn, mx];
    end
    if ~isempty(out)
        ylims = out;
    end
end

function [rows, isPreview, hintText] = warn_rows_for_table(cfg, def, style, fieldName, expandPoints)
    if nargin < 5
        expandPoints = false;
    end
    preview = bms.analyzer.PlotWarningLineResolver.tablePreview(cfg, def, style, fieldName, ...
        'ExpandPoints', expandPoints);
    rows = preview.rows;
    isPreview = preview.is_preview;
    hintText = preview.hint;
end

function lines = rows_to_warn_lines(rows)
    lines = struct('y', {}, 'label', {}, 'color', {}, 'linestyle', {});
    if isempty(rows)
        return;
    end
    for i = 1:size(rows, 1)
        y = parse_optional_number(rows{i, 1});
        if ~isfinite(y)
            continue;
        end
        line = struct();
        line.y = y;
        line.label = '';
        line.color = [];
        line.linestyle = '';
        label = strtrim(to_char(rows{i, 2}));
        if ~isempty(label)
            line.label = label;
        end
        rgb = [parse_optional_number(rows{i, 3}), parse_optional_number(rows{i, 4}), parse_optional_number(rows{i, 5})];
        if all(isfinite(rgb))
            line.color = rgb;
        end
        lineStyle = strtrim(to_char(rows{i, 6}));
        if ~isempty(lineStyle)
            line.linestyle = lineStyle;
        end
        lines(end+1) = line; %#ok<AGROW>
    end
end

function rows = peak_orders_to_rows(params)
    rows = cell(0, 6);
    if isstruct(params) && isfield(params, 'peak_orders') && ~isempty(params.peak_orders)
        orders = params.peak_orders;
        if iscell(orders)
            try
                orders = [orders{:}];
            catch
                orders = struct([]);
            end
        end
        if isstruct(orders)
            for i = 1:numel(orders)
                item = orders(i);
                rows(end+1, :) = { ...
                    text_field(item, {'label', 'name'}, ''), ...
                    numeric_field(item, {'order'}, []), ...
                    numeric_field(item, {'search_center_hz', 'target_hz', 'frequency_hz', 'freq_hz'}, []), ...
                    numeric_field(item, {'search_half_width_hz', 'tolerance_hz', 'half_width_hz'}, []), ...
                    numeric_field(item, {'theoretical_hz', 'theor_hz'}, []), ...
                    text_field(item, {'theor_label', 'theoretical_label'}, '')}; %#ok<AGROW>
            end
            return;
        end
    end

    freqs = getfield_default(params, 'target_freqs', []);
    if isempty(freqs)
        return;
    end
    tol = getfield_default(params, 'tolerance', 0.15);
    theor = getfield_default(params, 'theor_freqs', []);
    theorLabels = getfield_default(params, 'theor_labels', {});
    freqs = double(freqs(:).');
    for i = 1:numel(freqs)
        halfWidth = tol_value(tol, i);
        theorVal = index_value(theor, i);
        label = sprintf('%d阶', i);
        theorLabel = cell_index(theorLabels, i);
        rows(end+1, :) = {label, i, freqs(i), halfWidth, theorVal, theorLabel}; %#ok<AGROW>
    end
end

function orders = rows_to_peak_orders(rows)
    orders = struct('label', {}, 'order', {}, 'search_center_hz', {}, ...
        'search_half_width_hz', {}, 'theoretical_hz', {}, 'theor_label', {});
    if isempty(rows)
        return;
    end
    for i = 1:size(rows, 1)
        center = parse_optional_number(rows{i, 3});
        if ~isfinite(center)
            continue;
        end
        order = parse_optional_number(rows{i, 2});
        halfWidth = parse_optional_number(rows{i, 4});
        theor = parse_optional_number(rows{i, 5});
        label = strtrim(to_char(rows{i, 1}));
        theorLabel = strtrim(to_char(rows{i, 6}));

        item = struct();
        item.label = '';
        item.order = [];
        item.search_center_hz = center;
        item.search_half_width_hz = [];
        item.theoretical_hz = [];
        item.theor_label = '';
        if ~isempty(label), item.label = label; end
        if isfinite(order), item.order = order; end
        if isfinite(halfWidth), item.search_half_width_hz = halfWidth; end
        if isfinite(theor), item.theoretical_hz = theor; end
        if ~isempty(theorLabel), item.theor_label = theorLabel; end
        orders(end+1) = item; %#ok<AGROW>
    end
end

function [r, g, b] = color_to_rgb_fields(color)
    r = []; g = []; b = [];
    if isnumeric(color) && numel(color) == 3
        color = reshape(color, 1, 3);
        r = color(1); g = color(2); b = color(3);
    end
end

function rows = selected_rows(evt)
    rows = [];
    if ~isempty(evt.Indices)
        rows = unique(evt.Indices(:, 1), 'stable');
    end
end

function data = append_row(data, row)
    if isempty(data)
        data = row;
    else
        data = [data; row];
    end
end

function data = delete_rows_by_index(data, rows)
    if isempty(rows) || isempty(data)
        return;
    end
    keep = true(size(data, 1), 1);
    rows = rows(rows >= 1 & rows <= size(data, 1));
    keep(rows) = false;
    data = data(keep, :);
end

function style = rmfield_if_present(style, fieldName)
    if isfield(style, fieldName)
        style = rmfield(style, fieldName);
    end
end

function tf = get_truthy_field(s, fieldName, defaultVal)
    if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
        tf = logical(s.(fieldName));
    else
        tf = defaultVal;
    end
end

function value = getfield_default(s, fieldName, defaultVal)
    if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
        value = s.(fieldName);
    else
        value = defaultVal;
    end
end

function [mn, mx] = split_ylim(v)
    mn = [];
    mx = [];
    if isnumeric(v) && numel(v) == 2
        mn = v(1);
        mx = v(2);
    end
end

function out = format_num(v)
    if isempty(v) || ~isscalar(v) || ~isfinite(v)
        out = '';
    else
        out = num2str(v);
    end
end

function val = parse_optional_number(v)
    if isempty(v)
        val = NaN;
        return;
    end
    if isnumeric(v)
        if isscalar(v) && isfinite(v)
            val = double(v);
        else
            val = NaN;
        end
        return;
    end
    txt = strtrim(to_char(v));
    if isempty(txt)
        val = NaN;
        return;
    end
    val = str2double(txt);
    if ~isfinite(val)
        val = NaN;
    end
end

function txt = to_char(v)
    if isempty(v)
        txt = '';
    elseif isstring(v)
        txt = char(v);
    elseif ischar(v)
        txt = v;
    elseif isnumeric(v)
        txt = num2str(v);
    else
        txt = char(string(v));
    end
end

function out = on_off(tf)
    if tf
        out = 'on';
    else
        out = 'off';
    end
end

function txt = value_to_text(v)
    if isempty(v)
        txt = '';
    elseif isnumeric(v)
        txt = mat2str(v);
    elseif islogical(v)
        txt = char(string(v));
    elseif ischar(v) || isstring(v)
        txt = char(string(v));
    elseif iscell(v)
        try
            txt = strjoin(cellfun(@value_to_text, v, 'UniformOutput', false), '; ');
        catch
            txt = sprintf('cell(%d)', numel(v));
        end
    elseif isstruct(v)
        txt = sprintf('struct(%d)', numel(v));
    else
        txt = char(string(v));
    end
end

function value = numeric_field(s, names, defaultValue)
    value = defaultValue;
    for i = 1:numel(names)
        name = names{i};
        if isfield(s, name) && ~isempty(s.(name))
            raw = s.(name);
            if isnumeric(raw) && isscalar(raw)
                value = raw;
                return;
            elseif ischar(raw) || isstring(raw)
                parsed = str2double(char(string(raw)));
                if isfinite(parsed)
                    value = parsed;
                    return;
                end
            end
        end
    end
end

function value = text_field(s, names, defaultValue)
    value = defaultValue;
    for i = 1:numel(names)
        name = names{i};
        if isfield(s, name) && ~isempty(s.(name))
            value = to_char(s.(name));
            return;
        end
    end
end

function value = tol_value(tol, idx)
    value = [];
    if isempty(tol)
        value = [];
    elseif isnumeric(tol) && isscalar(tol)
        value = tol;
    elseif isnumeric(tol) && numel(tol) >= idx
        value = tol(idx);
    elseif isnumeric(tol) && ~isempty(tol)
        value = tol(end);
    end
end

function value = index_value(v, idx)
    value = [];
    if isnumeric(v) && numel(v) >= idx
        value = v(idx);
    end
end

function value = cell_index(v, idx)
    value = '';
    if isstring(v)
        v = cellstr(v(:));
    end
    if ischar(v)
        v = {v};
    end
    if iscell(v) && numel(v) >= idx
        value = to_char(v{idx});
    end
end

function out = ternary(cond, a, b)
    if cond
        out = a;
    else
        out = b;
    end
end
