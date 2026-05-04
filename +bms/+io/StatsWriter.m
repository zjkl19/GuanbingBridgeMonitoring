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
    end
end
