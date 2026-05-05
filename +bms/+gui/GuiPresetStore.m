classdef GuiPresetStore
    %GUIPRESETSTORE Load/save GUI presets with backward-compatible fields.

    methods (Static)
        function path = defaultPath(projectRoot)
            path = fullfile(char(projectRoot), 'outputs', 'ui_last_preset.json');
        end

        function state = load(path)
            if nargin < 1 || isempty(path) || ~isfile(path)
                state = bms.gui.GuiState();
                return;
            end
            data = jsondecode(fileread(path));
            state = bms.gui.GuiState.fromPreset(data);
        end

        function save(path, state)
            if isa(state, 'bms.gui.GuiState')
                preset = state.toPreset();
            elseif isstruct(state)
                preset = bms.gui.GuiState.fromPreset(state).toPreset();
            else
                error('BMS:GuiPresetStore:InvalidPreset', 'Preset must be GuiState or struct.');
            end
            folder = fileparts(char(path));
            if ~isempty(folder) && ~exist(folder, 'dir')
                mkdir(folder);
            end
            fid = fopen(path, 'wt', 'n', 'UTF-8');
            if fid < 0
                error('BMS:GuiPresetStore:WriteFailed', 'Unable to write preset: %s', char(path));
            end
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fwrite(fid, jsonencode(preset, 'PrettyPrint', true), 'char');
        end

        function state = loadLast(projectRoot)
            state = bms.gui.GuiPresetStore.load(bms.gui.GuiPresetStore.defaultPath(projectRoot));
        end

        function path = saveLast(projectRoot, state)
            path = bms.gui.GuiPresetStore.defaultPath(projectRoot);
            bms.gui.GuiPresetStore.save(path, state);
        end
    end
end
