function th = build_threshold_tab(tabCfg, f, cfgCache, cfgPath, cfgEdit, addLog, primaryBlue)
% build_threshold_tab  Build threshold configuration tab UI and logic.

    if nargin < 6 || isempty(addLog)
        addLog = @(~) [];
    end

    % layout: left threshold panel + right fig browser panel
    main = uigridlayout(tabCfg,[1 2]);
    main.RowHeight = {'1x'};
    main.ColumnWidth = {'3.5x', 340};
    main.Padding = [8 8 8 8];
    main.RowSpacing = 8; main.ColumnSpacing = 8;

    leftPanel = uipanel(main,'BorderType','none');
    leftPanel.Layout.Row = 1; leftPanel.Layout.Column = 1;
    rightPanel = uipanel(main,'BorderType','none');
    rightPanel.Layout.Row = 1; rightPanel.Layout.Column = 2;

    % left: threshold UI
    cfgGrid = uigridlayout(leftPanel,[8 4]);
    cfgGrid.RowHeight = {32,32,120,32,180,32,32,'1x'};
    cfgGrid.ColumnWidth = {200,190,240,220};
    cfgGrid.Padding = [8 8 8 8]; cfgGrid.RowSpacing = 6; cfgGrid.ColumnSpacing = 8;

    uilabel(cfgGrid,'Text','编辑阈值清洗规则：空=全时段不启用；时间格式 yyyy-MM-dd HH:mm:ss');
    uilabel(cfgGrid,'Text','传感器类型:','HorizontalAlignment','right');
    sensorList = list_sensors(cfgCache);
    if isempty(sensorList), sensorList = {'deflection'}; end
    sensorDrop = uidropdown(cfgGrid,'Items',sensorList,'Value',sensorList{1},'ValueChangedFcn',@(dd,~) refresh_tables());
    sensorDrop.Layout.Row=2; sensorDrop.Layout.Column=2;
    filterEdit = uieditfield(cfgGrid,'text','Placeholder','过滤 point_id (包含)...','ValueChangedFcn',@(ed,~) refresh_tables());
    filterEdit.Layout.Row=2; filterEdit.Layout.Column=3;
    reloadBtn = uibutton(cfgGrid,'Text','重新加载配置','ButtonPushedFcn',@(btn,~) onReloadCfg()); reloadBtn.Layout.Row=2; reloadBtn.Layout.Column=4;
    helpBtn = uibutton(cfgGrid,'Text','说明','ButtonPushedFcn',@(btn,~) show_help()); helpBtn.Layout.Row=1; helpBtn.Layout.Column=4;

    defaultsLabel = uilabel(cfgGrid,'Text','默认阈值 (min/max/时间窗)','FontWeight','bold'); defaultsLabel.Layout.Row=3; defaultsLabel.Layout.Column=1;
    defaultsTable = uitable(cfgGrid,'ColumnName',{'min','max','t_range_start','t_range_end'},'ColumnEditable',true(1,4));
    defaultsTable.Layout.Row=3; defaultsTable.Layout.Column=[2 4];
    zeroChk = uicheckbox(cfgGrid,'Text','zero_to_nan','Value',false); zeroChk.Layout.Row=4; zeroChk.Layout.Column=1;
    outWin = uieditfield(cfgGrid,'numeric','Placeholder','outlier window_sec','Limits',[0 Inf],'ValueDisplayFormat','%.0f','AllowEmpty','on'); outWin.Layout.Row=4; outWin.Layout.Column=2;
    outTh  = uieditfield(cfgGrid,'numeric','Placeholder','threshold_factor','Limits',[0 Inf],'ValueDisplayFormat','%.2f','AllowEmpty','on'); outTh.Layout.Row=4; outTh.Layout.Column=3;
    defaultsBtnGrid = uigridlayout(cfgGrid,[1 2]);
    defaultsBtnGrid.Layout.Row = 4; defaultsBtnGrid.Layout.Column = 4;
    defaultsBtnGrid.RowHeight = {'1x'};
    defaultsBtnGrid.ColumnWidth = {'1x','1x'};
    defaultsBtnGrid.Padding = [0 0 0 0];
    defaultsBtnGrid.ColumnSpacing = 6;
    defaultsBtnGrid.RowSpacing = 0;
    defaultsAddBtn = uibutton(defaultsBtnGrid,'Text','新增一行','ButtonPushedFcn',@(btn,~) add_default_row()); defaultsAddBtn.Layout.Row=1; defaultsAddBtn.Layout.Column=1;
    defaultsDelBtn = uibutton(defaultsBtnGrid,'Text','删除选中','ButtonPushedFcn',@(btn,~) delete_default_rows()); defaultsDelBtn.Layout.Row=1; defaultsDelBtn.Layout.Column=2;

    perLabel = uilabel(cfgGrid,'Text','per_point 阈值 (可新增/删除)','FontWeight','bold'); perLabel.Layout.Row=5; perLabel.Layout.Column=1;
    perTable = uitable(cfgGrid,'ColumnName',{'point_id','min','max','t_range_start','t_range_end','zero_to_nan','outlier_window_sec','outlier_threshold_factor'},'ColumnEditable',true(1,8));
    perTable.Layout.Row=5; perTable.Layout.Column=[1 4];
    addRowBtn = uibutton(cfgGrid,'Text','新增行','ButtonPushedFcn',@(btn,~) add_per_row()); addRowBtn.Layout.Row=6; addRowBtn.Layout.Column=1;
    delRowBtn = uibutton(cfgGrid,'Text','删除选中行','ButtonPushedFcn',@(btn,~) delete_per_rows()); delRowBtn.Layout.Row=6; delRowBtn.Layout.Column=2;
    actionBtnGrid = uigridlayout(cfgGrid,[1 3]);
    actionBtnGrid.Layout.Row = 6; actionBtnGrid.Layout.Column = [3 4];
    actionBtnGrid.RowHeight = {'1x'};
    actionBtnGrid.ColumnWidth = {'1x','1x','1x'};
    actionBtnGrid.Padding = [0 0 0 0];
    actionBtnGrid.ColumnSpacing = 6;
    actionBtnGrid.RowSpacing = 0;
    pickFigBtn = uibutton(actionBtnGrid,'Text','框选','Tooltip','从 FIG 中用矩形框选多条阈值','ButtonPushedFcn',@(btn,~) onPickFromFig('')); pickFigBtn.Layout.Row=1; pickFigBtn.Layout.Column=1;
    pickLineBtn = uibutton(actionBtnGrid,'Text','拖线设阈','Tooltip','选择一条曲线并拖动上下限线段设阈','ButtonPushedFcn',@(btn,~) onPickFromFigLines('')); pickLineBtn.Layout.Row=1; pickLineBtn.Layout.Column=2;
    timeBtn = uibutton(actionBtnGrid,'Text','时间窗','Tooltip','给选中行选择时间窗','ButtonPushedFcn',@(btn,~) pick_selected_timerange()); timeBtn.Layout.Row=1; timeBtn.Layout.Column=3;
    saveCfgBtn = uibutton(cfgGrid,'Text','保存','BackgroundColor',primaryBlue,'FontColor',[1 1 1],'ButtonPushedFcn',@(btn,~) onSaveCfg(false)); saveCfgBtn.Layout.Row=7; saveCfgBtn.Layout.Column=3;
    saveAsCfgBtn = uibutton(cfgGrid,'Text','另存为','ButtonPushedFcn',@(btn,~) onSaveCfg(true)); saveAsCfgBtn.Layout.Row=7; saveAsCfgBtn.Layout.Column=4;
    cfgMsg = uitextarea(cfgGrid,'Editable','off','Value',{'阈值编辑提示：时间格式 yyyy-MM-dd HH:mm:ss；留空表示全时段/不启用。'}); cfgMsg.Layout.Row=8; cfgMsg.Layout.Column=[1 4];

    % right: header + fig browser panel
    rightGrid = uigridlayout(rightPanel,[2 1]);
    rightGrid.RowHeight = {32,'1x'};
    rightGrid.ColumnWidth = {'1x'};
    rightGrid.Padding = [0 0 0 0];
    rightGrid.RowSpacing = 6;

    headerGrid = uigridlayout(rightGrid,[1 3]);
    headerGrid.ColumnWidth = {'1x',80,100};
    headerGrid.RowHeight = {22};
    headerGrid.Padding = [6 6 6 6];
    headerGrid.Layout.Row = 1; headerGrid.Layout.Column = 1;
    uilabel(headerGrid,'Text','FIG 资源','FontWeight','bold');
    collapseBtn = uibutton(headerGrid,'Text','收起','ButtonPushedFcn',@(btn,~) togglePanel());
    collapseBtn.Layout.Column = 2;
    widthSlider = uislider(headerGrid,'Limits',[260 600],'Value',340,'MajorTicks',[],'MinorTicks',[]);
    widthSlider.Layout.Column = 3;
    widthSlider.ValueChangedFcn = @(s,~) setPanelWidth(s.Value);

    bodyPanel = uipanel(rightGrid,'BorderType','none');
    bodyPanel.Layout.Row = 2; bodyPanel.Layout.Column = 1;

    figBrowser = build_fig_browser_panel(bodyPanel, f, @(p) onPickFromFigLines(p));

    currentVisibleSafeIds = {};
    refresh_tables();

    % collapse state
    isCollapsed = false;
    lastWidth = widthSlider.Value;

    function setPanelWidth(w)
        lastWidth = w;
        if ~isCollapsed
            main.ColumnWidth = {'3x', w};
        end
    end
    function togglePanel()
        if ~isCollapsed
            isCollapsed = true;
            collapseBtn.Text = '展开';
            main.ColumnWidth = {'1x', 0};
            rightPanel.Visible = 'off';
        else
            isCollapsed = false;
            collapseBtn.Text = '收起';
            rightPanel.Visible = 'on';
            main.ColumnWidth = {'3x', lastWidth};
        end
    end

    % callbacks
    function refresh_tables()
        currentVisibleSafeIds = {};
        sensors = list_sensors(cfgCache);
        if isempty(sensors)
            sensors = {'deflection'};
        end
        sensorDrop.Items = sensors;
        if ~ismember(sensorDrop.Value, sensors)
            sensorDrop.Value = sensors{1};
        end
        perTable.Selection = [];
        defaultsTable.Selection = [];

        sensor = sensorDrop.Value;
        filterStr = lower(strtrim(filterEdit.Value));
        def = struct(); if isfield(cfgCache,'defaults') && isfield(cfgCache.defaults, sensor), def = cfgCache.defaults.(sensor); end
        defRows = {};
        if isfield(def,'thresholds')
            ths = def.thresholds;
            for k = 1:numel(ths)
                defRows(end+1,:) = {num_or_empty(ths(k),'min'), num_or_empty(ths(k),'max'), str_or_empty(ths(k),'t_range_start'), str_or_empty(ths(k),'t_range_end')}; %#ok<AGROW>
            end
        end
        defaultsTable.Data = defRows;
        zeroChk.Value = isfield(def,'zero_to_nan') && logical(def.zero_to_nan);
        if isfield(def,'outlier') && ~isempty(def.outlier)
            outWin.Value = num_or_empty(def.outlier,'window_sec'); outTh.Value = num_or_empty(def.outlier,'threshold_factor');
        else
            outWin.Value = []; outTh.Value = [];
        end
        perRows = {};
        if isfield(cfgCache,'per_point') && isfield(cfgCache.per_point, sensor)
            pts = cfgCache.per_point.(sensor); pnames = fieldnames(pts);
            for i = 1:numel(pnames)
                pid = pnames{i};
                pidDisp = pid;
                if isfield(cfgCache,'name_map_global') && isfield(cfgCache.name_map_global, pid)
                    pidDisp = cfgCache.name_map_global.(pid);
                end
                pidKey = lower(pidDisp);
                if ~isempty(filterStr) && isempty(strfind(pidKey, filterStr)), continue; end %#ok<STREMP>
                currentVisibleSafeIds{end+1,1} = pid; %#ok<AGROW>
                rule = pts.(pid); ths = []; if isfield(rule,'thresholds'), ths = rule.thresholds; end
                if isempty(ths)
                    perRows(end+1,:) = {pidDisp, [], [], '', '', bool_or_empty(rule,'zero_to_nan'), num_or_empty_out(rule,'outlier','window_sec'), num_or_empty_out(rule,'outlier','threshold_factor')}; %#ok<AGROW>
                else
                    for k = 1:numel(ths)
                        perRows(end+1,:) = {pidDisp, num_or_empty(ths(k),'min'), num_or_empty(ths(k),'max'), str_or_empty(ths(k),'t_range_start'), str_or_empty(ths(k),'t_range_end'), bool_or_empty(rule,'zero_to_nan'), num_or_empty_out(rule,'outlier','window_sec'), num_or_empty_out(rule,'outlier','threshold_factor')}; %#ok<AGROW>
                    end
                end
            end
        end
        currentVisibleSafeIds = unique(currentVisibleSafeIds, 'stable');
        perTable.Data = perRows;
    end
    function add_default_row(), defaultsTable.Data = [defaultsTable.Data; {[], [], '', ''}]; end
    function delete_default_rows()
        idx = defaultsTable.Selection; if isempty(idx), return; end
        data = defaultsTable.Data; data(unique(idx(:,1)),:) = []; defaultsTable.Data = data;
    end
    function add_per_row(), perTable.Data = [perTable.Data; {'', [], [], '', '', false, [], []}]; end
    function delete_per_rows()
        idx = perTable.Selection; if isempty(idx), return; end
        data = perTable.Data; data(idx(:,1),:) = []; perTable.Data = data;
    end
    function pick_selected_timerange()
        [tableRef, rowIdx, startCol, endCol] = get_selected_time_target(defaultsTable, perTable, 3, 4, 4, 5);
        if isempty(tableRef)
            cfgMsg.Value = {'请先在默认表或 per_point 表中选中一行，再选择时间窗。'};
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
    function onPickFromFig(figPath)
        try
            if nargin < 1 || isempty(figPath)
                rows = pick_from_fig(f);
            else
                rows = pick_from_fig(f, figPath);
            end
            if isempty(rows), return; end
            perTable.Data = [perTable.Data; rows];
            addLog(sprintf('从图片追加 %d 条阈值记录', size(rows,1)));
        catch ME
            uialert(f, ['从图片框选失败: ' ME.message], '错误');
        end
    end
    function onPickFromFigLines(figPath)
        try
            if nargin < 1 || isempty(figPath)
                picked = pick_threshold_lines_from_fig(f);
            else
                picked = pick_threshold_lines_from_fig(f, figPath);
            end
            if isempty(picked), return; end
            newRow = {picked.point_id, picked.min, picked.max, picked.t_range_start, picked.t_range_end, false, [], []};
            perTable.Data = [perTable.Data; newRow];
            addLog(['从 FIG 拖线追加阈值: ' picked.point_id]);
        catch ME
            uialert(f, ['FIG 拖线设阈失败: ' ME.message], '错误');
        end
    end
    function onReloadCfg()
        try
            cfgCache = load_config(cfgEdit.Value); cfgPath = cfgEdit.Value; refresh_tables(); cfgMsg.Value = {'已重新加载配置。'};
        catch ME
            cfgMsg.Value = {['加载失败: ' ME.message]};
        end
    end
    function show_help()
        msg = sprintf(['字段说明:\n', ...
            '- t_range_start / t_range_end: 时间范围，格式 yyyy-MM-dd HH:mm:ss，留空表示全时段。\n', ...
            '- zero_to_nan: 勾选表示把数值为 0 视为缺失(NaN)。\n', ...
            '- outlier_window_sec: 移动窗长度(秒)，配合 threshold_factor 做 isoutlier(movmedian)；留空表示不启用。\n', ...
            '- outlier_threshold_factor: 异常阈值系数，越大越宽松；留空表示不启用。\n', ...
            '- thresholds: 每行 min/max 为必填，时间窗可选，超限将置 NaN。\n', ...
            '保存会先校验格式并自动备份。']);
        uialert(f, msg, '阈值配置说明');
    end
    function onSaveCfg(doSaveAs)
        try
            cfgNew = applyToCfg(cfgCache);

            targetPath = cfgPath;
            if doSaveAs
                [fname,fpath] = uiputfile('*.json','另存为',cfgPath); if isequal(fname,0), return; end
                targetPath = fullfile(fpath,fname);
            end
            save_config(cfgNew, targetPath, true); validate_config(cfgNew, false);
            cfgCache = cfgNew; cfgPath = targetPath; cfgEdit.Value = targetPath; cfgMsg.Value = {['已保存配置到 ' targetPath]};
        catch ME
            cfgMsg.Value = {['保存失败: ' ME.message]};
        end
    end

    function cfgNew = applyToCfg(baseCfg)
        cfgNew = baseCfg;
        sensor = sensorDrop.Value;

        dData = defaultsTable.Data;
        ths = struct('min',{},'max',{},'t_range_start',{},'t_range_end',{});
        for i = 1:size(dData,1)
            mn = str2num_safe(dData{i,1});
            mx = str2num_safe(dData{i,2});
            if isempty(mn) || isempty(mx), continue; end
            t0 = strtrim(dData{i,3});
            t1 = strtrim(dData{i,4});
            ths(end+1) = make_threshold(mn, mx, t0, t1); %#ok<AGROW>
        end
        cfgNew.defaults.(sensor).thresholds = ths;
        cfgNew.defaults.(sensor).zero_to_nan = logical(zeroChk.Value);
        ow = outWin.Value;
        ot = outTh.Value;
        if ~isempty(ow) || ~isempty(ot)
            cfgNew.defaults.(sensor).outlier = struct('window_sec', ow, 'threshold_factor', ot);
        else
            cfgNew.defaults.(sensor).outlier = [];
        end

        pData = perTable.Data;
        if isfield(cfgNew,'per_point') && isfield(cfgNew.per_point, sensor) && isstruct(cfgNew.per_point.(sensor))
            perStruct = cfgNew.per_point.(sensor);
        else
            perStruct = struct();
        end
        th_map = struct();
        meta_map = struct();
        if isfield(cfgNew,'name_map_global') && isstruct(cfgNew.name_map_global)
            name_map = cfgNew.name_map_global;
        else
            name_map = struct();
        end
        visibleIds = unique(currentVisibleSafeIds, 'stable');
        for ii = 1:numel(visibleIds)
            pid = visibleIds{ii};
            if ~isfield(perStruct, pid) || ~isstruct(perStruct.(pid))
                continue;
            end
            for fn = {'thresholds','zero_to_nan','outlier'}
                if isfield(perStruct.(pid), fn{1})
                    perStruct.(pid) = rmfield(perStruct.(pid), fn{1});
                end
            end
            if isempty(fieldnames(perStruct.(pid)))
                perStruct = rmfield(perStruct, pid);
            end
        end
        for i = 1:size(pData,1)
            pidOrig = strtrim(pData{i,1});
            if isempty(pidOrig), continue; end
            pidSafe = strrep(pidOrig,'-','_');
            mn = str2num_safe(pData{i,2});
            mx = str2num_safe(pData{i,3});
            if isempty(mn) || isempty(mx), continue; end
            t0 = strtrim(pData{i,4});
            t1 = strtrim(pData{i,5});
            th = make_threshold(mn, mx, t0, t1);
            if ~isfield(th_map, pidSafe)
                th_map.(pidSafe) = th;
                meta_map.(pidSafe) = struct( ...
                    'zero_to_nan', logical(pData{i,6}), ...
                    'ow', str2num_safe(pData{i,7}), ...
                    'ot', str2num_safe(pData{i,8}));
                name_map.(pidSafe) = pidOrig;
            else
                th_map.(pidSafe)(end+1) = th; %#ok<AGROW>
            end
        end
        pnames = fieldnames(th_map);
        for ii = 1:numel(pnames)
            pid = pnames{ii};
            perStruct.(pid).thresholds = th_map.(pid);
            perStruct.(pid).zero_to_nan = meta_map.(pid).zero_to_nan;
            owv = meta_map.(pid).ow;
            otv = meta_map.(pid).ot;
            if ~isempty(owv) || ~isempty(otv)
                perStruct.(pid).outlier = struct('window_sec', owv, 'threshold_factor', otv);
            else
                perStruct.(pid).outlier = [];
            end
        end
        cfgNew.per_point.(sensor) = perStruct;
        if ~isempty(fieldnames(name_map))
            cfgNew.name_map_global = name_map;
        end
        cfgCache = cfgNew;
    end

    % 工具
    function val = num_or_empty(s, field), val=[]; if isfield(s,field) && ~isempty(s.(field)), val = s.(field); end; end
    function val = num_or_empty_out(s, field, subfield), val=[]; if isfield(s,field)&&isstruct(s.(field))&&isfield(s.(field),subfield), val=s.(field).(subfield); end; end
    function val = bool_or_empty(s, field), val=false; if isfield(s,field)&&~isempty(s.(field)), val=logical(s.(field)); end; end
    function val = str_or_empty(s, field), val=''; if isfield(s,field)&&~isempty(s.(field)), val=s.(field); end; end
    function v = str2num_safe(x)
        if ischar(x) || isstring(x), v = str2double(x); elseif isnumeric(x), v = x; else, v = []; end; if isnan(v), v=[]; end
    end
    function names = list_sensors(c)
        names = {}; if isfield(c,'defaults'), fn = fieldnames(c.defaults); names = fn(~strcmp(fn,'header_marker')); end; if isempty(names), names={'deflection'}; end
    end
    function ths = make_threshold(mn, mx, t0, t1)
        ths = struct('min', mn, 'max', mx, 't_range_start', '', 't_range_end', '');
        if ~isempty(t0), ths.t_range_start = t0; end
        if ~isempty(t1), ths.t_range_end   = t1; end
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

    function onShow()
        if exist(cfgEdit.Value, 'file')
            try
                cfgCache = load_config(cfgEdit.Value);
                cfgPath = cfgEdit.Value;
            catch
            end
        end
        refresh_tables();
        if isstruct(figBrowser) && isfield(figBrowser,'refresh')
            figBrowser.refresh();
        end
    end

    th = struct('grid', cfgGrid, 'perTable', perTable, 'onShow', @onShow, 'applyToCfg', @applyToCfg);
end
