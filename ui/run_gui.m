function varargout = run_gui(varargin)
% run_gui  GUI 入口，便于配置并运行 run_all；含阈值配置页。
% 用法：addpath(fullfile(pwd,'ui')); run_gui
%       fig = run_gui('Visible','off');  % GUI smoke test

    import matlab.ui.control.*
    import matlab.ui.container.*
    if ~exist('uilabel','file')
        error('uilabel 不可用，请检查 uicomponents 路径是否已加入 (matlabroot/toolbox/matlab/uicomponents/uicomponents)');
    end

    uiOptions = parse_gui_options(varargin{:});

    % 项目根目录
    projRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(projRoot, fullfile(projRoot,'config'), fullfile(projRoot,'pipeline'), ...
        fullfile(projRoot,'analysis'), fullfile(projRoot,'scripts'));

    profiles = bms.profile.BridgeProfileRegistry.catalog(projRoot);
    if isempty(profiles)
        activeProfile = bms.profile.BridgeProfileRegistry.fromId('guanbing', projRoot);
    else
        activeProfile = profiles(1);
    end
    defaultCfgPath = activeProfile.DefaultConfig;
    if isempty(defaultCfgPath)
        defaultCfgPath = fullfile(projRoot,'config','default_config.json');
    end
    defaultDataRoot = activeProfile.DefaultDataRoot;
    if isempty(defaultDataRoot)
        defaultDataRoot = projRoot;
    end
    defaultLogDir  = bms.core.PathResolver.logDir(defaultDataRoot);

    primaryBlue = [0 94 172]/255;
    [cfgCache, cfgPath] = bms.gui.GuiConfigBinder.loadConfig(defaultCfgPath, defaultCfgPath);
    showWarningsDefault = bms.gui.GuiConfigBinder.showWarningsDefault(cfgCache);
    cfgPath = defaultCfgPath;

    f = uifigure('Name','福建建科院健康监测大数据分析', ...
        'Position',bms.gui.GuiLayout.mainWindowPosition(), ...
        'Color',[0.97 0.98 1], ...
        'Visible',uiOptions.Visible);
    mainGrid = uigridlayout(f,[1 1]); mainGrid.RowHeight = {'1x'}; mainGrid.ColumnWidth = {'1x'}; mainGrid.Padding = [0 0 0 0];
    tg = uitabgroup(mainGrid); tg.Layout.Row = 1; tg.Layout.Column = 1;
    tabRun = uitab(tg,'Title','运行');
    tabCfg = uitab(tg,'Title','阈值配置');
    tabAutoThreshold = uitab(tg,'Title','自动清洗建议');
    tabPostCfg = uitab(tg,'Title','滤波后二次清洗');
    tabOffsetCfg = uitab(tg,'Title','零点修正');
    tabGroupCfg = uitab(tg,'Title','组图配置');
    tabPlotCfg = uitab(tg,'Title','绘图参数');

    %% 运行页
    gl = uigridlayout(tabRun,[19 4]);
    bms.gui.GuiLayout.applyRunGridDefaults(gl);

    header = uipanel(gl,'BorderType','none'); header.Layout.Row = 1; header.Layout.Column = [1 4];
    hgl = uigridlayout(header,[2 6]); hgl.RowHeight = {'1x',28}; hgl.ColumnWidth = {120,90,260,'1x',110,150}; hgl.RowSpacing = 2; hgl.ColumnSpacing = 8;
    logoPath = fullfile(projRoot,'建科院标志PNG-01.png');
    uiimg = uiimage(hgl); uiimg.Layout.Row = [1 2]; uiimg.Layout.Column = 1; uiimg.ScaleMethod = 'fit';
    if exist(logoPath,'file'), uiimg.ImageSource = logoPath; end
    versionStr = 'v1.7.35';
    titleLbl = uilabel(hgl,'Text',['福建建科院健康监测大数据分析 ' versionStr],'FontSize',30,'FontWeight','bold','FontColor',primaryBlue,'HorizontalAlignment','center');
    titleLbl.Layout.Row = 1; titleLbl.Layout.Column = [2 6];
    profileLbl = uilabel(hgl, 'Text', '桥梁项目:', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    profileLbl.Layout.Row = 2; profileLbl.Layout.Column = 2;
    [profileNames, profileIds] = profileDropdownItems(profiles);
    profileDrop = uidropdown(hgl, 'Items', profileNames, 'ItemsData', profileIds);
    profileDrop.Layout.Row = 2; profileDrop.Layout.Column = 3;
    profileNote = uilabel(hgl, 'Text', '选择项目后自动带出默认配置、数据目录和模块。', 'FontColor', [0.35 0.40 0.50]);
    profileNote.Layout.Row = 2; profileNote.Layout.Column = 4;
    configCheckBtn = uibutton(hgl, 'Text', '检查配置', 'ButtonPushedFcn', @(btn,~) check_current_config());
    configCheckBtn.Layout.Row = 2; configCheckBtn.Layout.Column = 5;
    reportBuilderBtn = uibutton(hgl, 'Text', '打开报告生成器', 'ButtonPushedFcn', @(btn,~) open_report_builder());
    reportBuilderBtn.Layout.Row = 2; reportBuilderBtn.Layout.Column = 6;

    lblRoot = uilabel(gl,'Text','数据根目录:','FontWeight','bold','HorizontalAlignment','right'); lblRoot.Layout.Row=2; lblRoot.Layout.Column=1;
    rootEdit = uieditfield(gl,'text','Value',defaultDataRoot); rootEdit.Layout.Row=2; rootEdit.Layout.Column=[2 3];
    rootBtn  = uibutton(gl,'Text','浏览','ButtonPushedFcn',@(btn,~) onBrowseDir(rootEdit)); rootBtn.Layout.Row=2; rootBtn.Layout.Column=4;

    lblStart = uilabel(gl,'Text','开始日期:','HorizontalAlignment','right'); lblStart.Layout.Row=3; lblStart.Layout.Column=1;
    startPicker = uidatepicker(gl,'Value',datetime('today')-days(1),'DisplayFormat','yyyy-MM-dd'); startPicker.Layout.Row=3; startPicker.Layout.Column=2;
    lblEnd = uilabel(gl,'Text','结束日期:','HorizontalAlignment','right'); lblEnd.Layout.Row=3; lblEnd.Layout.Column=3;
    endPicker   = uidatepicker(gl,'Value',datetime('today'),'DisplayFormat','yyyy-MM-dd'); endPicker.Layout.Row=3; endPicker.Layout.Column=4;

    cbPrecheck = uicheckbox(gl,'Text','预检查压缩包数','Value',false); cbPrecheck.Layout.Row=4; cbPrecheck.Layout.Column=1;
    cbUnzip    = uicheckbox(gl,'Text','批量解压','Value',false);      cbUnzip.Layout.Row   =4; cbUnzip.Layout.Column   =2;
    cbRename   = uicheckbox(gl,'Text','批量重命名CSV','Value',false); cbRename.Layout.Row  =4; cbRename.Layout.Column  =3;
    cbRmHeader = uicheckbox(gl,'Text','去除表头','Value',false);      cbRmHeader.Layout.Row=4; cbRmHeader.Layout.Column=4;
    cbResample = uicheckbox(gl,'Text','重采样','Value',false);        cbResample.Layout.Row=5; cbResample.Layout.Column=1;
    cbLowfreqSync = uicheckbox(gl,'Text','基康低频同步','Value',false); cbLowfreqSync.Layout.Row=5; cbLowfreqSync.Layout.Column=2;

    cbSelectAll = uicheckbox(gl,'Text','全选/全不选','Value',false,'FontWeight','bold','ValueChangedFcn',@(cb,~) onSelectAll(cb));
    cbSelectAll.Layout.Row=5; cbSelectAll.Layout.Column=4;
    cbTemp   = uicheckbox(gl,'Text','温度','Value',false); cbTemp.Layout.Row=6; cbTemp.Layout.Column=1;
    cbHum    = uicheckbox(gl,'Text','湿度','Value',false); cbHum.Layout.Row=6; cbHum.Layout.Column=2;
    cbDef    = uicheckbox(gl,'Text','挠度','Value',true);  cbDef.Layout.Row=9; cbDef.Layout.Column=1;
    cbTilt   = uicheckbox(gl,'Text','倾角','Value',false); cbTilt.Layout.Row=9; cbTilt.Layout.Column=2;
    cbAccel  = uicheckbox(gl,'Text','加速度','Value',false); cbAccel.Layout.Row=7; cbAccel.Layout.Column=1;
    cbSpec   = uicheckbox(gl,'Text','加速度频谱','Value',false); cbSpec.Layout.Row=7; cbSpec.Layout.Column=2;
    cbCrack  = uicheckbox(gl,'Text','裂缝','Value',false);   cbCrack.Layout.Row=8; cbCrack.Layout.Column=4;
    cbStrain = uicheckbox(gl,'Text','应变','Value',false);   cbStrain.Layout.Row=8; cbStrain.Layout.Column=1;
    cbCableAccel = uicheckbox(gl,'Text','索力加速度','Value',false); cbCableAccel.Layout.Row=7; cbCableAccel.Layout.Column=3;
    cbCableSpec  = uicheckbox(gl,'Text','索力加速度频谱','Value',false); cbCableSpec.Layout.Row=7; cbCableSpec.Layout.Column=4;
    cbDynBox = uicheckbox(gl,'Text','动应变分析（高通+含箱线图）','Value',false); cbDynBox.Layout.Row=8; cbDynBox.Layout.Column=3;
    cbWind = uicheckbox(gl,'Text','风速风向','Value',false); cbWind.Layout.Row=6; cbWind.Layout.Column=4;
    cbEq = uicheckbox(gl,'Text','地震动','Value',false); cbEq.Layout.Row=9; cbEq.Layout.Column=3;
    cbWim = uicheckbox(gl,'Text','WIM','Value',false); cbWim.Layout.Row=9; cbWim.Layout.Column=4;
    cbBearing = uicheckbox(gl,'Text','支座位移','Value',false); cbBearing.Layout.Row=10; cbBearing.Layout.Column=1;
    cbRainfall = uicheckbox(gl,'Text','雨量','Value',false); cbRainfall.Layout.Row=6; cbRainfall.Layout.Column=3;
    cbGNSS = uicheckbox(gl,'Text','GNSS','Value',false); cbGNSS.Layout.Row=10; cbGNSS.Layout.Column=2;
    cbDynLowpass = uicheckbox(gl,'Text','动应变分析（低通+含箱线图）','Value',false); cbDynLowpass.Layout.Row=8; cbDynLowpass.Layout.Column=2;
    moduleControls = build_module_control_map();
    apply_module_registry_labels();
    profileDrop.ValueChangedFcn = @(dd,~) onProfileChanged(dd.Value);

    lblLog = uilabel(gl,'Text','日志目录:','HorizontalAlignment','right'); lblLog.Layout.Row=11; lblLog.Layout.Column=1;
    logEdit = uieditfield(gl,'text','Value',defaultLogDir); logEdit.Layout.Row=11; logEdit.Layout.Column=[2 3];
    logBtn  = uibutton(gl,'Text','浏览','ButtonPushedFcn',@(btn,~) onBrowseDir(logEdit)); logBtn.Layout.Row=11; logBtn.Layout.Column=4;

    lblCfg = uilabel(gl,'Text','配置文件(JSON):','HorizontalAlignment','right'); lblCfg.Layout.Row=12; lblCfg.Layout.Column=1;
    cfgEdit = uieditfield(gl,'text','Value',defaultCfgPath); cfgEdit.Layout.Row=12; cfgEdit.Layout.Column=[2 3];
    cfgBtn  = uibutton(gl,'Text','选择','ButtonPushedFcn',@(btn,~) onBrowseFile(cfgEdit,'*.json')); cfgBtn.Layout.Row=12; cfgBtn.Layout.Column=4;
    rootEdit.ValueChangedFcn = @(~,~) update_path_profile_note();
    logEdit.ValueChangedFcn = @(~,~) update_path_profile_note();
    cfgEdit.ValueChangedFcn = @(~,~) update_path_profile_note();
    pathProfileNote = uilabel(gl, 'Text', 'Path profile: 未刷新', 'FontColor', [0.35 0.40 0.50]);
    pathProfileNote.Layout.Row = 13; pathProfileNote.Layout.Column = [1 4];
    apply_profile_defaults(activeProfile, false);
    tg.SelectedTab = tabRun;

    presetSaveBtn = uibutton(gl,'Text','保存预设','Tooltip','Ctrl+S','ButtonPushedFcn',@(btn,~) onSavePreset()); presetSaveBtn.Layout.Row=14; presetSaveBtn.Layout.Column=1;
    presetLoadBtn = uibutton(gl,'Text','加载预设','Tooltip','Ctrl+L','ButtonPushedFcn',@(btn,~) onLoadPreset()); presetLoadBtn.Layout.Row=14; presetLoadBtn.Layout.Column=2;
    runBtn   = uibutton(gl,'Text','运行 (Ctrl+R)','FontWeight','bold','BackgroundColor',primaryBlue,'FontColor',[1 1 1], ...
        'Tooltip','启动异步运行','ButtonPushedFcn',@(btn,~) onRun());
    runBtn.Layout.Row=14; runBtn.Layout.Column=3;
    stopBtn  = uibutton(gl,'Text','停止 (Ctrl+.)','BackgroundColor',[0.8 0.2 0.2],'FontColor',[1 1 1], ...
        'Tooltip','请求停止当前异步运行','ButtonPushedFcn',@(btn,~) onStop());
    stopBtn.Layout.Row=14; stopBtn.Layout.Column=4;
    stopBtn.Enable = 'off';
    clearBtn = uibutton(gl,'Text','清空日志 (Ctrl+K)','Tooltip','清空运行日志');
    clearBtn.Layout.Row=15; clearBtn.Layout.Column=4;
    cbWarn = uicheckbox(gl,'Text','显示警告','Value',showWarningsDefault);
    cbWarn.Layout.Row=15; cbWarn.Layout.Column=3;
    refreshBtn = uibutton(gl,'Text','刷新状态','ButtonPushedFcn',@(btn,~) refresh_result_summary(true));
    refreshBtn.Layout.Row=15; refreshBtn.Layout.Column=1;
    cleanPreviewBtn = uibutton(gl,'Text','清理预览','ButtonPushedFcn',@(btn,~) preview_cleanup_generated());
    cleanPreviewBtn.Layout.Row=15; cleanPreviewBtn.Layout.Column=2;

    progressGrid = uigridlayout(gl, [1 2]);
    progressGrid.Layout.Row = 16; progressGrid.Layout.Column = [1 4];
    progressGrid.ColumnWidth = {130, '1x'};
    progressGrid.RowHeight = {'1x'};
    progressGrid.Padding = [0 0 0 0];
    progressGrid.ColumnSpacing = 8;
    progressLabel = uilabel(progressGrid, 'Text', '运行进度: 就绪', 'FontColor', primaryBlue);
    progressLabel.Layout.Row = 1; progressLabel.Layout.Column = 1;
    progressTrack = uipanel(progressGrid, 'BorderType', 'line', 'BackgroundColor', [0.92 0.92 0.92]);
    progressTrack.Layout.Row = 1; progressTrack.Layout.Column = 2;
    progressFill = uipanel(progressTrack, 'BorderType', 'none', 'BackgroundColor', [0.18 0.65 0.25], 'Position', [1 1 1 18]);

    statusLbl = uilabel(gl,'Text','就绪','FontColor',primaryBlue); statusLbl.Layout.Row=17; statusLbl.Layout.Column=[1 4];
    summaryTable = uitable(gl,'Data',cell(0,7),'ColumnName',{'模块','状态','耗时(s)','统计','图片','错误类型','消息'},'RowName',{});
    summaryTable.Layout.Row=18; summaryTable.Layout.Column=[1 4];
    logArea   = uitextarea(gl,'Editable','off','Value',{'准备就绪...'}); logArea.Layout.Row=19; logArea.Layout.Column=[1 4];
    statusPanel = bms.gui.GuiStatusPanel(statusLbl, summaryTable, logArea, primaryBlue);
    asyncRunState = [];
    asyncRunTimer = [];
    asyncLastStatus = '';
    asyncProgressValue = 0;
    f.CloseRequestFcn = @(~,~) onClose();
    f.KeyPressFcn = @(~,evt) onKeyPress(evt);
    clearBtn.ButtonPushedFcn = @(btn,~) statusPanel.clearLog();

    autoPreset = bms.gui.GuiPresetStore.defaultPath(projRoot);
    if exist(autoPreset,'file')
        try
            state = bms.gui.GuiPresetStore.load(autoPreset);
            apply_preset(state);
            if exist(cfgEdit.Value,'file')
                [cfgCache, cfgPath] = bms.gui.GuiConfigBinder.loadConfig(cfgEdit.Value, defaultCfgPath);
                cfgPath = cfgEdit.Value;
            end
            addLog(['已自动加载上次参数: ' autoPreset]);
        catch
        end
    end
    refresh_result_summary(false);

    %% 阈值配置页（拆分模块）
    th = build_threshold_tab(tabCfg, f, cfgCache, cfgPath, cfgEdit, @addLog, primaryBlue);
    at = build_auto_threshold_tab(tabAutoThreshold, f, cfgCache, cfgPath, cfgEdit, rootEdit, startPicker, endPicker, @addLog, primaryBlue);
    pf = build_post_filter_threshold_tab(tabPostCfg, f, cfgCache, cfgPath, cfgEdit, @addLog, primaryBlue);
    oc = build_offset_correction_tab(tabOffsetCfg, f, cfgCache, cfgPath, cfgEdit, @addLog, primaryBlue);
    gc = build_group_config_tab(tabGroupCfg, f, cfgCache, cfgPath, cfgEdit, @addLog, primaryBlue);
    pp = build_plot_settings_tab(tabPlotCfg, f, cfgCache, cfgPath, cfgEdit, @addLog, primaryBlue);
    tg.SelectionChangedFcn = @(src,evt) onTabChanged(evt);
    update_user_data();
    if nargout > 0
        varargout{1} = f;
    end

    %% 运行页回调
    function opts = parse_gui_options(varargin)
        opts = struct('Visible', 'on');
        if mod(numel(varargin), 2) ~= 0
            error('run_gui:InvalidArguments', 'GUI options must be name/value pairs.');
        end
        for ia = 1:2:numel(varargin)
            name = lower(char(string(varargin{ia})));
            value = varargin{ia + 1};
            switch name
                case 'visible'
                    value = lower(char(string(value)));
                    if ~any(strcmp(value, {'on', 'off'}))
                        error('run_gui:InvalidVisible', 'Visible must be ''on'' or ''off''.');
                    end
                    opts.Visible = value;
                otherwise
                    error('run_gui:UnknownOption', 'Unknown GUI option: %s', name);
            end
        end
    end

    function update_user_data()
        f.UserData = struct( ...
            'app', 'guanbing_main_gui', ...
            'version', versionStr, ...
            'project_root', projRoot, ...
            'active_profile_id', activeProfile.BridgeId, ...
            'profile_ids', {profileIds}, ...
            'controls', struct( ...
                'profileDrop', profileDrop, ...
                'rootEdit', rootEdit, ...
                'startPicker', startPicker, ...
                'endPicker', endPicker, ...
                'cfgEdit', cfgEdit, ...
                'logEdit', logEdit, ...
                'runBtn', runBtn, ...
                'stopBtn', stopBtn, ...
                'clearBtn', clearBtn, ...
                'refreshBtn', refreshBtn, ...
                'configCheckBtn', configCheckBtn, ...
                'lowfreqSync', cbLowfreqSync, ...
                'dynamicRawSamplingMode', pp.dynamicRawSamplingModeDrop, ...
                'pathProfileNote', pathProfileNote, ...
                'progressLabel', progressLabel, ...
                'progressTrack', progressTrack, ...
                'progressFill', progressFill, ...
                'statusLbl', statusLbl, ...
                'summaryTable', summaryTable, ...
                'logArea', logArea));
    end

    function controls = build_module_control_map()
        controls = struct();
        controls.precheck_zip_count = cbPrecheck;
        controls.doUnzip = cbUnzip;
        controls.doRenameCsv = cbRename;
        controls.doRemoveHeader = cbRmHeader;
        controls.doResample = cbResample;
        controls.doLowfreqSync = cbLowfreqSync;
        controls.doTemp = cbTemp;
        controls.doHumidity = cbHum;
        controls.doRainfall = cbRainfall;
        controls.doGNSS = cbGNSS;
        controls.doWind = cbWind;
        controls.doEq = cbEq;
        controls.doWIM = cbWim;
        controls.doDeflect = cbDef;
        controls.doBearingDisplacement = cbBearing;
        controls.doTilt = cbTilt;
        controls.doAccel = cbAccel;
        controls.doAccelSpectrum = cbSpec;
        controls.doCableAccel = cbCableAccel;
        controls.doCableAccelSpectrum = cbCableSpec;
        controls.doCrack = cbCrack;
        controls.doStrain = cbStrain;
        controls.doDynStrainBoxplot = cbDynBox;
        controls.doDynStrainLowpassBoxplot = cbDynLowpass;
    end

    function apply_module_registry_labels()
        bms.gui.GuiRunController.applyModuleLabels(moduleControls);
    end

    function handles = module_control_values()
        handles = bms.gui.GuiRunController.controlValues(moduleControls);
    end

    function [names, ids] = profileDropdownItems(profileList)
        if isempty(profileList)
            profileList = bms.profile.BridgeProfileRegistry.catalog(projRoot);
        end
        names = cell(1, numel(profileList));
        ids = cell(1, numel(profileList));
        for ip = 1:numel(profileList)
            names{ip} = profileList(ip).displayName();
            ids{ip} = profileList(ip).BridgeId;
        end
    end

    function onProfileChanged(profileId)
        profile = bms.profile.BridgeProfileRegistry.fromId(profileId, projRoot);
        if isempty(profile.BridgeId)
            return;
        end
        activeProfile = profile;
        apply_profile_defaults(profile, true);
        update_user_data();
        refresh_result_summary(false);
    end

    function apply_profile_defaults(profile, logChange)
        if nargin < 2, logChange = true; end
        if isempty(profile.BridgeId)
            return;
        end
        if ~isempty(profile.DefaultConfig)
            cfgEdit.Value = profile.DefaultConfig;
            defaultCfgPath = profile.DefaultConfig;
        end
        if ~isempty(profile.DefaultDataRoot)
            rootEdit.Value = profile.DefaultDataRoot;
            logEdit.Value = bms.core.PathResolver.logDir(profile.DefaultDataRoot);
        end
        if ~isempty(profile.DefaultStartDate)
            startPicker.Value = datetime(profile.DefaultStartDate, 'InputFormat', 'yyyy-MM-dd');
        end
        if ~isempty(profile.DefaultEndDate)
            endPicker.Value = datetime(profile.DefaultEndDate, 'InputFormat', 'yyyy-MM-dd');
        end
        set_profile_module_defaults(profile);
        profileNote.Text = bms.gui.GuiRunController.profileSummary(profile);
        update_path_profile_note();
        if logChange
            addLog(['已切换桥梁项目: ' profile.displayName()]);
        end
    end

    function set_profile_module_defaults(profile)
        targets = module_control_values();
        for ih = 1:numel(targets)
            targets(ih).Value = false;
        end
        hints = profile.EnabledModuleHints;
        if isempty(hints)
            return;
        end
        specs = bms.module.ModuleRegistry.catalog();
        for ispec = 1:numel(specs)
            if isempty(specs(ispec).GuiField) || ~isfield(moduleControls, specs(ispec).GuiField)
                continue;
            end
            if any(strcmp(hints, specs(ispec).Key))
                h = moduleControls.(specs(ispec).GuiField);
                if bms.gui.GuiRunController.isLiveControl(h)
                    h.Value = true;
                end
            end
        end
    end

    function state = build_gui_state()
        root = rootEdit.Value;
        startDate = datestr(startPicker.Value,'yyyy-mm-dd');
        endDate = datestr(endPicker.Value,'yyyy-mm-dd');
        logDir = fullfile(root, 'run_logs');
        preproc = bms.gui.GuiRunController.presetFromControls(moduleControls, 'preprocess');
        modules = bms.gui.GuiRunController.presetFromControls(moduleControls, 'analysis');
        state = bms.gui.GuiState.fromValues(root, startDate, endDate, cfgEdit.Value, logDir, logical(cbWarn.Value), preproc, modules);
    end

    function onBrowseDir(edit)
        p = uigetdir(edit.Value);
        if isequal(p,0), return; end

        if isstring(p), p = char(p); end
        if ischar(p), edit.Value = p; end

        if isequal(edit, rootEdit)
            logEdit.Value = fullfile(rootEdit.Value, 'run_logs');
            refresh_result_summary(false);
            sync_profile_selector_from_current();
            update_path_profile_note();
        end

        % 强制把主界面拉回前台
        figure(f);
        drawnow;
    end
    function onBrowseFile(edit, filter)
        [fname,fpath] = uigetfile(filter,'选择文件',edit.Value);
        if isequal(fname,0), return; end
        edit.Value = fullfile(fpath,fname);
        if isequal(edit, cfgEdit)
            sync_profile_selector_from_current();
            update_path_profile_note();
        end

        % 强制把主界面拉回前台
        figure(f);
        drawnow;
    end

    function open_report_builder()
        exePath = fullfile(projRoot, 'reporting', 'dist', 'BridgeReportBuilder', 'BridgeReportBuilder.exe');
        pyPath = fullfile(projRoot, 'reporting', '.venv', 'Scripts', 'python.exe');
        scriptPath = fullfile(projRoot, 'reporting', 'report_gui.py');
        try
            if exist(exePath, 'file') == 2
                cmd = sprintf('start "" "%s"', exePath);
                [status, msg] = system(cmd);
                if status ~= 0
                    error('%s', msg);
                end
                addLog(['已打开报告生成器: ' exePath]);
            elseif exist(pyPath, 'file') == 2 && exist(scriptPath, 'file') == 2
                cmd = sprintf('start "" "%s" "%s"', pyPath, scriptPath);
                [status, msg] = system(cmd);
                if status ~= 0
                    error('%s', msg);
                end
                addLog(['已用 Python 打开报告生成器: ' scriptPath]);
            else
                uialert(f, sprintf('未找到报告生成器 exe 或 Python 入口:\n%s\n%s', exePath, scriptPath), '打开失败', 'Icon', 'warning');
            end
        catch ME
            uialert(f, ME.message, '打开报告生成器失败', 'Icon', 'error');
        end
    end

    function check_current_config()
        try
            [cfg, loadedCfgPath] = bms.gui.GuiConfigBinder.loadConfig(cfgEdit.Value, defaultCfgPath);
            if ~strcmp(loadedCfgPath, cfgEdit.Value)
                cfgEdit.Value = loadedCfgPath;
            end
            cfg = apply_live_cfg(cfg);
            result = bms.config.ConfigLinter.lint(cfg);
            lines = bms.config.ConfigLinter.toLogLines(result, 12);
            for il = 1:numel(lines)
                addLog(lines{il});
            end
            icon = 'info';
            if strcmp(result.status, 'failed')
                icon = 'error';
            elseif strcmp(result.status, 'warning')
                icon = 'warning';
            end
            uialert(f, strjoin(lines, newline), '配置健康检查', 'Icon', icon);
        catch ME
            addLog(['配置健康检查失败: ' ME.message]);
            uialert(f, ME.message, '配置健康检查失败', 'Icon', 'error');
        end
    end

    function onRun()
        global RUN_STOP_FLAG;
        runBtn.Enable='off'; stopBtn.Enable='on'; RUN_STOP_FLAG=false;
        stop_async_timer();
        asyncRunState = [];
        asyncLastStatus = '';
        set_run_progress(0.02, '运行进度: 启动中', 'running');
        statusPanel.setRunning('启动异步运行...'); addLog('开始异步运行'); drawnow;
        try
            [cfg, loadedCfgPath] = bms.gui.GuiConfigBinder.loadConfig(cfgEdit.Value, defaultCfgPath);
            if ~strcmp(loadedCfgPath, cfgEdit.Value)
                addLog('指定配置文件不存在，使用默认配置');
                cfgEdit.Value = loadedCfgPath;
            end
            cfg = apply_live_cfg(cfg);
            showWarnings = logical(cbWarn.Value);
            if ~isfield(cfg,'gui') || ~isstruct(cfg.gui), cfg.gui = struct(); end
            cfg.gui.show_warnings = showWarnings;
            logEdit.Value = fullfile(rootEdit.Value, 'run_logs');
            state = build_gui_state();
            statusPanel.setPendingModules(state.toOptions());
            root = state.Root; start_date = state.StartDate; end_date = state.EndDate;
            logEdit.Value = state.LogDir;
            if exist(root, 'dir') ~= 7
                error('BMS:Gui:DataRootMissing', '数据根目录不存在: %s', root);
            end
            if exist(logEdit.Value,'dir')==0, mkdir(logEdit.Value); end
            [runRequest, preflight, preflightLines] = bms.gui.GuiRunController.prepareRun(state, cfg);
            if isfield(cfg,'plot_common') && isstruct(cfg.plot_common)
                if isfield(cfg.plot_common,'gap_mode')
                    addLog(sprintf('plot_common.gap_mode=%s', char(string(cfg.plot_common.gap_mode))));
                end
                if isfield(cfg.plot_common,'gap_break_factor')
                    addLog(sprintf('plot_common.gap_break_factor=%.3g', double(cfg.plot_common.gap_break_factor)));
                end
                if isfield(cfg.plot_common,'dynamic_raw_sampling_mode')
                    addLog(sprintf('plot_common.dynamic_raw_sampling_mode=%s', ...
                        char(string(cfg.plot_common.dynamic_raw_sampling_mode))));
                end
                if isfield(cfg.plot_common,'append_timestamp')
                    addLog(sprintf('plot_common.append_timestamp=%d', logical(cfg.plot_common.append_timestamp)));
                end
            end
            for ipf = 1:numel(preflightLines)
                addLog(preflightLines{ipf});
            end
            if strcmp(preflight.status, 'failed')
                error('BMS:RunPreflight:Failed', '运行前预检失败，请先处理数据目录、日期范围或配置问题。');
            end
            save_last_preset(state);
            addLog(sprintf('root=%s, %s -> %s', root, start_date, end_date));
            asyncRunState = bms.app.AsyncRunService.start(runRequest);
            asyncLastStatus = 'launched';
            set_run_progress(0.08, '运行进度: 子进程已启动', 'running');
            addLog(sprintf('异步执行器: %s', executor_label(asyncRunState)));
            addLog(sprintf('异步子进程已启动：pid=%s', format_pid(asyncRunState)));
            runnerPath = executor_path(asyncRunState);
            if ~isempty(runnerPath)
                addLog(['执行器路径: ' runnerPath]);
            end
            addLog(['异步请求文件: ' asyncRunState.request_path]);
            addLog(['异步输出日志: ' asyncRunState.stdout_log]);
            statusPanel.setRunning('运行中（异步子进程）...');
            start_async_timer();
        catch ME
            addLog(['运行失败: ' ME.message]); statusPanel.setFailed('失败');
            set_run_progress(1.0, '运行进度: 失败', 'failed');
            show_wim_error_help(ME);
            runBtn.Enable='on'; stopBtn.Enable='off';
        end
    end
    function log_result_summary(resultRoot)
        statusPanel.refreshFromRoot(resultRoot, true);
    end

    function refresh_result_summary(logDetails)
        if nargin < 1, logDetails = false; end
        statusPanel.refreshFromRoot(rootEdit.Value, logDetails);
    end

    function preview_cleanup_generated()
        try
            plan = bms.data.ArtifactCleaner.plan(rootEdit.Value, 'images', true);
            result = bms.data.ArtifactCleaner.clean(rootEdit.Value, 'images', true);
            n = numel(result.deleted);
            addLog(sprintf('Cleanup preview: images/figures %d files, %.2f MB; dry-run only.', n, double(plan.bytes) / 1024 / 1024));
            maxShow = min(n, 8);
            for ip = 1:maxShow
                addLog(['  ' result.deleted{ip}]);
            end
            if n > maxShow
                addLog(sprintf('  ... 还有 %d 个', n - maxShow));
            end
        catch MEclean
            addLog(['清理预览失败: ' MEclean.message]);
        end
    end

    function onStop()
        if isstruct(asyncRunState) && isfield(asyncRunState, 'stop_file') && ~isempty(asyncRunState.stop_file)
            bms.app.AsyncRunService.requestStop(asyncRunState, false);
            addLog(['已写入异步停止请求: ' asyncRunState.stop_file]);
            statusPanel.setRunning('停止请求已发送，等待当前步骤结束...');
            set_run_progress(asyncProgressValue, '运行进度: 正在停止', 'warning');
            return;
        end
        global RUN_STOP_FLAG; RUN_STOP_FLAG=true; addLog('收到停止请求，将跳过后续步骤');
        set_run_progress(asyncProgressValue, '运行进度: 正在停止', 'warning');
    end

    function onKeyPress(evt)
        try
            mods = lower(string(evt.Modifier));
            if ~any(mods == "control")
                return;
            end
            key = lower(char(string(evt.Key)));
            switch key
                case {'r', 'return'}
                    if strcmpi(runBtn.Enable, 'on')
                        onRun();
                    end
                case 'period'
                    onStop();
                case 'k'
                    statusPanel.clearLog();
                case 's'
                    onSavePreset();
                case 'l'
                    onLoadPreset();
                case 'g'
                    check_current_config();
                case 'b'
                    open_report_builder();
                otherwise
                    return;
            end
            update_user_data();
        catch MEkey
            try
                addLog(['快捷键处理失败: ' MEkey.message]);
            catch
            end
        end
    end

    function start_async_timer()
        stop_async_timer();
        asyncRunTimer = timer('ExecutionMode', 'fixedSpacing', ...
            'Period', 2.0, ...
            'TimerFcn', @(~,~) poll_async_run(), ...
            'ErrorFcn', @(~,evt) on_async_timer_error(evt));
        start(asyncRunTimer);
    end

    function stop_async_timer()
        try
            if ~isempty(asyncRunTimer) && isvalid(asyncRunTimer)
                stop(asyncRunTimer);
                delete(asyncRunTimer);
            end
        catch
        end
        asyncRunTimer = [];
    end

    function poll_async_run()
        if isempty(asyncRunState) || ~isstruct(asyncRunState)
            return;
        end
        st = bms.app.AsyncRunService.readStatus(asyncRunState);
        statusText = async_status_text(st);
        if isempty(statusText)
            statusText = 'unknown';
        end
        if ~strcmp(statusText, asyncLastStatus)
            addLog(['异步运行状态: ' statusText]);
            asyncLastStatus = statusText;
        end
            if isfield(st, 'is_terminal') && st.is_terminal
                stop_async_timer();
                if strcmpi(statusText, 'completed')
                    log_result_summary(rootEdit.Value);
                    addLog('异步运行完成');
                    statusPanel.setReady('异步运行完成');
                    set_run_progress(1.0, '运行进度: 完成', 'running');
                elseif strcmpi(statusText, 'stopped')
                    log_result_summary(rootEdit.Value);
                    addLog('异步运行已停止');
                    statusPanel.setReady('异步运行已停止');
                    set_run_progress(async_progress_value(st, 1.0), async_progress_label(st, '已停止'), 'warning');
                else
                    log_result_summary(rootEdit.Value);
                    msg = '异步运行失败';
                    if isfield(st, 'message') && ~isempty(st.message)
                        msg = [msg ': ' char(string(st.message))];
                end
                addLog(msg);
                statusPanel.setFailed('异步运行失败');
                set_run_progress(1.0, '运行进度: 失败', 'failed');
            end
            runBtn.Enable='on';
            stopBtn.Enable='off';
            return;
        end
        asyncProgressValue = async_progress_value(st, min(0.95, max(0.10, asyncProgressValue + 0.005)));
        progressMode = 'running';
        if strcmpi(statusText, 'stopping')
            progressMode = 'warning';
        end
        set_run_progress(asyncProgressValue, async_progress_label(st, statusText), progressMode);
        statusPanel.setRunning(['运行中（异步）：' async_module_text(st, statusText)]);
    end

    function set_run_progress(value, labelText, mode)
        if nargin < 3 || isempty(mode), mode = 'running'; end
        asyncProgressValue = max(0, min(1, double(value)));
        if nargin >= 2 && ~isempty(labelText)
            progressLabel.Text = char(string(labelText));
        end
        switch lower(char(string(mode)))
            case 'failed'
                progressFill.BackgroundColor = [0.75 0.18 0.18];
            case 'warning'
                progressFill.BackgroundColor = [0.86 0.55 0.14];
            otherwise
                progressFill.BackgroundColor = [0.18 0.65 0.25];
        end
        update_progress_bar();
    end

    function update_progress_bar()
        try
            pos = progressTrack.Position;
            width = max(1, (double(pos(3)) - 2) * asyncProgressValue);
            height = max(1, double(pos(4)) - 2);
            progressFill.Position = [1 1 width height];
        catch
        end
    end

    function on_async_timer_error(evt)
        msg = '未知错误';
        try
            if isprop(evt, 'Data') && isfield(evt.Data, 'message')
                msg = evt.Data.message;
            end
        catch
        end
        addLog(['异步状态轮询失败: ' char(string(msg))]);
    end

    function txt = async_status_text(st)
        txt = '';
        if isstruct(st) && isfield(st, 'status') && ~isempty(st.status)
            txt = char(string(st.status));
        end
    end

    function value = async_progress_value(st, fallback)
        value = fallback;
        try
            if isstruct(st) && isfield(st, 'progress_fraction') && ~isempty(st.progress_fraction)
                value = max(0, min(1, double(st.progress_fraction)));
            elseif isstruct(st) && isfield(st, 'completed_modules') && isfield(st, 'module_total') && ...
                    double(st.module_total) > 0
                value = max(0, min(1, double(st.completed_modules) / double(st.module_total)));
            end
        catch
            value = fallback;
        end
    end

    function txt = async_progress_label(st, statusText)
        txt = ['运行进度: ' async_module_text(st, statusText)];
        try
            etaText = async_eta_text(st);
            if ~isempty(etaText)
                txt = [txt '，' etaText];
            end
        catch
        end
    end

    function txt = async_module_text(st, statusText)
        txt = char(string(statusText));
        try
            if isstruct(st) && isfield(st, 'module_index') && isfield(st, 'module_total') && ...
                    ~isempty(st.module_index) && ~isempty(st.module_total)
                label = '';
                if isfield(st, 'current_module_label') && ~isempty(st.current_module_label)
                    label = char(string(st.current_module_label));
                elseif isfield(st, 'current_module_key') && ~isempty(st.current_module_key)
                    label = char(string(st.current_module_key));
                end
                if isempty(label)
                    label = char(string(statusText));
                end
                txt = sprintf('%d/%d %s', round(double(st.module_index)), round(double(st.module_total)), label);
                if isfield(st, 'current_module_status') && ~isempty(st.current_module_status)
                    stepStatus = char(string(st.current_module_status));
                    if ~strcmpi(stepStatus, 'running')
                        txt = [txt ' (' stepStatus ')'];
                    end
                end
            end
        catch
            txt = char(string(statusText));
        end
    end

    function txt = async_eta_text(st)
        txt = '';
        try
            if isstruct(st) && isfield(st, 'estimated_remaining_sec') && ~isempty(st.estimated_remaining_sec)
                sec = double(st.estimated_remaining_sec);
                if isfinite(sec) && sec >= 0
                    txt = ['预计剩余 ' format_duration(sec)];
                end
            end
        catch
            txt = '';
        end
    end

    function txt = format_duration(sec)
        sec = max(0, round(double(sec)));
        hh = floor(sec / 3600);
        mm = floor(mod(sec, 3600) / 60);
        ss = mod(sec, 60);
        if hh > 0
            txt = sprintf('%d:%02d:%02d', hh, mm, ss);
        else
            txt = sprintf('%02d:%02d', mm, ss);
        end
    end

    function txt = format_pid(state)
        txt = 'unknown';
        if isstruct(state) && isfield(state, 'pid') && isnumeric(state.pid) && isfinite(state.pid)
            txt = sprintf('%d', round(state.pid));
        end
    end

    function txt = executor_label(state)
        txt = 'unknown';
        if isstruct(state) && isfield(state, 'executor_type') && ~isempty(state.executor_type)
            txt = char(string(state.executor_type));
        end
    end

    function txt = executor_path(state)
        txt = '';
        if ~isstruct(state) || ~isfield(state, 'executor_type')
            return;
        end
        type = lower(char(string(state.executor_type)));
        if strcmp(type, 'compiled_runner') && isfield(state, 'runner_executable')
            txt = char(string(state.runner_executable));
        elseif strcmp(type, 'matlab_batch') && isfield(state, 'matlab_executable')
            txt = char(string(state.matlab_executable));
        end
    end

    function onClose()
        stop_async_timer();
        delete(f);
    end
    function onSavePreset()
        [fname,fpath] = uiputfile('*.json','保存预设','preset.json'); if isequal(fname,0), return; end
        outPath = fullfile(fpath,fname);
        try
            bms.gui.GuiPresetStore.save(outPath, build_gui_state());
            addLog(['预设已保存: ' outPath]);
        catch MEpreset
            addLog(['预设保存失败: ' MEpreset.message]);
        end
    end
    function onLoadPreset()
        [fname,fpath] = uigetfile('*.json','加载预设'); if isequal(fname,0), return; end
        presetPath = fullfile(fpath,fname);
        state = bms.gui.GuiPresetStore.load(presetPath);
        apply_preset(state);
        addLog(['预设已加载: ' presetPath]);
        update_path_profile_note();
        refresh_result_summary(false);
    end
    function onSelectAll(cb)
        targets = module_control_values();
        for i=1:numel(targets), targets(i).Value = cb.Value; end
    end
    function apply_preset(preset)
        if isa(preset, 'bms.gui.GuiState')
            preset = preset.toPreset();
        else
            preset = bms.gui.GuiState.fromPreset(preset).toPreset();
        end
        if isfield(preset,'root'), rootEdit.Value = preset.root; end
        if isfield(preset,'start_date'), startPicker.Value = datetime(preset.start_date,'InputFormat','yyyy-MM-dd'); end
        if isfield(preset,'end_date'),   endPicker.Value   = datetime(preset.end_date,'InputFormat','yyyy-MM-dd'); end
        if isfield(preset,'cfg'),        cfgEdit.Value = preset.cfg; end
        if isfield(preset,'logdir'),     logEdit.Value = preset.logdir; end
        if isfield(preset,'show_warnings'), cbWarn.Value = logical(preset.show_warnings); end
        if isfield(preset,'preproc')
            p = preset.preproc;
            if isfield(p,'precheck'), cbPrecheck.Value = p.precheck; end
            if isfield(p,'unzip'),    cbUnzip.Value    = p.unzip; end
            if isfield(p,'rename'),   cbRename.Value   = p.rename; end
            if isfield(p,'rmheader'), cbRmHeader.Value = p.rmheader; end
            if isfield(p,'resample'), cbResample.Value = p.resample; end
        end
        if isfield(preset,'modules')
            m = preset.modules;
            if isfield(m,'temp'),     cbTemp.Value   = m.temp; end
            if isfield(m,'humidity'), cbHum.Value    = m.humidity; end
            if isfield(m,'rainfall'), cbRainfall.Value = m.rainfall; end
            if isfield(m,'gnss'),     cbGNSS.Value   = m.gnss; end
            if isfield(m,'wind'),     cbWind.Value  = m.wind; end
            if isfield(m,'eq'),       cbEq.Value    = m.eq; end
            if isfield(m,'wim'),      cbWim.Value   = m.wim; end
            if isfield(m,'deflect'),  cbDef.Value    = m.deflect; end
            if isfield(m,'bearing_displacement'), cbBearing.Value = m.bearing_displacement; end
            if isfield(m,'tilt'),     cbTilt.Value   = m.tilt; end
            if isfield(m,'accel'),    cbAccel.Value  = m.accel; end
            if isfield(m,'spec'),     cbSpec.Value   = m.spec; end
            if isfield(m,'cable_accel'), cbCableAccel.Value = m.cable_accel; end
            if isfield(m,'cable_spec'),  cbCableSpec.Value  = m.cable_spec; end
            if isfield(m,'crack'),    cbCrack.Value  = m.crack; end
            if isfield(m,'strain'),   cbStrain.Value = m.strain; end
            if isfield(m,'dynbox'),   cbDynBox.Value = m.dynbox; end
            if isfield(m,'dynlowpass'), cbDynLowpass.Value = m.dynlowpass; end
            apply_module_values_from_preset(m);
        end
        sync_profile_selector_from_current();
        update_path_profile_note();
    end

    function sync_profile_selector_from_current()
        try
            inferred = bms.profile.BridgeProfileRegistry.infer(struct('source', cfgEdit.Value), rootEdit.Value);
            if ~isempty(inferred.BridgeId) && any(strcmp(profileIds, inferred.BridgeId))
                profileDrop.Value = inferred.BridgeId;
                activeProfile = inferred;
                profileNote.Text = bms.gui.GuiRunController.profileSummary(inferred);
            end
        catch
        end
    end
    function update_path_profile_note()
        try
            host = char(string(getenv('COMPUTERNAME')));
            if isempty(host), host = 'unknown'; end
            pathProfile = bms.profile.PathProfileResolver.active(projRoot);
            if isstruct(pathProfile) && isfield(pathProfile, 'profile_id') && ~isempty(pathProfile.profile_id)
                matchText = '';
                if isfield(pathProfile, 'match_type') && ~isempty(pathProfile.match_type)
                    matchText = char(string(pathProfile.match_type));
                end
                if isfield(pathProfile, 'match_reason') && ~isempty(pathProfile.match_reason)
                    matchText = strtrim([matchText ' ' char(string(pathProfile.match_reason))]);
                end
                pathProfileNote.Text = sprintf('Path profile: host %s -> %s (%s); data=%s; log=%s', ...
                    host, char(string(pathProfile.profile_id)), matchText, rootEdit.Value, logEdit.Value);
            else
                pathProfileNote.Text = sprintf('Path profile: host %s has no active path profile; using bridge default/preset/manual path; data=%s', ...
                    host, rootEdit.Value);
            end
            if isprop(pathProfileNote, 'Tooltip')
                pathProfileNote.Tooltip = pathProfileNote.Text;
            end
        catch MEpath
            pathProfileNote.Text = ['Path profile: 刷新失败 - ' MEpath.message];
        end
    end
    function apply_module_values_from_preset(m)
        bms.gui.GuiRunController.applyPresetModules(moduleControls, m);
    end
    function save_last_preset(preset)
        try
            bms.gui.GuiPresetStore.saveLast(projRoot, preset);
        catch
        end
    end
    function cfg = apply_live_cfg(cfg)
        tabStates = bms.gui.GuiRunController.liveConfigTabStates(th, pf, oc, gc, pp);
        cfg = bms.gui.GuiConfigBinder.applyLiveTabs(cfg, tabStates);
    end
    function restore_warnings(warnState, btState)
        try
            warning(warnState);
            if isstruct(btState) && isfield(btState,'state')
                warning(btState.state,'backtrace');
            end
        catch
        end
    end

    function addLog(msg)
        statusPanel.addLog(msg);
    end
    function onTabChanged(evt)
        try
            if isequal(evt.NewValue, tabCfg) && isstruct(th) && isfield(th,'onShow')
                th.onShow();
            elseif isequal(evt.NewValue, tabAutoThreshold) && isstruct(at) && isfield(at,'onShow')
                at.onShow();
            elseif isequal(evt.NewValue, tabPostCfg) && isstruct(pf) && isfield(pf,'onShow')
                pf.onShow();
            elseif isequal(evt.NewValue, tabOffsetCfg) && isstruct(oc) && isfield(oc,'onShow')
                oc.onShow();
            elseif isequal(evt.NewValue, tabGroupCfg) && isstruct(gc) && isfield(gc,'onShow')
                gc.onShow();
            elseif isequal(evt.NewValue, tabPlotCfg) && isstruct(pp) && isfield(pp,'onShow')
                pp.onShow();
            end
        catch
        end
    end

    function show_wim_error_help(ME)
        try
            [titleText, bodyText, logLines] = explain_wim_error(ME);
            if isempty(titleText)
                return;
            end
            for i = 1:numel(logLines)
                addLog(logLines{i});
            end
            uialert(f, bodyText, titleText, 'Icon', 'warning');
        catch
        end
    end

    function [titleText, bodyText, logLines] = explain_wim_error(ME)
        titleText = '';
        bodyText = '';
        logLines = {};
        switch string(ME.identifier)
            case "WIM:SQL:Instance"
                titleText = 'WIM SQL 实例问题';
                bodyText = sprintf(['无法连接到 SQL Server 实例。', newline, newline, ...
                    '请检查：', newline, ...
                    '1. wim_db.server 是否正确', newline, ...
                    '2. SQL Server 服务是否已启动', newline, ...
                    '3. 可先运行 scripts/setup_wim_sql.ps1 自动初始化', newline, newline, ...
                    '详细错误：', newline, '%s'], ME.message);
                logLines = { ...
                    'WIM 提示：SQL Server 实例不可达。', ...
                    '检查 wim_db.server / wim_db.service_name，确认 SQL Server 服务已启动。', ...
                    '如未初始化，可先运行 scripts/setup_wim_sql.ps1。'};
            case "WIM:SQL:Permission"
                titleText = 'WIM SQL 权限问题';
                bodyText = sprintf(['当前 Windows 用户没有足够的 SQL Server 权限。', newline, newline, ...
                    '请检查：', newline, ...
                    '1. 当前用户是否可登录 SQL Server', newline, ...
                    '2. 是否有目标数据库访问权限', newline, ...
                    '3. 是否具备 bulk import / db_owner 权限', newline, newline, ...
                    '详细错误：', newline, '%s'], ME.message);
                logLines = { ...
                    'WIM 提示：当前 Windows 用户的 SQL 权限不足。', ...
                    '检查登录权限、数据库权限以及 bulk import 权限。', ...
                    '可重新运行 scripts/setup_wim_sql.ps1 为当前用户授权。'};
            case "WIM:SQL:DatabaseMissing"
                titleText = 'WIM 数据库不存在';
                bodyText = sprintf(['目标数据库不存在或无法打开。', newline, newline, ...
                    '请检查：', newline, ...
                    '1. wim_db.database 是否正确', newline, ...
                    '2. HighSpeed_PROC 是否已创建', newline, ...
                    '3. 可先运行 scripts/setup_wim_sql.ps1 自动建库', newline, newline, ...
                    '详细错误：', newline, '%s'], ME.message);
                logLines = { ...
                    'WIM 提示：目标数据库不存在或无法打开。', ...
                    '检查 wim_db.database，确认 HighSpeed_PROC 已创建。', ...
                    '如未建库，可运行 scripts/setup_wim_sql.ps1。'};
            case "WIM:Input:MissingFmt"
                titleText = 'WIM 输入缺少 fmt';
                bodyText = sprintf(['未找到本月对应的 fmt 文件。', newline, newline, ...
                    '请检查：', newline, ...
                    '1. 洪塘当前默认目录为“数据根目录\\WIM”', newline, ...
                    '2. wim.input.zhichen.dir 是否正确', newline, ...
                    '3. 目标目录下是否存在 HS_Data_YYYYMM.fmt', newline, newline, ...
                    '详细错误：', newline, '%s'], ME.message);
                logLines = { ...
                    'WIM 提示：缺少 fmt 文件。', ...
                    '洪塘默认从“数据根目录\\WIM”读取原始称重文件。', ...
                    '检查 wim.input.zhichen.dir 以及 HS_Data_YYYYMM.fmt 是否存在。'};
            case "WIM:Input:MissingBcp"
                titleText = 'WIM 输入缺少 bcp';
                bodyText = sprintf(['未找到本月对应的 bcp 文件。', newline, newline, ...
                    '请检查：', newline, ...
                    '1. 洪塘当前默认目录为“数据根目录\\WIM”', newline, ...
                    '2. wim.input.zhichen.dir 是否正确', newline, ...
                    '3. 目标目录下是否存在 HS_Data_YYYYMM.bcp', newline, newline, ...
                    '详细错误：', newline, '%s'], ME.message);
                logLines = { ...
                    'WIM 提示：缺少 bcp 文件。', ...
                    '洪塘默认从“数据根目录\\WIM”读取原始称重文件。', ...
                    '检查 wim.input.zhichen.dir 以及 HS_Data_YYYYMM.bcp 是否存在。'};
            case "WIM:SQL:CommandFailed"
                titleText = 'WIM SQL 执行失败';
                bodyText = sprintf(['WIM SQL 命令执行失败。', newline, newline, ...
                    '请查看错误详情，并优先检查实例、权限、数据库名和输入文件。', newline, newline, ...
                    '详细错误：', newline, '%s'], ME.message);
                logLines = {'WIM 提示：SQL 命令执行失败，请查看日志中的详细错误。'};
        end
    end
end
