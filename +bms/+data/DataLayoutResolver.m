classdef DataLayoutResolver
    %DATALAYOUTRESOLVER Common data-root path conventions.

    methods (Static)
        function p = statsDir(root), p = fullfile(char(root), 'stats'); end
        function p = logDir(root), p = fullfile(char(root), 'run_logs'); end
        function p = wimDir(root), p = fullfile(char(root), 'WIM'); end
        function p = autoReportDir(root), p = fullfile(char(root), char([33258 21160 25253 21578])); end

        function p = dateFolder(root, dateValue, pattern)
            if nargin < 3 || isempty(pattern), pattern = 'yyyy-mm-dd'; end
            dt = bms.data.TimeRangeResolver.parseDate(dateValue);
            p = fullfile(char(root), datestr(dt, pattern));
        end
    end
end
