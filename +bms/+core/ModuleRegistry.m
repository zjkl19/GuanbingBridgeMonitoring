classdef ModuleRegistry
    %MODULEREGISTRY Compatibility facade for app-layer step definitions.

    methods (Static)
        function items = allModules()
            defs = bms.app.StepDefinition.catalog();
            items = cell(1, numel(defs));
            for i = 1:numel(defs)
                items{i} = struct( ...
                    'opt', defs(i).OptField, ...
                    'name', defs(i).Key, ...
                    'label', defs(i).Label, ...
                    'stats_file', defs(i).StatsFile, ...
                    'category', defs(i).Category);
            end
        end

        function mods = enabledModules(opts)
            defs = bms.app.StepDefinition.enabledFromOptions(opts);
            mods = cell(1, numel(defs));
            for i = 1:numel(defs)
                mods{i} = struct( ...
                    'opt', defs(i).OptField, ...
                    'name', defs(i).Key, ...
                    'label', defs(i).Label, ...
                    'stats_file', defs(i).StatsFile, ...
                    'category', defs(i).Category);
            end
        end

        function names = enabledNames(opts)
            defs = bms.app.StepDefinition.enabledFromOptions(opts);
            names = cell(1, numel(defs));
            for i = 1:numel(defs)
                names{i} = defs(i).Key;
            end
        end
    end
end
