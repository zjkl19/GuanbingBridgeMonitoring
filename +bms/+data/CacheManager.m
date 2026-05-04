classdef CacheManager
    %CACHEMANAGER Small helpers for cache file freshness checks.

    methods (Static)
        function p = cacheDir(folder), p = fullfile(char(folder), 'cache'); end

        function tf = isFresh(cacheFile, sourceFiles)
            if ~isfile(cacheFile)
                tf = false;
                return;
            end
            c = dir(cacheFile);
            if ischar(sourceFiles) || isstring(sourceFiles), sourceFiles = cellstr(string(sourceFiles)); end
            tf = true;
            for i = 1:numel(sourceFiles)
                src = char(string(sourceFiles{i}));
                if isfile(src)
                    d = dir(src);
                    if d.datenum > c.datenum
                        tf = false;
                        return;
                    end
                end
            end
        end
    end
end
