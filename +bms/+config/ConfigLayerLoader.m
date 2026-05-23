classdef ConfigLayerLoader
    %CONFIGLAYERLOADER Load JSON configs with optional extends/layers/includes.
    %
    % Supported optional fields:
    %   extends  - string or string array of base config files, merged first
    %   layers   - string or string array of overlay config files
    %   includes - struct mapping top-level fields to JSON fragment files

    methods (Static)
        function [cfg, combinedText, meta] = load(path)
            absPath = bms.config.ConfigLayerLoader.absolutePath(path, pwd);
            [cfg, meta] = bms.config.ConfigLayerLoader.loadRecursive(absPath, {});
            combinedText = strjoin(meta.texts, newline);
        end
    end

    methods (Static, Access = private)
        function [cfg, meta] = loadRecursive(path, stack)
            path = bms.config.ConfigLayerLoader.absolutePath(path, pwd);
            if any(strcmp(stack, path))
                chain = strjoin([stack(:); {path}], ' -> ');
                error('BMS:Config:LayerCycle', 'Config layering cycle detected: %s', chain);
            end
            if ~isfile(path)
                error('BMS:Config:MissingFile', 'Config file not found: %s', path);
            end

            txt = bms.config.ConfigLayerLoader.readText(path);
            own = jsondecode(txt);
            if ~isstruct(own)
                error('BMS:Config:InvalidJson', 'Config root must be a JSON object: %s', path);
            end

            baseDir = fileparts(path);
            cfg = struct();
            meta = struct('files', {{path}}, 'texts', {{txt}});
            nextStack = [stack(:); {path}];

            extendPaths = bms.config.ConfigLayerLoader.pathList(own, 'extends');
            for idx = 1:numel(extendPaths)
                [baseCfg, baseMeta] = bms.config.ConfigLayerLoader.loadRecursive( ...
                    bms.config.ConfigLayerLoader.resolveRelative(extendPaths{idx}, baseDir), nextStack);
                cfg = bms.config.ConfigLayerLoader.deepMerge(cfg, baseCfg);
                meta = bms.config.ConfigLayerLoader.mergeMeta(meta, baseMeta);
            end

            layerPaths = bms.config.ConfigLayerLoader.pathList(own, 'layers');
            for idx = 1:numel(layerPaths)
                [layerCfg, layerMeta] = bms.config.ConfigLayerLoader.loadRecursive( ...
                    bms.config.ConfigLayerLoader.resolveRelative(layerPaths{idx}, baseDir), nextStack);
                cfg = bms.config.ConfigLayerLoader.deepMerge(cfg, layerCfg);
                meta = bms.config.ConfigLayerLoader.mergeMeta(meta, layerMeta);
            end

            [own, includeMeta] = bms.config.ConfigLayerLoader.applyIncludes(own, baseDir);
            meta = bms.config.ConfigLayerLoader.mergeMeta(meta, includeMeta);
            own = bms.config.ConfigLayerLoader.removeMetaFields(own);
            cfg = bms.config.ConfigLayerLoader.deepMerge(cfg, own);
        end

        function [own, meta] = applyIncludes(own, baseDir)
            meta = struct('files', {{}}, 'texts', {{}});
            if ~isfield(own, 'includes') || ~isstruct(own.includes)
                return;
            end
            names = fieldnames(own.includes);
            for i = 1:numel(names)
                fieldName = names{i};
                paths = bms.config.ConfigLayerLoader.normalizePathValue(own.includes.(fieldName));
                includedValue = struct();
                hasIncluded = false;
                for j = 1:numel(paths)
                    includePath = bms.config.ConfigLayerLoader.resolveRelative(paths{j}, baseDir);
                    txt = bms.config.ConfigLayerLoader.readText(includePath);
                    value = jsondecode(txt);
                    meta.files{end+1} = includePath; %#ok<AGROW>
                    meta.texts{end+1} = txt; %#ok<AGROW>
                    if ~hasIncluded
                        includedValue = value;
                        hasIncluded = true;
                    else
                        includedValue = bms.config.ConfigLayerLoader.deepMerge(includedValue, value);
                    end
                end
                if ~hasIncluded
                    continue;
                end
                if isfield(own, fieldName)
                    own.(fieldName) = bms.config.ConfigLayerLoader.deepMerge(includedValue, own.(fieldName));
                else
                    own.(fieldName) = includedValue;
                end
            end
        end

        function cfg = removeMetaFields(cfg)
            for name = {'extends', 'layers', 'includes'}
                if isfield(cfg, name{1})
                    cfg = rmfield(cfg, name{1});
                end
            end
        end

        function merged = deepMerge(base, overlay)
            if isstruct(base) && isstruct(overlay) && isscalar(base) && isscalar(overlay)
                merged = base;
                names = fieldnames(overlay);
                for i = 1:numel(names)
                    name = names{i};
                    if isfield(merged, name)
                        merged.(name) = bms.config.ConfigLayerLoader.deepMerge(merged.(name), overlay.(name));
                    else
                        merged.(name) = overlay.(name);
                    end
                end
            else
                merged = overlay;
            end
        end

        function meta = mergeMeta(meta, other)
            meta.files = unique([other.files(:); meta.files(:)], 'stable')';
            meta.texts = [other.texts(:); meta.texts(:)]';
        end

        function paths = pathList(s, fieldName)
            paths = {};
            if isstruct(s) && isfield(s, fieldName)
                paths = bms.config.ConfigLayerLoader.normalizePathValue(s.(fieldName));
            end
        end

        function paths = normalizePathValue(value)
            paths = {};
            if isempty(value)
                return;
            end
            if ischar(value)
                cells = {value};
            elseif isstring(value)
                cells = cellstr(value(:));
            elseif iscell(value)
                cells = {};
                for i = 1:numel(value)
                    if ischar(value{i})
                        cells = [cells; {value{i}}]; %#ok<AGROW>
                    elseif isstring(value{i})
                        cells = [cells; cellstr(value{i}(:))]; %#ok<AGROW>
                    end
                end
            else
                return;
            end
            for i = 1:numel(cells)
                txt = strtrim(cells{i});
                if ~isempty(txt)
                    paths{end+1, 1} = txt; %#ok<AGROW>
                end
            end
        end

        function path = resolveRelative(path, baseDir)
            path = char(string(path));
            if bms.config.ConfigLayerLoader.isAbsolute(path)
                return;
            end
            candidate = fullfile(baseDir, path);
            if isfile(candidate)
                path = candidate;
            end
        end

        function path = absolutePath(path, baseDir)
            path = char(string(path));
            if bms.config.ConfigLayerLoader.isAbsolute(path)
                return;
            end
            path = fullfile(baseDir, path);
        end

        function tf = isAbsolute(path)
            path = char(string(path));
            tf = ~isempty(regexp(path, '^[A-Za-z]:[\\/]|^\\\\|^/', 'once'));
        end

        function txt = readText(path)
            txt = fileread(path);
            if ~isempty(txt) && double(txt(1)) == 65279
                txt = txt(2:end);
            end
        end
    end
end
