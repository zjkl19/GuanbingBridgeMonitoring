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
                if ~isempty(filterStr) && isempty(strfind(lower(dispId), filterStr)) %#ok<STREMP>
                    continue;
                end
                currentVisibleSafeIds{end+1,1} = safeId; %#ok<AGROW>
                rows(end+1, :) = {dispId, pt.offset_correction}; %#ok<AGROW>
            end
        end
        currentVisibleSafeIds = unique(currentVisibleSafeIds, 'stable');
        table.Data = rows;
        table.Selection = [];
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
            cfgCache = load_config(cfgEdit.Value);
            cfgPath = cfgEdit.Value;
            refresh_table();
            msgBox.Value = {'已重新加载配置。'};
        catch ME
            msgBox.Value = {['加载失败: ' ME.message]};
        end
    end

    function onSaveCfg(doSaveAs)
        try
            cfgNew = cfgCache;
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

            if isfield(cfgCache, 'name_map_global') && isstruct(cfgCache.name_map_global)
                nameMap = cfgCache.name_map_global;
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
                pidSafe = strrep(pidOrig, '-', '_');
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

            targetPath = cfgPath;
            if doSaveAs
                [fname, fpath] = uiputfile('*.json', '另存为', cfgPath);
                if isequal(fname, 0), return; end
                targetPath = fullfile(fpath, fname);
            end
            save_config(cfgNew, targetPath, true);
            validate_config(cfgNew);
            cfgCache = load_config(targetPath);
            cfgPath = targetPath;
            cfgEdit.Value = targetPath;
            refresh_table();
            msgBox.Value = {['已保存配置到 ' targetPath]};
            addLog(['零点修正已保存: ' targetPath]);
        catch ME
            msgBox.Value = {['保存失败: ' ME.message]};
        end
    end

    function onShow()
        if exist(cfgEdit.Value, 'file')
            try
                cfgCache = load_config(cfgEdit.Value);
                cfgPath = cfgEdit.Value;
            catch
            end
        end
        refresh_table();
    end

    oc = struct('grid', grid, 'onShow', @onShow);
end

function [sensorItems, sensorValues] = list_supported_sensors(cfg)
    sensorValues = {};
    if isfield(cfg, 'defaults') && isstruct(cfg.defaults)
        sensorValues = [sensorValues; fieldnames(cfg.defaults)]; %#ok<AGROW>
    end
    if isfield(cfg, 'per_point') && isstruct(cfg.per_point)
        sensorValues = [sensorValues; fieldnames(cfg.per_point)]; %#ok<AGROW>
    end
    sensorValues = unique(sensorValues, 'stable');
    exclude = {'header_marker', 'wind', 'eq', 'accel_spectrum', 'cable_accel_spectrum'};
    mask = ~ismember(sensorValues, exclude);
    sensorValues = sensorValues(mask);

    preferredOrder = { ...
        'deflection', 'bearing_displacement', 'tilt', 'strain', 'crack', ...
        'temperature', 'humidity', 'acceleration', 'cable_accel', ...
        'wind_speed', 'wind_direction', 'eq_x', 'eq_y', 'eq_z'};

    ordered = {};
    for i = 1:numel(preferredOrder)
        if any(strcmp(sensorValues, preferredOrder{i}))
            ordered{end+1, 1} = preferredOrder{i}; %#ok<AGROW>
        end
    end
    for i = 1:numel(sensorValues)
        if ~any(strcmp(ordered, sensorValues{i}))
            ordered{end+1, 1} = sensorValues{i}; %#ok<AGROW>
        end
    end
    sensorValues = ordered;
    if isempty(sensorValues)
        sensorValues = {'deflection'};
    end
    sensorItems = cellfun(@format_sensor_label, sensorValues, 'UniformOutput', false);
end

function label = format_sensor_label(sensor)
    switch sensor
        case 'wind_speed'
            label = 'wind_speed (风速)';
        case 'wind_direction'
            label = 'wind_direction (风向)';
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
    dispId = safeId;
    if isfield(cfg, 'name_map_global') && isstruct(cfg.name_map_global) && isfield(cfg.name_map_global, safeId)
        dispId = cfg.name_map_global.(safeId);
    end
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
