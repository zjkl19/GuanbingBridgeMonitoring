classdef ConfigPatch
    %CONFIGPATCH Small utility to patch nested struct paths.

    methods (Static)
        function cfg = setPath(cfg, dottedPath, value)
            parts = strsplit(char(dottedPath), '.');
            if isempty(parts) || any(cellfun(@isempty, parts))
                error('BMS:ConfigPatch:InvalidPath', 'Invalid config path: %s', char(dottedPath));
            end
            cfg = bms.config.ConfigPatch.setParts(cfg, parts, value);
        end

        function [tf, value] = getPath(cfg, dottedPath)
            parts = strsplit(char(dottedPath), '.');
            value = [];
            cur = cfg;
            for i = 1:numel(parts)
                part = parts{i};
                if ~isstruct(cur) || ~isfield(cur, part)
                    tf = false;
                    return;
                end
                cur = cur.(part);
            end
            tf = true;
            value = cur;
        end

        function cfg = setParts(cfg, parts, value)
            part = parts{1};
            if numel(parts) == 1
                cfg.(part) = value;
                return;
            end
            if ~isfield(cfg, part) || ~isstruct(cfg.(part))
                cfg.(part) = struct();
            end
            cfg.(part) = bms.config.ConfigPatch.setParts(cfg.(part), parts(2:end), value);
        end
    end
end
