classdef TimeSeriesLoader
    %TIMESERIESLOADER Shared CSV time-series loading helper.

    methods (Static)
        function T = readCsv(path)
            if nargin < 1 || isempty(path) || ~isfile(path)
                error('TimeSeriesLoader:InputMissing', 'CSV file not found: %s', char(path));
            end
            opts = detectImportOptions(path, 'VariableNamingRule', 'preserve');
            T = readtable(path, opts);
        end

        function name = detectTimeColumn(T)
            name = '';
            if ~istable(T) || isempty(T.Properties.VariableNames)
                return;
            end
            names = T.Properties.VariableNames;
            preferred = {'time','Time','timestamp','Timestamp','datetime','DateTime','date_time','日期','时间'};
            for i = 1:numel(preferred)
                idx = find(strcmpi(names, preferred{i}), 1);
                if ~isempty(idx)
                    name = names{idx};
                    return;
                end
            end
            for i = 1:numel(names)
                col = T.(names{i});
                if isdatetime(col) || isduration(col)
                    name = names{i};
                    return;
                end
            end
        end

        function name = detectValueColumn(T, preferredNames)
            if nargin < 2
                preferredNames = {};
            end
            name = '';
            if ~istable(T), return; end
            names = T.Properties.VariableNames;
            if ischar(preferredNames) || isstring(preferredNames)
                preferredNames = cellstr(string(preferredNames));
            end
            for i = 1:numel(preferredNames)
                idx = find(strcmpi(names, preferredNames{i}), 1);
                if ~isempty(idx) && isnumeric(T.(names{idx}))
                    name = names{idx};
                    return;
                end
            end
            timeName = bms.data.TimeSeriesLoader.detectTimeColumn(T);
            for i = 1:numel(names)
                if strcmp(names{i}, timeName), continue; end
                if isnumeric(T.(names{i}))
                    name = names{i};
                    return;
                end
            end
        end

        function [t, v] = columns(T, preferredValueNames)
            if nargin < 2, preferredValueNames = {}; end
            timeName = bms.data.TimeSeriesLoader.detectTimeColumn(T);
            valueName = bms.data.TimeSeriesLoader.detectValueColumn(T, preferredValueNames);
            if isempty(timeName) || isempty(valueName)
                error('TimeSeriesLoader:ColumnMissing', 'Cannot detect time/value columns.');
            end
            t = T.(timeName);
            v = T.(valueName);
            if ~isdatetime(t)
                t = bms.data.TimeSeriesLoader.toDatetime(t);
            end
        end

        function names = detectNumericColumns(T, excludeNames)
            if nargin < 2, excludeNames = {}; end
            if ischar(excludeNames) || isstring(excludeNames)
                excludeNames = cellstr(string(excludeNames));
            end
            names = {};
            if ~istable(T), return; end
            vars = T.Properties.VariableNames;
            for i = 1:numel(vars)
                if ismember(vars{i}, excludeNames), continue; end
                if isnumeric(T.(vars{i}))
                    names{end+1} = vars{i}; %#ok<AGROW>
                end
            end
        end

        function series = readSeries(path, preferredValueNames, startDate, endDate)
            if nargin < 2, preferredValueNames = {}; end
            T = bms.data.TimeSeriesLoader.readCsv(path);
            [t, v] = bms.data.TimeSeriesLoader.columns(T, preferredValueNames);
            if nargin >= 4 && ~isempty(startDate) && ~isempty(endDate)
                [t, v] = bms.data.TimeSeriesLoader.clip(t, v, startDate, endDate);
            end
            series = struct();
            series.path = char(string(path));
            series.time = t;
            series.value = v;
            series.time_column = bms.data.TimeSeriesLoader.detectTimeColumn(T);
            series.value_column = bms.data.TimeSeriesLoader.detectValueColumn(T, preferredValueNames);
            series.sample_count = numel(v);
            series.valid_count = sum(~isnan(v));
        end

        function [t, v] = clipClosedRange(t, v, rangeStart, rangeEnd)
            if ~isdatetime(t)
                t = bms.data.TimeSeriesLoader.toDatetime(t);
            end
            if ~isdatetime(rangeStart), rangeStart = bms.data.TimeSeriesLoader.toDatetime(rangeStart); end
            if ~isdatetime(rangeEnd), rangeEnd = bms.data.TimeSeriesLoader.toDatetime(rangeEnd); end
            mask = t >= rangeStart & t <= rangeEnd;
            t = t(mask);
            v = v(mask);
        end

        function summary = summarize(t, v)
            if ~isdatetime(t)
                t = bms.data.TimeSeriesLoader.toDatetime(t);
            end
            summary = struct();
            summary.sample_count = numel(v);
            summary.nan_count = sum(isnan(v));
            summary.valid_count = sum(~isnan(v));
            summary.start_time = '';
            summary.end_time = '';
            summary.min_value = NaN;
            summary.max_value = NaN;
            summary.mean_value = NaN;
            if ~isempty(t)
                summary.start_time = datestr(min(t), 'yyyy-mm-dd HH:MM:ss');
                summary.end_time = datestr(max(t), 'yyyy-mm-dd HH:MM:ss');
            end
            if ~isempty(v)
                summary.min_value = min(v, [], 'omitnan');
                summary.max_value = max(v, [], 'omitnan');
                summary.mean_value = mean(v, 'omitnan');
            end
        end

        function [t, v] = clip(t, v, startDate, endDate)
            if ~isdatetime(t)
                t = bms.data.TimeSeriesLoader.toDatetime(t);
            end
            s = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
            e = datetime(endDate, 'InputFormat', 'yyyy-MM-dd') + days(1) - seconds(1);
            mask = t >= s & t <= e;
            t = t(mask);
            v = v(mask);
        end

        function t = toDatetime(raw)
            if isdatetime(raw)
                t = raw;
            elseif isnumeric(raw)
                t = datetime(raw, 'ConvertFrom', 'datenum');
            else
                txt = string(raw);
                try
                    t = datetime(txt, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
                catch
                    t = datetime(txt);
                end
            end
        end
    end
end
