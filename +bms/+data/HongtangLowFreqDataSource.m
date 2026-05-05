classdef HongtangLowFreqDataSource < bms.data.BaseDataSource
    %HONGTANGLOWFREQDATASOURCE Hongtang period folder with lowfreq/WIM layout.

    methods
        function obj = HongtangLowFreqDataSource(root, cfg)
            if nargin < 2, cfg = struct(); end
            obj@bms.data.BaseDataSource(root, cfg, 'hongtang_period');
        end

        function folders = candidateDirs(obj, subfolder, startDate, endDate) %#ok<INUSD>
            folders = candidateDirs@bms.data.BaseDataSource(obj, subfolder, startDate, endDate);
            lowfreq = bms.data.DataLayoutResolver.lowfreqDir(obj.Root);
            if isfolder(lowfreq)
                subfolder = char(string(subfolder));
                if isempty(subfolder)
                    folders{end+1} = lowfreq;
                else
                    candidate = fullfile(lowfreq, subfolder);
                    if isfolder(candidate)
                        folders{end+1} = candidate;
                    end
                end
            end
            folders = bms.data.BaseDataSource.uniqueExistingFolders(folders);
        end

        function p = lowfreqPath(obj)
            p = bms.data.DataLayoutResolver.lowfreqDir(obj.Root);
        end
    end
end
