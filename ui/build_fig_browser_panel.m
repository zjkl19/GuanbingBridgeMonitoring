function fb = build_fig_browser_panel(parent, f, onOpenFig)
% build_fig_browser_panel  Build a FIG file browser panel.
% onOpenFig(fullpath) is called when user opens a file.

    if nargin < 3 || isempty(onOpenFig)
        onOpenFig = @(~) [];
    end

    fb = struct();
    fb.panel = uipanel(parent,'BorderType','none');
    grid = uigridlayout(fb.panel,[6 1]);
    grid.RowHeight = {30,30,'1x',70,120,32};
    grid.ColumnWidth = {'1x'};
    grid.Padding = [6 6 6 6];
    grid.RowSpacing = 6; grid.ColumnSpacing = 6;

    % Row 1: directory
    topGrid = uigridlayout(grid,[1 4]);
    topGrid.ColumnWidth = {60,'1x',70,70};
    topGrid.RowHeight = {22};
    topGrid.Layout.Row = 1;
    uilabel(topGrid,'Text','目录:','HorizontalAlignment','right');
    dirEdit = uieditfield(topGrid,'text','Value',pwd);
    browseBtn = uibutton(topGrid,'Text','浏览', 'ButtonPushedFcn',@(btn,~) onBrowseDir()); %#ok<NASGU>
    refreshBtn = uibutton(topGrid,'Text','刷新', 'ButtonPushedFcn',@(btn,~) refreshList()); %#ok<NASGU>

    % Row 2: filter
    filterGrid = uigridlayout(grid,[1 2]);
    filterGrid.ColumnWidth = {60,'1x'};
    filterGrid.RowHeight = {22};
    filterGrid.Layout.Row = 2;
    uilabel(filterGrid,'Text','过滤:','HorizontalAlignment','right');
    filterEdit = uieditfield(filterGrid,'text','Placeholder','文件名包含...', ...
        'ValueChangedFcn',@(ed,~) refreshList());

    % Row 3: list
    listBox = uilistbox(grid,'Items',{},'ValueChangedFcn',@(lb,~) onSelect());
    listBox.Layout.Row = 3;

    % Row 4: info
    infoPanel = uipanel(grid,'Title','文件信息');
    infoPanel.Layout.Row = 4;
    infoGrid = uigridlayout(infoPanel,[3 1]);
    infoGrid.RowHeight = {22,22,22};
    infoPath = uilabel(infoGrid,'Text','路径:','HorizontalAlignment','left');
    infoTime = uilabel(infoGrid,'Text','时间:','HorizontalAlignment','left');
    infoSize = uilabel(infoGrid,'Text','大小:','HorizontalAlignment','left');

    % Row 5: preview placeholder
    previewPanel = uipanel(grid,'Title','预览');
    previewPanel.Layout.Row = 5;
    previewGrid = uigridlayout(previewPanel,[2 1]);
    previewGrid.RowHeight = {'1x',22};
    previewGrid.ColumnWidth = {'1x'};
    previewGrid.Padding = [6 6 6 6];
    previewImg = uiimage(previewGrid);
    previewImg.Layout.Row = 1;
    previewImg.ScaleMethod = 'fit';
    previewLabel = uilabel(previewGrid,'Text','(无预览图片)','HorizontalAlignment','center');
    previewLabel.Layout.Row = 2;
    previewLabel.FontColor = [0.5 0.5 0.5];

    % Row 6: open button
    openBtn = uibutton(grid,'Text','从图片设置阈值', ...
        'ButtonPushedFcn',@(btn,~) openSelected()); %#ok<NASGU>
    openBtn.Layout.Row = 6;

    files = struct('name',{},'path',{},'bytes',{},'datenum',{});
    refreshList();
    fb.refresh = @refreshList;

    function onBrowseDir()
        p = uigetdir(dirEdit.Value);
        if isequal(p,0), return; end
        dirEdit.Value = p;
        refreshList();
    end

    function refreshList()
        root = dirEdit.Value;
        if isempty(root) || ~isfolder(root)
            listBox.Items = {'(无目录)'};
            listBox.UserData = [];
            return;
        end
        filt = strtrim(filterEdit.Value);
        d = dir(fullfile(root,'*.fig'));
        files = struct('name',{},'path',{},'bytes',{},'datenum',{});
        items = {};
        for i = 1:numel(d)
            if d(i).isdir, continue; end
            name = d(i).name;
            if ~isempty(filt) && ~contains(lower(name), lower(filt))
                continue;
            end
            items{end+1} = name; %#ok<AGROW>
            files(end+1) = struct( ... %#ok<AGROW>
                'name', name, ...
                'path', fullfile(d(i).folder, d(i).name), ...
                'bytes', d(i).bytes, ...
                'datenum', d(i).datenum);
        end
        if isempty(items)
            listBox.Items = {'(无 .fig 文件)'};
            listBox.UserData = [];
        else
            listBox.Items = items;
            listBox.UserData = files;
            listBox.Value = items{1};
            onSelect();
        end
    end

    function onSelect()
        if isempty(listBox.UserData) || isempty(listBox.Items)
            infoPath.Text = '路径:';
            infoTime.Text = '时间:';
            infoSize.Text = '大小:';
            previewImg.ImageSource = '';
            previewLabel.Text = '(无预览图片)';
            return;
        end
        idx = find(strcmp(listBox.Items, listBox.Value), 1);
        if isempty(idx), return; end
        fitem = listBox.UserData(idx);
        infoPath.Text = ['路径: ' fitem.path];
        infoTime.Text = ['时间: ' datestr(fitem.datenum,'yyyy-mm-dd HH:MM:ss')];
        infoSize.Text = ['大小: ' format_bytes(fitem.bytes)];
        [imgDir, imgBase, ~] = fileparts(fitem.path);
        jpgPath = fullfile(imgDir, [imgBase '.jpg']);
        pngPath = fullfile(imgDir, [imgBase '.png']);
        if isfile(jpgPath)
            previewImg.ImageSource = jpgPath;
            previewLabel.Text = ['预览: ' imgBase '.jpg'];
        elseif isfile(pngPath)
            previewImg.ImageSource = pngPath;
            previewLabel.Text = ['预览: ' imgBase '.png'];
        else
            previewImg.ImageSource = '';
            previewLabel.Text = '(无预览图片)';
        end

        % double-click support
        try
            if isprop(f,'SelectionType') && strcmp(f.SelectionType,'open')
                openSelected();
            end
        catch
        end
    end

    function openSelected()
        if isempty(listBox.UserData) || isempty(listBox.Items), return; end
        idx = find(strcmp(listBox.Items, listBox.Value), 1);
        if isempty(idx), return; end
        fitem = listBox.UserData(idx);
        if ~isfile(fitem.path), return; end
        onOpenFig(fitem.path);
    end

    function s = format_bytes(b)
        if b < 1024
            s = sprintf('%d B', b);
        elseif b < 1024^2
            s = sprintf('%.1f KB', b/1024);
        elseif b < 1024^3
            s = sprintf('%.1f MB', b/1024^2);
        else
            s = sprintf('%.2f GB', b/1024^3);
        end
    end
end
