classdef DefaultCsvDataSource < bms.data.BaseDataSource
    %DEFAULTCSVDATASOURCE Date-folder based CSV data source.

    methods
        function obj = DefaultCsvDataSource(root, cfg)
            if nargin < 2, cfg = struct(); end
            obj@bms.data.BaseDataSource(root, cfg, 'dated_folders');
        end
    end
end
