function run_gui()
% run_gui  GUI 入口，便于配置并运行 run_all；含阈值配置页。
% 用法：addpath(fullfile(pwd,'ui')); run_gui

    import matlab.ui.control.*
    import matlab.ui.container.*
    if ~exist('uilabel','file')
        error('uilabel 不可用，请检查 uicomponents 路径是否已加入 (matlabroot/toolbox/matlab/uicomponents/uicomponents)');
    end

    % 项目根目录
    projRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(projRoot, fullfile(projRoot,'config'), fullfile(projRoot,'pipeline'), ...
        fullfile(projRoot,'analysis'), fullfile(projRoot,'scripts'));

    defaultCfgPath = fullfile(projRoot,'config','default_config.json');
    defaultLogDir  = fullfile(projRoot,'outputs','run_logs');
    if ~exist(defaultLogDir,'dir'), mkdir(defaultLogDir); end

    primaryBlue = [0 94 172]/255;
    cfgCache = load_config(defaultCfgPath);
    cfgPath = defaultCfgPath;

    f = uifigure('Name','福建建科院健康监测大数据分析','Position',[80 80 1040 760],'Color',[0.97 0.98 1]);
    mainGrid = uigridlayout(f,[1 1]); mainGrid.RowHeight = {'1x'}; mainGrid.ColumnWidth = {'1x'}; mainGrid.Padding = [0 0 0 0];
    tg = uitabgroup(mainGrid); tg.Layout.Row = 1; tg.Layout.Column = 1;
    tabRun = uitab(tg,'Title','运行');
    tabCfg = uitab(tg,'Title','阈值配置');

    %% 运行页
    gl = uigridlayout(tabRun,[14 4]);
    gl.RowHeight = {90,32,32,32,32,32,32,32,32,32,32,32,24,'1x'};
    gl.ColumnWidth = {190,240,240,'1x'};
    gl.Padding = [12 12 12 12]; gl.RowSpacing = 6; gl.ColumnSpacing = 8;

    header = uipanel(gl,'BorderType','none'); header.Layout.Row = 1; header.Layout.Column = [1 4];
    hgl = uigridlayout(header,[1 4]); hgl.ColumnWidth = {120,'1x','1x','1x'}; hgl.RowSpacing = 0; hgl.ColumnSpacing = 8;
    logoPath = fullfile(projRoot,'建科院标志PNG-01.png');
    uiimg = uiimage(hgl); uiimg.Layout.Row = 1; uiimg.Layout.Column = 1; uiimg.ScaleMethod = 'fit';
    if exist(logoPath,'file'), uiimg.ImageSource = logoPath; end
    versionStr = 'v1.0.0';
    titleLbl = uilabel(hgl,'Text',['福建建科院健康监测大数据分析 ' versionStr],'FontSize',30,'FontWeight','bold','FontColor',primaryBlue,'HorizontalAlignment','center');
    titleLbl.Layout.Row = 1; titleLbl.Layout.Column = [2 4];

    lblRoot = uilabel(gl,'Text','数据根目录:','FontWeight','bold','HorizontalAlignment','right'); lblRoot.Layout.Row=2; lblRoot.Layout.Column=1;
    rootEdit = uieditfield(gl,'text','Value',projRoot); rootEdit.Layout.Row=2; rootEdit.Layout.Column=[2 3];
    rootBtn  = uibutton(gl,'Text','浏览','ButtonPushedFcn',@(btn,~) onBrowseDir(rootEdit)); rootBtn.Layout.Row=2; rootBtn.Layout.Column=4;

    lblStart = uilabel(gl,'Text','开始日期:','HorizontalAlignment','right'); lblStart.Layout.Row=3; lblStart.Layout.Column=1;
    startPicker = uidatepicker(gl,'Value',datetime('today')-days(1),'DisplayFormat','yyyy-MM-dd'); startPicker.Layout.Row=3; startPicker.Layout.Column=2;
    lblEnd = uilabel(gl,'Text','结束日期:','HorizontalAlignment','right'); lblEnd.Layout.Row=3; lblEnd.Layout.Column=3;
    endPicker   = uidatepicker(gl,'Value',datetime('today'),'DisplayFormat','yyyy-MM-dd'); endPicker.Layout.Row=3; endPicker.Layout.Column=4;

    cbPrecheck = uicheckbox(gl,'Text','预检查压缩包数','Value',false); cbPrecheck.Layout.Row=4; cbPrecheck.Layout.Column=1;
    cbUnzip    = uicheckbox(gl,'Text','批量解压','Value',false);      cbUnzip.Layout.Row   =4; cbUnzip.Layout.Column   =2;
    cbRename   = uicheckbox(gl,'Text','重命名CSV','Value',false);     cbRename.Layout.Row  =4; cbRename.Layout.Column  =3;
    cbRmHeader = uicheckbox(gl,'Text','去除表头','Value',false);      cbRmHeader.Layout.Row=4; cbRmHeader.Layout.Column=4;
    cbResample = uicheckbox(gl,'Text','重采样','Value',false);        cbResample.Layout.Row=5; cbResample.Layout.Column=1;

    cbSelectAll = uicheckbox(gl,'Text','全选/全不选','Value',false,'FontWeight','bold','ValueChangedFcn',@(cb,~) onSelectAll(cb));
    cbSelectAll.Layout.Row=5; cbSelectAll.Layout.Column=4;
    cbTemp   = uicheckbox(gl,'Text','温度','Value',false); cbTemp.Layout.Row=6; cbTemp.Layout.Column=1;
    cbHum    = uicheckbox(gl,'Text','湿度','Value',false); cbHum.Layout.Row=6; cbHum.Layout.Column=2;
    cbDef    = uicheckbox(gl,'Text','挠度','Value',true);  cbDef.Layout.Row=6; cbDef.Layout.Column=3;
    cbTilt   = uicheckbox(gl,'Text','倾角','Value',false); cbTilt.Layout.Row=6; cbTilt.Layout.Column=4;
    cbAccel  = uicheckbox(gl,'Text','加速度','Value',false); cbAccel.Layout.Row=7; cbAccel.Layout.Column=1;
    cbSpec   = uicheckbox(gl,'Text','加速度频谱','Value',false); cbSpec.Layout.Row=7; cbSpec.Layout.Column=2;
    cbCrack  = uicheckbox(gl,'Text','裂缝','Value',false);   cbCrack.Layout.Row=7; cbCrack.Layout.Column=3;
    cbStrain = uicheckbox(gl,'Text','应变','Value',false);   cbStrain.Layout.Row=7; cbStrain.Layout.Column=4;
    cbDynBox = uicheckbox(gl,'Text','动应变箱线图','Value',false); cbDynBox.Layout.Row=8; cbDynBox.Layout.Column=1;

    lblLog = uilabel(gl,'Text','日志目录:','HorizontalAlignment','right'); lblLog.Layout.Row=9; lblLog.Layout.Column=1;
    logEdit = uieditfield(gl,'text','Value',defaultLogDir); logEdit.Layout.Row=9; logEdit.Layout.Column=[2 3];
    logBtn  = uibutton(gl,'Text','浏览','ButtonPushedFcn',@(btn,~) onBrowseDir(logEdit)); logBtn.Layout.Row=9; logBtn.Layout.Column=4;

    lblCfg = uilabel(gl,'Text','配置文件(JSON):','HorizontalAlignment','right'); lblCfg.Layout.Row=10; lblCfg.Layout.Column=1;
    cfgEdit = uieditfield(gl,'text','Value',defaultCfgPath); cfgEdit.Layout.Row=10; cfgEdit.Layout.Column=[2 3];
    cfgBtn  = uibutton(gl,'Text','选择','ButtonPushedFcn',@(btn,~) onBrowseFile(cfgEdit,'*.json')); cfgBtn.Layout.Row=10; cfgBtn.Layout.Column=4;

    presetSaveBtn = uibutton(gl,'Text','保存预设','ButtonPushedFcn',@(btn,~) onSavePreset()); presetSaveBtn.Layout.Row=11; presetSaveBtn.Layout.Column=1;
    presetLoadBtn = uibutton(gl,'Text','加载预设','ButtonPushedFcn',@(btn,~) onLoadPreset()); presetLoadBtn.Layout.Row=11; presetLoadBtn.Layout.Column=2;
    runBtn   = uibutton(gl,'Text','运行','FontWeight','bold','BackgroundColor',primaryBlue,'FontColor',[1 1 1],'ButtonPushedFcn',@(btn,~) onRun());
    runBtn.Layout.Row=11; runBtn.Layout.Column=3;
    stopBtn  = uibutton(gl,'Text','停止','BackgroundColor',[0.8 0.2 0.2],'FontColor',[1 1 1],'ButtonPushedFcn',@(btn,~) onStop());
    stopBtn.Layout.Row=11; stopBtn.Layout.Column=4;
    clearBtn = uibutton(gl,'Text','清空日志','ButtonPushedFcn',@(btn,~) set(logArea,'Value',{}));
    clearBtn.Layout.Row=12; clearBtn.Layout.Column=4;

    statusLbl = uilabel(gl,'Text','就绪','FontColor',primaryBlue); statusLbl.Layout.Row=13; statusLbl.Layout.Column=[1 4];
    logArea   = uitextarea(gl,'Editable','off','Value',{'准备就绪...'}); logArea.Layout.Row=14; logArea.Layout.Column=[1 4];

    autoPreset = fullfile(projRoot,'outputs','ui_last_preset.json');
    if exist(autoPreset,'file')
        try
            preset = jsondecode(fileread(autoPreset));
            apply_preset(preset);
            addLog(['已自动加载上次参数: ' autoPreset]);
        catch
        end
    end

    %% 阈值配置页
    cfgGrid = uigridlayout(tabCfg,[8 4]);
    cfgGrid.RowHeight = {32,32,120,32,180,32,32,'1x'};
    cfgGrid.ColumnWidth = {180,180,240,'1x'};
    cfgGrid.Padding = [12 12 12 12]; cfgGrid.RowSpacing = 6; cfgGrid.ColumnSpacing = 8;

    uilabel(cfgGrid,'Text','编辑阈值/清洗规则：空=全时段/不启用；时间格式 yyyy-MM-dd HH:mm:ss');
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
    defaultsAddBtn = uibutton(cfgGrid,'Text','新增一行','ButtonPushedFcn',@(btn,~) add_default_row()); defaultsAddBtn.Layout.Row=4; defaultsAddBtn.Layout.Column=4;

    perLabel = uilabel(cfgGrid,'Text','per_point 阈值 (可新增/删除行)','FontWeight','bold'); perLabel.Layout.Row=5; perLabel.Layout.Column=1;
    perTable = uitable(cfgGrid,'ColumnName',{'point_id','min','max','t_range_start','t_range_end','zero_to_nan','outlier_window_sec','outlier_threshold_factor'},'ColumnEditable',true(1,8));
    perTable.Layout.Row=5; perTable.Layout.Column=[1 4];
    addRowBtn = uibutton(cfgGrid,'Text','新增行','ButtonPushedFcn',@(btn,~) add_per_row()); addRowBtn.Layout.Row=6; addRowBtn.Layout.Column=1;
    delRowBtn = uibutton(cfgGrid,'Text','删除选中行','ButtonPushedFcn',@(btn,~) delete_per_rows()); delRowBtn.Layout.Row=6; delRowBtn.Layout.Column=2;
    saveCfgBtn = uibutton(cfgGrid,'Text','保存','BackgroundColor',primaryBlue,'FontColor',[1 1 1],'ButtonPushedFcn',@(btn,~) onSaveCfg(false)); saveCfgBtn.Layout.Row=7; saveCfgBtn.Layout.Column=3;
    saveAsCfgBtn = uibutton(cfgGrid,'Text','另存为','ButtonPushedFcn',@(btn,~) onSaveCfg(true)); saveAsCfgBtn.Layout.Row=7; saveAsCfgBtn.Layout.Column=4;
    cfgMsg = uitextarea(cfgGrid,'Editable','off','Value',{'阈值编辑提示：时间格式 yyyy-MM-dd HH:mm:ss；留空表示全时段/不启用。'}); cfgMsg.Layout.Row=8; cfgMsg.Layout.Column=[1 4];

    refresh_tables();

    %% 运行页回调
    function onBrowseDir(edit)
        p = uigetdir(edit.Value);
        if isequal(p,0), return; end

        if isstring(p), p = char(p); end
        if ischar(p), edit.Value = p; end

        % === 强制把主界面拉回前台 ===
        figure(f);        % 关键：把 uifigure 设为当前窗口
        drawnow;          % 立即刷新事件队列
    end
    function onBrowseFile(edit, filter)
        [fname,fpath] = uigetfile(filter,'选择文件',edit.Value);
        if isequal(fname,0), return; end
        edit.Value = fullfile(fpath,fname);

        % === 强制回到前台 ===
        figure(f);
        drawnow;
    end
    function onRun()
        global RUN_STOP_FLAG;
        runBtn.Enable='off'; stopBtn.Enable='on'; RUN_STOP_FLAG=false;
        statusLbl.Text='运行中...'; addLog('开始运行'); drawnow; t0=tic;
        try
            if exist(cfgEdit.Value,'file'), cfg = load_config(cfgEdit.Value); else, addLog('指定配置文件不存在，使用默认配置'); cfg = load_config(); end
            opts = struct('precheck_zip_count',cbPrecheck.Value,'doUnzip',cbUnzip.Value,'doRenameCsv',cbRename.Value,'doRemoveHeader',cbRmHeader.Value,'doResample',cbResample.Value, ...
                'doTemp',cbTemp.Value,'doHumidity',cbHum.Value,'doDeflect',cbDef.Value,'doTilt',cbTilt.Value,'doAccel',cbAccel.Value,'doAccelSpectrum',cbSpec.Value, ...
                'doRenameCrk',false,'doCrack',cbCrack.Value,'doStrain',cbStrain.Value,'doDynStrainBoxplot',cbDynBox.Value);
            root = rootEdit.Value; start_date = datestr(startPicker.Value,'yyyy-mm-dd'); end_date = datestr(endPicker.Value,'yyyy-mm-dd');
            if exist(logEdit.Value,'dir')==0, mkdir(logEdit.Value); end
            save_last_preset(struct('root',root,'start_date',start_date,'end_date',end_date,'cfg',cfgEdit.Value,'logdir',logEdit.Value, ...
                'preproc',struct('precheck',cbPrecheck.Value,'unzip',cbUnzip.Value,'rename',cbRename.Value,'rmheader',cbRmHeader.Value,'resample',cbResample.Value), ...
                'modules',struct('temp',cbTemp.Value,'humidity',cbHum.Value,'deflect',cbDef.Value,'tilt',cbTilt.Value,'accel',cbAccel.Value,'spec',cbSpec.Value,'crack',cbCrack.Value,'strain',cbStrain.Value,'dynbox',cbDynBox.Value)));
            addLog(sprintf('root=%s, %s -> %s', root, start_date, end_date));
            run_all(root, start_date, end_date, opts, cfg);
            elapsed = toc(t0); addLog(sprintf('运行完成，用时 %.2f 秒', elapsed)); statusLbl.Text = sprintf('完成，用时 %.2f 秒', elapsed); statusLbl.FontColor = [0 0.5 0];
        catch ME
            addLog(['运行失败: ' ME.message]); statusLbl.Text='失败'; statusLbl.FontColor=[0.8 0 0];
        end
        runBtn.Enable='on'; stopBtn.Enable='off';
    end
    function onStop()
        global RUN_STOP_FLAG; RUN_STOP_FLAG=true; addLog('收到停止请求，将跳过后续步骤');
    end
    function onSavePreset()
        preset = struct('root',rootEdit.Value,'start_date',datestr(startPicker.Value,'yyyy-MM-dd'),'end_date',datestr(endPicker.Value,'yyyy-MM-dd'), ...
            'cfg',cfgEdit.Value,'logdir',logEdit.Value,'modules',struct('temp',cbTemp.Value,'humidity',cbHum.Value,'deflect',cbDef.Value,'tilt',cbTilt.Value,'accel',cbAccel.Value,'spec',cbSpec.Value,'crack',cbCrack.Value,'strain',cbStrain.Value,'dynbox',cbDynBox.Value));
        [fname,fpath] = uiputfile('*.json','保存预设','preset.json'); if isequal(fname,0), return; end
        fid=fopen(fullfile(fpath,fname),'wt'); if fid<0, addLog('预设保存失败'); return; end
        fwrite(fid,jsonencode(preset),'char'); fclose(fid); addLog(['预设已保存: ' fullfile(fpath,fname)]);
    end
    function onLoadPreset()
        [fname,fpath] = uigetfile('*.json','加载预设'); if isequal(fname,0), return; end
        preset = jsondecode(fileread(fullfile(fpath,fname))); apply_preset(preset); addLog(['预设已加载: ' fullfile(fpath,fname)]);
    end
    function onSelectAll(cb)
        targets = [cbPrecheck, cbUnzip, cbRename, cbRmHeader, cbResample, cbTemp, cbHum, cbDef, cbTilt, cbAccel, cbSpec, cbCrack, cbStrain, cbDynBox];
        for i=1:numel(targets), targets(i).Value = cb.Value; end
    end
    function apply_preset(preset)
        if isfield(preset,'root'), rootEdit.Value = preset.root; end
        if isfield(preset,'start_date'), startPicker.Value = datetime(preset.start_date,'InputFormat','yyyy-MM-dd'); end
        if isfield(preset,'end_date'),   endPicker.Value   = datetime(preset.end_date,'InputFormat','yyyy-MM-dd'); end
        if isfield(preset,'cfg'),        cfgEdit.Value = preset.cfg; end
        if isfield(preset,'logdir'),     logEdit.Value = preset.logdir; end
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
            if isfield(m,'deflect'),  cbDef.Value    = m.deflect; end
            if isfield(m,'tilt'),     cbTilt.Value   = m.tilt; end
            if isfield(m,'accel'),    cbAccel.Value  = m.accel; end
            if isfield(m,'spec'),     cbSpec.Value   = m.spec; end
            if isfield(m,'crack'),    cbCrack.Value  = m.crack; end
            if isfield(m,'strain'),   cbStrain.Value = m.strain; end
            if isfield(m,'dynbox'),   cbDynBox.Value = m.dynbox; end
        end
    end
    function save_last_preset(preset)
        lastPath = fullfile(projRoot,'outputs','ui_last_preset.json');
        try
            if ~exist(fileparts(lastPath),'dir'), mkdir(fileparts(lastPath)); end
            fid = fopen(lastPath,'wt'); if fid<0, return; end
            fwrite(fid, jsonencode(preset),'char'); fclose(fid);
        catch
        end
    end
    function addLog(msg)
        val = logArea.Value; val{end+1} = sprintf('[%s] %s', datestr(now,'HH:MM:SS'), msg); logArea.Value = val; drawnow;
    end

    %% 阈值 Tab 逻辑
    function refresh_tables()
        % 确保下拉有效
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

        sensor = sensorDrop.Value; filterStr = lower(strtrim(filterEdit.Value));
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
                pid = pnames{i}; if ~isempty(filterStr) && isempty(strfind(lower(pid), filterStr)), continue; end %#ok<STREMP>
                rule = pts.(pid); ths = []; if isfield(rule,'thresholds'), ths = rule.thresholds; end
                if isempty(ths)
                    perRows(end+1,:) = {pid, [], [], '', '', bool_or_empty(rule,'zero_to_nan'), num_or_empty_out(rule,'outlier','window_sec'), num_or_empty_out(rule,'outlier','threshold_factor')}; %#ok<AGROW>
                else
                    for k = 1:numel(ths)
                        perRows(end+1,:) = {pid, num_or_empty(ths(k),'min'), num_or_empty(ths(k),'max'), str_or_empty(ths(k),'t_range_start'), str_or_empty(ths(k),'t_range_end'), bool_or_empty(rule,'zero_to_nan'), num_or_empty_out(rule,'outlier','window_sec'), num_or_empty_out(rule,'outlier','threshold_factor')}; %#ok<AGROW>
                    end
                end
            end
        end
        perTable.Data = perRows;
    end
    function add_default_row(), defaultsTable.Data = [defaultsTable.Data; {[], [], '', ''}]; end
    function add_per_row(), perTable.Data = [perTable.Data; {'', [], [], '', '', false, [], []}]; end
    function delete_per_rows()
        idx = perTable.Selection; if isempty(idx), return; end
        data = perTable.Data; data(idx(:,1),:) = []; perTable.Data = data;
    end
    function onReloadCfg()
        try
            cfgCache = load_config(cfgEdit.Value); cfgPath = cfgEdit.Value; refresh_tables(); cfgMsg.Value = {'已重新加载配置。'};
        catch ME
            cfgMsg.Value = {['加载失败: ' ME.message]};
        end
    end
    function show_help()
        msg = sprintf(['字段说明:\n',...
            '- t_range_start / t_range_end: 时间范围，格式 yyyy-MM-dd HH:mm:ss，留空表示全时段。\n',...
            '- zero_to_nan: 勾选表示把数值为 0 视为缺失(NaN)。\n',...
            '- outlier_window_sec: 移动窗长(秒)，配合 threshold_factor 做 isoutlier(movmedian)；留空表示不启用。\n',...
            '- outlier_threshold_factor: 异常阈值系数，越大越宽松；留空表示不启用。\n',...
            '- thresholds: 每行 min/max 为必填，时间窗可选，超限将置 NaN。\n',...
            '保存会先校验格式并自动备份。']);
        uialert(f, msg, '阈值配置说明');
    end
    function onSaveCfg(doSaveAs)
        try
            cfgNew = cfgCache; sensor = sensorDrop.Value;
            % --- defaults ---
            dData = defaultsTable.Data; ths = struct('min',{},'max',{},'t_range_start',{},'t_range_end',{});
            for i = 1:size(dData,1)
                mn = str2num_safe(dData{i,1}); mx = str2num_safe(dData{i,2}); if isempty(mn) || isempty(mx), continue; end
                t0 = strtrim(dData{i,3}); t1 = strtrim(dData{i,4});
                ths(end+1) = make_threshold(mn, mx, t0, t1); %#ok<AGROW>
            end
            cfgNew.defaults.(sensor).thresholds = ths;
            cfgNew.defaults.(sensor).zero_to_nan = logical(zeroChk.Value);
            ow = outWin.Value; ot = outTh.Value; if ~isempty(ow) || ~isempty(ot), cfgNew.defaults.(sensor).outlier = struct('window_sec', ow, 'threshold_factor', ot); else, cfgNew.defaults.(sensor).outlier = []; end

            % 组装 per_point，按测点聚合阈值，避免结构体字段不一致导致赋值报错
            pData = perTable.Data;
            perStruct = struct();
            th_map = struct(); meta_map = struct();
            for i = 1:size(pData,1)
                pid = strtrim(pData{i,1}); if isempty(pid), continue; end
                mn = str2num_safe(pData{i,2}); mx = str2num_safe(pData{i,3}); if isempty(mn) || isempty(mx), continue; end
                t0 = strtrim(pData{i,4}); t1 = strtrim(pData{i,5});
                th = make_threshold(mn, mx, t0, t1);
                if ~isfield(th_map, pid)
                    th_map.(pid) = th;
                    meta_map.(pid) = struct( ...
                        'zero_to_nan', logical(pData{i,6}), ...
                        'ow', str2num_safe(pData{i,7}), ...
                        'ot', str2num_safe(pData{i,8}));
                else
                    th_map.(pid)(end+1) = th; %#ok<AGROW>
                end
            end
            pnames = fieldnames(th_map);
            for ii = 1:numel(pnames)
                pid = pnames{ii};
                perStruct.(pid).thresholds = th_map.(pid);
                perStruct.(pid).zero_to_nan = meta_map.(pid).zero_to_nan;
                owv = meta_map.(pid).ow; otv = meta_map.(pid).ot;
                if ~isempty(owv) || ~isempty(otv)
                    perStruct.(pid).outlier = struct('window_sec', owv, 'threshold_factor', otv);
                else
                    perStruct.(pid).outlier = [];
                end
            end
            cfgNew.per_point.(sensor) = prune_per_struct(perStruct);

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

    %% 工具
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
    function th = make_threshold(mn, mx, t0, t1)
        th = struct('min', mn, 'max', mx, 't_range_start', '', 't_range_end', '');
        if ~isempty(t0), th.t_range_start = t0; end
        if ~isempty(t1), th.t_range_end   = t1; end
    end
    % 移除缺少 min/max 的阈值行；若测点无有效阈值则移除该测点
    function cleaned = prune_per_struct(perStruct)
        cleaned = struct();
        if isempty(perStruct) || ~isstruct(perStruct), return; end
        pnames = fieldnames(perStruct);
        for i = 1:numel(pnames)
            pid = pnames{i};
            ths = perStruct.(pid).thresholds;
            if isempty(ths) || ~isstruct(ths), continue; end
            newThs = struct('min', {}, 'max', {}, 't_range_start', {}, 't_range_end', {});
            for k = 1:numel(ths)
                if isfield(ths(k),'min') && isfield(ths(k),'max') ...
                        && ~isempty(ths(k).min) && ~isempty(ths(k).max) ...
                        && isnumeric(ths(k).min) && isnumeric(ths(k).max)
                    newThs(end+1) = make_threshold( ...
                        ths(k).min, ths(k).max, ...
                        str_or_empty(ths(k),'t_range_start'), ...
                        str_or_empty(ths(k),'t_range_end')); %#ok<AGROW>
                end
            end
            if ~isempty(newThs)
                cleaned.(pid) = perStruct.(pid);
                cleaned.(pid).thresholds = newThs;
            end
        end
    end
end
