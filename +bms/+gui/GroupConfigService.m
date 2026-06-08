classdef GroupConfigService
    %GROUPCONFIGSERVICE Read, validate, and write grouped-plot config.

    methods (Static)
        function text = groupKeyRuleText()
            text = 'group_key 只能使用英文字母、数字、下划线，例如 A_3rd_span_mid_5_12；中文名称请填“显示名称”。';
        end

        function keys = editableModuleKeys(cfg)
            keys = bms.gui.ConfigEditorService.editableModuleKeys(cfg, 'groups');
        end

        function groups = readGroups(cfg, moduleKey)
            groups = bms.config.ModuleConfigResolver.resolveGroups(cfg, moduleKey);
        end

        function labels = readGroupLabels(cfg, moduleKey)
            labels = struct();
            styleKey = bms.gui.GroupConfigService.styleKey(moduleKey);
            if isstruct(cfg) && isfield(cfg, 'plot_styles') && isstruct(cfg.plot_styles) && ...
                    isfield(cfg.plot_styles, styleKey) && isstruct(cfg.plot_styles.(styleKey))
                style = cfg.plot_styles.(styleKey);
                if isfield(style, 'group_labels') && isstruct(style.group_labels)
                    labels = style.group_labels;
                end
            end
        end

        function points = availablePoints(cfg, moduleKey)
            points = {};
            spec = bms.config.ModuleConfigRegistry.fromKey(moduleKey);
            aliases = bms.config.ModuleConfigRegistry.aliasesForKey(spec.value);
            keys = unique([{spec.value, spec.point_key, spec.group_key, spec.per_point_key, spec.style_key}, aliases(:)'], 'stable');

            if isstruct(cfg) && isfield(cfg, 'points') && isstruct(cfg.points)
                for i = 1:numel(keys)
                    key = keys{i};
                    if ~isempty(key) && isfield(cfg.points, key)
                        points = [points; bms.data.PointResolver.normalize(cfg.points.(key))]; %#ok<AGROW>
                    end
                end
            end

            if isstruct(cfg) && isfield(cfg, 'per_point') && isstruct(cfg.per_point)
                for i = 1:numel(keys)
                    key = keys{i};
                    if ~isempty(key) && isfield(cfg.per_point, key) && isstruct(cfg.per_point.(key))
                        names = fieldnames(cfg.per_point.(key));
                        for j = 1:numel(names)
                            points{end+1, 1} = bms.data.PointResolver.originalId(names{j}, cfg); %#ok<AGROW>
                        end
                    end
                end
            end

            if isempty(points) && isstruct(cfg) && isfield(cfg, 'groups') && isstruct(cfg.groups)
                for i = 1:numel(keys)
                    key = keys{i};
                    if ~isempty(key) && isfield(cfg.groups, key)
                        points = [points; bms.data.PointResolver.flattenGroups(cfg.groups.(key))]; %#ok<AGROW>
                    end
                end
            end
            points = bms.data.PointResolver.uniqueText(points);
        end

        function cfg = setGroups(cfg, moduleKey, groups, labels)
            if nargin < 4
                labels = struct();
            end
            report = bms.gui.GroupConfigService.validateGroups(cfg, moduleKey, groups, labels);
            if ~report.ok
                error('GroupConfigService:InvalidGroups', '%s', strjoin(report.errors, newline));
            end

            groupKey = bms.gui.GroupConfigService.groupKey(moduleKey);
            styleKey = bms.gui.GroupConfigService.styleKey(moduleKey);
            if ~isfield(cfg, 'groups') || ~isstruct(cfg.groups)
                cfg.groups = struct();
            end
            cfg.groups.(groupKey) = groups;

            if ~isfield(cfg, 'plot_styles') || ~isstruct(cfg.plot_styles)
                cfg.plot_styles = struct();
            end
            if ~isfield(cfg.plot_styles, styleKey) || ~isstruct(cfg.plot_styles.(styleKey))
                cfg.plot_styles.(styleKey) = struct();
            end
            cfg.plot_styles.(styleKey).group_labels = bms.gui.GroupConfigService.cleanLabels(labels, groups);
        end

        function report = validateGroups(cfg, moduleKey, groups, labels)
            if nargin < 4
                labels = struct();
            end
            report = struct('ok', true, 'errors', {{}}, 'warnings', {{}});
            if ~isstruct(groups)
                report.errors{end+1} = 'groups must be a struct.';
                report.ok = false;
                return;
            end

            names = fieldnames(groups);
            if isempty(names)
                report.warnings{end+1} = '当前模块没有配置任何组图分组。';
            end
            knownPoints = bms.gui.GroupConfigService.availablePoints(cfg, moduleKey);
            seen = {};
            for i = 1:numel(names)
                key = char(string(names{i}));
                if isempty(strtrim(key))
                    report.errors{end+1} = 'group_key 不能为空。'; %#ok<AGROW>
                elseif ~bms.gui.GroupConfigService.isValidGroupKey(key)
                    report.errors{end+1} = sprintf('group_key "%s" 不合法；只能使用英文字母、数字、下划线。', key); %#ok<AGROW>
                elseif any(strcmp(seen, key))
                    report.errors{end+1} = sprintf('group_key "%s" 重复。', key); %#ok<AGROW>
                end
                seen{end+1} = key; %#ok<AGROW>

                rawPts = bms.gui.GroupConfigService.rawPointList(groups.(names{i}));
                pts = bms.data.PointResolver.normalize(rawPts);
                if isempty(rawPts)
                    report.errors{end+1} = sprintf('group_key "%s" 组内测点不能为空。', key); %#ok<AGROW>
                end
                if numel(rawPts) ~= numel(unique(rawPts, 'stable'))
                    report.errors{end+1} = sprintf('group_key "%s" 组内存在重复测点。', key); %#ok<AGROW>
                end
                if ~isempty(knownPoints)
                    for j = 1:numel(pts)
                        if ~bms.gui.GroupConfigService.pointIsKnown(pts{j}, knownPoints, cfg)
                            report.errors{end+1} = sprintf('group_key "%s" 引用了未知测点 "%s"。', key, pts{j}); %#ok<AGROW>
                        end
                    end
                end
            end

            if isstruct(labels)
                labelKeys = fieldnames(labels);
                for i = 1:numel(labelKeys)
                    if ~any(strcmp(names, labelKeys{i}))
                        report.warnings{end+1} = sprintf('显示名称 "%s" 没有对应 group_key，保存时会清理。', labelKeys{i}); %#ok<AGROW>
                    end
                end
            end
            report.ok = isempty(report.errors);
        end

        function report = validateGroupRows(cfg, moduleKey, groupKeys, pointLists, groupLabels)
            if nargin < 5
                groupLabels = cell(size(groupKeys));
            end
            report = struct('ok', true, 'errors', {{}}, 'warnings', {{}});
            keys = cellstr(string(groupKeys(:)));
            seen = {};
            for i = 1:numel(keys)
                key = strtrim(keys{i});
                if isempty(key)
                    report.errors{end+1} = sprintf('第 %d 行 group_key 不能为空。', i); %#ok<AGROW>
                elseif ~bms.gui.GroupConfigService.isValidGroupKey(key)
                    report.errors{end+1} = sprintf('第 %d 行 group_key "%s" 不合法；只能使用英文字母、数字、下划线。', i, key); %#ok<AGROW>
                elseif any(strcmp(seen, key))
                    report.errors{end+1} = sprintf('第 %d 行 group_key "%s" 重复。', i, key); %#ok<AGROW>
                end
                seen{end+1} = key; %#ok<AGROW>
            end
            if ~isempty(report.errors)
                report.ok = false;
                return;
            end

            groups = bms.gui.GroupConfigService.makeGroups(keys, pointLists);
            labels = bms.gui.GroupConfigService.makeLabels(keys, groupLabels);
            structReport = bms.gui.GroupConfigService.validateGroups(cfg, moduleKey, groups, labels);
            report.errors = [report.errors, structReport.errors];
            report.warnings = [report.warnings, structReport.warnings];
            report.ok = isempty(report.errors);
        end

        function tf = isValidGroupKey(key)
            key = char(string(key));
            tf = ~isempty(regexp(key, '^[A-Za-z0-9_]+$', 'once'));
        end

        function groups = makeGroups(groupKeys, pointLists)
            groups = struct();
            for i = 1:numel(groupKeys)
                key = strtrim(char(string(groupKeys{i})));
                if isempty(key)
                    continue;
                end
                pts = {};
                if i <= numel(pointLists)
                    pts = bms.data.PointResolver.normalize(pointLists{i});
                end
                groups.(key) = pts;
            end
        end

        function labels = makeLabels(groupKeys, groupLabels)
            labels = struct();
            for i = 1:numel(groupKeys)
                if i > numel(groupLabels)
                    continue;
                end
                key = strtrim(char(string(groupKeys{i})));
                label = strtrim(char(string(groupLabels{i})));
                if ~isempty(key) && ~isempty(label)
                    labels.(key) = label;
                end
            end
        end

        function labels = cleanLabels(labels, groups)
            cleaned = struct();
            if ~isstruct(labels)
                labels = cleaned;
                return;
            end
            groupNames = fieldnames(groups);
            labelKeys = fieldnames(labels);
            for i = 1:numel(labelKeys)
                key = labelKeys{i};
                if any(strcmp(groupNames, key))
                    value = labels.(key);
                    if ischar(value) || (isstring(value) && isscalar(value))
                        value = char(string(value));
                        if ~isempty(strtrim(value))
                            cleaned.(key) = value;
                        end
                    end
                end
            end
            labels = cleaned;
        end

        function key = groupKey(moduleKey)
            spec = bms.config.ModuleConfigRegistry.fromKey(moduleKey);
            key = spec.group_key;
            if isempty(key)
                key = spec.value;
            end
        end

        function key = styleKey(moduleKey)
            spec = bms.config.ModuleConfigRegistry.fromKey(moduleKey);
            key = spec.style_key;
            if isempty(key)
                key = spec.value;
            end
        end
    end

    methods (Static, Access = private)
        function pts = rawPointList(value)
            pts = {};
            if ischar(value) || (isstring(value) && isscalar(value))
                value = cellstr(string(value));
            end
            if isstring(value)
                value = cellstr(value(:));
            end
            if iscell(value)
                for i = 1:numel(value)
                    item = value{i};
                    if ischar(item) || (isstring(item) && isscalar(item))
                        item = strtrim(char(string(item)));
                        if ~isempty(item)
                            pts{end+1, 1} = item; %#ok<AGROW>
                        end
                    end
                end
            end
        end

        function tf = pointIsKnown(pointId, knownPoints, cfg)
            tf = any(strcmp(knownPoints, pointId));
            if tf
                return;
            end
            candidates = bms.data.PointResolver.keyCandidates(pointId, cfg);
            for i = 1:numel(candidates)
                if any(strcmp(knownPoints, candidates{i}))
                    tf = true;
                    return;
                end
            end
            for i = 1:numel(knownPoints)
                knownCandidates = bms.data.PointResolver.keyCandidates(knownPoints{i}, cfg);
                if any(strcmp(knownCandidates, pointId))
                    tf = true;
                    return;
                end
            end
        end
    end
end
