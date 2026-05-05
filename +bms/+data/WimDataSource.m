classdef WimDataSource < bms.data.BaseDataSource
    %WIMDATASOURCE Month-file discovery for WIM fmt/bcp inputs.

    methods
        function obj = WimDataSource(root, cfg)
            if nargin < 2, cfg = struct(); end
            obj@bms.data.BaseDataSource(root, cfg, 'wim_month_files');
        end

        function files = monthFiles(obj, startDate, endDate)
            files = bms.data.DataLayoutResolver.wimMonthFiles(obj.Root, startDate, endDate, obj.filePrefix());
        end

        function prefix = filePrefix(obj)
            prefix = 'HS_Data_';
            if isstruct(obj.Config) && isfield(obj.Config, 'wim') && isstruct(obj.Config.wim) ...
                    && isfield(obj.Config.wim, 'file_prefix') && ~isempty(obj.Config.wim.file_prefix)
                prefix = char(string(obj.Config.wim.file_prefix));
            end
        end
    end
end
