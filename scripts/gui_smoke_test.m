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
    newHandles = gobjects(0);
    cleanupObj = onCleanup(@() closeNewHandles(newHandles));

    run_gui();
    pause(1);

    afterHandles = allchild(groot);
    newHandles = setdiff(afterHandles, beforeHandles);
    assert(~isempty(newHandles), 'GUI smoke failed: no GUI window was created.');

    tabGroups = findall(newHandles, 'Type', 'uitabgroup');
    tabs = findall(newHandles, 'Type', 'uitab');
    tables = findall(newHandles, 'Type', 'uitable');
    textAreas = findall(newHandles, 'Type', 'uitextarea');

    pos = newHandles(1).Position;
    assert(pos(4) >= 760, 'GUI smoke failed: default window height is too small.');
    assert(~isempty(tabGroups), 'GUI smoke failed: tab group was not created.');
    assert(numel(tabs) >= 5, 'GUI smoke failed: expected at least 5 tabs.');
    assert(hasSummaryTable(tables), 'GUI smoke failed: summary table was not created.');
    assert(~isempty(textAreas), 'GUI smoke failed: log/status text area was not created.');
    assert(summaryTableHasRows(tables), 'GUI smoke failed: result summary table was empty.');

    fprintf('GUI smoke passed: windows=%d, height=%.0f, tabs=%d, tables=%d\n', ...
        numel(newHandles), pos(4), numel(tabs), numel(tables));
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
