classdef AlarmBoundsEditorService
    %ALARMBOUNDSEDITORSERVICE Expand and edit per-point alarm_bounds.

    methods (Static)
        function rows = rows(cfg, moduleSpec)
            spec = bms.config.ModuleConfigRegistry.normalize(moduleSpec);
            pointIds = bms.gui.AlarmBoundsEditorService.modulePointIds(cfg, spec);
            rows = cell(0, 5);
            for i = 1:numel(pointIds)
                pointId = pointIds{i};
                [bounds, source] = bms.gui.AlarmBoundsEditorService.resolveBounds(cfg, spec, pointId);
                if isempty(bounds)
                    continue;
                end
                rows = [rows; bms.gui.AlarmBoundsEditorService.boundsToRows(pointId, bounds, source)]; %#ok<AGROW>
            end
        end

        function cfg = applyRows(cfg, moduleSpec, rows)
            spec = bms.config.ModuleConfigRegistry.normalize(moduleSpec);
            key = char(string(spec.per_point_key));
            if isempty(key)
                error('bms:gui:AlarmBoundsEditorService:NoPerPointKey', ...
                    'Module does not have a per_point key.');
            end
            if isempty(rows)
                rows = cell(0, 5);
            end
            if istable(rows)
                rows = table2cell(rows);
            end
            if ~iscell(rows)
                error('bms:gui:AlarmBoundsEditorService:InvalidRows', ...
                    'Alarm bounds rows must be a cell array.');
            end
            if size(rows, 2) < 4
                error('bms:gui:AlarmBoundsEditorService:InvalidRows', ...
                    'Alarm bounds rows must contain point_id, level, lower, and upper.');
            end

            hasExistingPerPoint = isfield(cfg, 'per_point') && isstruct(cfg.per_point) && ...
                isfield(cfg.per_point, key) && isstruct(cfg.per_point.(key));
            if isempty(rows) && ~hasExistingPerPoint
                return;
            end

            if ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point)
                cfg.per_point = struct();
            end
            if ~isfield(cfg.per_point, key) || ~isstruct(cfg.per_point.(key))
                cfg.per_point.(key) = struct();
            end
            perStruct = cfg.per_point.(key);

            managedKeys = bms.gui.AlarmBoundsEditorService.managedPointKeys(cfg, spec);
            for i = 1:numel(managedKeys)
                safeId = managedKeys{i};
                if isfield(perStruct, safeId) && isstruct(perStruct.(safeId)) && ...
                        isfield(perStruct.(safeId), 'alarm_bounds')
                    perStruct.(safeId) = rmfield(perStruct.(safeId), 'alarm_bounds');
                    if isempty(fieldnames(perStruct.(safeId)))
                        perStruct = rmfield(perStruct, safeId);
                    end
                end
            end

            boundsByPoint = struct();
            originalByPoint = struct();
            seen = struct();
            for i = 1:size(rows, 1)
                pointId = bms.gui.AlarmBoundsEditorService.toChar(rows{i, 1});
                level = bms.gui.AlarmBoundsEditorService.normalizeLevel(rows{i, 2});
                lower = bms.gui.AlarmBoundsEditorService.parseNumber(rows{i, 3}, 'lower');
                upper = bms.gui.AlarmBoundsEditorService.parseNumber(rows{i, 4}, 'upper');
                if isempty(pointId)
                    error('bms:gui:AlarmBoundsEditorService:EmptyPointId', ...
                        'point_id cannot be empty.');
                end
                if upper <= lower
                    error('bms:gui:AlarmBoundsEditorService:InvalidBounds', ...
                        'Upper alarm bound must be greater than lower alarm bound.');
                end

                safeId = bms.gui.AlarmBoundsEditorService.configKeyForPoint(cfg, key, pointId);
                seenKey = [safeId '__' level];
                if isfield(seen, seenKey)
                    error('bms:gui:AlarmBoundsEditorService:DuplicateLevel', ...
                        'Duplicate alarm level for the same point: %s %s.', pointId, level);
                end
                seen.(seenKey) = true;
                if ~isfield(boundsByPoint, safeId) || ~isstruct(boundsByPoint.(safeId))
                    boundsByPoint.(safeId) = struct();
                    originalByPoint.(safeId) = pointId;
                end
                boundsByPoint.(safeId).(level) = sort([lower, upper]);
            end

            safeIds = fieldnames(boundsByPoint);
            for i = 1:numel(safeIds)
                safeId = safeIds{i};
                if ~isfield(perStruct, safeId) || ~isstruct(perStruct.(safeId))
                    perStruct.(safeId) = struct();
                end
                perStruct.(safeId).alarm_bounds = boundsByPoint.(safeId);
            end
            cfg.per_point.(key) = perStruct;

            cfg = bms.gui.AlarmBoundsEditorService.updateNameMap(cfg, originalByPoint);
        end

        function pointIds = modulePointIds(cfg, moduleSpec)
            spec = bms.config.ModuleConfigRegistry.normalize(moduleSpec);
            pointIds = bms.config.ModuleConfigResolver.resolvePoints(cfg, spec, {});
            key = char(string(spec.per_point_key));
            if isstruct(cfg) && isfield(cfg, 'per_point') && isstruct(cfg.per_point) && ...
                    ~isempty(key) && isfield(cfg.per_point, key) && isstruct(cfg.per_point.(key))
                names = fieldnames(cfg.per_point.(key));
                for i = 1:numel(names)
                    pointIds{end+1, 1} = bms.data.PointResolver.originalId(names{i}, cfg); %#ok<AGROW>
                end
            end
            pointIds = bms.data.PointResolver.uniqueText(pointIds);
        end
    end

    methods (Static, Access = private)
        function [bounds, source] = resolveBounds(cfg, spec, pointId)
            bounds = [];
            source = '';
            key = char(string(spec.per_point_key));
            if isstruct(cfg) && isfield(cfg, 'per_point') && isstruct(cfg.per_point) && ...
                    isfield(cfg.per_point, key) && isstruct(cfg.per_point.(key))
                [ok, pointCfg] = bms.data.PointResolver.getPointConfig(cfg.per_point.(key), pointId, cfg);
                if ok && isstruct(pointCfg) && isfield(pointCfg, 'alarm_bounds') && ...
                        isstruct(pointCfg.alarm_bounds) && ~isempty(fieldnames(pointCfg.alarm_bounds))
                    bounds = pointCfg.alarm_bounds;
                    source = 'per_point';
                    return;
                end
            end
            if isstruct(cfg) && isfield(cfg, 'defaults') && isstruct(cfg.defaults) && ...
                    isfield(cfg.defaults, key) && isstruct(cfg.defaults.(key)) && ...
                    isfield(cfg.defaults.(key), 'alarm_bounds') && isstruct(cfg.defaults.(key).alarm_bounds)
                bounds = cfg.defaults.(key).alarm_bounds;
                source = 'defaults';
            end
        end

        function rows = boundsToRows(pointId, bounds, source)
            rows = cell(0, 5);
            names = fieldnames(bounds);
            names = bms.gui.AlarmBoundsEditorService.sortLevels(names);
            for i = 1:numel(names)
                level = names{i};
                vals = bounds.(level);
                if ~isnumeric(vals) || numel(vals) ~= 2
                    continue;
                end
                vals = sort(double(vals(:)).');
                if any(~isfinite(vals))
                    continue;
                end
                rows(end+1, :) = {pointId, level, vals(1), vals(2), source}; %#ok<AGROW>
            end
        end

        function names = sortLevels(names)
            [~, idx] = sort(cellfun(@(x)bms.gui.AlarmBoundsEditorService.levelOrder(x), names));
            names = names(idx);
        end

        function n = levelOrder(name)
            token = regexp(char(string(name)), '^level(\d+)$', 'tokens', 'once');
            if isempty(token)
                n = inf;
            else
                n = str2double(token{1});
            end
        end

        function keys = managedPointKeys(cfg, spec)
            points = bms.gui.AlarmBoundsEditorService.modulePointIds(cfg, spec);
            keys = cell(size(points));
            key = char(string(spec.per_point_key));
            for i = 1:numel(points)
                keys{i} = bms.gui.AlarmBoundsEditorService.configKeyForPoint(cfg, key, points{i});
            end
            keys = bms.data.PointResolver.uniqueText(keys);
        end

        function safeId = configKeyForPoint(cfg, perPointKey, pointId)
            pointId = char(string(pointId));
            if isstruct(cfg) && isfield(cfg, 'per_point') && isstruct(cfg.per_point) && ...
                    isfield(cfg.per_point, perPointKey) && isstruct(cfg.per_point.(perPointKey))
                [ok, ~, existingKey] = bms.data.PointResolver.getPointConfig(cfg.per_point.(perPointKey), pointId, cfg);
                if ok
                    safeId = existingKey;
                    return;
                end
            end
            safeId = bms.data.PointResolver.configKey(pointId);
        end

        function cfg = updateNameMap(cfg, originalByPoint)
            if isempty(fieldnames(originalByPoint))
                return;
            end
            if ~isfield(cfg, 'name_map_global') || ~isstruct(cfg.name_map_global)
                cfg.name_map_global = struct();
            end
            names = fieldnames(originalByPoint);
            for i = 1:numel(names)
                safeId = names{i};
                originalId = originalByPoint.(safeId);
                if ~strcmp(safeId, originalId)
                    cfg.name_map_global.(safeId) = originalId;
                end
            end
        end

        function level = normalizeLevel(value)
            level = strtrim(bms.gui.AlarmBoundsEditorService.toChar(value));
            if isempty(regexp(level, '^level[1-9]\d*$', 'once'))
                error('bms:gui:AlarmBoundsEditorService:InvalidLevel', ...
                    'Alarm level must use level1, level2, level3 ... format.');
            end
        end

        function value = parseNumber(raw, name)
            if isnumeric(raw) && isscalar(raw)
                value = double(raw);
            else
                value = str2double(strtrim(bms.gui.AlarmBoundsEditorService.toChar(raw)));
            end
            if ~isfinite(value)
                error('bms:gui:AlarmBoundsEditorService:InvalidNumber', ...
                    'Alarm bound %s must be a finite number.', name);
            end
        end

        function txt = toChar(value)
            if isempty(value)
                txt = '';
            elseif ischar(value)
                txt = value;
            elseif isstring(value)
                txt = char(value);
            elseif isnumeric(value)
                txt = num2str(value);
            else
                txt = char(string(value));
            end
        end
    end
end
