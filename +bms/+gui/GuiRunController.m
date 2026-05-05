classdef GuiRunController
    %GUIRUNCONTROLLER Small helpers that bind GUI controls to module metadata.

    methods (Static)
        function opts = optsFromControls(controlMap)
            opts = bms.module.ModuleRegistry.optsFromHandles(controlMap);
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
                if isvalid(h) && ~isempty(specs(i).GuiLabel)
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
                if isvalid(h)
                    h.Value = logical(modulesPreset.(presetField));
                end
            end
        end
    end
end
