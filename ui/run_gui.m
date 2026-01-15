function run_gui()
% run_gui  图形入口，便于配置并运行 run_all。
% 用法：在项目根目录执行 addpath(fullfile(pwd,'ui')); run_gui
%
% 依赖：config/load_config.m、pipeline/*、analysis/*、scripts/*、run_all.m

    % 定位项目根目录（ui 的上一级）
    projRoot = fileparts(mfilename('fullpath'));
    projRoot = fileparts(projRoot);

    % 确保依赖在路径上
    addpath(projRoot, ...
            fullfile(projRoot,'config'), ...
            fullfile(projRoot,'pipeline'), ...
            fullfile(projRoot,'analysis'), ...
            fullfile(projRoot,'scripts'));

    defaultCfgPath = fullfile(projRoot,'config','default_config.json');
    defaultLogDir  = fullfile(projRoot,'outputs','run_logs');
    if ~exist(defaultLogDir,'dir')
        mkdir(defaultLogDir);
    end

    % 颜色主题（来自 logo 的蓝色）
    primaryBlue = [0 94 172] / 255;

    % ----------- UI -----------
    f = uifigure('Name','福建建科院健康监测大数据分析', ...
                 'Position',[80 80 960 720], ...
                 'Color',[0.97 0.98 1]);
    gl = uigridlayout(f,[11 4]);
    gl.RowHeight = {90,32,32,32,32,32,32,32,32,24,'1x'};
    gl.ColumnWidth = {210,210,210,'1x'};
    gl.Padding = [12 12 12 12];
    gl.RowSpacing = 6;
    gl.ColumnSpacing = 8;

    % 头部（logo + 居中标题）
    headerPanel = uipanel(gl,'BorderType','none');
    headerPanel.Layout.Row = 1;
    headerPanel.Layout.Column = [1 4];
    headerGL = uigridlayout(headerPanel,[1 4]);
    headerGL.RowHeight = {'1x'};
    headerGL.ColumnWidth = {120,'1x','1x','1x'};
    headerGL.RowSpacing = 0; headerGL.ColumnSpacing = 8;

    logoPath = fullfile(projRoot,'建科院标志PNG-01.png');
    uiimg = uiimage(headerGL);
    uiimg.Layout.Row = 1;
    uiimg.Layout.Column = 1;
    uiimg.ScaleMethod = 'fit';
    if exist(logoPath,'file')
        uiimg.ImageSource = logoPath;
    else
        uiimg.ImageSource = '';
    end

    titleLbl = uilabel(headerGL, ...
        'Text','福建建科院健康监测大数据分析', ...
        'FontSize',18, ...
        'FontWeight','bold', ...
        'FontColor',primaryBlue);
    titleLbl.Layout.Row = 1;
    titleLbl.Layout.Column = [2 4];
    titleLbl.HorizontalAlignment = 'center';

    % 根目录行
    lblRoot = uilabel(gl,'Text','数据根目录:','FontWeight','bold', ...
        'HorizontalAlignment','right');
    lblRoot.Layout.Row = 2;
    lblRoot.Layout.Column = 1;
    rootEdit = uieditfield(gl,'text','Value',projRoot);
    rootEdit.Layout.Row = 2; rootEdit.Layout.Column = [2 3];
    rootBtn = uibutton(gl,'Text','浏览','ButtonPushedFcn',@(btn,~) onBrowseDir(rootEdit));
    rootBtn.Layout.Row = 2; rootBtn.Layout.Column = 4;

    % 日期行
    lblStart = uilabel(gl,'Text','开始日期:','HorizontalAlignment','right');
    lblStart.Layout.Row = 3; lblStart.Layout.Column = 1;
    startPicker = uidatepicker(gl,'Value',datetime('today')-days(1), ...
        'DisplayFormat','yyyy-MM-dd');
    startPicker.Layout.Row = 3; startPicker.Layout.Column = 2;

    lblEnd = uilabel(gl,'Text','结束日期:','HorizontalAlignment','right');
    lblEnd.Layout.Row = 3; lblEnd.Layout.Column = 3;
    endPicker = uidatepicker(gl,'Value',datetime('today'), ...
        'DisplayFormat','yyyy-MM-dd');
    endPicker.Layout.Row = 3; endPicker.Layout.Column = 4;

    % 模块开关 + 全选
    cbSelectAll = uicheckbox(gl,'Text','全选/全不选','Value',false, ...
        'FontWeight','bold','ValueChangedFcn',@(cb,~) onSelectAll(cb));
    cbSelectAll.Layout.Row = 4; cbSelectAll.Layout.Column = 4;

    cbTemp    = uicheckbox(gl,'Text','温度','Value',false);          cbTemp.Layout.Row = 4; cbTemp.Layout.Column = 1;
    cbHum     = uicheckbox(gl,'Text','湿度','Value',false);          cbHum.Layout.Row = 4; cbHum.Layout.Column = 2;
    cbDef     = uicheckbox(gl,'Text','挠度','Value',true);           cbDef.Layout.Row = 4; cbDef.Layout.Column = 3;
    cbTilt    = uicheckbox(gl,'Text','倾角','Value',false);          cbTilt.Layout.Row = 5; cbTilt.Layout.Column = 1;
    cbAccel   = uicheckbox(gl,'Text','加速度','Value',false);        cbAccel.Layout.Row = 5; cbAccel.Layout.Column = 2;
    cbSpec    = uicheckbox(gl,'Text','加速度频谱','Value',false);    cbSpec.Layout.Row = 5; cbSpec.Layout.Column = 3;
    cbCrack   = uicheckbox(gl,'Text','裂缝','Value',false);          cbCrack.Layout.Row = 6; cbCrack.Layout.Column = 1;
    cbStrain  = uicheckbox(gl,'Text','应变','Value',false);          cbStrain.Layout.Row = 6; cbStrain.Layout.Column = 2;
    cbDynBox  = uicheckbox(gl,'Text','动应变箱线图','Value',false);  cbDynBox.Layout.Row = 6; cbDynBox.Layout.Column = 3;

    % 配置文件
    lblCfg = uilabel(gl,'Text','配置文件(JSON):','HorizontalAlignment','right');
    lblCfg.Layout.Row = 8; lblCfg.Layout.Column = 2;
    cfgEdit = uieditfield(gl,'text','Value',defaultCfgPath);
    cfgEdit.Layout.Row = 8; cfgEdit.Layout.Column = 3;
    cfgBtn = uibutton(gl,'Text','选择','ButtonPushedFcn',@(btn,~) onBrowseFile(cfgEdit,'*.json'));
    cfgBtn.Layout.Row = 8; cfgBtn.Layout.Column = 4;

    % 日志路径
    lblLog = uilabel(gl,'Text','日志目录:','HorizontalAlignment','right');
    lblLog.Layout.Row = 7; lblLog.Layout.Column = 1;
    logEdit = uieditfield(gl,'text','Value',defaultLogDir);
    logEdit.Layout.Row = 7; logEdit.Layout.Column = [2 3];
    logBtn = uibutton(gl,'Text','浏览','ButtonPushedFcn',@(btn,~) onBrowseDir(logEdit));
    logBtn.Layout.Row = 7; logBtn.Layout.Column = 4;

    % 预设
    presetSaveBtn = uibutton(gl,'Text','保存预设','ButtonPushedFcn',@(btn,~) onSavePreset());
    presetSaveBtn.Layout.Row = 9; presetSaveBtn.Layout.Column = 1;
    presetLoadBtn = uibutton(gl,'Text','加载预设','ButtonPushedFcn',@(btn,~) onLoadPreset());
    presetLoadBtn.Layout.Row = 9; presetLoadBtn.Layout.Column = 2;

    % 控制按钮
    runBtn = uibutton(gl,'Text','运行','FontWeight','bold','BackgroundColor',primaryBlue, ...
        'FontColor',[1 1 1],'ButtonPushedFcn',@(btn,~) onRun());
    runBtn.Layout.Row = 9; runBtn.Layout.Column = 3;
    clearBtn = uibutton(gl,'Text','清空日志','ButtonPushedFcn',@(btn,~) set(logArea,'Value',{}));
    clearBtn.Layout.Row = 9; clearBtn.Layout.Column = 4;

    % 状态标签
    statusLbl = uilabel(gl,'Text','就绪','FontColor',primaryBlue);
    statusLbl.Layout.Row = 10; statusLbl.Layout.Column = [1 4];

    % 日志显示
    logArea = uitextarea(gl,'Editable','off','Value',{'准备就绪...'});
    logArea.Layout.Row = 11; logArea.Layout.Column = [1 4];

    % ------------- 回调函数 -------------
    function onBrowseDir(edit)
        p = uigetdir(edit.Value);
        if isequal(p,0)
            return; % 用户取消
        end
        % uigetdir 返回 char 或 string；统一成 char
        if isstring(p), p = char(p); end
        if ischar(p)
            edit.Value = p;
        end
    end

    function onBrowseFile(edit, filter)
        [fname,fpath] = uigetfile(filter,'选择文件',edit.Value);
        if isequal(fname,0), return; end
        edit.Value = fullfile(fpath,fname);
    end

    function onRun()
        runBtn.Enable = 'off';
        statusLbl.Text = '运行中...';
        addLog('开始运行');
        drawnow;
        try
            % 配置
            if exist(cfgEdit.Value,'file')
                cfg = load_config(cfgEdit.Value);
            else
                addLog('指定配置文件不存在，使用默认配置');
                cfg = load_config();
            end

            opts = struct( ...
                'precheck_zip_count', false, ...
                'doUnzip', false, ...
                'doRenameCsv', false, ...
                'doRemoveHeader', false, ...
                'doResample', false, ...
                'doTemp', cbTemp.Value, ...
                'doHumidity', cbHum.Value, ...
                'doDeflect', cbDef.Value, ...
                'doTilt', cbTilt.Value, ...
                'doAccel', cbAccel.Value, ...
                'doAccelSpectrum', cbSpec.Value, ...
                'doRenameCrk', false, ...
                'doCrack', cbCrack.Value, ...
                'doStrain', cbStrain.Value, ...
                'doDynStrainBoxplot', cbDynBox.Value ...
                );

            root = rootEdit.Value;
            start_date = datestr(startPicker.Value,'yyyy-mm-dd');
            end_date   = datestr(endPicker.Value,'yyyy-mm-dd');

            if exist(logEdit.Value,'dir')==0
                mkdir(logEdit.Value);
            end

            addLog(sprintf('root=%s, %s -> %s', root, start_date, end_date));
            run_all(root, start_date, end_date, opts, cfg);
            addLog('运行完成');
            statusLbl.Text = '完成';
            statusLbl.FontColor = [0 0.5 0];
        catch ME
            addLog(['运行失败: ' ME.message]);
            statusLbl.Text = '失败';
            statusLbl.FontColor = [0.8 0 0];
        end
        runBtn.Enable = 'on';
    end

    function onSavePreset()
        preset = struct();
        preset.root = rootEdit.Value;
        preset.start_date = datestr(startPicker.Value,'yyyy-MM-dd');
        preset.end_date   = datestr(endPicker.Value,'yyyy-MM-dd');
        preset.cfg = cfgEdit.Value;
        preset.logdir = logEdit.Value;
        preset.modules = struct( ...
            'temp', cbTemp.Value, ...
            'humidity', cbHum.Value, ...
            'deflect', cbDef.Value, ...
            'tilt', cbTilt.Value, ...
            'accel', cbAccel.Value, ...
            'spec', cbSpec.Value, ...
            'crack', cbCrack.Value, ...
            'strain', cbStrain.Value, ...
            'dynbox', cbDynBox.Value);

        [fname,fpath] = uiputfile('*.json','保存预设','preset.json');
        if isequal(fname,0), return; end
        fid = fopen(fullfile(fpath,fname),'wt');
        if fid < 0
            addLog('预设保存失败');
            return;
        end
        fwrite(fid, jsonencode(preset),'char');
        fclose(fid);
        addLog(['预设已保存: ' fullfile(fpath,fname)]);
    end

    function onLoadPreset()
        [fname,fpath] = uigetfile('*.json','加载预设');
        if isequal(fname,0), return; end
        txt = fileread(fullfile(fpath,fname));
        preset = jsondecode(txt);

        if isfield(preset,'root'),       rootEdit.Value = preset.root; end
        if isfield(preset,'start_date'), startPicker.Value = datetime(preset.start_date,'InputFormat','yyyy-MM-dd'); end
        if isfield(preset,'end_date'),   endPicker.Value   = datetime(preset.end_date,'InputFormat','yyyy-MM-dd'); end
        if isfield(preset,'cfg'),        cfgEdit.Value = preset.cfg; end
        if isfield(preset,'logdir'),     logEdit.Value = preset.logdir; end
        if isfield(preset,'modules')
            m = preset.modules;
            if isfield(m,'temp'),     cbTemp.Value = m.temp; end
            if isfield(m,'humidity'), cbHum.Value  = m.humidity; end
            if isfield(m,'deflect'),  cbDef.Value  = m.deflect; end
            if isfield(m,'tilt'),     cbTilt.Value = m.tilt; end
            if isfield(m,'accel'),    cbAccel.Value = m.accel; end
            if isfield(m,'spec'),     cbSpec.Value  = m.spec; end
            if isfield(m,'crack'),    cbCrack.Value = m.crack; end
            if isfield(m,'strain'),   cbStrain.Value = m.strain; end
            if isfield(m,'dynbox'),   cbDynBox.Value = m.dynbox; end
        end
        addLog(['预设已加载: ' fullfile(fpath,fname)]);
    end

    function onSelectAll(cb)
        targets = [cbTemp, cbHum, cbDef, cbTilt, cbAccel, cbSpec, cbCrack, cbStrain, cbDynBox];
        for i = 1:numel(targets)
            targets(i).Value = cb.Value;
        end
    end

    function addLog(msg)
        val = logArea.Value;
        val{end+1} = sprintf('[%s] %s', datestr(now,'HH:MM:SS'), msg);
        logArea.Value = val;
        drawnow;
    end
end
