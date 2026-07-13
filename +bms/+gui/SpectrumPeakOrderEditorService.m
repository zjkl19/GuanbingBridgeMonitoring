classdef SpectrumPeakOrderEditorService
    %SPECTRUMPEAKORDEREDITORSERVICE Table adapter for spectrum peak orders.

    methods (Static)
        function names = columnNames()
            names = {'scope', 'point_id', 'order', 'label', 'theoretical_hz', ...
                'search_min_hz', 'search_max_hz', 'enabled', 'theor_label', 'source'};
        end

        function rows = rows(cfg, moduleSpec)
            spec = bms.config.ModuleConfigRegistry.normalize(moduleSpec);
            rows = cell(0, numel(bms.gui.SpectrumPeakOrderEditorService.columnNames()));
            if isempty(spec.params_key)
                return;
            end

            params = bms.config.ModuleConfigResolver.resolveParams(cfg, spec);
            rows = [rows; bms.gui.SpectrumPeakOrderEditorService.configRows( ...
                params, 'default', '', 'params')]; %#ok<AGROW>

            key = char(string(spec.per_point_key));
            if ~isstruct(cfg) || ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point) || ...
                    isempty(key) || ~isfield(cfg.per_point, key) || ~isstruct(cfg.per_point.(key))
                return;
            end

            pointIds = bms.gui.SpectrumPeakOrderEditorService.modulePointIds(cfg, spec);
            for i = 1:numel(pointIds)
                pointId = pointIds{i};
                [ok, pointCfg] = bms.data.PointResolver.getPointConfig(cfg.per_point.(key), pointId, cfg);
                if ~ok || ~isstruct(pointCfg)
                    continue;
                end
                rows = [rows; bms.gui.SpectrumPeakOrderEditorService.configRows( ...
                    pointCfg, 'point', pointId, 'per_point')]; %#ok<AGROW>
            end
        end

        function cfg = applyRows(cfg, moduleSpec, rows)
            spec = bms.config.ModuleConfigRegistry.normalize(moduleSpec);
            if isempty(spec.params_key)
                return;
            end
            if isempty(rows)
                rows = cell(0, numel(bms.gui.SpectrumPeakOrderEditorService.columnNames()));
            end
            if istable(rows)
                rows = table2cell(rows);
            end
            if ~iscell(rows)
                error('bms:gui:SpectrumPeakOrderEditorService:InvalidRows', ...
                    'Spectrum peak rows must be a cell array.');
            end
            if size(rows, 2) < 8
                error('bms:gui:SpectrumPeakOrderEditorService:InvalidRows', ...
                    'Spectrum peak rows must contain scope, point_id, order, label, theoretical_hz, search_min_hz, search_max_hz, and enabled.');
            end

            defaultOrders = struct('label', {}, 'order', {}, 'search_center_hz', {}, ...
                'search_half_width_hz', {}, 'search_min_hz', {}, 'search_max_hz', {}, ...
                'theoretical_hz', {}, 'theor_label', {});
            pointOrders = struct();
            originalByPoint = struct();
            seen = struct();

            for i = 1:size(rows, 1)
                if ~bms.gui.SpectrumPeakOrderEditorService.parseLogical(rows{i, 8}, true)
                    continue;
                end
                scope = bms.gui.SpectrumPeakOrderEditorService.normalizeScope(rows{i, 1});
                pointId = strtrim(bms.gui.SpectrumPeakOrderEditorService.toChar(rows{i, 2}));
                orderNo = bms.gui.SpectrumPeakOrderEditorService.parseOptionalNumber(rows{i, 3});
                label = strtrim(bms.gui.SpectrumPeakOrderEditorService.toChar(rows{i, 4}));
                theor = bms.gui.SpectrumPeakOrderEditorService.parseOptionalNumber(rows{i, 5});
                searchMin = bms.gui.SpectrumPeakOrderEditorService.parseRequiredNumber(rows{i, 6}, 'search_min_hz');
                searchMax = bms.gui.SpectrumPeakOrderEditorService.parseRequiredNumber(rows{i, 7}, 'search_max_hz');
                theorLabel = '';
                if size(rows, 2) >= 9
                    theorLabel = strtrim(bms.gui.SpectrumPeakOrderEditorService.toChar(rows{i, 9}));
                end
                if searchMax <= searchMin
                    error('bms:gui:SpectrumPeakOrderEditorService:InvalidRange', ...
                        'search_max_hz must be greater than search_min_hz.');
                end

                if strcmp(scope, 'point') && isempty(pointId)
                    error('bms:gui:SpectrumPeakOrderEditorService:EmptyPointId', ...
                        'point_id is required when scope is point.');
                end

                item = bms.gui.SpectrumPeakOrderEditorService.makeOrder( ...
                    orderNo, label, theor, searchMin, searchMax, theorLabel);
                if strcmp(scope, 'default')
                    seenKey = matlab.lang.makeValidName(sprintf('default__%s', ...
                        bms.gui.SpectrumPeakOrderEditorService.orderKey(orderNo, label, numel(defaultOrders) + 1)));
                    if isfield(seen, seenKey)
                        error('bms:gui:SpectrumPeakOrderEditorService:DuplicateOrder', ...
                            'Duplicate default peak order.');
                    end
                    seen.(seenKey) = true;
                    defaultOrders(end+1) = item; %#ok<AGROW>
                else
                    safeId = bms.gui.SpectrumPeakOrderEditorService.configKeyForPoint(cfg, spec.per_point_key, pointId);
                    seenKey = matlab.lang.makeValidName(sprintf('point__%s__%s', safeId, ...
                        bms.gui.SpectrumPeakOrderEditorService.orderKey(orderNo, label, 1)));
                    if isfield(seen, seenKey)
                        error('bms:gui:SpectrumPeakOrderEditorService:DuplicateOrder', ...
                            'Duplicate peak order for point %s.', pointId);
                    end
                    seen.(seenKey) = true;
                    if ~isfield(pointOrders, safeId)
                        pointOrders.(safeId) = item;
                    else
                        pointOrders.(safeId)(end+1) = item;
                    end
                    originalByPoint.(safeId) = pointId;
                end
            end

            params = bms.config.ModuleConfigResolver.resolveParams(cfg, spec);
            params = bms.gui.SpectrumPeakOrderEditorService.clearFrequencyFields(params);
            if ~isempty(defaultOrders)
                params.peak_orders = defaultOrders;
            end
            cfg.(spec.params_key) = params;

            cfg = bms.gui.SpectrumPeakOrderEditorService.applyPointOrders(cfg, spec, pointOrders);
            cfg = bms.gui.SpectrumPeakOrderEditorService.updateNameMap(cfg, originalByPoint);
        end

        function row = defaultRow(pointId, scope)
            if nargin < 1
                pointId = '';
            end
            if nargin < 2 || isempty(scope)
                scope = 'default';
            end
            if strcmp(char(string(scope)), 'point') && isempty(pointId)
                pointId = '';
            end
            row = {char(string(scope)), char(string(pointId)), [], '', [], [], [], true, '', 'new'};
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
        function rows = configRows(block, scope, pointId, source)
            rows = cell(0, numel(bms.gui.SpectrumPeakOrderEditorService.columnNames()));
            if ~isstruct(block)
                return;
            end
            if isfield(block, 'peak_orders') && ~isempty(block.peak_orders)
                orders = block.peak_orders;
                if iscell(orders)
                    try
                        orders = [orders{:}];
                    catch
                        orders = struct([]);
                    end
                end
                if isstruct(orders)
                    for i = 1:numel(orders)
                        item = orders(i);
                        [searchMin, searchMax] = bms.gui.SpectrumPeakOrderEditorService.searchRangeFromOrder(item, 0.15);
                        rows(end+1, :) = {scope, pointId, ...
                            bms.gui.SpectrumPeakOrderEditorService.numericField(item, {'order'}, []), ...
                            bms.gui.SpectrumPeakOrderEditorService.textField(item, {'label', 'name'}, ''), ...
                            bms.gui.SpectrumPeakOrderEditorService.numericField(item, {'theoretical_hz', 'theor_hz'}, []), ...
                            searchMin, searchMax, true, ...
                            bms.gui.SpectrumPeakOrderEditorService.textField(item, {'theor_label', 'theoretical_label'}, ''), ...
                            source}; %#ok<AGROW>
                    end
                    return;
                end
            end

            freqs = bms.gui.SpectrumPeakOrderEditorService.numericArrayField(block, 'target_freqs');
            if isempty(freqs)
                return;
            end
            tol = bms.gui.SpectrumPeakOrderEditorService.numericArrayField(block, 'tolerance');
            if isempty(tol)
                tol = 0.15;
            end
            theor = bms.gui.SpectrumPeakOrderEditorService.numericArrayField(block, 'theor_freqs');
            theorLabels = bms.gui.SpectrumPeakOrderEditorService.textArrayField(block, 'theor_labels');
            peakLabels = bms.gui.SpectrumPeakOrderEditorService.textArrayField(block, 'peak_labels');
            for i = 1:numel(freqs)
                halfWidth = bms.gui.SpectrumPeakOrderEditorService.indexOrLast(tol, i, 0.15);
                rows(end+1, :) = {scope, pointId, i, ...
                    bms.gui.SpectrumPeakOrderEditorService.cellIndex(peakLabels, i, sprintf('peak%d', i)), ...
                    bms.gui.SpectrumPeakOrderEditorService.indexOrNaN(theor, i), ...
                    freqs(i) - halfWidth, freqs(i) + halfWidth, true, ...
                    bms.gui.SpectrumPeakOrderEditorService.cellIndex(theorLabels, i, ''), ...
                    '兼容配置'}; %#ok<AGROW>
            end
        end

        function [searchMin, searchMax] = searchRangeFromOrder(item, defaultHalfWidth)
            searchMin = bms.gui.SpectrumPeakOrderEditorService.numericField(item, {'search_min_hz', 'min_hz', 'lower_hz'}, NaN);
            searchMax = bms.gui.SpectrumPeakOrderEditorService.numericField(item, {'search_max_hz', 'max_hz', 'upper_hz'}, NaN);
            if isfinite(searchMin) && isfinite(searchMax)
                return;
            end
            center = bms.gui.SpectrumPeakOrderEditorService.numericField( ...
                item, {'search_center_hz', 'target_hz', 'frequency_hz', 'freq_hz'}, NaN);
            if ~isfinite(center)
                center = bms.gui.SpectrumPeakOrderEditorService.numericField(item, {'theoretical_hz', 'theor_hz'}, NaN);
            end
            halfWidth = bms.gui.SpectrumPeakOrderEditorService.numericField( ...
                item, {'search_half_width_hz', 'tolerance_hz', 'half_width_hz'}, NaN);
            if ~isfinite(halfWidth) || halfWidth <= 0
                halfWidth = defaultHalfWidth;
            end
            if isfinite(center)
                searchMin = center - halfWidth;
                searchMax = center + halfWidth;
            else
                searchMin = [];
                searchMax = [];
            end
        end

        function item = makeOrder(orderNo, label, theor, searchMin, searchMax, theorLabel)
            center = (searchMin + searchMax) / 2;
            halfWidth = (searchMax - searchMin) / 2;
            item = struct();
            item.label = '';
            item.order = [];
            item.search_center_hz = center;
            item.search_half_width_hz = halfWidth;
            item.search_min_hz = searchMin;
            item.search_max_hz = searchMax;
            item.theoretical_hz = [];
            item.theor_label = '';
            if ~isempty(label)
                item.label = label;
            end
            if isfinite(orderNo)
                item.order = orderNo;
            end
            if isfinite(theor)
                item.theoretical_hz = theor;
            end
            if ~isempty(theorLabel)
                item.theor_label = theorLabel;
            end
        end

        function cfg = applyPointOrders(cfg, spec, pointOrders)
            key = char(string(spec.per_point_key));
            if isempty(key)
                return;
            end
            if ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point)
                cfg.per_point = struct();
            end
            if ~isfield(cfg.per_point, key) || ~isstruct(cfg.per_point.(key))
                cfg.per_point.(key) = struct();
            end
            perStruct = cfg.per_point.(key);

            managedKeys = bms.gui.SpectrumPeakOrderEditorService.managedPointKeys(cfg, spec);
            names = fieldnames(pointOrders);
            managedKeys = bms.data.PointResolver.uniqueText([managedKeys; names]);
            for i = 1:numel(managedKeys)
                safeId = managedKeys{i};
                if isfield(perStruct, safeId) && isstruct(perStruct.(safeId))
                    perStruct.(safeId) = bms.gui.SpectrumPeakOrderEditorService.clearFrequencyFields(perStruct.(safeId));
                    if isempty(fieldnames(perStruct.(safeId)))
                        perStruct = rmfield(perStruct, safeId);
                    end
                end
            end

            for i = 1:numel(names)
                safeId = names{i};
                if ~isfield(perStruct, safeId) || ~isstruct(perStruct.(safeId))
                    perStruct.(safeId) = struct();
                end
                perStruct.(safeId).peak_orders = pointOrders.(safeId);
            end
            cfg.per_point.(key) = perStruct;
        end

        function out = clearFrequencyFields(out)
            fields = {'peak_orders', 'target_freqs', 'tolerance', 'theor_freqs', 'theor_labels', 'peak_labels'};
            for i = 1:numel(fields)
                if isstruct(out) && isfield(out, fields{i})
                    out = rmfield(out, fields{i});
                end
            end
        end

        function keys = managedPointKeys(cfg, spec)
            points = bms.gui.SpectrumPeakOrderEditorService.modulePointIds(cfg, spec);
            keys = cell(size(points));
            key = char(string(spec.per_point_key));
            for i = 1:numel(points)
                keys{i} = bms.gui.SpectrumPeakOrderEditorService.configKeyForPoint(cfg, key, points{i});
            end
            if isstruct(cfg) && isfield(cfg, 'per_point') && isstruct(cfg.per_point) && ...
                    ~isempty(key) && isfield(cfg.per_point, key) && isstruct(cfg.per_point.(key))
                keys = [keys; fieldnames(cfg.per_point.(key))]; %#ok<AGROW>
            end
            keys = bms.data.PointResolver.uniqueText(keys);
        end

        function safeId = configKeyForPoint(cfg, perPointKey, pointId)
            pointId = char(string(pointId));
            perPointKey = char(string(perPointKey));
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

        function scope = normalizeScope(raw)
            scope = lower(strtrim(bms.gui.SpectrumPeakOrderEditorService.toChar(raw)));
            if isempty(scope) || any(strcmp(scope, {'default', 'module', 'params'}))
                scope = 'default';
            elseif any(strcmp(scope, {'point', 'per_point', 'sensor'}))
                scope = 'point';
            else
                error('bms:gui:SpectrumPeakOrderEditorService:InvalidScope', ...
                    'scope must be default or point.');
            end
        end

        function key = orderKey(orderNo, label, fallback)
            if isfinite(orderNo)
                key = sprintf('order_%g', orderNo);
            elseif ~isempty(label)
                key = ['label_' matlab.lang.makeValidName(label)];
            else
                key = sprintf('row_%d', fallback);
            end
        end

        function value = parseRequiredNumber(raw, name)
            value = bms.gui.SpectrumPeakOrderEditorService.parseOptionalNumber(raw);
            if ~isfinite(value)
                error('bms:gui:SpectrumPeakOrderEditorService:InvalidNumber', ...
                    '%s must be a finite number.', name);
            end
        end

        function value = parseOptionalNumber(raw)
            if isempty(raw)
                value = NaN;
            elseif isnumeric(raw) && isscalar(raw)
                value = double(raw);
            else
                value = str2double(strtrim(bms.gui.SpectrumPeakOrderEditorService.toChar(raw)));
            end
            if ~isfinite(value)
                value = NaN;
            end
        end

        function tf = parseLogical(raw, defaultValue)
            if isempty(raw)
                tf = defaultValue;
            elseif islogical(raw)
                tf = raw;
            elseif isnumeric(raw)
                tf = raw ~= 0;
            else
                txt = lower(strtrim(bms.gui.SpectrumPeakOrderEditorService.toChar(raw)));
                if isempty(txt)
                    tf = defaultValue;
                else
                    tf = any(strcmp(txt, {'true', '1', 'yes', 'on'}));
                end
            end
        end

        function value = numericField(s, names, defaultValue)
            value = defaultValue;
            for i = 1:numel(names)
                name = names{i};
                if isfield(s, name) && ~isempty(s.(name))
                    raw = s.(name);
                    if isnumeric(raw) && isscalar(raw)
                        value = double(raw);
                        return;
                    elseif ischar(raw) || isstring(raw)
                        parsed = str2double(char(string(raw)));
                        if isfinite(parsed)
                            value = parsed;
                            return;
                        end
                    end
                end
            end
        end

        function value = textField(s, names, defaultValue)
            value = defaultValue;
            for i = 1:numel(names)
                name = names{i};
                if isfield(s, name) && ~isempty(s.(name))
                    value = bms.gui.SpectrumPeakOrderEditorService.toChar(s.(name));
                    return;
                end
            end
        end

        function arr = numericArrayField(s, fieldName)
            arr = [];
            if isstruct(s) && isfield(s, fieldName) && isnumeric(s.(fieldName))
                arr = double(s.(fieldName)(:).');
            end
        end

        function arr = textArrayField(s, fieldName)
            arr = {};
            if ~isstruct(s) || ~isfield(s, fieldName) || isempty(s.(fieldName))
                return;
            end
            raw = s.(fieldName);
            if isstring(raw)
                arr = cellstr(raw(:));
            elseif ischar(raw)
                arr = {raw};
            elseif iscell(raw)
                arr = cellfun(@(x)bms.gui.SpectrumPeakOrderEditorService.toChar(x), raw(:), 'UniformOutput', false);
            end
        end

        function value = indexOrLast(arr, idx, defaultValue)
            if isempty(arr)
                value = defaultValue;
            elseif numel(arr) >= idx
                value = arr(idx);
            else
                value = arr(end);
            end
        end

        function value = indexOrNaN(arr, idx)
            value = [];
            if ~isempty(arr) && numel(arr) >= idx
                value = arr(idx);
            end
        end

        function value = cellIndex(arr, idx, defaultValue)
            value = defaultValue;
            if iscell(arr) && numel(arr) >= idx
                value = bms.gui.SpectrumPeakOrderEditorService.toChar(arr{idx});
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
            elseif islogical(value)
                txt = char(string(value));
            else
                txt = char(string(value));
            end
        end
    end
end
