function psTab = build_plot_settings_tab(tabCfg, f, cfgCache, cfgPath, cfgEdit, addLog, primaryBlue)
% build_plot_settings_tab Build plot-settings editor UI.

    if nargin < 6 || isempty(addLog)
        addLog = @(~) [];
    end

    moduleDefs = { ...
        struct('value', 'acceleration', 'label', '鍔犻€熷害'), ...
        struct('value', 'cable_accel', 'label', '绱㈠姏鍔犻€熷害'), ...
        struct('value', 'strain', 'label', '搴斿彉'), ...
        struct('value', 'dynamic_strain', 'label', '鍔ㄥ簲鍙橀珮閫?), ...
        struct('value', 'dynamic_strain_lowpass', 'label', '鍔ㄥ簲鍙樹綆閫?), ...
        struct('value', 'tilt', 'label', '鍊捐'), ...
        struct('value', 'bearing_displacement', 'label', '鏀骇浣嶇Щ'), ...
        struct('value', 'deflection', 'label', '鎸犲害'), ...
        struct('value', 'eq', 'label', '鍦伴渿鍔?), ...
        struct('value', 'crack', 'label', '瑁傜紳'), ...
        struct('value', 'temperature', 'label', '娓╁害'), ...
        struct('value', 'humidity', 'label', '婀垮害'), ...
        struct('value', 'rainfall', 'label', '闆ㄩ噺'), ...
        struct('value', 'gnss', 'label', 'GNSS')};
    moduleValues = cellfun(@(x) x.value, moduleDefs, 'UniformOutput', false);
    moduleLabels = cellfun(@(x) x.label, moduleDefs, 'UniformOutput', false);

    draftCfg = cfgCache;
    currentModule = moduleValues{1};
    selectedRows = [];
    updating = false;

    grid = uigridlayout(tabCfg, [8 4]);
    % The global plot-settings panel now has four rows; give it enough
    % height so the gap controls are not clipped.
    grid.RowHeight = {170, 32, 96, 32, 230, 32, 32, '1x'};
    grid.ColumnWidth = {'1x', '1x', '1x', 160};
    grid.Padding = [8 8 8 8];
    grid.RowSpacing = 8;
    grid.ColumnSpacing = 8;

    globalPanel = uipanel(grid, 'Title', '鍏ㄥ眬缁樺浘淇濆瓨璁剧疆');
    globalPanel.Layout.Row = 1; globalPanel.Layout.Column = [1 4];
    globalGrid = uigridlayout(globalPanel, [4 4]);
    globalGrid.RowHeight = {28, 28, 28, 28};
    globalGrid.ColumnWidth = {'1x', '1x', 160, '1x'};

    cbSaveFig = uicheckbox(globalGrid, 'Text', '淇濆瓨 .fig', ...
        'ValueChangedFcn', @(~,~) onGlobalChanged());
    cbSaveFig.Layout.Row = 1; cbSaveFig.Layout.Column = 1;

    cbLightFig = uicheckbox(globalGrid, 'Text', '杞婚噺 .fig', ...
        'ValueChangedFcn', @(~,~) onGlobalChanged());
    cbLightFig.Layout.Row = 1; cbLightFig.Layout.Column = 2;

    figMaxLabel = uilabel(globalGrid, 'Text', 'fig_max_points', 'HorizontalAlignment', 'right', ...
        'Tooltip', '鍗曟潯鏇茬嚎鐐规暟瓒呰繃姝ら槇鍊兼椂锛屼繚瀛?.fig 鍓嶅仛淇濆嘲闄嶉噰鏍枫€?);
    figMaxLabel.Layout.Row = 1; figMaxLabel.Layout.Column = 3;
    figMaxEdit = uieditfield(globalGrid, 'numeric', 'Limits', [1000 Inf], ...
        'RoundFractionalValues', true, 'ValueDisplayFormat', '%.0f', ...
        'ValueChangedFcn', @(~,~) onGlobalChanged());
    figMaxEdit.Layout.Row = 1; figMaxEdit.Layout.Column = 4;

    cbAutoFolders = uicheckbox(globalGrid, 'Text', '鑷姩鏁寸悊缁撴灉鐩綍瑙嗗浘', ...
        'ValueChangedFcn', @(~,~) onGlobalChanged());
    cbAutoFolders.Layout.Row = 2; cbAutoFolders.Layout.Column = [1 2];

    cbAppendTimestamp = uicheckbox(globalGrid, 'Text', '鍥剧墖杩藉姞杩愯鏃堕棿鎴?, ...
        'Tooltip', '鍙栨秷鍚庝繚鐣欐暟鎹懆鏈燂紝浣嗗幓鎺夎繍琛屾椂闂存埑锛涘悓涓€鍛ㄦ湡閲嶇畻浼氳鐩栨棫鍥剧墖銆?, ...
        'ValueChangedFcn', @(~,~) onGlobalChanged());
    cbAppendTimestamp.Layout.Row = 2; cbAppendTimestamp.Layout.Column = [3 4];

    globalHint = uilabel(globalGrid, 'Text', '浠呭奖鍝嶇粯鍥句繚瀛樹笌缁撴灉鐩綍灞曠ず锛屼笉褰卞搷鍘熷鏁版嵁澶勭悊銆?);
    globalHint.Layout.Row = 4; globalHint.Layout.Column = [1 4];

    gapModeLabel = uilabel(globalGrid, 'Text', 'Gap mode', 'HorizontalAlignment', 'right', ...
        'Tooltip', 'connect: 缂哄彛鐩存帴杩炵嚎; break: 缂哄彛鐣欑┖');
    gapModeLabel.Layout.Row = 3; gapModeLabel.Layout.Column = 1;
    gapModeDrop = uidropdown(globalGrid, 'Items', {'break', 'connect'}, ...
        'ValueChangedFcn', @(~,~) onGlobalChanged());
    gapModeDrop.Layout.Row = 3; gapModeDrop.Layout.Column = 2;

    gapFactorLabel = uilabel(globalGrid, 'Text', 'Gap factor', 'HorizontalAlignment', 'right', ...
        'Tooltip', '鐩搁偦鏃堕棿宸秴杩?median(diff)*璇ュ€嶆暟鏃讹紝break 妯″紡鏂嚎');
    gapFactorLabel.Layout.Row = 3; gapFactorLabel.Layout.Column = 3;
    gapFactorEdit = uieditfield(globalGrid, 'numeric', 'Limits', [1.1 Inf], ...
        'ValueDisplayFormat', '%.1f', 'RoundFractionalValues', false, ...
        'ValueChangedFcn', @(~,~) onGlobalChanged());
    gapFactorEdit.Layout.Row = 3; gapFactorEdit.Layout.Column = 4;

    moduleLabel = uilabel(grid, 'Text', '妯″潡', 'HorizontalAlignment', 'right');
    moduleLabel.Layout.Row = 2; moduleLabel.Layout.Column = 1;
    moduleDrop = uidropdown(grid, 'Items', moduleLabels, 'ItemsData', moduleValues, ...
        'Value', currentModule, 'ValueChangedFcn', @(~,~) onModuleChanged());
    moduleDrop.Layout.Row = 2; moduleDrop.Layout.Column = 2;

    reloadBtn = uibutton(grid, 'Text', '閲嶆柊鍔犺浇閰嶇疆', 'ButtonPushedFcn', @(~,~) onReloadCfg());
    reloadBtn.Layout.Row = 2; reloadBtn.Layout.Column = 4;

    modulePanel = uipanel(grid, 'Title', '妯″潡绾х粯鍥惧弬鏁?);
    modulePanel.Layout.Row = 3; modulePanel.Layout.Column = [1 4];
    moduleGrid = uigridlayout(modulePanel, [3 4]);
    moduleGrid.RowHeight = {28, 28, 28};
    moduleGrid.ColumnWidth = {130, 110, 110, '1x'};

    cbYlimAuto = uicheckbox(moduleGrid, 'Text', 'Y杞磋嚜鍔?, ...
        'ValueChangedFcn', @(~,~) onModuleFieldChanged());
    cbYlimAuto.Layout.Row = 1; cbYlimAuto.Layout.Column = 1;

    ylimMinLabel = uilabel(moduleGrid, 'Text', 'ylim_min', 'HorizontalAlignment', 'right');
    ylimMinLabel.Layout.Row = 1; ylimMinLabel.Layout.Column = 2;
    ylimMinEdit = uieditfield(moduleGrid, 'text', 'ValueChangedFcn', @(~,~) onModuleFieldChanged());
    ylimMinEdit.Layout.Row = 1; ylimMinEdit.Layout.Column = 3;

    ylimMaxLabel = uilabel(moduleGrid, 'Text', 'ylim_max', 'HorizontalAlignment', 'right');
    ylimMaxLabel.Layout.Row = 2; ylimMaxLabel.Layout.Column = 2;
    ylimMaxEdit = uieditfield(moduleGrid, 'text', 'ValueChangedFcn', @(~,~) onModuleFieldChanged());
    ylimMaxEdit.Layout.Row = 2; ylimMaxEdit.Layout.Column = 3;

    moduleHint = uilabel(moduleGrid, 'Text', '褰撳墠妯″潡鐨勫叏灞€ Y 杞磋寖鍥淬€傝嫢鍚敤 Y杞磋嚜鍔紝鍒欐澶勫彧浣滃閫変繚瀛樸€?);
    moduleHint.Layout.Row = [1 2]; moduleHint.Layout.Column = 4;

    cbShowOutliers = uicheckbox(moduleGrid, 'Text', '绠辩嚎鍥炬樉绀虹缇ゅ€?, ...
        'ValueChangedFcn', @(~,~) onModuleFieldChanged());
    cbShowOutliers.Layout.Row = 3; cbShowOutliers.Layout.Column = 1;

    cbShowWarnPoint = uicheckbox(moduleGrid, 'Text', '鍗曠偣鍥炬樉绀洪璀︾嚎', ...
        'ValueChangedFcn', @(~,~) onModuleFieldChanged());
    cbShowWarnPoint.Layout.Row = 3; cbShowWarnPoint.Layout.Column = 2;

    cbShowWarnBox = uicheckbox(moduleGrid, 'Text', '绠辩嚎鍥炬樉绀洪璀︾嚎', ...
        'ValueChangedFcn', @(~,~) onModuleFieldChanged());
    cbShowWarnBox.Layout.Row = 3; cbShowWarnBox.Layout.Column = 3;

    ylimsLabel = uilabel(grid, 'Text', 'ylims 瑕嗙洊', 'FontWeight', 'bold');
    ylimsLabel.Layout.Row = 4; ylimsLabel.Layout.Column = 1;
    ylimsTable = uitable(grid, ...
        'ColumnName', {'name', 'ylim_min', 'ylim_max'}, ...
        'ColumnEditable', [true true true], ...
        'CellSelectionCallback', @(~, evt) onTableSelected(evt), ...
        'CellEditCallback', @(~,~) onTableEdited());
    ylimsTable.Layout.Row = 5; ylimsTable.Layout.Column = [1 4];

    addRowBtn = uibutton(grid, 'Text', '鏂板涓€琛?, 'ButtonPushedFcn', @(~,~) add_row());
    addRowBtn.Layout.Row = 6; addRowBtn.Layout.Column = 1;
    delRowBtn = uibutton(grid, 'Text', '鍒犻櫎閫変腑琛?, 'ButtonPushedFcn', @(~,~) delete_rows());
    delRowBtn.Layout.Row = 6; delRowBtn.Layout.Column = 2;

    saveBtn = uibutton(grid, 'Text', '淇濆瓨', 'BackgroundColor', primaryBlue, ...
        'FontColor', [1 1 1], 'ButtonPushedFcn', @(~,~) onSaveCfg(false));
    saveBtn.Layout.Row = 6; saveBtn.Layout.Column = 3;
    saveAsBtn = uibutton(grid, 'Text', '鍙﹀瓨涓?, 'ButtonPushedFcn', @(~,~) onSaveCfg(true));
    saveAsBtn.Layout.Row = 6; saveAsBtn.Layout.Column = 4;

    msgBox = uitextarea(grid, 'Editable', 'off', 'Value', { ...
        '璇ラ〉浠呯紪杈戠粯鍥惧弬鏁帮細妯″潡绾?ylim / ylims 瑕嗙洊 / strain 鏄剧ず寮€鍏?/ .fig 淇濆瓨琛屼负銆?, ...
        '涓嶄慨鏀归槇鍊兼竻娲椼€佹护娉㈠悗浜屾娓呮礂鎴栭浂鐐逛慨姝ｃ€?});
    msgBox.Layout.Row = [7 8]; msgBox.Layout.Column = [1 4];

    refresh_all_controls();

    function onReloadCfg()
        try
            draftCfg = load_config(cfgEdit.Value);
            cfgCache = draftCfg;
            cfgPath = cfgEdit.Value;
            currentModule = moduleDrop.Value;
            refresh_all_controls();
            msgBox.Value = {'宸查噸鏂板姞杞介厤缃€?};
        catch ME
            msgBox.Value = {['鍔犺浇澶辫触: ' ME.message]};
        end
    end

    function onGlobalChanged()
        if updating
            return;
        end
        persist_global_to_draft();
    end

    function onModuleChanged()
        if updating
            currentModule = moduleDrop.Value;
            return;
        end
        persist_current_module_to_draft();
        currentModule = moduleDrop.Value;
        refresh_module_controls();
    end

    function onModuleFieldChanged()
        if updating
            return;
        end
        persist_current_module_to_draft();
        sync_module_enable_state();
    end

    function onTableSelected(evt)
        selectedRows = [];
        if ~isempty(evt.Indices)
            selectedRows = unique(evt.Indices(:, 1), 'stable');
        end
    end

    function onTableEdited()
        if updating
            return;
        end
        persist_current_module_to_draft();
    end

    function add_row()
        data = ylimsTable.Data;
        if isempty(data)
            data = {'', [], []};
        else
            data = [data; {'', [], []}];
        end
        ylimsTable.Data = data;
        persist_current_module_to_draft();
    end

    function delete_rows()
        if isempty(selectedRows)
            return;
        end
        data = ylimsTable.Data;
        keep = true(size(data, 1), 1);
        keep(selectedRows) = false;
        ylimsTable.Data = data(keep, :);
        selectedRows = [];
        persist_current_module_to_draft();
    end

    function onSaveCfg(doSaveAs)
        try
            cfgNew = applyToCfg(cfgCache);

            targetPath = cfgPath;
            if doSaveAs
                [fname, fpath] = uiputfile('*.json', '鍙﹀瓨涓?, cfgPath);
                if isequal(fname, 0)
                    return;
                end
                targetPath = fullfile(fpath, fname);
            end

            save_config(cfgNew, targetPath, true);
            cfgCache = load_config(targetPath);
            draftCfg = cfgCache;
            cfgPath = targetPath;
            cfgEdit.Value = targetPath;
            refresh_all_controls();
            msgBox.Value = {['宸蹭繚瀛橀厤缃埌 ' targetPath]};
            addLog(['缁樺浘鍙傛暟宸蹭繚瀛? ' targetPath]);
        catch ME
            msgBox.Value = {['淇濆瓨澶辫触: ' ME.message]};
        end
    end

    function onShow()
        if exist(cfgEdit.Value, 'file')
            try
                cfgCache = load_config(cfgEdit.Value);
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
        style = get_plot_style(draftCfg, currentModule);
        cbYlimAuto.Value = get_truthy_field(style, 'ylim_auto', false);
        [ylimMin, ylimMax] = split_ylim(getfield_default(style, 'ylim', [])); %#ok<GFLD>
        ylimMinEdit.Value = format_num(ylimMin);
        ylimMaxEdit.Value = format_num(ylimMax);

        isStrain = strcmp(currentModule, 'strain');
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

        ylimsTable.Data = ylims_to_rows(getfield_default(style, 'ylims', [])); %#ok<GFLD>
        selectedRows = [];
        sync_module_enable_state();
    end

    function sync_module_enable_state()
        manual = ~cbYlimAuto.Value;
        ylimMinEdit.Editable = manual;
        ylimMaxEdit.Editable = manual;
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
        module = currentModule;
        if isempty(module)
            return;
        end
        if ~isfield(draftCfg, 'plot_styles') || ~isstruct(draftCfg.plot_styles)
            draftCfg.plot_styles = struct();
        end
        if ~isfield(draftCfg.plot_styles, module) || ~isstruct(draftCfg.plot_styles.(module))
            draftCfg.plot_styles.(module) = struct();
        end
        style = draftCfg.plot_styles.(module);

        style.ylim_auto = logical(cbYlimAuto.Value);

        minVal = parse_optional_number(ylimMinEdit.Value);
        maxVal = parse_optional_number(ylimMaxEdit.Value);
        if isfinite(minVal) && isfinite(maxVal) && maxVal > minVal
            style.ylim = [minVal, maxVal];
        else
            style = rmfield_if_present(style, 'ylim');
        end

        rows = ylimsTable.Data;
        ylimsValue = rows_to_ylims(rows);
        if isempty(ylimsValue)
            style = rmfield_if_present(style, 'ylims');
        else
            style.ylims = ylimsValue;
        end

        if strcmp(module, 'strain')
            style.show_boxplot_outliers = logical(cbShowOutliers.Value);
            style.show_warn_lines_point = logical(cbShowWarnPoint.Value);
            style.show_warn_lines_boxplot = logical(cbShowWarnBox.Value);
        end

        draftCfg.plot_styles.(module) = style;
    end

    psTab = struct('grid', grid, 'onShow', @onShow, 'applyToCfg', @applyToCfg);
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
        if isfield(src, 'save_fig') && ~isempty(src.save_fig)
            common.save_fig = logical(src.save_fig);
        end
        if isfield(src, 'lightweight_fig') && ~isempty(src.lightweight_fig)
            common.lightweight_fig = logical(src.lightweight_fig);
        end
        if isfield(src, 'fig_max_points') && isnumeric(src.fig_max_points) && isscalar(src.fig_max_points) && isfinite(src.fig_max_points)
            common.fig_max_points = max(1000, round(src.fig_max_points));
        end
        if isfield(src, 'append_timestamp') && ~isempty(src.append_timestamp)
            common.append_timestamp = logical(src.append_timestamp);
        end
        if isfield(src, 'gap_mode') && ~isempty(src.gap_mode)
            mode = lower(char(string(src.gap_mode)));
            if ismember(mode, {'break', 'connect'})
                common.gap_mode = mode;
            end
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

function style = get_plot_style(cfg, module)
    style = struct();
    if isstruct(cfg) && isfield(cfg, 'plot_styles') && isstruct(cfg.plot_styles) && ...
            isfield(cfg.plot_styles, module) && isstruct(cfg.plot_styles.(module))
        style = cfg.plot_styles.(module);
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
        names = fieldnames(ylims);
        if isfield(ylims, 'name') && isfield(ylims, 'ylim') && isscalar(ylims)
            [mn, mx] = split_ylim(ylims.ylim);
            rows(end+1, :) = {to_char(ylims.name), mn, mx}; %#ok<AGROW>
            return;
        end
        for i = 1:numel(names)
            [mn, mx] = split_ylim(ylims.(names{i}));
            rows(end+1, :) = {names{i}, mn, mx}; %#ok<AGROW>
        end
        return;
    end
    if iscell(ylims)
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
    ylims = struct('name', {}, 'ylim', {});
    if isempty(rows)
        ylims = [];
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
    if isempty(out)
        ylims = [];
    else
        ylims = out;
    end
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
    if isstruct(s) && isfield(s, fieldName)
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
    if isstring(v)
        txt = char(v);
    elseif ischar(v)
        txt = v;
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

