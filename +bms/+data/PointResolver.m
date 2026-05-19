classdef PointResolver
    %POINTRESOLVER Normalizes point ids and MATLAB-safe field names.

    methods (Static)
        function safe = safeId(pointId)
            pointId = char(string(pointId));
            legacy = bms.data.PointResolver.legacySafeId(pointId);
            dashSafe = bms.data.PointResolver.dashSafeId(pointId);
            if strcmp(legacy, dashSafe) && isvarname(legacy)
                safe = legacy;
                return;
            end

            suffix = ['__p' bms.data.PointResolver.shortHash(pointId)];
            maxBaseLen = max(1, namelengthmax - numel(suffix));
            if numel(legacy) > maxBaseLen
                legacy = legacy(1:maxBaseLen);
            end
            safe = [legacy suffix];
        end

        function safe = legacySafeId(pointId)
            safe = matlab.lang.makeValidName(bms.data.PointResolver.dashSafeId(pointId));
        end

        function safe = dashSafeId(pointId)
            safe = strrep(char(string(pointId)), '-', '_');
        end

        function candidates = keyCandidates(pointId, cfg)
            if nargin < 2
                cfg = struct();
            end
            pointId = char(string(pointId));
            candidates = {pointId, ...
                bms.data.PointResolver.safeId(pointId), ...
                bms.data.PointResolver.legacySafeId(pointId), ...
                bms.data.PointResolver.dashSafeId(pointId)};

            if isstruct(cfg) && isfield(cfg, 'name_map_global') && isstruct(cfg.name_map_global)
                keys = fieldnames(cfg.name_map_global);
                for i = 1:numel(keys)
                    mapped = cfg.name_map_global.(keys{i});
                    if strcmp(char(string(mapped)), pointId)
                        candidates{end+1} = keys{i}; %#ok<AGROW>
                    end
                end
            end
            candidates = bms.data.PointResolver.uniqueText(candidates);
        end

        function [tf, value, key] = getPointConfig(container, pointId, cfg)
            tf = false;
            value = [];
            key = '';
            if nargin < 3
                cfg = struct();
            end
            if ~isstruct(container) || isempty(pointId)
                return;
            end
            candidates = bms.data.PointResolver.keyCandidates(pointId, cfg);
            for i = 1:numel(candidates)
                candidate = candidates{i};
                if isfield(container, candidate)
                    tf = true;
                    value = container.(candidate);
                    key = candidate;
                    return;
                end
            end
        end

        function key = configKey(pointId)
            key = bms.data.PointResolver.safeId(pointId);
        end

        function original = originalId(safeId, cfg)
            original = char(string(safeId));
            if nargin >= 2 && isstruct(cfg)
                if isfield(cfg, 'name_map_global') && isstruct(cfg.name_map_global) ...
                        && isfield(cfg.name_map_global, safeId)
                    original = cfg.name_map_global.(safeId);
                    return;
                end

                ids = bms.data.PointResolver.configuredIds(cfg);
                for i = 1:numel(ids)
                    candidates = bms.data.PointResolver.keyCandidates(ids{i}, cfg);
                    if any(strcmp(candidates, safeId))
                        original = ids{i};
                        return;
                    end
                end
            end
        end

        function ids = configuredIds(cfg)
            ids = {};
            if ~isstruct(cfg)
                return;
            end
            fields = {'points', 'groups', 'design_points_pending', 'point_aliases', 'point_metadata'};
            for i = 1:numel(fields)
                field = fields{i};
                if isfield(cfg, field)
                    ids = [ids; bms.data.PointResolver.collectTextValues(cfg.(field))]; %#ok<AGROW>
                end
            end
            ids = bms.data.PointResolver.uniqueText(ids);
        end

        function pts = normalize(points)
            pts = {};
            if isstring(points)
                pts = cellstr(points(:));
            elseif ischar(points)
                if ~isempty(strtrim(points)), pts = {strtrim(points)}; end
            elseif iscell(points)
                for i = 1:numel(points)
                    item = points{i};
                    if isstring(item) && isscalar(item), item = char(item); end
                    if ischar(item) && ~isempty(strtrim(item))
                        pts{end+1,1} = strtrim(item); %#ok<AGROW>
                    end
                end
            end
            if ~isempty(pts)
                pts = unique(pts, 'stable');
            end
        end

        function pts = fromConfig(cfg, key, fallback)
            if nargin < 3
                fallback = {};
            end
            pts = bms.data.PointResolver.normalize(fallback);
            if isstruct(cfg) && isfield(cfg, 'points') && isstruct(cfg.points) && isfield(cfg.points, key)
                configured = bms.data.PointResolver.normalize(cfg.points.(key));
                pts = configured;
            end
        end

        function groups = normalizeGroups(raw)
            groups = struct();
            if isempty(raw)
                return;
            end
            if isstruct(raw)
                names = fieldnames(raw);
                for i = 1:numel(names)
                    pts = bms.data.PointResolver.normalize(raw.(names{i}));
                    if ~isempty(pts)
                        groups.(names{i}) = pts;
                    end
                end
            elseif iscell(raw)
                for i = 1:numel(raw)
                    pts = bms.data.PointResolver.normalize(raw{i});
                    if ~isempty(pts)
                        groups.(sprintf('G%d', i)) = pts;
                    end
                end
            end
        end

        function tf = hasGroups(raw)
            groups = bms.data.PointResolver.normalizeGroups(raw);
            tf = isstruct(groups) && ~isempty(fieldnames(groups));
        end

        function pts = flattenGroups(raw)
            groups = bms.data.PointResolver.normalizeGroups(raw);
            names = fieldnames(groups);
            pts = {};
            for i = 1:numel(names)
                pts = [pts; groups.(names{i})(:)]; %#ok<AGROW>
            end
            if ~isempty(pts)
                pts = unique(pts, 'stable');
            end
        end

        function tf = filenameHasPointToken(filePath, pointId)
            [~, stem] = fileparts(char(string(filePath)));
            token = regexptranslate('escape', char(string(pointId)));
            tf = ~isempty(regexp(stem, ['(?<![A-Za-z0-9])' token '(?![A-Za-z0-9])'], 'once'));
        end

        function matches = filterFilesForPoint(files, pointId)
            if ischar(files) || isstring(files)
                files = cellstr(string(files));
            end
            matches = {};
            for i = 1:numel(files)
                if bms.data.PointResolver.filenameHasPointToken(files{i}, pointId)
                    matches{end+1} = files{i}; %#ok<AGROW>
                end
            end
        end

        function ids = collectTextValues(value)
            ids = {};
            if isempty(value)
                return;
            end
            if ischar(value)
                txt = strtrim(value);
                if ~isempty(txt)
                    ids = {txt};
                end
            elseif isstring(value)
                cells = cellstr(value(:));
                for i = 1:numel(cells)
                    txt = strtrim(cells{i});
                    if ~isempty(txt)
                        ids{end+1, 1} = txt; %#ok<AGROW>
                    end
                end
            elseif iscell(value)
                for i = 1:numel(value)
                    ids = [ids; bms.data.PointResolver.collectTextValues(value{i})]; %#ok<AGROW>
                end
            elseif isstruct(value)
                for n = 1:numel(value)
                    names = fieldnames(value(n));
                    for i = 1:numel(names)
                        ids = [ids; bms.data.PointResolver.collectTextValues(value(n).(names{i}))]; %#ok<AGROW>
                    end
                end
            end
            ids = bms.data.PointResolver.uniqueText(ids);
        end

        function out = uniqueText(items)
            out = {};
            if isempty(items)
                return;
            end
            if ischar(items) || isstring(items)
                items = cellstr(string(items));
            end
            for i = 1:numel(items)
                if isempty(items{i})
                    continue;
                end
                txt = char(string(items{i}));
                if ~any(strcmp(out, txt))
                    out{end+1, 1} = txt; %#ok<AGROW>
                end
            end
        end

        function h = shortHash(text)
            bytes = unicode2native(char(string(text)), 'UTF-8');
            hash = uint32(2166136261);
            for i = 1:numel(bytes)
                hash = bitxor(hash, uint32(bytes(i)));
                hash = uint32(mod(uint64(hash) * uint64(16777619), uint64(4294967296)));
            end
            h = lower(dec2hex(hash, 8));
        end
    end
end
