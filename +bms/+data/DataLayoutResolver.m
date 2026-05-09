classdef DataLayoutResolver
    %DATALAYOUTRESOLVER Common data-root path conventions.

    methods (Static)
        function p = statsDir(root), p = fullfile(char(root), 'stats'); end
        function p = logDir(root), p = fullfile(char(root), 'run_logs'); end
        function p = wimDir(root), p = bms.data.PeriodFolderAdapter.wimDir(root); end
        function p = lowfreqDir(root), p = bms.data.PeriodFolderAdapter.lowfreqDir(root); end
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

        function layout = inferLayout(root, cfg)
            if nargin < 2, cfg = struct(); end
            profile = bms.profile.BridgeProfileRegistry.infer(cfg, root);
            layout = profile.DataLayout;
            if isstruct(cfg) && isfield(cfg, 'vendor')
                vendor = lower(char(string(cfg.vendor)));
                if any(strcmp(vendor, {'shuixianhua','sxh'}))
                    layout = 'jlj_daily_export';
                end
            end
            root = char(root);
            if bms.data.PeriodFolderAdapter.hasPeriodLayout(root)
                layout = 'hongtang_period';
            elseif bms.data.DataLayoutResolver.hasJljDailyExport(root, cfg)
                layout = 'jlj_daily_export';
            elseif bms.data.DataLayoutResolver.hasDailyExportZip(root, cfg)
                layout = 'jlj_daily_export';
            elseif bms.data.DataLayoutResolver.hasDateFolders(root)
                layout = 'dated_folders';
            end
        end

        function info = describe(root, cfg)
            if nargin < 2, cfg = struct(); end
            layout = bms.data.DataLayoutResolver.inferLayout(root, cfg);
            info = struct();
            info.root = char(root);
            info.layout = layout;
            info.stats_dir = bms.data.DataLayoutResolver.statsDir(root);
            info.log_dir = bms.data.DataLayoutResolver.logDir(root);
            info.wim_dir = bms.data.DataLayoutResolver.wimDir(root);
            info.lowfreq_dir = bms.data.DataLayoutResolver.lowfreqDir(root);
            info.exists = isfolder(root);
            switch char(layout)
                case 'jlj_daily_export'
                    info.adapter = 'bms.data.ZipDailyExportAdapter';
                case 'hongtang_period'
                    info.adapter = 'bms.data.PeriodFolderAdapter';
                otherwise
                    info.adapter = 'bms.data.DatedFolderAdapter';
            end
        end

        function tf = hasJljDailyExport(root, cfg)
            if nargin < 2, cfg = struct(); end
            tf = bms.data.ZipDailyExportAdapter.hasExtracted(root, cfg);
        end

        function tf = hasDailyExportZip(root, cfg)
            if nargin < 2, cfg = struct(); end
            tf = bms.data.ZipDailyExportAdapter.hasZip(root, cfg);
        end

        function tf = hasDateFolders(root)
            tf = bms.data.DatedFolderAdapter.hasDateFolders(root);
        end

        function folders = dateFolders(root, startDate, endDate, layout)
            if nargin < 4 || isempty(layout)
                layout = bms.data.DataLayoutResolver.inferLayout(root, struct());
            end
            days = bms.data.TimeRangeResolver.daysBetween(startDate, endDate);
            folders = {};
            for i = 1:numel(days)
                switch char(layout)
                    case 'jlj_daily_export'
                        candidates = bms.data.ZipDailyExportAdapter.dateFolders(root, days(i), days(i), struct());
                    case 'hongtang_period'
                        candidates = bms.data.PeriodFolderAdapter.dateFolders(root, days(i), days(i));
                    otherwise
                        candidates = bms.data.DatedFolderAdapter.dateFolderCandidates(root, days(i));
                end
                for j = 1:numel(candidates)
                    if isfolder(candidates{j})
                        folders{end+1} = candidates{j}; %#ok<AGROW>
                        break;
                    end
                end
            end
            folders = bms.data.BaseDataSource.uniqueExistingFolders(folders);
        end

        function folders = jljCsvDirs(root, startDate, endDate)
            folders = bms.data.ZipDailyExportAdapter.csvDirs(root, startDate, endDate, struct());
        end

        function files = wimMonthFiles(root, startDate, endDate, prefix)
            if nargin < 4 || isempty(prefix), prefix = 'HS_Data_'; end
            months = bms.data.TimeRangeResolver.monthKeys(startDate, endDate);
            files = struct('month', {}, 'fmt', {}, 'bcp', {}, 'exists', {});
            for i = 1:numel(months)
                month = months{i};
                [fmt, bcp] = bms.data.DataLayoutResolver.findWimMonthPair(root, month, prefix);
                files(end+1) = struct('month', month, 'fmt', fmt, 'bcp', bcp, 'exists', isfile(fmt) && isfile(bcp)); %#ok<AGROW>
            end
        end

        function [fmt, bcp] = findWimMonthPair(root, month, prefix)
            if nargin < 3 || isempty(prefix), prefix = 'HS_Data_'; end
            candidates = bms.data.DataLayoutResolver.wimSearchDirs(root, month);
            fmt = '';
            bcp = '';
            names = {[prefix month], month};
            for i = 1:numel(candidates)
                for j = 1:numel(names)
                    f = fullfile(candidates{i}, [names{j} '.fmt']);
                    b = fullfile(candidates{i}, [names{j} '.bcp']);
                    if isempty(fmt) && isfile(f), fmt = f; end
                    if isempty(bcp) && isfile(b), bcp = b; end
                    if ~isempty(fmt) && ~isempty(bcp), return; end
                end
            end
            if isempty(candidates)
                candidates = {bms.data.DataLayoutResolver.wimDir(root)};
            end
            fmt = fullfile(candidates{1}, [prefix month '.fmt']);
            bcp = fullfile(candidates{1}, [prefix month '.bcp']);
        end

        function dirs = wimSearchDirs(root, month)
            root = char(root);
            dirs = {fullfile(root, 'WIM'), root};
            dirs{end+1} = fullfile(root, 'WIM', month);
            dirs{end+1} = fullfile(root, 'WIM', [month(1:4) '-' month(5:6)]);
            keep = false(size(dirs));
            for i = 1:numel(dirs)
                keep(i) = isfolder(dirs{i});
            end
            dirs = unique(dirs(keep), 'stable');
        end
    end
end
