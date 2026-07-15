classdef CachePrebuildService
    %CACHEPREBUILDSERVICE Select the cache builder for the active data layout.
    %   Daily multi-channel exports keep their dedicated jlj_csv_v2 cache.
    %   Dated-folder and Hongtang-period projects use the shared two-column
    %   csv_timeseries_v2 cache consumed by TimeSeriesLoader.  No analysis,
    %   cleaning or statistics are performed here.

    methods (Static)
        function result = run(root, startDate, endDate, cfg, taskOptions)
            if nargin < 4, cfg = struct(); end
            if nargin < 5, taskOptions = struct(); end
            layout = char(string(bms.data.DataLayoutResolver.inferLayout(root, cfg)));
            switch layout
                case 'jlj_daily_export'
                    result = bms.data.JljCachePrebuildService.run( ...
                        root, startDate, endDate, cfg, taskOptions);
                case {'dated_folders', 'hongtang_period'}
                    result = bms.data.TimeSeriesCachePrebuildService.run( ...
                        root, startDate, endDate, cfg, taskOptions);
                otherwise
                    startedAt = datetime('now');
                    message = sprintf( ...
                        'Cache pre-generation does not support data layout: %s', layout);
                    result = bms.analyzer.AnalyzerResult.fail( ...
                        'cache_prebuild', message, '', startedAt, datetime('now'), ...
                        'BMS:CachePrebuild:UnsupportedLayout');
            end
        end

        function tf = supportsLayout(layout)
            tf = any(strcmp(char(string(layout)), ...
                {'dated_folders', 'hongtang_period', 'jlj_daily_export'}));
        end
    end
end
