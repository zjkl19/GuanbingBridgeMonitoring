classdef GuiConfigBinder
    %GUICONFIGBINDER Loads config and applies live tab edits consistently.

    methods (Static)
        function [cfg, actualPath] = loadConfig(path, defaultPath)
            if nargin < 2, defaultPath = ''; end
            actualPath = char(path);
            if isempty(actualPath) || ~isfile(actualPath)
                actualPath = char(defaultPath);
            end
            if isempty(actualPath) || ~isfile(actualPath)
                cfg = bms.core.ConfigStore.load();
                actualPath = bms.app.RunRequest.configPathFromConfig(cfg);
            else
                cfg = bms.core.ConfigStore.load(actualPath);
            end
        end

        function cfg = applyLiveTabs(cfg, tabStates)
            if nargin < 2 || isempty(tabStates), return; end
            for i = 1:numel(tabStates)
                tabState = tabStates{i};
                if isstruct(tabState) && isfield(tabState, 'applyToCfg')
                    cfg = tabState.applyToCfg(cfg);
                end
            end
            cfg = bms.config.ConfigMigrator.migrate(cfg);
        end

        function showWarnings = showWarningsDefault(cfg)
            showWarnings = false;
            if isstruct(cfg) && isfield(cfg, 'gui') && isstruct(cfg.gui) && isfield(cfg.gui, 'show_warnings')
                showWarnings = bms.config.ConfigReader.boolValue(cfg.gui.show_warnings, false);
            end
        end
    end
end
