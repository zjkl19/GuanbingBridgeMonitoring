classdef DataLayoutResolver
    %DATALAYOUTRESOLVER Common data-root path conventions.

    methods (Static)
        function p = statsDir(root), p = fullfile(char(root), 'stats'); end
        function p = logDir(root), p = fullfile(char(root), 'run_logs'); end
        function p = wimDir(root), p = fullfile(char(root), 'WIM'); end
        function p = autoReportDir(root), p = fullfile(char(root), char([33258 21160 25253 21578])); end

        function p = ensureDir(p)
            p = char(string(p));
            if ~isempty(p) && ~exist(p, 'dir')
                mkdir(p);
            end
        end

        function p = moduleOutputDir(root, relativeDir)
            p = fullfile(char(root), char(string(relativeDir)));
            bms.data.DataLayoutResolver.ensureDir(p);
        end

        function outPath = statsFile(root, fileName)
            outPath = bms.data.DataLayoutResolver.resolveOutputPath(root, fileName, 'stats');
        end

        function outPath = resolveOutputPath(root, relativePath, subdir)
            if nargin < 3
                subdir = '';
            end
            if nargin < 2 || isempty(relativePath)
                outPath = relativePath;
                return;
            end

            pathStr = char(string(relativePath));
            if bms.data.DataLayoutResolver.isAbsolutePath(pathStr)
                outPath = pathStr;
                bms.data.DataLayoutResolver.ensureParentDir(outPath);
                return;
            end

            baseDir = char(root);
            if ~isempty(subdir)
                baseDir = fullfile(baseDir, char(string(subdir)));
            end
            bms.data.DataLayoutResolver.ensureDir(baseDir);
            outPath = fullfile(baseDir, pathStr);
            bms.data.DataLayoutResolver.ensureParentDir(outPath);
        end

        function ensureParentDir(pathStr)
            parent = fileparts(char(string(pathStr)));
            if ~isempty(parent)
                bms.data.DataLayoutResolver.ensureDir(parent);
            end
        end

        function tf = isAbsolutePath(pathStr)
            pathStr = char(string(pathStr));
            if isempty(pathStr)
                tf = false;
            elseif ispc
                tf = ~isempty(regexp(pathStr, '^[A-Za-z]:[\\/]|^\\\\', 'once'));
            else
                tf = startsWith(pathStr, '/');
            end
        end

        function p = dateFolder(root, dateValue, pattern)
            if nargin < 3 || isempty(pattern), pattern = 'yyyy-mm-dd'; end
            dt = bms.data.TimeRangeResolver.parseDate(dateValue);
            p = fullfile(char(root), datestr(dt, pattern));
        end
    end
end
