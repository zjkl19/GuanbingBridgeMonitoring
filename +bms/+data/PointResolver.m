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
        end

        function pts = fromConfig(cfg, key, fallback)
            if nargin < 3
                fallback = {};
            end
            pts = bms.data.PointResolver.normalize(fallback);
            if isstruct(cfg) && isfield(cfg, 'points') && isstruct(cfg.points) && isfield(cfg.points, key)
                configured = bms.data.PointResolver.normalize(cfg.points.(key));
                if ~isempty(configured)
                    pts = configured;
                end
            end
        end
    end
end
