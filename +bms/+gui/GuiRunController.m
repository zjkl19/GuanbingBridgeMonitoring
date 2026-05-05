classdef GuiRunController
    %GUIRUNCONTROLLER Small helpers that bind GUI controls to module metadata.

    methods (Static)
        function opts = optsFromControls(controlMap)
            opts = bms.module.ModuleRegistry.optsFromHandles(controlMap);
        end

        function opts = optsFromPreset(preset)
            if isa(preset, 'bms.gui.GuiState')
                preset = preset.toPreset();
            end
            opts = struct();
            specs = bms.module.ModuleRegistry.catalog();
            for i = 1:numel(specs)
                opt = specs(i).OptField;
                presetField = specs(i).PresetField;
                if isempty(opt) || isempty(presetField)
                    continue;
                end
                opts.(opt) = false;
                if isstruct(preset) && isfield(preset, 'preproc') && isstruct(preset.preproc) && isfield(preset.preproc, presetField)
                    opts.(opt) = bms.config.ConfigReader.boolValue(preset.preproc.(presetField), false);
                end
                if isstruct(preset) && isfield(preset, 'modules') && isstruct(preset.modules) && isfield(preset.modules, presetField)
                    opts.(opt) = bms.config.ConfigReader.boolValue(preset.modules.(presetField), opts.(opt));
                end
            end
        end

        function preset = presetFromControls(controlMap, category)
            if nargin < 2, category = ''; end
            preset = struct();
            if ~isstruct(controlMap)
                return;
            end
            specs = bms.module.ModuleRegistry.catalog();
            for i = 1:numel(specs)
                if ~isempty(category) && ~strcmpi(specs(i).Category, category)
                    continue;
                end
                field = specs(i).GuiField;
                presetField = specs(i).PresetField;
                if isempty(field) || isempty(presetField) || ~isfield(controlMap, field)
                    continue;
                end
                [ok, value] = bms.gui.GuiRunController.controlBool(controlMap.(field), false);
                if ok
                    preset.(presetField) = value;
                end
            end
        end

        function request = createRunRequest(state, cfg)
            if ~isa(state, 'bms.gui.GuiState')
                state = bms.gui.GuiState.fromPreset(state);
            end
            request = state.toRunRequest(cfg);
        end

        function [request, preflight, logLines] = prepareRun(state, cfg)
            request = bms.gui.GuiRunController.createRunRequest(state, cfg);
            preflight = bms.app.RunPreflight.check(request);
            logLines = bms.app.RunPreflight.toLogLines(preflight);
        end

        function handles = controlValues(controlMap)
            handles = gobjects(0);
            if ~isstruct(controlMap)
                return;
            end
            names = fieldnames(controlMap);
            for i = 1:numel(names)
                h = controlMap.(names{i});
                if isvalid(h)
                    handles(end+1) = h; %#ok<AGROW>
                end
            end
        end

        function applyModuleLabels(controlMap)
            if ~isstruct(controlMap)
                return;
            end
            specs = bms.module.ModuleRegistry.catalog();
            for i = 1:numel(specs)
                field = specs(i).GuiField;
                if isempty(field) || ~isfield(controlMap, field)
                    continue;
                end
                h = controlMap.(field);
                if bms.gui.GuiRunController.isLiveControl(h) && ~isempty(specs(i).GuiLabel)
                    h.Text = specs(i).GuiLabel;
                end
            end
        end

        function applyPresetModules(controlMap, modulesPreset)
            if ~isstruct(controlMap) || ~isstruct(modulesPreset)
                return;
            end
            specs = bms.module.ModuleRegistry.catalog();
            for i = 1:numel(specs)
                field = specs(i).GuiField;
                presetField = specs(i).PresetField;
                if isempty(field) || isempty(presetField) || ~isfield(controlMap, field) || ~isfield(modulesPreset, presetField)
                    continue;
                end
                h = controlMap.(field);
                if bms.gui.GuiRunController.isLiveControl(h)
                    h.Value = logical(modulesPreset.(presetField));
                end
            end
        end

        function [ok, value] = controlBool(control, defaultValue)
            ok = false;
            value = logical(defaultValue);
            try
                if bms.gui.GuiRunController.isLiveControl(control) && isprop(control, 'Value')
                    ok = true;
                    value = logical(control.Value);
                elseif isstruct(control) && isfield(control, 'Value')
                    ok = true;
                    value = logical(control.Value);
                end
            catch
                ok = false;
                value = logical(defaultValue);
            end
        end

        function tf = isLiveControl(h)
            tf = false;
            try
                tf = isobject(h) && isvalid(h);
            catch
                tf = false;
            end
        end
    end
end
