classdef PeriodFolderAdapter
    %PERIODFOLDERADAPTER Shared rules for period roots such as Hongtang.

    methods (Static)
        function tf = hasPeriodLayout(root)
            root = char(root);
            tf = isfolder(fullfile(root, 'lowfreq')) || ...
                (isfolder(fullfile(root, 'WIM')) && isfolder(fullfile(root, 'lowfreq')));
        end

        function p = lowfreqDir(root)
            p = fullfile(char(root), 'lowfreq');
        end

        function p = wimDir(root)
            p = fullfile(char(root), 'WIM');
        end

        function folders = dateFolders(root, startDate, endDate) %#ok<INUSD>
            folders = {};
            if isfolder(root)
                folders{end+1} = char(root);
            end
            lowfreq = bms.data.PeriodFolderAdapter.lowfreqDir(root);
            if isfolder(lowfreq)
                folders{end+1} = lowfreq;
            end
            folders = bms.data.BaseDataSource.uniqueExistingFolders(folders);
        end

        function folders = candidateDirs(root, subfolder, startDate, endDate) %#ok<INUSD>
            folders = {};
            subfolder = char(string(subfolder));
            if bms.data.DataLayoutResolver.isAbsolutePath(subfolder)
                if isfolder(subfolder), folders = {subfolder}; end
                return;
            end

            roots = bms.data.PeriodFolderAdapter.dateFolders(root, startDate, endDate);
            for i = 1:numel(roots)
                if isempty(subfolder)
                    folders{end+1} = roots{i}; %#ok<AGROW>
                    continue;
                end
                candidate = fullfile(roots{i}, subfolder);
                if isfolder(candidate)
                    folders{end+1} = candidate; %#ok<AGROW>
                end
            end
            folders = bms.data.BaseDataSource.uniqueExistingFolders(folders);
        end
    end
end
