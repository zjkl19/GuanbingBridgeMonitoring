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

        function cfg = patchFile(filepath, operations, makeBackup)
            if nargin < 3, makeBackup = true; end
            if ~isfile(filepath)
                error('BMS:Config:MissingFile', 'Config file not found: %s', filepath);
            end
            cfg = bms.config.ConfigMigrator.migrate(bms.core.ConfigStore.readJson(filepath));
            cfg = bms.config.ConfigPatch.apply(cfg, operations);
            bms.core.ConfigStore.saveGuarded(cfg, filepath, makeBackup);
        end

        function result = validate(cfg)
            result = bms.config.SchemaValidator.validateDetailed(cfg);
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
