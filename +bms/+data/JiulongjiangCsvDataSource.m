classdef JiulongjiangCsvDataSource < bms.data.BaseDataSource
    %JIULONGJIANGCSVDATASOURCE Jiulongjiang data_jlj_yyyy-mm-dd export layout.

    methods
        function obj = JiulongjiangCsvDataSource(root, cfg)
            if nargin < 2, cfg = struct(); end
            obj@bms.data.BaseDataSource(root, cfg, 'jlj_daily_export');
        end

        function folders = dateFolders(obj, startDate, endDate)
            folders = bms.data.ZipDailyExportAdapter.dateFolders(obj.Root, startDate, endDate, obj.Config);
        end

        function folders = candidateDirs(obj, subfolder, startDate, endDate)
            csvDirs = bms.data.ZipDailyExportAdapter.csvDirs(obj.Root, startDate, endDate, obj.Config);
            subfolder = char(string(subfolder));
            folders = {};
            for i = 1:numel(csvDirs)
                candidates = {csvDirs{i}};
                if ~isempty(subfolder)
                    candidates = [{fullfile(csvDirs{i}, subfolder)}, candidates]; %#ok<AGROW>
                end
                for j = 1:numel(candidates)
                    if isfolder(candidates{j})
                        folders{end+1} = candidates{j}; %#ok<AGROW>
                        break;
                    end
                end
            end
            folders = bms.data.BaseDataSource.uniqueExistingFolders(folders);
        end
    end
end
