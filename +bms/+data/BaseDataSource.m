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
            switch char(obj.Layout)
                case 'hongtang_period'
                    folders = bms.data.PeriodFolderAdapter.candidateDirs(obj.Root, subfolder, startDate, endDate);
                case 'dated_folders'
                    folders = bms.data.DatedFolderAdapter.candidateDirs(obj.Root, subfolder, startDate, endDate);
                otherwise
                    folders = bms.data.DatedFolderAdapter.candidateDirs(obj.Root, subfolder, startDate, endDate);
            end
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
                    if isempty(hits)
                        hits = bms.data.BaseDataSource.listFilesRecursive(dirs{i}, char(patterns{j}));
                    end
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

        function files = listFilesRecursive(folder, pattern)
            files = {};
            if nargin < 2 || isempty(pattern), pattern = '*'; end
            if ~exist(folder, 'dir'), return; end
            d = dir(fullfile(folder, '**', char(string(pattern))));
            d = d(~[d.isdir]);
            files = cell(1, numel(d));
            for i = 1:numel(d)
                files{i} = fullfile(d(i).folder, d(i).name);
            end
        end
    end
end
