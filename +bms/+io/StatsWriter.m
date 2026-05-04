classdef StatsWriter
    %STATSWRITER Centralized stats table writing helper.

    methods (Static)
        function path = writeTable(T, path)
            folder = fileparts(path);
            if ~isempty(folder) && ~exist(folder, 'dir')
                mkdir(folder);
            end
            writetable(T, path);
        end
    end
end
