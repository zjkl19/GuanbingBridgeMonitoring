classdef DatedFolderAdapter
    %DATEDFOLDERADAPTER Shared rules for <root>\YYYY-MM-DD and YYYYMMDD data.

    methods (Static)
        function tf = hasDateFolders(root)
            root = char(root);
            d1 = dir(fullfile(root, '20??-??-??'));
            d2 = dir(fullfile(root, '20??????'));
            tf = any([d1.isdir]) || any([d2.isdir]);
        end

        function candidates = dateFolderCandidates(root, dateValue)
            dt = bms.data.TimeRangeResolver.parseDate(dateValue);
            candidates = { ...
                fullfile(char(root), datestr(dt, 'yyyy-mm-dd')), ...
                fullfile(char(root), datestr(dt, 'yyyymmdd'))};
        end

        function folders = dateFolders(root, startDate, endDate)
            daysList = bms.data.TimeRangeResolver.daysBetween(startDate, endDate);
            folders = {};
            for i = 1:numel(daysList)
                candidates = bms.data.DatedFolderAdapter.dateFolderCandidates(root, daysList(i));
                for j = 1:numel(candidates)
                    if isfolder(candidates{j})
                        folders{end+1} = candidates{j}; %#ok<AGROW>
                        break;
                    end
                end
            end
        end

        function folders = candidateDirs(root, subfolder, startDate, endDate)
            folders = {};
            subfolder = char(string(subfolder));
            if isempty(subfolder)
                return;
            end
            if bms.data.DataLayoutResolver.isAbsolutePath(subfolder)
                if isfolder(subfolder), folders = {subfolder}; end
                return;
            end

            dayFolders = bms.data.DatedFolderAdapter.dateFolders(root, startDate, endDate);
            for i = 1:numel(dayFolders)
                candidates = {fullfile(dayFolders{i}, subfolder), dayFolders{i}};
                for j = 1:numel(candidates)
                    if isfolder(candidates{j})
                        folders{end+1} = candidates{j}; %#ok<AGROW>
                        break;
                    end
                end
            end

            rootCandidate = fullfile(char(root), subfolder);
            if isfolder(rootCandidate)
                folders{end+1} = rootCandidate;
            end
            folders = bms.data.BaseDataSource.uniqueExistingFolders(folders);
        end
    end
end
