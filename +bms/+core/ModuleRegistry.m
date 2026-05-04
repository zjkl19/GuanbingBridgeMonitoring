classdef ModuleRegistry
    %MODULEREGISTRY Compatibility facade for app-layer step definitions.

    methods (Static)
        function items = allModules()
            defs = bms.module.ModuleRegistry.catalog();
            items = cell(1, numel(defs));
            for i = 1:numel(defs)
                s = defs(i).toStruct('');
                s.opt = defs(i).OptField;
                s.name = defs(i).Key;
                items{i} = s;
            end
        end

        function mods = enabledModules(opts)
            defs = bms.module.ModuleRegistry.enabledFromOptions(opts);
            mods = cell(1, numel(defs));
            for i = 1:numel(defs)
                s = defs(i).toStruct('');
                s.opt = defs(i).OptField;
                s.name = defs(i).Key;
                mods{i} = s;
            end
        end

        function names = enabledNames(opts)
            names = bms.module.ModuleRegistry.enabledKeys(opts);
        end
    end
end
