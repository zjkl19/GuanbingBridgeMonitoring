function gui_smoke_test()
% gui_smoke_test  Open the MATLAB GUI and verify the main controls build.
%
% Intended for manual/release smoke checks:
%   matlab -batch "addpath('scripts'); gui_smoke_test"

    projectRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(projectRoot, fullfile(projectRoot, 'ui'), ...
        fullfile(projectRoot, 'config'), fullfile(projectRoot, 'pipeline'), ...
        fullfile(projectRoot, 'analysis'), fullfile(projectRoot, 'scripts'));

    beforeHandles = allchild(groot);
    beforeTimers = timerfindall;
    newHandles = gobjects(0);
    cleanupObj = onCleanup(@() cleanupGuiSmoke(newHandles, beforeTimers));

    run_gui();
    pause(1);

    afterHandles = allchild(groot);
    newHandles = setdiff(afterHandles, beforeHandles);
    assert(~isempty(newHandles), 'GUI smoke failed: no GUI window was created.');

    tabGroups = findall(newHandles, 'Type', 'uitabgroup');
    tabs = findall(newHandles, 'Type', 'uitab');
    tables = findall(newHandles, 'Type', 'uitable');
    textAreas = findall(newHandles, 'Type', 'uitextarea');
    dropdowns = findall(newHandles, 'Type', 'uidropdown');

    pos = newHandles(1).Position;
    assert(pos(4) >= 760, 'GUI smoke failed: default window height is too small.');
    assert(~isempty(tabGroups), 'GUI smoke failed: tab group was not created.');
    assert(numel(tabs) >= 5, 'GUI smoke failed: expected at least 5 tabs.');
    assert(hasSummaryTable(tables), 'GUI smoke failed: summary table was not created.');
    assert(~isempty(textAreas), 'GUI smoke failed: log/status text area was not created.');
    assert(summaryTableHasRows(tables), 'GUI smoke failed: result summary table was empty.');
    profileCount = bridgeProfileCount(dropdowns);
    assert(profileCount >= 4, 'GUI smoke failed: bridge profile dropdown missing expected profiles.');

    profileDrop = findBridgeProfileDropdown(dropdowns);
    assert(~isempty(profileDrop), 'GUI smoke failed: bridge profile dropdown handle not found.');
    verifyProfileSwitch(profileDrop, 'shuixianhua');

    fprintf('GUI smoke passed: windows=%d, height=%.0f, tabs=%d, tables=%d, profiles=%d\n', ...
        numel(newHandles), pos(4), numel(tabs), numel(tables), profileCount);
end

function tf = hasSummaryTable(tables)
    tf = false;
    for i = 1:numel(tables)
        try
            names = tables(i).ColumnName;
            if iscell(names) && numel(names) == 7
                tf = true;
                return;
            end
        catch
        end
    end
end

function tf = summaryTableHasRows(tables)
    tf = false;
    for i = 1:numel(tables)
        try
            names = tables(i).ColumnName;
            if iscell(names) && numel(names) == 7 && ~isempty(tables(i).Data)
                tf = true;
                return;
            end
        catch
        end
    end
end

function count = bridgeProfileCount(dropdowns)
    count = 0;
    expected = {'guanbing', 'hongtang', 'jiulongjiang', 'shuixianhua'};
    for i = 1:numel(dropdowns)
        try
            itemsData = cellstr(string(dropdowns(i).ItemsData));
            if all(ismember(expected, itemsData))
                count = numel(itemsData);
                return;
            end
        catch
        end
    end
end

function dropdown = findBridgeProfileDropdown(dropdowns)
dropdown = [];
expected = {'guanbing', 'hongtang', 'jiulongjiang', 'shuixianhua'};
for i = 1:numel(dropdowns)
    try
        itemsData = cellstr(string(dropdowns(i).ItemsData));
        if all(ismember(expected, itemsData))
            dropdown = dropdowns(i);
            return;
        end
    catch
    end
end
end

function verifyProfileSwitch(profileDrop, profileId)
    profileDrop.Value = profileId;
    cb = profileDrop.ValueChangedFcn;
    if isa(cb, 'function_handle')
        cb(profileDrop, []);
    elseif iscell(cb) && ~isempty(cb) && isa(cb{1}, 'function_handle')
        cb{1}(profileDrop, []);
    end
    pause(0.2);
    fig = ancestor(profileDrop, 'figure');
    edits = findall(fig, 'Type', 'uieditfield');
    values = cell(1, numel(edits));
    for i = 1:numel(edits)
        try
            values{i} = char(string(edits(i).Value));
        catch
            values{i} = '';
        end
    end
    joined = strjoin(values, newline);
    assert(contains(joined, 'shuixianhua_config.json'), 'GUI smoke failed: profile switch did not update config path.');
    sxhToken = char([27700 20185 33457 22823 26725]);
    assert(contains(joined, sxhToken), 'GUI smoke failed: profile switch did not update data root.');
end

function cleanupGuiSmoke(handles, beforeTimers)
    stopNewTimers(beforeTimers);
    closeNewHandles(handles);
    stopNewTimers(beforeTimers);
end

function stopNewTimers(beforeTimers)
    try
        timers = timerfindall;
        timers = setdiff(timers, beforeTimers);
        for i = 1:numel(timers)
            try
                stop(timers(i));
                delete(timers(i));
            catch
            end
        end
    catch
    end
end

function closeNewHandles(handles)
    for i = 1:numel(handles)
        try
            if isvalid(handles(i))
                delete(handles(i));
            end
        catch
        end
    end
end
