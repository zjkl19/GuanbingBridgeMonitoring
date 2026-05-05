classdef TimeRangeResolver
    %TIMERANGERESOLVER Parses dates and expands daily/monthly ranges.

    methods (Static)
        function dt = parseDate(value)
            if isa(value, 'datetime')
                dt = value;
                return;
            end
            if ~(ischar(value) || isstring(value))
                error('BMS:TimeRange:UnsupportedDate', 'Unsupported date value.');
            end
            txt = strtrim(char(string(value)));
            formats = {'yyyy-MM-dd HH:mm:ss','yyyy-MM-dd','yyyy/MM/dd HH:mm:ss','yyyy/MM/dd','yyyy.MM.dd HH:mm:ss','yyyy.MM.dd'};
            lastErr = [];
            for i = 1:numel(formats)
                try
                    dt = datetime(txt, 'InputFormat', formats{i});
                    return;
                catch ME
                    lastErr = ME;
                end
            end
            rethrow(lastErr);
        end

        function [startDt, endDt] = parseRange(startDate, endDate)
            startDt = bms.data.TimeRangeResolver.parseDate(startDate);
            endDt = bms.data.TimeRangeResolver.parseDate(endDate);
            if endDt < startDt
                error('BMS:TimeRange:InvalidRange', 'End date is earlier than start date.');
            end
        end

        function [startDt, endDt] = closedRange(startDate, endDate)
            [startDt, endDt] = bms.data.TimeRangeResolver.parseRange(startDate, endDate);
            startDt = dateshift(startDt, 'start', 'day');
            if endDt == dateshift(endDt, 'start', 'day')
                endDt = dateshift(endDt, 'start', 'day') + days(1) - seconds(1);
            end
            if endDt < startDt
                error('BMS:TimeRange:InvalidRange', 'End date is earlier than start date.');
            end
        end

        function mask = contains(timeValues, startDate, endDate)
            [startDt, endDt] = bms.data.TimeRangeResolver.closedRange(startDate, endDate);
            mask = timeValues >= startDt & timeValues <= endDt;
        end

        function daysList = daysBetween(startDate, endDate)
            [t0, t1] = bms.data.TimeRangeResolver.parseRange(startDate, endDate);
            t0 = dateshift(t0, 'start', 'day');
            t1 = dateshift(t1, 'start', 'day');
            daysList = t0:caldays(1):t1;
        end

        function keys = monthKeys(startDate, endDate)
            [t0, t1] = bms.data.TimeRangeResolver.parseRange(startDate, endDate);
            t0 = dateshift(t0, 'start', 'month');
            t1 = dateshift(t1, 'start', 'month');
            months = t0:calmonths(1):t1;
            keys = cell(1, numel(months));
            for i = 1:numel(months)
                keys{i} = datestr(months(i), 'yyyymm');
            end
        end

        function dt = applyHourOffset(dt, offsetHours)
            dt = bms.data.TimeRangeResolver.parseDate(dt) + hours(double(offsetHours));
        end

        function s = toDateString(dt)
            dt = bms.data.TimeRangeResolver.parseDate(dt);
            s = datestr(dt, 'yyyy-mm-dd');
        end

        function s = normalizeDateText(value)
            s = bms.data.TimeRangeResolver.toDateString(value);
        end
    end
end
