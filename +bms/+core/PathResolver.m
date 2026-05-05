classdef PathResolver
    %PATHRESOLVER Centralizes project/data output paths.

    methods (Static)
        function p = projectRoot()
            here = fileparts(mfilename('fullpath'));
            p = fileparts(fileparts(here));
        end

        function p = defaultConfigPath(projectRoot)
            if nargin < 1 || isempty(projectRoot)
                projectRoot = bms.core.PathResolver.projectRoot();
            end
            p = fullfile(projectRoot, 'config', 'default_config.json');
        end

        function p = statsDir(dataRoot)
            p = fullfile(char(dataRoot), 'stats');
        end

        function p = logDir(dataRoot)
            p = fullfile(char(dataRoot), 'run_logs');
        end

        function p = autoReportDir(dataRoot)
            p = fullfile(char(dataRoot), char([33258 21160 25253 21578]));
        end

        function ensureDir(p)
            if ~exist(p, 'dir')
                mkdir(p);
            end
        end

        function file = latestFile(folder, pattern)
            file = '';
            if nargin < 2 || isempty(pattern), pattern = '*'; end
            if ~exist(folder, 'dir'), return; end
            d = dir(fullfile(folder, pattern));
            d = d(~[d.isdir]);
            if isempty(d), return; end
            [~, idx] = max([d.datenum]);
            file = fullfile(d(idx).folder, d(idx).name);
        end
    end
end
