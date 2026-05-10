classdef WimReportTableService
    %WIMREPORTTABLESERVICE Shared table builders for WIM reports.

    methods (Static)
        function [labels, counts] = binTable(edges, counts)
            n = numel(edges) - 1;
            labels = strings(n, 1);
            for i = 1:n
                lo = edges(i);
                hi = edges(i + 1);
                if i == n
                    labels(i) = sprintf('>=%.0f', lo);
                else
                    labels(i) = sprintf('%.0f-%.0f', lo, hi - 1);
                end
            end
        end

        function headers = normalizeHeaders(headers)
            if ischar(headers) || isstring(headers)
                headers = cellstr(headers);
            end
            for i = 1:numel(headers)
                if isempty(headers{i})
                    headers{i} = sprintf('Var%d', i);
                end
            end
        end

        function T = buildTopNTable(topn)
            rows = topn.std_rows;
            rows = rows(~cellfun('isempty', rows));
            if isempty(rows)
                T = table();
                return;
            end

            cols = bms.analyzer.WimReportTableService.topNColumns();
            rows = bms.analyzer.WimReportTableService.normalizeRows(rows, numel(cols));
            mat = vertcat(rows{:});
            T = cell2table(mat, 'VariableNames', cols);
            if ismember('plate', T.Properties.VariableNames)
                if iscell(T.plate)
                    T.plate = string(cellfun(@(x) bms.analyzer.WimReportTableService.toStringScalar(x), ...
                        T.plate, 'UniformOutput', false));
                else
                    T.plate = string(T.plate);
                end
            end
            T = addvars(T, (1:height(T)).', 'Before', 1, 'NewVariableNames', 'rank');
        end

        function T = buildRawTopNTable(headers, rawRows)
            rawRows = rawRows(~cellfun('isempty', rawRows));
            if isempty(headers) || isempty(rawRows)
                T = table();
                return;
            end

            headers = bms.analyzer.WimReportTableService.normalizeHeaders(headers);
            rawRows = bms.analyzer.WimReportTableService.normalizeRows(rawRows, numel(headers));
            mat = vertcat(rawRows{:});
            T = cell2table(mat, 'VariableNames', headers);
        end

        function T = convertAxleDistancesMmToM(T)
            if ~istable(T) || isempty(T)
                return;
            end

            varNames = T.Properties.VariableNames;
            for i = 1:numel(varNames)
                name = varNames{i};
                if startsWith(name, 'axledis', 'IgnoreCase', true)
                    vals = bms.analyzer.WimReportTableService.toDouble(T.(name));
                    T.(name) = round(vals ./ 1000, 3);
                end
            end
        end

        function rows = normalizeRows(rows, ncol)
            for i = 1:numel(rows)
                row = rows{i};
                if numel(row) < ncol
                    row = [row, repmat({[]}, 1, ncol - numel(row))];
                elseif numel(row) > ncol
                    row = row(1:ncol);
                end
                rows{i} = row;
            end
        end

        function cols = topNColumns()
            cols = {'lane', 'time', 'axle_num', 'gross_kg', 'speed_kmh', 'plate', ...
                'axle1', 'axle2', 'axle3', 'axle4', 'axle5', 'axle6', 'axle7', 'axle8', ...
                'axledis1', 'axledis2', 'axledis3', 'axledis4', 'axledis5', 'axledis6', 'axledis7'};
        end

        function s = toStringScalar(x)
            if isstring(x)
                if numel(x) > 1
                    s = strjoin(x(:).', '');
                else
                    s = x;
                end
            elseif ischar(x)
                if size(x, 1) > 1
                    s = strjoin(cellstr(x), '');
                else
                    s = string(x);
                end
            elseif isnumeric(x)
                s = string(x);
                if numel(s) > 1
                    s = strjoin(s(:).', '');
                end
            else
                try
                    s = string(x);
                    if numel(s) > 1
                        s = strjoin(s(:).', '');
                    end
                catch
                    s = "";
                end
            end
        end

        function values = toDouble(x)
            values = NaN(size(x));
            if iscell(x)
                for i = 1:numel(x)
                    values(i) = str2double(string(x{i}));
                end
            elseif isstring(x) || ischar(x)
                values = str2double(string(x));
            else
                values = double(x);
            end
        end
    end
end
