classdef HongtangLowFreqDataSource < bms.data.BaseDataSource
    %HONGTANGLOWFREQDATASOURCE Hongtang period folder with lowfreq/WIM layout.

    methods
        function obj = HongtangLowFreqDataSource(root, cfg)
            if nargin < 2, cfg = struct(); end
            obj@bms.data.BaseDataSource(root, cfg, 'hongtang_period');
        end

        function folders = candidateDirs(obj, subfolder, startDate, endDate) %#ok<INUSD>
            folders = bms.data.PeriodFolderAdapter.candidateDirs(obj.Root, subfolder, startDate, endDate);
        end

        function p = lowfreqPath(obj)
            p = bms.data.DataLayoutResolver.lowfreqDir(obj.Root);
        end
    end
end
