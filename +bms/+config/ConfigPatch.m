classdef ConfigPatch
    %CONFIGPATCH Small utility to patch nested struct paths.

    methods (Static)
        function cfg = setPath(cfg, dottedPath, value)
            parts = bms.config.ConfigPatch.pathParts(dottedPath);
            cfg = bms.config.ConfigPatch.setParts(cfg, parts, value);
        end

        function cfg = removePath(cfg, dottedPath)
            parts = bms.config.ConfigPatch.pathParts(dottedPath);
            cfg = bms.config.ConfigPatch.removeParts(cfg, parts);
        end

        function [tf, value] = getPath(cfg, dottedPath)
            parts = bms.config.ConfigPatch.pathParts(dottedPath);
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

        function cfg = apply(cfg, operations)
            if isempty(operations)
                return;
            end
            if isstruct(operations)
                operations = num2cell(operations);
            end
            for i = 1:numel(operations)
                op = operations{i};
                if ~isstruct(op) || ~isfield(op, 'op') || ~isfield(op, 'path')
                    error('BMS:ConfigPatch:InvalidOperation', 'Patch operation must contain op and path.');
                end
                switch lower(char(op.op))
                    case {'set','replace','add'}
                        if ~isfield(op, 'value')
                            error('BMS:ConfigPatch:InvalidOperation', 'Set operation must contain value.');
                        end
                        cfg = bms.config.ConfigPatch.setPath(cfg, op.path, op.value);
                    case {'remove','delete'}
                        cfg = bms.config.ConfigPatch.removePath(cfg, op.path);
                    otherwise
                        error('BMS:ConfigPatch:InvalidOperation', 'Unsupported patch operation: %s', char(op.op));
                end
            end
        end

        function op = setOp(dottedPath, value)
            op = struct('op', 'set', 'path', char(dottedPath), 'value', value);
        end

        function op = removeOp(dottedPath)
            op = struct('op', 'remove', 'path', char(dottedPath));
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

        function cfg = removeParts(cfg, parts)
            part = parts{1};
            if ~isstruct(cfg) || ~isfield(cfg, part)
                return;
            end
            if numel(parts) == 1
                cfg = rmfield(cfg, part);
                return;
            end
            cfg.(part) = bms.config.ConfigPatch.removeParts(cfg.(part), parts(2:end));
        end

        function parts = pathParts(dottedPath)
            parts = strsplit(char(dottedPath), '.');
            if isempty(parts) || any(cellfun(@isempty, parts))
                error('BMS:ConfigPatch:InvalidPath', 'Invalid config path: %s', char(dottedPath));
            end
        end
    end
end
