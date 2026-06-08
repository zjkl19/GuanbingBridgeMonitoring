function gc = build_group_config_tab(tabCfg, f, cfgCache, cfgPath, cfgEdit, addLog, primaryBlue)
% build_group_config_tab  Build grouped-plot configuration editor.

    if nargin < 6 || isempty(addLog)
        addLog = @(~) [];
    end
    if nargin < 7 || isempty(primaryBlue)
        primaryBlue = [0 94 172] / 255;
    end

    draftCfg = cfgCache;
    currentModule = '';
    selectedGroupRow = [];
    selectedPointRows = [];
    selectedAvailableRows = [];
    pointLists = {};
    updating = false;

    grid = uigridlayout(tabCfg, [5 3]);
    grid.RowHeight = {34, 30, '1x', 36, 70};
    grid.ColumnWidth = {'1.1x', '1x', '1x'};
    grid.Padding = [8 8 8 8];
    grid.RowSpacing = 8;
    grid.ColumnSpacing = 8;

    moduleLabel = uilabel(grid, 'Text', '模块', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    moduleLabel.Layout.Row = 1; moduleLabel.Layout.Column = 1;
    moduleDrop = uidropdown(grid, 'ValueChangedFcn', @(~,~) onModuleChanged());
    moduleDrop.Layout.Row = 1; moduleDrop.Layout.Column = 2;
    reloadBtn = uibutton(grid, 'Text', '重新加载配置', 'ButtonPushedFcn', @(~,~) onReloadCfg());
    reloadBtn.Layout.Row = 1; reloadBtn.Layout.Column = 3;

    ruleLabel = uilabel(grid, ...
        'Text', bms.gui.GroupConfigService.groupKeyRuleText(), ...
        'FontWeight', 'bold', 'FontColor', [0.75 0.18 0.08]);
    ruleLabel.Layout.Row = 2; ruleLabel.Layout.Column = [1 3];

    groupPanel = uipanel(grid, 'Title', '分组');
    groupPanel.Layout.Row = 3; groupPanel.Layout.Column = 1;
    groupGrid = uigridlayout(groupPanel, [2 1]);
    groupGrid.RowHeight = {'1x', 32};
    groupGrid.Padding = [6 6 6 6];
    groupTable = uitable(groupGrid, ...
        'ColumnName', {'group_key', '显示名称', '点数'}, ...
        'ColumnEditable', [true true false], ...
        'CellSelectionCallback', @(~,evt) onGroupSelected(evt), ...
        'CellEditCallback', @(~,~) onGroupEdited());
    groupTable.Layout.Row = 1; groupTable.Layout.Column = 1;
    groupBtnGrid = uigridlayout(groupGrid, [1 2]);
    groupBtnGrid.RowHeight = {'1x'}; groupBtnGrid.ColumnWidth = {'1x','1x'};
    groupBtnGrid.Padding = [0 0 0 0]; groupBtnGrid.ColumnSpacing = 6;
    addGroupBtn = uibutton(groupBtnGrid, 'Text', '新增组', 'ButtonPushedFcn', @(~,~) addGroup());
    addGroupBtn.Layout.Row = 1; addGroupBtn.Layout.Column = 1;
    delGroupBtn = uibutton(groupBtnGrid, 'Text', '删除组', 'ButtonPushedFcn', @(~,~) deleteGroups());
    delGroupBtn.Layout.Row = 1; delGroupBtn.Layout.Column = 2;

    pointPanel = uipanel(grid, 'Title', '当前组测点');
    pointPanel.Layout.Row = 3; pointPanel.Layout.Column = 2;
    pointGrid = uigridlayout(pointPanel, [2 1]);
    pointGrid.RowHeight = {'1x', 32};
    pointGrid.Padding = [6 6 6 6];
    pointTable = uitable(pointGrid, ...
        'ColumnName', {'point_id'}, ...
        'ColumnEditable', true, ...
        'CellSelectionCallback', @(~,evt) onPointSelected(evt), ...
        'CellEditCallback', @(~,~) onPointEdited());
    pointTable.Layout.Row = 1; pointTable.Layout.Column = 1;
    pointBtnGrid = uigridlayout(pointGrid, [1 4]);
    pointBtnGrid.RowHeight = {'1x'}; pointBtnGrid.ColumnWidth = {'1x','1x','1x','1x'};
    pointBtnGrid.Padding = [0 0 0 0]; pointBtnGrid.ColumnSpacing = 6;
    addPointBtn = uibutton(pointBtnGrid, 'Text', '加入所选', 'ButtonPushedFcn', @(~,~) addSelectedPoints());
    addPointBtn.Layout.Row = 1; addPointBtn.Layout.Column = 1;
    delPointBtn = uibutton(pointBtnGrid, 'Text', '移除', 'ButtonPushedFcn', @(~,~) deleteSelectedPoints());
    delPointBtn.Layout.Row = 1; delPointBtn.Layout.Column = 2;
    upPointBtn = uibutton(pointBtnGrid, 'Text', '上移', 'ButtonPushedFcn', @(~,~) movePoint(-1));
    upPointBtn.Layout.Row = 1; upPointBtn.Layout.Column = 3;
    downPointBtn = uibutton(pointBtnGrid, 'Text', '下移', 'ButtonPushedFcn', @(~,~) movePoint(1));
    downPointBtn.Layout.Row = 1; downPointBtn.Layout.Column = 4;

    availablePanel = uipanel(grid, 'Title', '可选测点');
    availablePanel.Layout.Row = 3; availablePanel.Layout.Column = 3;
    availGrid = uigridlayout(availablePanel, [2 1]);
    availGrid.RowHeight = {30, '1x'};
    availGrid.Padding = [6 6 6 6];
    filterEdit = uieditfield(availGrid, 'text', ...
        'Placeholder', '过滤 point_id (包含)...', ...
        'ValueChangedFcn', @(~,~) refreshAvailablePoints());
    filterEdit.Layout.Row = 1; filterEdit.Layout.Column = 1;
    availableTable = uitable(availGrid, ...
        'ColumnName', {'point_id'}, ...
        'ColumnEditable', false, ...
        'CellSelectionCallback', @(~,evt) onAvailableSelected(evt));
    availableTable.Layout.Row = 2; availableTable.Layout.Column = 1;

    saveBtn = uibutton(grid, 'Text', '保存', 'BackgroundColor', primaryBlue, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~,~) onSaveCfg(false));
    saveBtn.Layout.Row = 4; saveBtn.Layout.Column = 2;
    saveAsBtn = uibutton(grid, 'Text', '另存为', 'ButtonPushedFcn', @(~,~) onSaveCfg(true));
    saveAsBtn.Layout.Row = 4; saveAsBtn.Layout.Column = 3;

    msgBox = uitextarea(grid, 'Editable', 'off', 'Value', { ...
        '组图配置会写入 groups.<模块> 和 plot_styles.<模块>.group_labels。', ...
        bms.gui.GroupConfigService.groupKeyRuleText()});
    msgBox.Layout.Row = 5; msgBox.Layout.Column = [1 3];

    refreshAll();

    function refreshAll()
        updating = true;
        moduleValues = bms.gui.GroupConfigService.editableModuleKeys(draftCfg);
        if isempty(moduleValues)
            moduleValues = {'deflection'};
        end
        moduleDrop.ItemsData = moduleValues;
        moduleDrop.Items = bms.gui.ConfigEditorService.moduleLabels(moduleValues);
        if isempty(currentModule) || ~any(strcmp(moduleValues, currentModule))
            currentModule = moduleValues{1};
        end
        moduleDrop.Value = currentModule;
        loadModuleGroups();
        refreshAvailablePoints();
        updating = false;
    end

    function loadModuleGroups()
        groups = bms.gui.GroupConfigService.readGroups(draftCfg, currentModule);
        labels = bms.gui.GroupConfigService.readGroupLabels(draftCfg, currentModule);
        groupNames = fieldnames(groups);
        rows = cell(numel(groupNames), 3);
        pointLists = cell(numel(groupNames), 1);
        for i = 1:numel(groupNames)
            key = groupNames{i};
            pts = bms.data.PointResolver.normalize(groups.(key));
            pointLists{i} = pts;
            label = '';
            if isstruct(labels) && isfield(labels, key)
                label = labels.(key);
            end
            rows(i, :) = {key, label, numel(pts)};
        end
        groupTable.Data = rows;
        if isempty(rows)
            selectedGroupRow = [];
        else
            if isempty(selectedGroupRow)
                selectedGroupRow = 1;
            else
                selectedGroupRow = min(max(1, selectedGroupRow), size(rows, 1));
            end
        end
        refreshPointTable();
        selectedPointRows = [];
        selectedAvailableRows = [];
    end

    function onModuleChanged()
        if updating
            return;
        end
        persistPointTable();
        currentModule = moduleDrop.Value;
        selectedGroupRow = [];
        loadModuleGroups();
        refreshAvailablePoints();
    end

    function onReloadCfg()
        try
            draftCfg = bms.gui.ConfigEditorService.load(cfgEdit.Value);
            cfgPath = cfgEdit.Value;
            refreshAll();
            msgBox.Value = {'已重新加载配置。', bms.gui.GroupConfigService.groupKeyRuleText()};
        catch ME
            msgBox.Value = {['加载失败: ' ME.message]};
        end
    end

    function onGroupSelected(evt)
        if isempty(evt.Indices)
            selectedGroupRow = [];
            refreshPointTable();
            return;
        end
        oldRow = selectedGroupRow;
        persistPointTable(oldRow);
        selectedGroupRow = evt.Indices(1, 1);
        refreshPointTable();
    end

    function onPointSelected(evt)
        selectedPointRows = selectedRows(evt);
    end

    function onAvailableSelected(evt)
        selectedAvailableRows = selectedRows(evt);
    end

    function onGroupEdited()
        updateGroupCounts();
    end

    function onPointEdited()
        persistPointTable();
        updateGroupCounts();
    end

    function addGroup()
        persistPointTable();
        data = groupTable.Data;
        newKey = nextGroupKey(data);
        data = [data; {newKey, '', 0}];
        pointLists{end+1, 1} = {};
        groupTable.Data = data;
        selectedGroupRow = size(data, 1);
        refreshPointTable();
    end

    function deleteGroups()
        rows = selectedRowsFromTable(groupTable);
        if isempty(rows)
            return;
        end
        data = groupTable.Data;
        rows = rows(rows >= 1 & rows <= size(data, 1));
        data(rows, :) = [];
        pointLists(rows) = [];
        groupTable.Data = data;
        if isempty(data)
            selectedGroupRow = [];
        else
            selectedGroupRow = min(rows(1), size(data, 1));
        end
        refreshPointTable();
    end

    function addSelectedPoints()
        if isempty(selectedGroupRow) || selectedGroupRow < 1
            msgBox.Value = {'请先选择一个分组，再加入测点。'};
            return;
        end
        rows = selectedAvailableRows;
        if isempty(rows)
            rows = selectedRowsFromTable(availableTable);
        end
        if isempty(rows)
            return;
        end
        data = availableTable.Data;
        rows = rows(rows >= 1 & rows <= size(data, 1));
        pts = data(rows, 1);
        current = pointLists{selectedGroupRow};
        current = bms.data.PointResolver.uniqueText([current(:); pts(:)]);
        pointLists{selectedGroupRow} = current;
        refreshPointTable();
        updateGroupCounts();
    end

    function deleteSelectedPoints()
        if isempty(selectedGroupRow)
            return;
        end
        rows = selectedPointRows;
        if isempty(rows)
            rows = selectedRowsFromTable(pointTable);
        end
        pts = pointLists{selectedGroupRow};
        rows = rows(rows >= 1 & rows <= numel(pts));
        pts(rows) = [];
        pointLists{selectedGroupRow} = pts;
        selectedPointRows = [];
        refreshPointTable();
        updateGroupCounts();
    end

    function movePoint(delta)
        if isempty(selectedGroupRow) || isempty(selectedPointRows)
            return;
        end
        row = selectedPointRows(1);
        pts = pointLists{selectedGroupRow};
        target = row + delta;
        if row < 1 || row > numel(pts) || target < 1 || target > numel(pts)
            return;
        end
        tmp = pts{row};
        pts{row} = pts{target};
        pts{target} = tmp;
        pointLists{selectedGroupRow} = pts;
        selectedPointRows = target;
        refreshPointTable();
    end

    function refreshPointTable()
        if isempty(selectedGroupRow) || selectedGroupRow < 1 || selectedGroupRow > numel(pointLists)
            pointTable.Data = cell(0, 1);
            return;
        end
        pts = pointLists{selectedGroupRow};
        pointTable.Data = pts(:);
    end

    function refreshAvailablePoints()
        pts = bms.gui.GroupConfigService.availablePoints(draftCfg, currentModule);
        filter = lower(strtrim(char(string(filterEdit.Value))));
        if ~isempty(filter)
            keep = false(size(pts));
            for i = 1:numel(pts)
                keep(i) = contains(lower(pts{i}), filter);
            end
            pts = pts(keep);
        end
        availableTable.Data = pts(:);
        selectedAvailableRows = [];
    end

    function persistPointTable(row)
        if nargin < 1 || isempty(row)
            row = selectedGroupRow;
        end
        if isempty(row) || row < 1 || row > numel(pointLists)
            return;
        end
        data = pointTable.Data;
        pointLists{row} = bms.data.PointResolver.normalize(data(:, 1));
    end

    function updateGroupCounts()
        data = groupTable.Data;
        for i = 1:size(data, 1)
            if i <= numel(pointLists)
                data{i, 3} = numel(pointLists{i});
            else
                data{i, 3} = 0;
            end
        end
        groupTable.Data = data;
    end

    function cfgOut = applyToCfg(baseCfg)
        if nargin < 1 || isempty(baseCfg)
            baseCfg = draftCfg;
        end
        persistPointTable();
        data = groupTable.Data;
        groupKeys = data(:, 1);
        groupLabels = data(:, 2);
        localPointLists = pointLists;
        if numel(localPointLists) < numel(groupKeys)
            localPointLists(end+1:numel(groupKeys), 1) = {{}};
        end
        report = bms.gui.GroupConfigService.validateGroupRows( ...
            baseCfg, currentModule, groupKeys, localPointLists, groupLabels);
        if ~report.ok
            error('build_group_config_tab:InvalidGroups', '%s', strjoin(report.errors, newline));
        end
        groups = bms.gui.GroupConfigService.makeGroups(groupKeys, localPointLists);
        labels = bms.gui.GroupConfigService.makeLabels(groupKeys, groupLabels);
        cfgOut = bms.gui.GroupConfigService.setGroups(baseCfg, currentModule, groups, labels);
        if ~isempty(report.warnings)
            msgBox.Value = [{'已保存，但存在提示:'}, report.warnings(:)'];
        end
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
            validate_config(cfgNew, false);
            [draftCfg, saveReport] = bms.gui.ConfigEditorService.saveAndReload(cfgNew, targetPath, true);
            cfgPath = targetPath;
            cfgEdit.Value = targetPath;
            refreshAll();
            msgBox.Value = {sprintf('已保存组图配置到 %s（变更 %d 项）', targetPath, saveReport.changed_count)};
            addLog(sprintf('组图配置已保存: %s（变更 %d 项）', targetPath, saveReport.changed_count));
        catch ME
            msgBox.Value = {['保存失败: ' ME.message], bms.gui.GroupConfigService.groupKeyRuleText()};
        end
    end

    function onShow()
        if exist(cfgEdit.Value, 'file')
            try
                draftCfg = bms.gui.ConfigEditorService.load(cfgEdit.Value);
                cfgPath = cfgEdit.Value;
            catch
            end
        end
        refreshAll();
    end

    function rows = selectedRows(evt)
        rows = [];
        try
            if ~isempty(evt.Indices)
                rows = unique(evt.Indices(:, 1), 'stable');
            end
        catch
        end
    end

    function rows = selectedRowsFromTable(tbl)
        rows = [];
        try
            if ~isempty(tbl.Selection)
                rows = unique(tbl.Selection(:, 1), 'stable');
            end
        catch
        end
    end

    function key = nextGroupKey(data)
        idx = size(data, 1) + 1;
        while true
            key = sprintf('Group_%d', idx);
            if isempty(data) || ~any(strcmp(data(:, 1), key))
                return;
            end
            idx = idx + 1;
        end
    end

    gc = struct();
    gc.grid = grid;
    gc.moduleDrop = moduleDrop;
    gc.groupTable = groupTable;
    gc.pointTable = pointTable;
    gc.availableTable = availableTable;
    gc.filterEdit = filterEdit;
    gc.msgBox = msgBox;
    gc.ruleLabel = ruleLabel;
    gc.onShow = @onShow;
    gc.applyToCfg = @applyToCfg;
end
