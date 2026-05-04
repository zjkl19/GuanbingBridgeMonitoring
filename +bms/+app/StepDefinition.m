classdef StepDefinition
    %STEPDEFINITION Metadata for one legacy analysis step.

    properties
        Key char = ''
        OptField char = ''
        Label char = ''
        StatsFile char = ''
        Category char = 'analysis'
    end

    methods
        function obj = StepDefinition(key, optField, label, statsFile, category)
            if nargin >= 1, obj.Key = char(key); end
            if nargin >= 2, obj.OptField = char(optField); end
            if nargin >= 3, obj.Label = char(label); end
            if nargin >= 4, obj.StatsFile = char(statsFile); end
            if nargin >= 5, obj.Category = char(category); end
        end

        function s = toStruct(obj, statsDir)
            if nargin < 2, statsDir = ''; end
            s = struct();
            s.key = obj.Key;
            s.opt_field = obj.OptField;
            s.label = obj.Label;
            s.category = obj.Category;
            s.stats_file = obj.StatsFile;
            s.stats_path = '';
            if ~isempty(statsDir) && ~isempty(obj.StatsFile)
                s.stats_path = fullfile(statsDir, obj.StatsFile);
            end
        end
    end

    methods (Static)
        function defs = catalog()
            specs = bms.module.ModuleRegistry.catalog();
            defs = bms.app.StepDefinition.empty();
            for i = 1:numel(specs)
                defs(end+1) = bms.app.StepDefinition( ...
                    specs(i).Key, specs(i).OptField, specs(i).Label, specs(i).StatsFile, specs(i).Category); %#ok<AGROW>
            end
        end

        function def = fromLabel(label)
            label = char(label);
            defs = bms.app.StepDefinition.catalog();
            def = bms.app.StepDefinition('', '', label, '', 'analysis');
            for i = 1:numel(defs)
                if strcmp(defs(i).Label, label)
                    def = defs(i);
                    return;
                end
            end
        end

        function def = fromKey(key)
            key = char(key);
            defs = bms.app.StepDefinition.catalog();
            def = bms.app.StepDefinition(key, '', key, '', 'analysis');
            for i = 1:numel(defs)
                if strcmp(defs(i).Key, key)
                    def = defs(i);
                    return;
                end
            end
        end

        function defs = enabledFromOptions(opts)
            all = bms.module.ModuleRegistry.enabledFromOptions(opts);
            defs = bms.app.StepDefinition.empty();
            for i = 1:numel(all)
                defs(end+1) = bms.app.StepDefinition( ...
                    all(i).Key, all(i).OptField, all(i).Label, all(i).StatsFile, all(i).Category); %#ok<AGROW>
            end
        end
    end
end
