classdef StatsWriter
    %STATSWRITER Centralized stats table writing helper.

    methods (Static)
        function path = writeTable(T, path, varargin)
            bms.data.DataLayoutResolver.ensureParentDir(path);
            if isempty(T) && ~istable(T)
                T = table();
            end
            writetable(T, path, varargin{:});
        end

        function path = writeTableChecked(T, path, varargin)
            bms.io.StatsWriter.writeTable(T, path, varargin{:});
            if ~isfile(path)
                error('StatsWriter:WriteFailed', 'Stats file was not written: %s', path);
            end
        end

        function path = writeStatsTable(root, fileName, T, varargin)
            path = bms.data.DataLayoutResolver.statsFile(root, fileName);
            bms.io.StatsWriter.writeTable(T, path, varargin{:});
        end

        function path = writeSheet(T, path, sheetName, varargin)
            if nargin < 3 || isempty(sheetName)
                bms.io.StatsWriter.writeTable(T, path, varargin{:});
            else
                bms.io.StatsWriter.writeTable(T, path, 'Sheet', sheetName, varargin{:});
            end
        end

        function T = cellToTable(data, variableNames)
            if nargin < 2
                variableNames = {};
            end
            if isempty(variableNames)
                T = cell2table(data);
            else
                T = cell2table(data, 'VariableNames', variableNames);
            end
        end

        function T = roundNumericColumns(T, digits, columns)
            if nargin < 2 || isempty(digits)
                digits = 2;
            end
            if nargin < 3 || isempty(columns)
                columns = T.Properties.VariableNames;
            elseif ischar(columns) || isstring(columns)
                columns = cellstr(string(columns));
            end
            for i = 1:numel(columns)
                name = char(columns{i});
                if ismember(name, T.Properties.VariableNames) && isnumeric(T.(name))
                    T.(name) = round(T.(name), digits);
                end
            end
        end

        function value = missingText(value, replacement)
            if nargin < 2
                replacement = '/';
            end
            if isnumeric(value) && isscalar(value) && isnan(value)
                value = replacement;
            elseif ismissing(value)
                value = replacement;
            end
        end

        function T = normalizeForReport(T, digits, missingReplacement)
            if nargin < 2 || isempty(digits), digits = 2; end
            if nargin < 3 || isempty(missingReplacement), missingReplacement = '/'; end
            T = bms.io.StatsWriter.roundNumericColumns(T, digits);
            vars = T.Properties.VariableNames;
            for i = 1:numel(vars)
                col = T.(vars{i});
                if isnumeric(col)
                    mask = isnan(col);
                    if any(mask)
                        c = num2cell(col);
                        c(mask) = {missingReplacement};
                        T.(vars{i}) = c;
                    end
                elseif iscell(col)
                    for j = 1:numel(col)
                        if isempty(col{j}) || (isnumeric(col{j}) && isscalar(col{j}) && isnan(col{j}))
                            col{j} = missingReplacement;
                        end
                    end
                    T.(vars{i}) = col;
                end
            end
        end
    end
end
