classdef ConfigEditorService
    %CONFIGEDITORSERVICE Shared config helpers for GUI editor tabs.

    methods (Static)
        function cfg = load(path)
            if nargin < 1 || isempty(path)
                cfg = bms.core.ConfigStore.load();
            else
                cfg = bms.core.ConfigStore.load(path);
            end
        end

        function [cfg, report] = saveAndReload(cfgDraft, targetPath, makeBackup)
            if nargin < 3
                makeBackup = true;
            end
            report = bms.core.ConfigStore.saveGuardedWithReport(cfgDraft, targetPath, makeBackup);
            cfg = bms.core.ConfigStore.load(targetPath);
        end

        function keys = editableModuleKeys(cfg, mode)
            if nargin < 2 || isempty(mode)
                mode = 'all';
            end
            keys = bms.gui.ConfigEditorService.collectConfiguredKeys(cfg);
            keys = bms.gui.ConfigEditorService.filterByMode(keys, mode);
            keys = bms.gui.ConfigEditorService.orderKeys(keys);
            if isempty(keys)
                keys = {'deflection'};
            end
        end

        function labels = moduleLabels(keys)
            labels = cell(size(keys));
            for i = 1:numel(keys)
                labels{i} = bms.gui.ConfigEditorService.moduleLabel(keys{i});
            end
        end
    end

    methods (Static, Access = private)
        function keys = collectConfiguredKeys(cfg)
            keys = {};
            sections = {'defaults', 'per_point', 'points', 'groups', 'plot_styles'};
            for i = 1:numel(sections)
                section = sections{i};
                if isstruct(cfg) && isfield(cfg, section) && isstruct(cfg.(section))
                    keys = [keys; fieldnames(cfg.(section))]; %#ok<AGROW>
                end
            end
            exclude = {'header_marker'};
            known = bms.config.ModuleConfigRegistry.knownConfigKeys();
            keys = unique(keys, 'stable');
            keys = keys(~ismember(keys, exclude));
            keys = keys(ismember(keys, known));
        end

        function keys = filterByMode(keys, mode)
            mode = char(string(mode));
            switch mode
                case 'post_filter'
                    supported = {'deflection', 'bearing_displacement', ...
                        'dynamic_strain', 'dynamic_strain_lowpass'};
                    keys = keys(ismember(keys, supported));
                case 'offset'
                    exclude = {'wind', 'wind_speed', 'wind_direction', 'wind_raw', ...
                        'eq', 'eq_raw', 'accel_spectrum', 'cable_accel_spectrum', ...
                        'wim', 'temp_humidity'};
                    keys = keys(~ismember(keys, exclude));
                otherwise
                    % Keep all known editable modules.
            end
        end

        function ordered = orderKeys(keys)
            preferred = { ...
                'temperature', 'humidity', 'rainfall', 'wind_speed', 'wind_direction', ...
                'strain', 'dynamic_strain', 'dynamic_strain_lowpass', ...
                'deflection', 'bearing_displacement', 'tilt', 'crack', ...
                'earthquake', 'eq', 'eq_x', 'eq_y', 'eq_z', 'acceleration', 'accel_spectrum', ...
                'cable_accel', 'cable_accel_spectrum', 'gnss', 'wim'};
            ordered = {};
            for i = 1:numel(preferred)
                if any(strcmp(keys, preferred{i}))
                    ordered{end+1, 1} = preferred{i}; %#ok<AGROW>
                end
            end
            for i = 1:numel(keys)
                if ~any(strcmp(ordered, keys{i}))
                    ordered{end+1, 1} = keys{i}; %#ok<AGROW>
                end
            end
        end

        function label = moduleLabel(key)
            spec = bms.config.ModuleConfigRegistry.fromKey(key);
            if ~isempty(spec.label) && ~strcmp(spec.label, key)
                label = sprintf('%s (%s)', key, spec.label);
            else
                label = key;
            end
        end
    end
end
