classdef DataSourceFactory
    %DATASOURCEFACTORY Creates a bridge data source from layout inference.

    methods (Static)
        function src = create(root, cfg)
            if nargin < 2, cfg = struct(); end
            layout = bms.data.DataLayoutResolver.inferLayout(root, cfg);
            switch char(layout)
                case 'jlj_daily_export'
                    src = bms.data.JiulongjiangCsvDataSource(root, cfg);
                case 'hongtang_period'
                    src = bms.data.HongtangLowFreqDataSource(root, cfg);
                otherwise
                    src = bms.data.DefaultCsvDataSource(root, cfg);
            end
        end

        function src = wim(root, cfg)
            if nargin < 2, cfg = struct(); end
            src = bms.data.WimDataSource(root, cfg);
        end
    end
end
