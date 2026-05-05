classdef BaseDataSource
    %BASEDATASOURCE Common file discovery interface for bridge data roots.

    properties
        Root char = ''
        Config struct = struct()
        Layout char = ''
    end

    methods
        function obj = BaseDataSource(root, cfg, layout)
            if nargin >= 1, obj.Root = char(string(root)); end
            if nargin >= 2 && isstruct(cfg), obj.Config = cfg; end
            if nargin >= 3 && ~isempty(layout)
                obj.Layout = char(string(layout));
            else
                obj.Layout = bms.data.DataLayoutResolver.inferLayout(obj.Root, obj.Config);
            end
        end

        function info = describe(obj)
            info = bms.data.DataLayoutResolver.describe(obj.Root, obj.Config);
            info.data_source = class(obj);
        end

        function folders = dateFolders(obj, startDate, endDate)
            folders = bms.data.DataLayoutResolver.dateFolders(obj.Root, startDate, endDate, obj.Layout);
        end

        function folders = candidateDirs(obj, subfolder, startDate, endDate)
            folders = {};
            subfolder = char(string(subfolder));
            if isempty(subfolder)
                return;
            end
            if bms.data.DataLayoutResolver.isAbsolutePath(subfolder)
                if isfolder(subfolder), folders = {subfolder}; end
                return;
            end

            dayFolders = obj.dateFolders(startDate, endDate);
            for i = 1:numel(dayFolders)
                candidates = {fullfile(dayFolders{i}, subfolder), dayFolders{i}};
                for j = 1:numel(candidates)
                    if isfolder(candidates{j})
                        folders{end+1} = candidates{j}; %#ok<AGROW>
                        break;
                    end
                end
            end

            rootCandidate = fullfile(obj.Root, subfolder);
            if isfolder(rootCandidate)
                folders{end+1} = rootCandidate;
            end
            folders = bms.data.BaseDataSource.uniqueExistingFolders(folders);
        end

        function files = findPointFiles(obj, pointId, subfolder, startDate, endDate, patterns)
            if nargin < 6 || isempty(patterns)
                patterns = {['*' char(string(pointId)) '*']};
            end
            if ischar(patterns) || isstring(patterns)
                patterns = cellstr(string(patterns));
            end
            dirs = obj.candidateDirs(subfolder, startDate, endDate);
            files = {};
            for i = 1:numel(dirs)
                for j = 1:numel(patterns)
                    hits = bms.core.Logger.listFiles(dirs{i}, char(patterns{j}));
                    files = [files, hits]; %#ok<AGROW>
                end
            end
            files = bms.data.BaseDataSource.uniqueExistingFiles(files);
        end
    end

    methods (Static)
        function out = uniqueExistingFolders(items)
            out = {};
            seen = containers.Map('KeyType','char','ValueType','logical');
            for i = 1:numel(items)
                p = char(string(items{i}));
                if isempty(p) || ~isfolder(p), continue; end
                key = char(java.io.File(p).getCanonicalPath());
                if ~isKey(seen, key)
                    seen(key) = true;
                    out{end+1} = key; %#ok<AGROW>
                end
            end
        end

        function out = uniqueExistingFiles(items)
            out = {};
            seen = containers.Map('KeyType','char','ValueType','logical');
            for i = 1:numel(items)
                p = char(string(items{i}));
                if isempty(p) || ~isfile(p), continue; end
                key = char(java.io.File(p).getCanonicalPath());
                if ~isKey(seen, key)
                    seen(key) = true;
                    out{end+1} = key; %#ok<AGROW>
                end
            end
        end
    end
end
