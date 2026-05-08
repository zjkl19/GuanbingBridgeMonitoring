classdef ConfigStore
    %CONFIGSTORE Safe config load/save facade for GUI tabs and scripts.

    methods (Static)
        function cfg = load(path)
            if nargin < 1 || isempty(path)
                cfg = load_config();
            else
                cfg = load_config(path);
            end
            cfg = bms.config.ConfigMigrator.migrate(cfg);
        end

        function saveGuarded(cfg, filepath, makeBackup)
            if nargin < 3, makeBackup = true; end
            oldCfg = [];
            if isfile(filepath)
                oldCfg = bms.core.ConfigStore.readJson(filepath);
            end
            bms.core.ConfigStore.validateNoAccidentalDrop(oldCfg, cfg);
            save_config(cfg, filepath, makeBackup);
            newCfg = bms.core.ConfigStore.readJson(filepath);
            bms.core.ConfigStore.validateNoAccidentalDrop(oldCfg, newCfg);
        end

        function report = saveGuardedWithReport(cfg, filepath, makeBackup)
            if nargin < 3, makeBackup = true; end
            oldCfg = [];
            if isfile(filepath)
                oldCfg = bms.core.ConfigStore.readJson(filepath);
            end
            bms.core.ConfigStore.validateNoAccidentalDrop(oldCfg, cfg);
            save_config(cfg, filepath, makeBackup);
            newCfg = bms.core.ConfigStore.readJson(filepath);
            bms.core.ConfigStore.validateNoAccidentalDrop(oldCfg, newCfg);
            report = bms.core.ConfigStore.changeReport(oldCfg, newCfg);
        end

        function cfg = patchFile(filepath, operations, makeBackup)
            if nargin < 3, makeBackup = true; end
            if ~isfile(filepath)
                error('BMS:Config:MissingFile', 'Config file not found: %s', filepath);
            end
            cfg = bms.config.ConfigMigrator.migrate(bms.core.ConfigStore.readJson(filepath));
            cfg = bms.config.ConfigPatch.apply(cfg, operations);
            bms.core.ConfigStore.saveGuarded(cfg, filepath, makeBackup);
        end

        function [cfg, report] = patchFileWithReport(filepath, operations, makeBackup)
            if nargin < 3, makeBackup = true; end
            if ~isfile(filepath)
                error('BMS:Config:MissingFile', 'Config file not found: %s', filepath);
            end
            oldCfg = bms.config.ConfigMigrator.migrate(bms.core.ConfigStore.readJson(filepath));
            cfg = bms.config.ConfigPatch.apply(oldCfg, operations);
            report = bms.core.ConfigStore.saveGuardedWithReport(cfg, filepath, makeBackup);
        end

        function result = validate(cfg)
            result = bms.config.SchemaValidator.validateDetailed(cfg);
        end

        function report = changeReport(oldCfg, newCfg)
            changes = bms.core.ConfigStore.diffPaths(oldCfg, newCfg, '', 200);
            report = struct();
            report.changed_count = numel(changes);
            report.changed_paths = changes;
            report.truncated = numel(changes) >= 200;
        end

        function changes = diffPaths(oldValue, newValue, prefix, limit)
            if nargin < 3, prefix = ''; end
            if nargin < 4, limit = 200; end
            changes = {};
            if numel(changes) >= limit
                return;
            end
            if isstruct(oldValue) && isstruct(newValue) && isscalar(oldValue) && isscalar(newValue)
                oldFields = fieldnames(oldValue);
                newFields = fieldnames(newValue);
                allFields = unique([oldFields; newFields], 'stable');
                for i = 1:numel(allFields)
                    if numel(changes) >= limit, return; end
                    f = allFields{i};
                    childPath = bms.core.ConfigStore.joinPath(prefix, f);
                    inOld = isfield(oldValue, f);
                    inNew = isfield(newValue, f);
                    if ~inOld || ~inNew
                        changes{end+1} = childPath; %#ok<AGROW>
                    else
                        sub = bms.core.ConfigStore.diffPaths(oldValue.(f), newValue.(f), childPath, limit - numel(changes));
                        changes = [changes, sub]; %#ok<AGROW>
                    end
                end
            elseif ~bms.core.ConfigStore.valuesEqual(oldValue, newValue)
                if isempty(prefix), prefix = '<root>'; end
                changes{end+1} = prefix;
            end
        end

        function tf = valuesEqual(a, b)
            try
                tf = isequaln(a, b);
            catch
                tf = false;
            end
        end

        function out = joinPath(prefix, field)
            if isempty(prefix)
                out = field;
            else
                out = [prefix '.' field];
            end
        end

        function validateNoAccidentalDrop(oldCfg, newCfg)
            if isempty(oldCfg) || ~isstruct(oldCfg) || ~isstruct(newCfg)
                return;
            end
            volatile = {'source','warnings','name_map_global'};
            oldTop = setdiff(fieldnames(oldCfg), volatile, 'stable');
            newTop = setdiff(fieldnames(newCfg), volatile, 'stable');
            missingTop = setdiff(oldTop, newTop, 'stable');
            if ~isempty(missingTop)
                error('BMS:Config:FieldDropped', ...
                    'Config save would drop top-level fields: %s', strjoin(missingTop, ', '));
            end
            bms.core.ConfigStore.checkPerPointDrops(oldCfg, newCfg);
        end

        function checkPerPointDrops(oldCfg, newCfg)
            if ~isfield(oldCfg, 'per_point') || ~isstruct(oldCfg.per_point)
                return;
            end
            if ~isfield(newCfg, 'per_point') || ~isstruct(newCfg.per_point)
                error('BMS:Config:FieldDropped', 'Config save would drop per_point.');
            end
            modules = fieldnames(oldCfg.per_point);
            for i = 1:numel(modules)
                module = modules{i};
                if ~isfield(newCfg.per_point, module) || ~isstruct(newCfg.per_point.(module))
                    error('BMS:Config:FieldDropped', 'Config save would drop per_point.%s.', module);
                end
                oldPts = oldCfg.per_point.(module);
                newPts = newCfg.per_point.(module);
                if ~isstruct(oldPts), continue; end
                points = fieldnames(oldPts);
                for j = 1:numel(points)
                    point = points{j};
                    oldPoint = oldPts.(point);
                    if ~isstruct(oldPoint), continue; end
                    if isfield(oldPoint, 'offset_correction')
                        if ~isfield(newPts, point) || ~isfield(newPts.(point), 'offset_correction')
                            error('BMS:Config:ProtectedFieldDropped', ...
                                'Config save would drop per_point.%s.%s.offset_correction.', module, point);
                        end
                    end
                end
            end
        end

        function data = readJson(path)
            txt = fileread(path);
            if ~isempty(txt) && double(txt(1)) == 65279
                txt = txt(2:end);
            end
            data = jsondecode(txt);
        end
    end
end
