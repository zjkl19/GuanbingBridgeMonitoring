classdef PlotWarningLineResolver
    %PLOTWARNINGLINERESOLVER Resolve plot warning-line config for GUI/reports.
    %
    % This service intentionally keeps legacy config formats readable:
    % - plot_styles.<module>.warn_lines / rms_warn_lines / group_warn_lines
    % - per_point.<module>.*.alarm_bounds
    % - eq_params/per_point.eq.*.alarm_levels

    methods (Static)
        function preview = tablePreview(cfg, moduleSpec, style, fieldName, varargin)
            spec = bms.analyzer.PlotWarningLineResolver.normalizeSpec(moduleSpec);
            if nargin < 4 || isempty(fieldName)
                fieldName = 'warn_lines';
            end
            fieldName = char(string(fieldName));
            expandPoints = bms.analyzer.PlotWarningLineResolver.parseExpandPoints(varargin{:});

            if isstruct(style) && isfield(style, fieldName) && ~isempty(style.(fieldName))
                [rows, isMap] = bms.analyzer.PlotWarningLineResolver.warnLinesToRows(style.(fieldName));
                if isMap
                    preview = bms.analyzer.PlotWarningLineResolver.previewStruct(rows, true, ...
                        '只读预览：当前字段是分组映射配置，表格已展开显示；如需改成统一自定义线，可点“改为自定义预警线”。', ...
                        'explicit_map');
                else
                    preview = bms.analyzer.PlotWarningLineResolver.previewStruct(rows, false, ...
                        '正在编辑当前模块 plot_styles 中显式配置的图上预警线。', ...
                        'explicit');
                end
                return;
            end

            [rows, reason, source] = bms.analyzer.PlotWarningLineResolver.deriveRows(cfg, spec, style, fieldName, expandPoints);
            if isempty(rows)
                preview = bms.analyzer.PlotWarningLineResolver.previewStruct(rows, false, ...
                    '当前字段没有显式图上预警线配置，也没有可从测点阈值推导出的统一预警线。', ...
                    'none');
            else
                preview = bms.analyzer.PlotWarningLineResolver.previewStruct(rows, true, ...
                    ['只读预览：' reason '；如需修改阈值本身，请到阈值配置/滤波后二次清洗页；如需画统一自定义线，可点“改为自定义预警线”。'], ...
                    source);
            end
        end

        function [rows, isMap] = warnLinesToRows(lines, scope)
            if nargin < 2
                scope = '';
            end
            rows = cell(0, 6);
            isMap = false;
            if isstruct(lines) && ~bms.analyzer.PlotWarningLineResolver.isWarnLineStruct(lines)
                names = fieldnames(lines);
                isMap = true;
                for i = 1:numel(names)
                    [partRows, ~] = bms.analyzer.PlotWarningLineResolver.warnLinesToRows(lines.(names{i}), names{i});
                    rows = [rows; partRows]; %#ok<AGROW>
                end
                return;
            end

            lines = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(lines);
            for i = 1:numel(lines)
                item = lines{i};
                if ~isstruct(item)
                    continue;
                end
                y = [];
                if isfield(item, 'y') && isnumeric(item.y) && isscalar(item.y)
                    y = item.y;
                end
                label = bms.analyzer.StructuralPlotConfigService.warnLabel(item);
                if isempty(label) && isfield(item, 'label')
                    label = bms.analyzer.PlotWarningLineResolver.toChar(item.label);
                end
                if ~isempty(scope)
                    if isempty(label)
                        label = char(string(scope));
                    else
                        label = sprintf('%s | %s', char(string(scope)), label);
                    end
                end
                [r, g, b] = bms.analyzer.PlotWarningLineResolver.colorToRgbFields( ...
                    bms.analyzer.PlotWarningLineResolver.getField(item, 'color', []));
                lineStyle = bms.analyzer.PlotWarningLineResolver.getField(item, 'linestyle', '--');
                rows(end+1, :) = {y, label, r, g, b, bms.analyzer.PlotWarningLineResolver.toChar(lineStyle)}; %#ok<AGROW>
            end
        end

        function lines = earthquakeAlarmLines(params)
            levels = [];
            if isstruct(params) && isfield(params, 'alarm_levels') && ~isempty(params.alarm_levels)
                levels = double(params.alarm_levels(:))';
            end
            levels = sort(levels(isfinite(levels)));
            labels = {'E1地震作用加速度峰值', 'E2地震作用加速度峰值'};
            colors = [1 0.85 0; 0.85 0.1 0.1];
            lines = {};
            for i = 1:numel(levels)
                label = sprintf('地震动预警值 %.6g', levels(i));
                if i <= numel(labels)
                    label = sprintf('%s %.6g', labels{i}, levels(i));
                end
                color = [0.72 0.50 0.00];
                if i <= size(colors, 1)
                    color = colors(i, :);
                end
                lines{end+1, 1} = struct('y', levels(i), 'label', label, ...
                    'color', color, 'linestyle', '--'); %#ok<AGROW>
            end
        end
    end

    methods (Static, Access = private)
        function preview = previewStruct(rows, isPreview, hintText, source)
            preview = struct();
            preview.rows = rows;
            preview.is_preview = logical(isPreview);
            preview.hint = char(string(hintText));
            preview.source = char(string(source));
        end

        function spec = normalizeSpec(moduleSpec)
            spec = bms.config.ModuleConfigRegistry.normalize(moduleSpec);
        end

        function expandPoints = parseExpandPoints(varargin)
            expandPoints = false;
            if isempty(varargin)
                return;
            end
            if isscalar(varargin) && (islogical(varargin{1}) || isnumeric(varargin{1}))
                expandPoints = logical(varargin{1});
                return;
            end
            if mod(numel(varargin), 2) ~= 0
                error('BMS:PlotWarningLineResolver:InvalidOptions', 'Options must be name-value pairs.');
            end
            for i = 1:2:numel(varargin)
                key = lower(char(string(varargin{i})));
                switch key
                    case {'expandpoints', 'expand_points'}
                        expandPoints = logical(varargin{i+1});
                    otherwise
                        error('BMS:PlotWarningLineResolver:InvalidOption', 'Unknown option: %s', key);
                end
            end
        end

        function [rows, reason, source] = deriveRows(cfg, spec, style, fieldName, expandPoints)
            rows = cell(0, 6);
            reason = '';
            source = 'none';
            if ~isstruct(cfg)
                return;
            end

            if strcmp(spec.value, 'earthquake') && strcmp(fieldName, 'warn_lines')
                [rows, reason] = bms.analyzer.PlotWarningLineResolver.deriveEarthquakeRows(cfg, expandPoints);
                source = 'eq_alarm_levels';
                return;
            end

            warnKey = char(string(spec.per_point_key));
            if strcmp(fieldName, 'group_warn_lines')
                [rows, reason] = bms.analyzer.PlotWarningLineResolver.deriveGroupRows(cfg, warnKey, style, spec, expandPoints);
                source = 'per_point_group_alarm_bounds';
            elseif strcmp(fieldName, 'warn_lines')
                [rows, reason] = bms.analyzer.PlotWarningLineResolver.derivePointRows(cfg, warnKey, style, spec, expandPoints);
                source = 'per_point_alarm_bounds';
            end
        end

        function [rows, reason] = deriveEarthquakeRows(cfg, expandPoints)
            rows = cell(0, 6);
            reason = '';
            points = bms.config.ModuleConfigResolver.resolvePoints(cfg, 'earthquake', {});
            if isempty(points)
                points = {''};
            end

            if expandPoints
                for i = 1:numel(points)
                    pid = points{i};
                    params = bms.analyzer.EarthquakeAnalysisPipeline.params(cfg, pid);
                    lines = bms.analyzer.PlotWarningLineResolver.earthquakeAlarmLines(params);
                    if isempty(lines)
                        continue;
                    end
                    scope = pid;
                    if isempty(scope)
                        scope = 'global';
                    end
                    [partRows, ~] = bms.analyzer.PlotWarningLineResolver.warnLinesToRows(lines, scope);
                    rows = [rows; partRows]; %#ok<AGROW>
                end
                if ~isempty(rows)
                    reason = 'earthquake alarm lines expanded by point';
                end
                return;
            end

            grouped = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for i = 1:numel(points)
                pid = points{i};
                params = bms.analyzer.EarthquakeAnalysisPipeline.params(cfg, pid);
                lines = bms.analyzer.PlotWarningLineResolver.earthquakeAlarmLines(params);
                sig = bms.analyzer.PlotWarningLineResolver.warnLineSignature(lines);
                if isempty(sig)
                    continue;
                end
                if isKey(grouped, sig)
                    entry = grouped(sig);
                else
                    entry = struct('count', 0, 'samplePoint', pid, 'lines', {lines});
                end
                entry.count = entry.count + 1;
                grouped(sig) = entry;
            end

            sigs = keys(grouped);
            for i = 1:numel(sigs)
                entry = grouped(sigs{i});
                scope = entry.samplePoint;
                if isempty(scope)
                    scope = '全局';
                elseif entry.count > 1
                    scope = sprintf('%s 等%d个测点', entry.samplePoint, entry.count);
                end
                [partRows, ~] = bms.analyzer.PlotWarningLineResolver.warnLinesToRows(entry.lines, scope);
                rows = [rows; partRows]; %#ok<AGROW>
            end
            if ~isempty(rows)
                reason = '地震动图上预警线由 eq_params/per_point.eq.*.alarm_levels 推导';
            end
        end

        function [rows, reason] = derivePointRows(cfg, warnKey, style, spec, expandPoints)
            rows = cell(0, 6);
            reason = '';
            points = bms.analyzer.PlotWarningLineResolver.modulePoints(cfg, spec);
            if isempty(points)
                return;
            end

            if expandPoints
                for i = 1:numel(points)
                    pid = points{i};
                    lines = bms.analyzer.StructuralPlotConfigService.resolveWarnLines(style, cfg, warnKey, pid);
                    lines = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(lines);
                    if isempty(lines)
                        continue;
                    end
                    [partRows, ~] = bms.analyzer.PlotWarningLineResolver.warnLinesToRows(lines, pid);
                    rows = [rows; partRows]; %#ok<AGROW>
                end
                if ~isempty(rows)
                    reason = sprintf('per_point.%s.*.alarm_bounds expanded by point', warnKey);
                end
                return;
            end

            grouped = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for i = 1:numel(points)
                pid = points{i};
                lines = bms.analyzer.StructuralPlotConfigService.resolveWarnLines(style, cfg, warnKey, pid);
                lines = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(lines);
                if isempty(lines)
                    continue;
                end
                sig = bms.analyzer.PlotWarningLineResolver.warnLineSignature(lines);
                if isempty(sig)
                    continue;
                end
                if isKey(grouped, sig)
                    entry = grouped(sig);
                else
                    entry = struct('count', 0, 'samplePoint', pid, 'lines', {lines});
                end
                entry.count = entry.count + 1;
                grouped(sig) = entry;
            end

            sigs = keys(grouped);
            for i = 1:numel(sigs)
                entry = grouped(sigs{i});
                scope = entry.samplePoint;
                if entry.count > 1
                    scope = sprintf('%s 等%d个测点', entry.samplePoint, entry.count);
                end
                [partRows, ~] = bms.analyzer.PlotWarningLineResolver.warnLinesToRows(entry.lines, scope);
                rows = [rows; partRows]; %#ok<AGROW>
            end
            if ~isempty(rows)
                reason = sprintf('当前模块未显式配置 warn_lines，表内数值由 per_point.%s.*.alarm_bounds 推导', warnKey);
            end
        end

        function [rows, reason] = deriveGroupRows(cfg, warnKey, style, spec, expandPoints)
            rows = cell(0, 6);
            reason = '';
            entries = bms.analyzer.PlotWarningLineResolver.moduleGroupEntries(cfg, spec);
            if isempty(entries)
                return;
            end

            for i = 1:numel(entries)
                lines = bms.analyzer.PlotWarningLineResolver.commonWarnLinesForPoints( ...
                    cfg, warnKey, style, entries(i).points);
                if isempty(lines)
                    continue;
                end
                if expandPoints
                    for j = 1:numel(entries(i).points)
                        scope = sprintf('%s/%s', entries(i).name, entries(i).points{j});
                        [partRows, ~] = bms.analyzer.PlotWarningLineResolver.warnLinesToRows(lines, scope);
                        rows = [rows; partRows]; %#ok<AGROW>
                    end
                else
                    [partRows, ~] = bms.analyzer.PlotWarningLineResolver.warnLinesToRows(lines, entries(i).name);
                    rows = [rows; partRows]; %#ok<AGROW>
                end
            end
            if ~isempty(rows)
                reason = sprintf('当前模块未显式配置 group_warn_lines，表内数值由 groups.%s 内测点的 alarm_bounds 推导', ...
                    bms.analyzer.PlotWarningLineResolver.groupKey(cfg, spec));
            end
        end

        function points = modulePoints(cfg, spec)
            key = char(string(spec.point_key));
            points = bms.data.PointResolver.fromConfig(cfg, key, {});
            if isempty(points)
                entries = bms.analyzer.PlotWarningLineResolver.moduleGroupEntries(cfg, spec);
                for i = 1:numel(entries)
                    points = [points; entries(i).points(:)]; %#ok<AGROW>
                end
            end
            if ~isempty(points)
                points = unique(points(:), 'stable');
            end
        end

        function entries = moduleGroupEntries(cfg, spec)
            entries = struct('name', {}, 'points', {});
            groups = bms.config.ModuleConfigResolver.resolveGroups(cfg, spec);
            if ~isstruct(groups) || isempty(fieldnames(groups))
                return;
            end
            names = fieldnames(groups);
            for i = 1:numel(names)
                pts = bms.data.PointResolver.normalize(groups.(names{i}));
                if isempty(pts), continue; end
                entries(end+1).name = names{i}; %#ok<AGROW>
                entries(end).points = pts(:);
            end
        end

        function gkey = groupKey(cfg, spec)
            aliases = bms.config.ModuleConfigResolver.groupAliases(spec);
            gkey = aliases{1};
            if isstruct(cfg) && isfield(cfg, 'groups') && isstruct(cfg.groups)
                for i = 1:numel(aliases)
                    if isfield(cfg.groups, aliases{i})
                        gkey = aliases{i};
                        return;
                    end
                end
            end
        end

        function lines = commonWarnLinesForPoints(cfg, warnKey, style, points)
            lines = {};
            if isempty(points)
                return;
            end
            firstSig = '';
            for i = 1:numel(points)
                current = bms.analyzer.StructuralPlotConfigService.resolveWarnLines(style, cfg, warnKey, points{i});
                current = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(current);
                if isempty(current)
                    lines = {};
                    return;
                end
                sig = bms.analyzer.PlotWarningLineResolver.warnLineSignature(current);
                if i == 1
                    firstSig = sig;
                    lines = current;
                elseif ~strcmp(firstSig, sig)
                    lines = {};
                    return;
                end
            end
        end

        function sig = warnLineSignature(lines)
            ys = [];
            lines = bms.analyzer.StructuralPlotConfigService.normalizeWarnLines(lines);
            for i = 1:numel(lines)
                item = lines{i};
                if isstruct(item) && isfield(item, 'y') && isnumeric(item.y) && ...
                        isscalar(item.y) && isfinite(item.y)
                    ys(end+1) = item.y; %#ok<AGROW>
                end
            end
            if isempty(ys)
                sig = '';
            else
                sig = sprintf('%.12g|', sort(ys));
            end
        end

        function tf = isWarnLineStruct(value)
            tf = isstruct(value) && any(isfield(value, {'y', 'label', 'level', 'color', 'linestyle'}));
        end

        function value = getField(s, fieldName, defaultValue)
            if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
                value = s.(fieldName);
            else
                value = defaultValue;
            end
        end

        function [r, g, b] = colorToRgbFields(color)
            r = []; g = []; b = [];
            if isnumeric(color) && numel(color) == 3
                color = reshape(color, 1, 3);
                r = color(1); g = color(2); b = color(3);
            end
        end

        function txt = toChar(value)
            if isempty(value)
                txt = '';
            elseif isstring(value)
                txt = char(value);
            elseif ischar(value)
                txt = value;
            elseif isnumeric(value)
                txt = num2str(value);
            else
                txt = char(string(value));
            end
        end
    end
end
