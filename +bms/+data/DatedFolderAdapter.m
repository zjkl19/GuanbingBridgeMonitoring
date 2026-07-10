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

        function [folders, sourceRoots, status] = adjacentPartitionCandidateDirs(root, subfolder, dateValue)
            %ADJACENTPARTITIONCANDIDATEDIRS Resolve a cross-month/quarter date folder.
            % Search is intentionally narrow: only a later exact date folder
            % under a sibling partition with the same strict naming family is
            % eligible.  Ambiguous matches are rejected rather than guessed.
            folders = {};
            sourceRoots = {};
            status = 'not_applicable';
            root = char(string(root));
            if numel(root) > 3
                root = regexprep(root, '[\\/]+$', '');
            end
            subfolder = char(string(subfolder));
            if isempty(root) || isempty(subfolder) ...
                    || bms.data.DataLayoutResolver.isAbsolutePath(subfolder)
                return;
            end

            targetDate = dateshift(bms.data.TimeRangeResolver.parseDate(dateValue), 'start', 'day');
            maxDate = bms.data.DatedFolderAdapter.maxDirectDate(root);
            if isnat(maxDate) || targetDate <= maxDate
                status = 'within_current_partition';
                return;
            end

            [parentDir, rootName] = fileparts(root);
            family = bms.data.DatedFolderAdapter.partitionFamily(rootName);
            if isempty(parentDir) || isempty(family) || ~isfolder(parentDir)
                return;
            end

            siblings = dir(parentDir);
            siblings = siblings([siblings.isdir]);
            dayFolders = {};
            roots = {};
            for i = 1:numel(siblings)
                name = siblings(i).name;
                if any(strcmp(name, {'.', '..', rootName})) ...
                        || ~strcmp(bms.data.DatedFolderAdapter.partitionFamily(name), family)
                    continue;
                end
                siblingRoot = fullfile(siblings(i).folder, name);
                dateCandidates = bms.data.DatedFolderAdapter.dateFolderCandidates(siblingRoot, targetDate);
                for j = 1:numel(dateCandidates)
                    if isfolder(dateCandidates{j})
                        dayFolders{end+1, 1} = dateCandidates{j}; %#ok<AGROW>
                        roots{end+1, 1} = siblingRoot; %#ok<AGROW>
                        break;
                    end
                end
            end

            if isempty(dayFolders)
                status = 'missing';
                return;
            end
            uniqueDays = bms.data.BaseDataSource.uniqueExistingFolders(dayFolders);
            if numel(uniqueDays) ~= 1
                status = 'ambiguous';
                sourceRoots = bms.data.BaseDataSource.uniqueExistingFolders(roots);
                return;
            end

            dayFolder = uniqueDays{1};
            nested = fullfile(dayFolder, subfolder);
            if isfolder(nested)
                folders = {nested};
            else
                folders = {dayFolder};
            end
            sourceRoots = bms.data.BaseDataSource.uniqueExistingFolders(roots);
            status = 'resolved';
        end

        function dt = maxDirectDate(root)
            dt = NaT;
            if isempty(root) || ~isfolder(root)
                return;
            end
            entries = dir(root);
            entries = entries([entries.isdir]);
            values = NaT(numel(entries), 1);
            n = 0;
            for i = 1:numel(entries)
                name = entries(i).name;
                if isempty(regexp(name, '^(20\d{2})-(\d{2})-(\d{2})$', 'once')) ...
                        && isempty(regexp(name, '^(20\d{2})(\d{2})(\d{2})$', 'once'))
                    continue;
                end
                try
                    n = n + 1;
                    if contains(name, '-')
                        values(n) = datetime(name, 'InputFormat', 'yyyy-MM-dd');
                    else
                        values(n) = datetime(name, 'InputFormat', 'yyyyMMdd');
                    end
                catch
                    n = n - 1;
                end
            end
            if n > 0
                dt = max(values(1:n));
            end
        end

        function family = partitionFamily(name)
            name = char(string(name));
            family = '';
            if ~isempty(regexp(name, '^20\d{2}年\d{1,2}月$', 'once'))
                family = 'cn_month';
            elseif ~isempty(regexp(name, '^20\d{2}年\d{1,2}-\d{1,2}月$', 'once'))
                family = 'cn_period';
            elseif ~isempty(regexp(name, '^20\d{2}[-_]\d{1,2}$', 'once'))
                family = 'numeric_month';
            elseif ~isempty(regexp(name, '^20\d{4}$', 'once'))
                family = 'compact_month';
            end
        end
    end
end
