classdef PointResolver
    %POINTRESOLVER Normalizes point ids and MATLAB-safe field names.

    methods (Static)
        function safe = safeId(pointId)
            safe = matlab.lang.makeValidName(strrep(char(string(pointId)), '-', '_'));
        end

        function original = originalId(safeId, cfg)
            original = char(string(safeId));
            if nargin >= 2 && isstruct(cfg) && isfield(cfg, 'name_map_global') && isstruct(cfg.name_map_global)
                if isfield(cfg.name_map_global, safeId)
                    original = cfg.name_map_global.(safeId);
                end
            end
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
    end
end
