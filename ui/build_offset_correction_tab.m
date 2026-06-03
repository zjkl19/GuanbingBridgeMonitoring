function oc = build_offset_correction_tab(tabCfg, f, cfgCache, cfgPath, cfgEdit, addLog, primaryBlue)
% build_offset_correction_tab  Build per-point offset correction editor UI.

    if nargin < 6 || isempty(addLog)
        addLog = @(~) [];
    end

    grid = uigridlayout(tabCfg, [7 4]);
    grid.RowHeight = {32, 32, 260, 32, 32, 32, '1x'};
    grid.ColumnWidth = {200, 190, 240, 220};
    grid.Padding = [8 8 8 8];
    grid.RowSpacing = 6;
    grid.ColumnSpacing = 8;

    uilabel(grid, 'Text', '零点修正：按点位配置 offset_correction，计算时执行 vals = vals + offset_correction。');
    uilabel(grid, 'Text', '传感器类型', 'HorizontalAlignment', 'right');
    [sensorItems, sensorValues] = list_supported_sensors(cfgCache);
    if isempty(sensorValues)
        sensorItems = {'deflection'};
        sensorValues = {'deflection'};
    end
    sensorDrop = uidropdown(grid, 'Items', sensorItems, 'ItemsData', sensorValues, 'Value', sensorValues{1}, ...
        'ValueChangedFcn', @(~,~) refresh_table());
    sensorDrop.Layout.Row = 2; sensorDrop.Layout.Column = 2;
    filterEdit = uieditfield(grid, 'text', 'Placeholder', '过滤 point_id (包含)...', ...
        'ValueChangedFcn', @(~,~) refresh_table());
    filterEdit.Layout.Row = 2; filterEdit.Layout.Column = 3;
    reloadBtn = uibutton(grid, 'Text', '重新加载配置', 'ButtonPushedFcn', @(~,~) onReloadCfg());
    reloadBtn.Layout.Row = 2; reloadBtn.Layout.Column = 4;

    label = uilabel(grid, 'Text', 'per_point offset_correction', 'FontWeight', 'bold');
    label.Layout.Row = 3; label.Layout.Column = 1;
    table = uitable(grid, ...
        'ColumnName', {'point_id', 'offset_correction'}, ...
        'ColumnEditable', [true true]);
    table.Layout.Row = 3; table.Layout.Column = [1 4];

    addBtn = uibutton(grid, 'Text', '新增行', 'ButtonPushedFcn', @(~,~) add_row());
    addBtn.Layout.Row = 4; addBtn.Layout.Column = 1;
    delBtn = uibutton(grid, 'Text', '删除选中行', 'ButtonPushedFcn', @(~,~) delete_rows());
    delBtn.Layout.Row = 4; delBtn.Layout.Column = 2;
    helpBtn = uibutton(grid, 'Text', '说明', 'ButtonPushedFcn', @(~,~) show_help());
    helpBtn.Layout.Row = 4; helpBtn.Layout.Column = 4;

    saveBtn = uibutton(grid, 'Text', '保存', 'BackgroundColor', primaryBlue, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~,~) onSaveCfg(false));
    saveBtn.Layout.Row = 5; saveBtn.Layout.Column = 3;
    saveAsBtn = uibutton(grid, 'Text', '另存为', 'ButtonPushedFcn', @(~,~) onSaveCfg(true));
    saveAsBtn.Layout.Row = 5; saveAsBtn.Layout.Column = 4;

    msgBox = uitextarea(grid, 'Editable', 'off', ...
        'Value', {'仅保存 per_point.<module>.<point_id>.offset_correction；运行后会在数据目录/run_logs 生成修正记录表。'});
    msgBox.Layout.Row = [6 7]; msgBox.Layout.Column = [1 4];

    currentVisibleSafeIds = {};
    refresh_table();

    function refresh_table()
        currentVisibleSafeIds = {};
        [sensorItems, sensorValues] = list_supported_sensors(cfgCache);
        if isempty(sensorValues)
            sensorItems = {'deflection'};
            sensorValues = {'deflection'};
        end
        sensorDrop.Items = sensorItems;
        sensorDrop.ItemsData = sensorValues;
        if ~ismember(sensorDrop.Value, sensorValues)
            sensorDrop.Value = sensorValues{1};
        end

        sensor = sensorDrop.Value;
        filterStr = lower(strtrim(filterEdit.Value));
        rows = {};
        if isfield(cfgCache, 'per_point') && isfield(cfgCache.per_point, sensor)
            pts = cfgCache.per_point.(sensor);
            names = fieldnames(pts);
            for i = 1:numel(names)
                safeId = names{i};
                pt = pts.(safeId);
                if ~isstruct(pt) || ~isfield(pt, 'offset_correction') || isempty(pt.offset_correction)
                    continue;
                end
                dispId = get_display_id(cfgCache, safeId);
                filterKey = lower([dispId ' ' safeId]);
                if ~isempty(filterStr) && isempty(strfind(filterKey, filterStr)) %#ok<STREMP>
                    continue;
                end
                currentVisibleSafeIds{end+1,1} = safeId; %#ok<AGROW>
                rows(end+1, :) = {dispId, pt.offset_correction}; %#ok<AGROW>
            end
        end
        currentVisibleSafeIds = unique(currentVisibleSafeIds, 'stable');
        table.Data = rows;
        table.Selection = [];
        msgBox.Value = offset_summary_message(cfgCache, sensor, size(rows, 1));
    end

    function add_row()
        table.Data = [table.Data; {'', []}];
    end

    function delete_rows()
        idx = table.Selection;
        if isempty(idx), return; end
        data = table.Data;
        data(unique(idx(:,1)), :) = [];
        table.Data = data;
    end

    function show_help()
        msg = sprintf(['规则说明:\n', ...
            '- 每个点单独设置 offset_correction。\n', ...
            '- 计算时执行: vals = vals + offset_correction。\n', ...
            '- 该修正先于阈值清洗、滤波和统计。\n', ...
            '- 每次 run_all 结束后，会在当前数据根目录/run_logs 输出修正记录表。']);
        uialert(f, msg, '零点修正说明');
    end

    function onReloadCfg()
        try
            cfgCache = bms.gui.ConfigEditorService.load(cfgEdit.Value);
            cfgPath = cfgEdit.Value;
            refresh_table();
            msgBox.Value = {'已重新加载配置。'};
        catch ME
            msgBox.Value = {['加载失败: ' ME.message]};
        end
    end

    function onSaveCfg(doSaveAs)
        try
            cfgNew = applyToCfg(cfgCache);

            targetPath = cfgPath;
            if doSaveAs
                [fname, fpath] = uiputfile('*.json', '另存为', cfgPath);
                if isequal(fname, 0), return; end
                targetPath = fullfile(fpath, fname);
            end
            validate_config(cfgNew);
            [cfgCache, saveReport] = bms.gui.ConfigEditorService.saveAndReload(cfgNew, targetPath, true);
            cfgPath = targetPath;
            cfgEdit.Value = targetPath;
            refresh_table();
            msgBox.Value = {sprintf('已保存配置到 %s（变更 %d 项）', targetPath, saveReport.changed_count)};
            addLog(sprintf('零点修正已保存: %s（变更 %d 项）', targetPath, saveReport.changed_count));
        catch ME
            msgBox.Value = {['保存失败: ' ME.message]};
        end
    end

    function cfgNew = applyToCfg(baseCfg)
        cfgNew = baseCfg;
        sensor = sensorDrop.Value;

        if ~isfield(cfgNew, 'per_point') || ~isstruct(cfgNew.per_point)
            cfgNew.per_point = struct();
        end
        if ~isfield(cfgNew.per_point, sensor) || ~isstruct(cfgNew.per_point.(sensor))
            cfgNew.per_point.(sensor) = struct();
        end

        perStruct = cfgNew.per_point.(sensor);
        visibleIds = unique(currentVisibleSafeIds, 'stable');
        for i = 1:numel(visibleIds)
            pid = visibleIds{i};
            if isfield(perStruct, pid) && isfield(perStruct.(pid), 'offset_correction')
                perStruct.(pid) = rmfield(perStruct.(pid), 'offset_correction');
                if isempty(fieldnames(perStruct.(pid)))
                    perStruct = rmfield(perStruct, pid);
                end
            end
        end

        if isfield(cfgNew, 'name_map_global') && isstruct(cfgNew.name_map_global)
            nameMap = cfgNew.name_map_global;
        else
            nameMap = struct();
        end

        data = table.Data;
        for i = 1:size(data, 1)
            pidOrig = strtrim(to_char(data{i,1}));
            offset = parse_offset(data{i,2});
            if isempty(pidOrig) || isempty(offset)
                continue;
            end
            pidSafe = bms.data.PointResolver.configKey(pidOrig);
            if ~isfield(perStruct, pidSafe) || ~isstruct(perStruct.(pidSafe))
                perStruct.(pidSafe) = struct();
            end
            perStruct.(pidSafe).offset_correction = offset;
            nameMap.(pidSafe) = pidOrig;
        end

        perNames = fieldnames(perStruct);
        for i = numel(perNames):-1:1
            pid = perNames{i};
            if isempty(fieldnames(perStruct.(pid)))
                perStruct = rmfield(perStruct, pid);
            end
        end

        cfgNew.per_point.(sensor) = perStruct;
        if ~isempty(fieldnames(nameMap))
            cfgNew.name_map_global = nameMap;
        end
        cfgCache = cfgNew;
    end

    function onShow()
        if exist(cfgEdit.Value, 'file')
            try
                cfgCache = bms.gui.ConfigEditorService.load(cfgEdit.Value);
                cfgPath = cfgEdit.Value;
            catch
            end
        end
        refresh_table();
    end

    oc = struct('grid', grid, 'onShow', @onShow, 'applyToCfg', @applyToCfg);
end

function [sensorItems, sensorValues] = list_supported_sensors(cfg)
    sensorValues = bms.gui.ConfigEditorService.editableModuleKeys(cfg, 'offset');
    sensorItems = bms.gui.ConfigEditorService.moduleLabels(sensorValues);
end

function label = format_sensor_label(sensor)
    switch sensor
        case 'wind_speed'
            label = 'wind_speed (风速)';
        case 'wind_direction'
            label = 'wind_direction (风向)';
        case 'gnss'
            label = 'gnss (GNSS)';
        case 'eq_x'
            label = 'eq_x (地震 X)';
        case 'eq_y'
            label = 'eq_y (地震 Y)';
        case 'eq_z'
            label = 'eq_z (地震 Z)';
        otherwise
            label = sensor;
    end
end

function dispId = get_display_id(cfg, safeId)
    dispId = bms.data.PointResolver.originalId(safeId, cfg);
end

function txt = to_char(v)
    if isstring(v)
        txt = char(v);
    elseif ischar(v)
        txt = v;
    else
        txt = '';
    end
end

function offset = parse_offset(raw)
    offset = [];
    if isempty(raw)
        return;
    end
    if ischar(raw) || isstring(raw)
        raw = str2double(raw);
    end
    if isnumeric(raw) && isscalar(raw) && isfinite(raw)
        offset = double(raw);
    end
end

function lines = offset_summary_message(cfg, sensor, perPointCount)
    if nargin < 3
        perPointCount = 0;
    end
    lines = {};
    defaultText = describe_default_offset(cfg, sensor);
    if ~isempty(defaultText)
        lines{end+1} = ['模块默认零点修正: ' defaultText]; %#ok<AGROW>
    else
        lines{end+1} = '模块默认零点修正: 未配置'; %#ok<AGROW>
    end
    lines{end+1} = sprintf('逐点覆盖规则: %d 条。上方表格只显示 per_point.<module>.<point_id>.offset_correction。', perPointCount); %#ok<AGROW>
    lines{end+1} = '计算时会先执行零点修正，再执行阈值过滤和统计。'; %#ok<AGROW>
end

function txt = describe_default_offset(cfg, sensor)
    txt = '';
    if ~isstruct(cfg) || ~isfield(cfg, 'defaults') || ~isstruct(cfg.defaults) ...
            || ~isfield(cfg.defaults, sensor) || ~isstruct(cfg.defaults.(sensor)) ...
            || ~isfield(cfg.defaults.(sensor), 'offset_correction') ...
            || isempty(cfg.defaults.(sensor).offset_correction)
        return;
    end
    raw = cfg.defaults.(sensor).offset_correction;
    if isnumeric(raw) && isscalar(raw)
        txt = sprintf('%g', raw);
        return;
    end
    if ischar(raw) || isstring(raw)
        txt = char(string(raw));
        return;
    end
    if ~isstruct(raw)
        txt = '<unsupported>';
        return;
    end
    parts = {};
    fields = fieldnames(raw);
    for i = 1:numel(fields)
        name = fields{i};
        value = raw.(name);
        if ischar(value) || isstring(value)
            valueText = char(string(value));
        elseif isnumeric(value) && isscalar(value)
            valueText = sprintf('%g', value);
        elseif islogical(value) && isscalar(value)
            valueText = mat2str(value);
        else
            continue;
        end
        parts{end+1} = sprintf('%s=%s', name, valueText); %#ok<AGROW>
    end
    txt = strjoin(parts, ', ');
end
