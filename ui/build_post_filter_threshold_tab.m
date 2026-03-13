function pf = build_post_filter_threshold_tab(tabCfg, f, cfgCache, cfgPath, cfgEdit, addLog, primaryBlue)
% build_post_filter_threshold_tab  Build post-filter threshold editor UI.

    if nargin < 6 || isempty(addLog)
        addLog = @(~) [];
    end

    grid = uigridlayout(tabCfg, [8 4]);
    grid.RowHeight = {32, 32, 120, 32, 220, 32, 32, '1x'};
    grid.ColumnWidth = {200, 190, 240, 220};
    grid.Padding = [8 8 8 8];
    grid.RowSpacing = 6;
    grid.ColumnSpacing = 8;

    uilabel(grid, 'Text', '编辑滤波后二次清洗规则：支持上下限和时间段，保存到 post_filter_thresholds');
    uilabel(grid, 'Text', '传感器类型', 'HorizontalAlignment', 'right');
    sensorList = list_supported_sensors(cfgCache);
    if isempty(sensorList), sensorList = {'deflection'}; end
    sensorDrop = uidropdown(grid, 'Items', sensorList, 'Value', sensorList{1}, ...
        'ValueChangedFcn', @(~,~) refresh_tables());
    sensorDrop.Layout.Row = 2; sensorDrop.Layout.Column = 2;
    filterEdit = uieditfield(grid, 'text', 'Placeholder', '过滤 point_id (包含)...', ...
        'ValueChangedFcn', @(~,~) refresh_tables());
    filterEdit.Layout.Row = 2; filterEdit.Layout.Column = 3;
    reloadBtn = uibutton(grid, 'Text', '重新加载配置', 'ButtonPushedFcn', @(~,~) onReloadCfg());
    reloadBtn.Layout.Row = 2; reloadBtn.Layout.Column = 4;

    defaultsLabel = uilabel(grid, 'Text', '默认滤波后二次清洗 (min/max/时间窗)', 'FontWeight', 'bold');
    defaultsLabel.Layout.Row = 3; defaultsLabel.Layout.Column = 1;
    defaultsTable = uitable(grid, ...
        'ColumnName', {'min','max','t_range_start','t_range_end'}, ...
        'ColumnEditable', true(1,4));
    defaultsTable.Layout.Row = 3; defaultsTable.Layout.Column = [2 4];

    helpBtn = uibutton(grid, 'Text', '说明', 'ButtonPushedFcn', @(~,~) show_help());
    helpBtn.Layout.Row = 4; helpBtn.Layout.Column = 3;
    defaultsBtnGrid = uigridlayout(grid, [1 2]);
    defaultsBtnGrid.Layout.Row = 4; defaultsBtnGrid.Layout.Column = 4;
    defaultsBtnGrid.RowHeight = {'1x'};
    defaultsBtnGrid.ColumnWidth = {'1x','1x'};
    defaultsBtnGrid.Padding = [0 0 0 0];
    defaultsBtnGrid.ColumnSpacing = 6;
    defaultsBtnGrid.RowSpacing = 0;
    defaultsAddBtn = uibutton(defaultsBtnGrid, 'Text', '新增一行', 'ButtonPushedFcn', @(~,~) add_default_row());
    defaultsAddBtn.Layout.Row = 1; defaultsAddBtn.Layout.Column = 1;
    defaultsDelBtn = uibutton(defaultsBtnGrid, 'Text', '删除选中', 'ButtonPushedFcn', @(~,~) delete_default_rows());
    defaultsDelBtn.Layout.Row = 1; defaultsDelBtn.Layout.Column = 2;

    perLabel = uilabel(grid, 'Text', 'per_point 滤波后二次清洗', 'FontWeight', 'bold');
    perLabel.Layout.Row = 5; perLabel.Layout.Column = 1;
    perTable = uitable(grid, ...
        'ColumnName', {'point_id','min','max','t_range_start','t_range_end'}, ...
        'ColumnEditable', true(1,5));
    perTable.Layout.Row = 5; perTable.Layout.Column = [1 4];

    addRowBtn = uibutton(grid, 'Text', '新增行', 'ButtonPushedFcn', @(~,~) add_per_row());
    addRowBtn.Layout.Row = 6; addRowBtn.Layout.Column = 1;
    delRowBtn = uibutton(grid, 'Text', '删除选中行', 'ButtonPushedFcn', @(~,~) delete_per_rows());
    delRowBtn.Layout.Row = 6; delRowBtn.Layout.Column = 2;
    timeBtn = uibutton(grid, 'Text', '选择时间窗', 'ButtonPushedFcn', @(~,~) pick_selected_timerange());
    timeBtn.Layout.Row = 6; timeBtn.Layout.Column = 3;
    saveCfgBtn = uibutton(grid, 'Text', '保存', 'BackgroundColor', primaryBlue, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~,~) onSaveCfg(false));
    saveCfgBtn.Layout.Row = 7; saveCfgBtn.Layout.Column = 3;
    saveAsCfgBtn = uibutton(grid, 'Text', '另存为', 'ButtonPushedFcn', @(~,~) onSaveCfg(true));
    saveAsCfgBtn.Layout.Row = 7; saveAsCfgBtn.Layout.Column = 4;

    msgBox = uitextarea(grid, 'Editable', 'off', ...
        'Value', {'仅对模块滤波后的结果生效；规则按 defaults + per_point 顺序叠加执行。'});
    msgBox.Layout.Row = 8; msgBox.Layout.Column = [1 4];

    refresh_tables();

    function refresh_tables()
        sensorList = list_supported_sensors(cfgCache);
        if isempty(sensorList), sensorList = {'deflection'}; end
        sensorDrop.Items = sensorList;
        if ~ismember(sensorDrop.Value, sensorList)
            sensorDrop.Value = sensorList{1};
        end

        sensor = sensorDrop.Value;
        filterStr = lower(strtrim(filterEdit.Value));

        defaultsRows = {};
        if isfield(cfgCache, 'defaults') && isfield(cfgCache.defaults, sensor)
            defaultsRows = thresholds_to_rows(get_post_thresholds(cfgCache.defaults.(sensor)));
        end
        defaultsTable.Data = defaultsRows;

        perRows = {};
        if isfield(cfgCache, 'per_point') && isfield(cfgCache.per_point, sensor)
            pts = cfgCache.per_point.(sensor);
            pnames = fieldnames(pts);
            for i = 1:numel(pnames)
                safeId = pnames{i};
                dispId = safeId;
                if isfield(cfgCache, 'name_map_global') && isfield(cfgCache.name_map_global, safeId)
                    dispId = cfgCache.name_map_global.(safeId);
                end
                if ~isempty(filterStr) && isempty(strfind(lower(dispId), filterStr)) %#ok<STREMP>
                    continue;
                end
                rows = thresholds_to_rows(get_post_thresholds(pts.(safeId)));
                for k = 1:size(rows, 1)
                    perRows(end+1, :) = [{dispId}, rows(k, :)]; %#ok<AGROW>
                end
            end
        end
        perTable.Data = perRows;
    end

    function add_default_row()
        defaultsTable.Data = [defaultsTable.Data; {[], [], '', ''}];
    end

    function delete_default_rows()
        idx = defaultsTable.Selection;
        if isempty(idx), return; end
        data = defaultsTable.Data;
        data(unique(idx(:,1)), :) = [];
        defaultsTable.Data = data;
    end

    function add_per_row()
        perTable.Data = [perTable.Data; {'', [], [], '', ''}];
    end

    function delete_per_rows()
        idx = perTable.Selection;
        if isempty(idx), return; end
        data = perTable.Data;
        data(unique(idx(:,1)), :) = [];
        perTable.Data = data;
    end

    function pick_selected_timerange()
        [tableRef, rowIdx, startCol, endCol] = get_selected_time_target(defaultsTable, perTable, 3, 4, 4, 5);
        if isempty(tableRef)
            msgBox.Value = {'请先在默认表或 per_point 表中选中一行，再选择时间窗。'};
            return;
        end
        data = tableRef.Data;
        initStart = ''; initEnd = '';
        if size(data,1) >= rowIdx
            initStart = data{rowIdx, startCol};
            initEnd = data{rowIdx, endCol};
        end
        [t0, t1, ok] = pick_datetime_range(f, initStart, initEnd);
        if ~ok
            return;
        end
        data{rowIdx, startCol} = t0;
        data{rowIdx, endCol} = t1;
        tableRef.Data = data;
    end

    function onReloadCfg()
        try
            cfgCache = load_config(cfgEdit.Value);
            cfgPath = cfgEdit.Value;
            refresh_tables();
            msgBox.Value = {'已重新加载配置。'};
        catch ME
            msgBox.Value = {['加载失败: ' ME.message]};
        end
    end

    function show_help()
        msg = sprintf(['字段说明:\n', ...
            '- post_filter_thresholds 在滤波后执行，仅支持上下限和可选时间窗。\n', ...
            '- t_range_start / t_range_end 格式: yyyy-MM-dd HH:mm:ss；留空表示全时段。\n', ...
            '- defaults 与 per_point 会按顺序叠加执行。\n', ...
            '- 未配置该字段的模块不会执行滤波后二次清洗。']);
        uialert(f, msg, '滤波后二次清洗说明');
    end

    function onSaveCfg(doSaveAs)
        try
            cfgNew = cfgCache;
            sensor = sensorDrop.Value;

            cfgNew.defaults.(sensor).post_filter_thresholds = rows_to_thresholds(defaultsTable.Data);

            if ~isfield(cfgNew, 'per_point') || ~isstruct(cfgNew.per_point)
                cfgNew.per_point = struct();
            end
            if ~isfield(cfgNew.per_point, sensor) || ~isstruct(cfgNew.per_point.(sensor))
                cfgNew.per_point.(sensor) = struct();
            end
            perStruct = cfgNew.per_point.(sensor);
            perNames = fieldnames(perStruct);
            for i = 1:numel(perNames)
                pid = perNames{i};
                if isfield(perStruct.(pid), 'post_filter_thresholds')
                    perStruct.(pid) = rmfield(perStruct.(pid), 'post_filter_thresholds');
                end
            end

            pData = perTable.Data;
            if isfield(cfgCache, 'name_map_global') && isstruct(cfgCache.name_map_global)
                nameMap = cfgCache.name_map_global;
            else
                nameMap = struct();
            end

            pointMap = struct();
            for i = 1:size(pData, 1)
                pidOrig = strtrim(to_char(pData{i,1}));
                if isempty(pidOrig), continue; end
                pidSafe = strrep(pidOrig, '-', '_');
                rowThreshold = row_to_threshold(pData(i, 2:5));
                if isempty(rowThreshold), continue; end
                if ~isfield(pointMap, pidSafe)
                    pointMap.(pidSafe) = rowThreshold;
                else
                    pointMap.(pidSafe)(end+1, 1) = rowThreshold; %#ok<AGROW>
                end
                nameMap.(pidSafe) = pidOrig;
            end

            pointNames = fieldnames(pointMap);
            for i = 1:numel(pointNames)
                pid = pointNames{i};
                if ~isfield(perStruct, pid) || ~isstruct(perStruct.(pid))
                    perStruct.(pid) = struct();
                end
                perStruct.(pid).post_filter_thresholds = pointMap.(pid);
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
            validate_config(cfgNew, false);
            cfgCache = cfgNew;
            cfgPath = targetPath;
            cfgEdit.Value = targetPath;
            msgBox.Value = {['已保存配置到 ' targetPath]};
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
        refresh_tables();
    end

    pf = struct('grid', grid, 'onShow', @onShow);
end

function [tableRef, rowIdx, startCol, endCol] = get_selected_time_target(defTable, ptTable, defStartCol, defEndCol, ptStartCol, ptEndCol)
    tableRef = [];
    rowIdx = [];
    startCol = [];
    endCol = [];
    if ~isempty(ptTable.Selection)
        rowIdx = ptTable.Selection(1,1);
        tableRef = ptTable;
        startCol = ptStartCol;
        endCol = ptEndCol;
        return;
    end
    if ~isempty(defTable.Selection)
        rowIdx = defTable.Selection(1,1);
        tableRef = defTable;
        startCol = defStartCol;
        endCol = defEndCol;
    end
end

function sensorList = list_supported_sensors(cfg)
    supported = {'deflection', 'bearing_displacement', 'dynamic_strain'};
    sensorList = {};
    if isfield(cfg, 'defaults') && isstruct(cfg.defaults)
        defaultsFields = fieldnames(cfg.defaults);
        for i = 1:numel(supported)
            if any(strcmp(defaultsFields, supported{i}))
                sensorList{end+1} = supported{i}; %#ok<AGROW>
            end
        end
    end
end

function rows = thresholds_to_rows(ths)
    rows = {};
    if isempty(ths) || ~isstruct(ths)
        return;
    end
    ths = ths(:);
    for i = 1:numel(ths)
        rows(end+1, :) = {num_or_empty(ths(i), 'min'), num_or_empty(ths(i), 'max'), ... %#ok<AGROW>
            str_or_empty(ths(i), 't_range_start'), str_or_empty(ths(i), 't_range_end')};
    end
end

function ths = rows_to_thresholds(data)
    ths = struct('min', {}, 'max', {}, 't_range_start', {}, 't_range_end', {});
    for i = 1:size(data, 1)
        th = row_to_threshold(data(i, :));
        if ~isempty(th)
            ths(end+1, 1) = th; %#ok<AGROW>
        end
    end
end

function th = row_to_threshold(row)
    th = [];
    mn = str2num_safe(row{1});
    mx = str2num_safe(row{2});
    if isempty(mn) || isempty(mx)
        return;
    end
    th = struct('min', mn, 'max', mx, 't_range_start', '', 't_range_end', '');
    t0 = strtrim(to_char(row{3}));
    t1 = strtrim(to_char(row{4}));
    if ~isempty(t0), th.t_range_start = t0; end
    if ~isempty(t1), th.t_range_end = t1; end
end

function ths = get_post_thresholds(block)
    ths = struct('min', {}, 'max', {}, 't_range_start', {}, 't_range_end', {});
    if ~isstruct(block) || ~isfield(block, 'post_filter_thresholds')
        return;
    end
    raw = block.post_filter_thresholds;
    if isempty(raw) || ~isstruct(raw)
        return;
    end
    ths = raw(:);
end

function val = num_or_empty(s, field)
    val = [];
    if isfield(s, field) && ~isempty(s.(field))
        val = s.(field);
    end
end

function val = str_or_empty(s, field)
    val = '';
    if isfield(s, field) && ~isempty(s.(field))
        val = to_char(s.(field));
    end
end

function out = to_char(v)
    if isstring(v)
        out = char(v);
    elseif ischar(v)
        out = v;
    else
        out = '';
    end
end

function v = str2num_safe(x)
    if ischar(x) || isstring(x)
        v = str2double(x);
    elseif isnumeric(x)
        v = x;
    else
        v = [];
    end
    if isempty(v) || any(isnan(v))
        v = [];
    end
end
