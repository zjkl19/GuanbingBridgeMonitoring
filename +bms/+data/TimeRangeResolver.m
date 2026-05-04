classdef TimeRangeResolver
    %TIMERANGERESOLVER Parses dates and expands daily/monthly ranges.

    methods (Static)
        function dt = parseDate(value)
            if isa(value, 'datetime')
                dt = value;
            elseif ischar(value) || isstring(value)
                txt = char(string(value));
                try
                    dt = datetime(txt, 'InputFormat', 'yyyy-MM-dd');
                catch
                    dt = datetime(txt, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
                end
            else
                error('BMS:TimeRange:UnsupportedDate', 'Unsupported date value.');
            end
        end

        function daysList = daysBetween(startDate, endDate)
            t0 = dateshift(bms.data.TimeRangeResolver.parseDate(startDate), 'start', 'day');
            t1 = dateshift(bms.data.TimeRangeResolver.parseDate(endDate), 'start', 'day');
            daysList = t0:caldays(1):t1;
        end

        function keys = monthKeys(startDate, endDate)
            t0 = dateshift(bms.data.TimeRangeResolver.parseDate(startDate), 'start', 'month');
            t1 = dateshift(bms.data.TimeRangeResolver.parseDate(endDate), 'start', 'month');
            months = t0:calmonths(1):t1;
            keys = cell(1, numel(months));
            for i = 1:numel(months)
                keys{i} = datestr(months(i), 'yyyymm');
            end
        end
    end
end
