classdef ZipDailyExportAdapter
    %ZIPDAILYEXPORTADAPTER Shared helpers for data_<bridge>_YYYY-MM-DD exports.
    %   Jiulongjiang and Shuixianhua use the same daily ZIP/extracted-folder
    %   convention. Centralising the rules avoids hard-coded data_jlj/data_sxh
    %   checks in preflight, unzip and data loading code.

    methods (Static)
        function adapter = resolve(cfg)
            if nargin < 1 || isempty(cfg), cfg = struct(); end
            adapter = struct();
            adapter.prefixes = bms.data.ZipDailyExportAdapter.prefixes(cfg);
            adapter.zip = struct();
            adapter.csv = struct();
            adapter.cache = struct();

            if isstruct(cfg) && isfield(cfg, 'data_adapter') && isstruct(cfg.data_adapter)
                if isfield(cfg.data_adapter, 'zip') && isstruct(cfg.data_adapter.zip)
                    adapter.zip = cfg.data_adapter.zip;
                end
                if isfield(cfg.data_adapter, 'csv') && isstruct(cfg.data_adapter.csv)
                    adapter.csv = cfg.data_adapter.csv;
                end
                if isfield(cfg.data_adapter, 'cache') && isstruct(cfg.data_adapter.cache)
                    adapter.cache = cfg.data_adapter.cache;
                end
            end

            adapter.zip.glob = bms.data.ZipDailyExportAdapter.fieldDefault(adapter.zip, 'glob', bms.data.ZipDailyExportAdapter.defaultGlobs(adapter.prefixes));
            adapter.zip.date_pattern = bms.data.ZipDailyExportAdapter.fieldDefault(adapter.zip, 'date_pattern', bms.data.ZipDailyExportAdapter.defaultDatePatterns(adapter.prefixes));
            adapter.zip.subdir = bms.data.ZipDailyExportAdapter.fieldDefault(adapter.zip, 'subdir', fullfile('data', adapter.prefixes{1}, 'csv'));
            adapter.zip.staging_root = bms.data.ZipDailyExportAdapter.fieldDefault(adapter.zip, 'staging_root', fullfile('outputs', '_staging', adapter.prefixes{1}));
            adapter.csv.encoding = bms.data.ZipDailyExportAdapter.fieldDefault(adapter.csv, 'encoding', 'UTF-8');
            adapter.csv.delimiter = bms.data.ZipDailyExportAdapter.fieldDefault(adapter.csv, 'delimiter', ',');
            adapter.csv.time_column = bms.data.ZipDailyExportAdapter.fieldDefault(adapter.csv, 'time_column', 'ts');
            adapter.csv.time_format = bms.data.ZipDailyExportAdapter.fieldDefault(adapter.csv, 'time_format', 'yyyy-MM-dd HH:mm:ss.SSS');
            adapter.csv.strip_quotes = bms.data.ZipDailyExportAdapter.fieldDefault(adapter.csv, 'strip_quotes', true);
            adapter.cache.enabled = bms.data.ZipDailyExportAdapter.fieldDefault(adapter.cache, 'enabled', true);
            adapter.cache.dir = bms.data.ZipDailyExportAdapter.fieldDefault(adapter.cache, 'dir', 'cache');
            adapter.cache.validate = bms.data.ZipDailyExportAdapter.fieldDefault(adapter.cache, 'validate', 'mtime_size');
        end

        function prefixes = prefixes(cfg)
            prefixes = {};
            vendor = '';
            if isstruct(cfg) && isfield(cfg, 'vendor') && ~isempty(cfg.vendor)
                vendor = lower(char(string(cfg.vendor)));
            end
            if any(strcmp(vendor, {'shuixianhua', 'sxh'}))
                prefixes = {'sxh'};
            elseif any(strcmp(vendor, {'jiulongjiang', 'jlj'}))
                prefixes = {'jlj'};
            end

            globText = '';
            if isstruct(cfg) && isfield(cfg, 'data_adapter') && isstruct(cfg.data_adapter) ...
                    && isfield(cfg.data_adapter, 'zip') && isstruct(cfg.data_adapter.zip) ...
                    && isfield(cfg.data_adapter.zip, 'glob')
                globText = char(string(cfg.data_adapter.zip.glob));
            end
            if contains(globText, 'data_sxh')
                prefixes = {'sxh'};
            elseif contains(globText, 'data_jlj')
                prefixes = {'jlj'};
            end

            if isempty(prefixes)
                prefixes = {'jlj', 'sxh'};
            end
        end

        function globs = defaultGlobs(prefixes)
            globs = {};
            for i = 1:numel(prefixes)
                globs{end+1} = sprintf('data_%s_*.zip', prefixes{i}); %#ok<AGROW>
                if strcmpi(prefixes{i}, 'jlj')
                    globs{end+1} = 'jljData*.zip'; %#ok<AGROW>
                end
            end
        end

        function patterns = defaultDatePatterns(prefixes)
            patterns = {};
            for i = 1:numel(prefixes)
                patterns{end+1} = ['data_' prefixes{i} '_(\d{4})-(\d{2})-(\d{2})']; %#ok<AGROW>
                if strcmpi(prefixes{i}, 'jlj')
                    patterns{end+1} = 'jljData(\d{8})-\d{8}'; %#ok<AGROW>
                end
            end
        end

        function tf = hasExtracted(root, cfg)
            if nargin < 2, cfg = struct(); end
            root = char(root);
            prefixes = bms.data.ZipDailyExportAdapter.prefixes(cfg);
            tf = false;
            for i = 1:numel(prefixes)
                d = dir(fullfile(root, sprintf('data_%s_*', prefixes{i})));
                tf = tf || any([d.isdir]);
            end
            if any(strcmpi(prefixes, 'jlj'))
                d = dir(fullfile(root, 'jljData*'));
                tf = tf || any([d.isdir]);
            end
        end

        function tf = hasZip(root, cfg)
            if nargin < 2, cfg = struct(); end
            root = char(root);
            adapter = bms.data.ZipDailyExportAdapter.resolve(cfg);
            globs = bms.data.ZipDailyExportAdapter.asCell(adapter.zip.glob);
            tf = false;
            for i = 1:numel(globs)
                tf = tf || ~isempty(dir(fullfile(root, globs{i})));
            end
        end

        function folders = dateFolders(root, startDate, endDate, cfg)
            if nargin < 4, cfg = struct(); end
            root = char(root);
            daysList = bms.data.TimeRangeResolver.daysBetween(startDate, endDate);
            prefixes = bms.data.ZipDailyExportAdapter.prefixes(cfg);
            folders = {};
            for i = 1:numel(daysList)
                dayText = datestr(daysList(i), 'yyyy-mm-dd');
                found = false;
                for p = 1:numel(prefixes)
                    folder = fullfile(root, sprintf('data_%s_%s', prefixes{p}, dayText));
                    if isfolder(folder)
                        folders{end+1} = folder; %#ok<AGROW>
                        found = true;
                        break;
                    end
                end
                if any(strcmpi(prefixes, 'jlj'))
                    startText = datestr(daysList(i), 'yyyymmdd');
                    endText = datestr(daysList(i) + days(1), 'yyyymmdd');
                    legacyFolder = fullfile(root, sprintf('jljData%s-%s', startText, endText));
                    if isfolder(legacyFolder) && (~found || ~strcmp(folder, legacyFolder))
                        folders{end+1} = legacyFolder; %#ok<AGROW>
                    end
                end
            end
        end

        function folders = csvDirs(root, startDate, endDate, cfg)
            if nargin < 4, cfg = struct(); end
            dayFolders = bms.data.ZipDailyExportAdapter.dateFolders(root, startDate, endDate, cfg);
            prefixes = bms.data.ZipDailyExportAdapter.prefixes(cfg);
            folders = {};
            for i = 1:numel(dayFolders)
                candidates = {};
                for p = 1:numel(prefixes)
                    candidates{end+1} = fullfile(dayFolders{i}, 'data', prefixes{p}, 'csv'); %#ok<AGROW>
                end
                candidates = [candidates, {fullfile(dayFolders{i}, 'data', 'jlj', 'csv'), fullfile(dayFolders{i}, 'data', 'sxh', 'csv'), fullfile(dayFolders{i}, 'data', 'csv'), fullfile(dayFolders{i}, 'csv')}]; %#ok<AGROW>
                candidates = unique(candidates, 'stable');
                for j = 1:numel(candidates)
                    if isfolder(candidates{j})
                        folders{end+1} = candidates{j}; %#ok<AGROW>
                        break;
                    end
                end
            end
        end

        function records = collectCsvPointIds(root, startDate, endDate, cfg)
            if nargin < 4, cfg = struct(); end
            dirs = bms.data.ZipDailyExportAdapter.csvDirs(root, startDate, endDate, cfg);
            map = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for i = 1:numel(dirs)
                files = dir(fullfile(dirs{i}, '*.csv'));
                dayText = bms.data.ZipDailyExportAdapter.dayFromPath(dirs{i});
                for j = 1:numel(files)
                    [~, id, ~] = fileparts(files(j).name);
                    if isKey(map, id)
                        rec = map(id);
                    else
                        rec = struct('point_id', id, 'files', {{}}, 'days', {{}});
                    end
                    rec.files{end+1} = fullfile(files(j).folder, files(j).name);
                    if ~isempty(dayText) && ~any(strcmp(rec.days, dayText))
                        rec.days{end+1} = dayText;
                    end
                    map(id) = rec;
                end
            end
            keys = sort(map.keys);
            records = cell(1, numel(keys));
            for i = 1:numel(keys)
                records{i} = map(keys{i});
            end
        end

        function targets = dailyZipTargets(root, startDate, endDate, cfg)
            if nargin < 4, cfg = struct(); end
            root = char(root);
            dn0 = datenum(startDate, 'yyyy-mm-dd');
            dn1 = datenum(endDate, 'yyyy-mm-dd');
            prefixes = bms.data.ZipDailyExportAdapter.prefixes(cfg);
            targets = struct('zip', {}, 'out_dir', {}, 'prefix', {}, 'day', {});
            for p = 1:numel(prefixes)
                files = dir(fullfile(root, sprintf('data_%s_*.zip', prefixes{p})));
                for i = 1:numel(files)
                    tok = regexp(files(i).name, sprintf('^data_%s_(\\d{4})-(\\d{2})-(\\d{2})\\.zip$', prefixes{p}), 'tokens', 'once');
                    if isempty(tok), continue; end
                    day = sprintf('%s-%s-%s', tok{1}, tok{2}, tok{3});
                    dn = datenum(day, 'yyyy-mm-dd');
                    if dn < dn0 || dn > dn1, continue; end
                    targets(end+1) = struct( ...
                        'zip', fullfile(files(i).folder, files(i).name), ...
                        'out_dir', fullfile(root, sprintf('data_%s_%s', prefixes{p}, day)), ...
                        'prefix', prefixes{p}, ...
                        'day', day); %#ok<AGROW>
                end
            end
        end

        function zipPath = findZip(root, dt, zipCfg)
            root = char(root);
            zipPath = '';
            if nargin < 3 || isempty(zipCfg)
                zipCfg = bms.data.ZipDailyExportAdapter.resolve(struct()).zip;
            end
            globs = bms.data.ZipDailyExportAdapter.asCell(zipCfg.glob);
            pats = bms.data.ZipDailyExportAdapter.asCell(zipCfg.date_pattern);
            startText = datestr(dt, 'yyyymmdd');
            dayText = datestr(dt, 'yyyy-mm-dd');
            for g = 1:numel(globs)
                files = dir(fullfile(root, globs{g}));
                for i = 1:numel(files)
                    name = files(i).name;
                    matched = false;
                    for p = 1:numel(pats)
                        tokens = regexp(name, pats{p}, 'tokens', 'once');
                        if isempty(tokens), continue; end
                        if numel(tokens) == 1 && strcmp(tokens{1}, startText)
                            matched = true;
                        elseif numel(tokens) >= 3
                            matched = strcmp(sprintf('%s-%s-%s', tokens{1}, tokens{2}, tokens{3}), dayText);
                        end
                        if matched, break; end
                    end
                    if matched
                        zipPath = fullfile(files(i).folder, name);
                        return;
                    end
                end
            end
        end

        function value = fieldDefault(s, fieldName, fallback)
            value = fallback;
            if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
                value = s.(fieldName);
            end
            if isstring(value), value = char(value); end
        end

        function values = asCell(value)
            if isempty(value)
                values = {};
            elseif iscell(value)
                values = cellstr(string(value));
            elseif isstring(value)
                values = cellstr(value(:));
            else
                values = {char(value)};
            end
        end

        function dayText = dayFromPath(pathValue)
            dayText = '';
            parts = regexp(char(pathValue), '[\\/]', 'split');
            for i = 1:numel(parts)
                tok = regexp(parts{i}, '^data_[A-Za-z0-9]+_(\d{4}-\d{2}-\d{2})$', 'tokens', 'once');
                if ~isempty(tok)
                    dayText = tok{1};
                    return;
                end
            end
        end
    end
end
