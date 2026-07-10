classdef TimeSeriesRangeLoader
    %TIMESERIESRANGELOADER Orchestrates vendor-aware range loading and cleaning.

    methods (Static)
        function [times, vals, meta] = load(rootDir, subfolder, pointId, startDate, endDate, cfg, sensorType)
            if nargin < 7 || isempty(sensorType)
                sensorType = 'generic';
            end
            if nargin < 6 || isempty(cfg)
                cfg = load_config();
            end

            meta = struct();
            meta.files = {};

            dateList = bms.data.TimeSeriesRangeLoader.buildDateList(startDate, endDate);
            [rangeStart, rangeEnd] = bms.data.TimeRangeResolver.closedRange(startDate, endDate);
            range = struct('start', rangeStart, 'end', rangeEnd);

            loader = bms.data.TimeSeriesRangeLoader.vendorLoader(cfg);
            rules = bms.data.CleaningPipeline.resolveRules(cfg, sensorType, pointId);
            meta.applied_rules = rules;

            [allT, allV, meta, usedRangeLoader] = bms.data.TimeSeriesRangeLoader.tryReadRange( ...
                loader, rootDir, subfolder, pointId, sensorType, range, meta);
            if ~usedRangeLoader
                [allT, allV, meta] = bms.data.TimeSeriesRangeLoader.readByDay( ...
                    loader, rootDir, subfolder, pointId, sensorType, range, dateList, meta);
            end

            if isempty(allT)
                times = [];
                vals = [];
                return;
            end

            [times, vals] = bms.data.TimeSeriesRangeLoader.sortSeries(allT, allV);
            [times, vals] = bms.data.TimeSeriesLoader.clipClosedRange(times, vals, rangeStart, rangeEnd);
            [vals, meta] = bms.data.TimeSeriesRangeLoader.applyCleaning(vals, times, rules, sensorType, pointId, meta);
        end

        function [times, vals, meta] = loadCalendarDay(rootDir, subfolder, pointId, day, cfg, sensorType)
            %LOADCALENDARDAY Reconstruct a day from dated rolling exports.
            % Donghua/Hongtang waveform folders are commonly named for the
            % export end date while their samples span roughly previous-day
            % 09:00 through folder-day 09:00.  A calendar day therefore needs
            % the same-named folder plus the following export folder.  Merge
            % raw inputs first, clip to [day, day+1), then clean exactly once.
            if nargin < 6 || isempty(sensorType)
                sensorType = 'generic';
            end
            if nargin < 5 || isempty(cfg)
                cfg = load_config();
            end

            meta = struct( ...
                'files', {{}}, ...
                'duplicate_timestamp_count', 0, ...
                'conflicting_timestamp_count', 0);
            dayStart = dateshift(bms.data.TimeRangeResolver.parseDate(day), 'start', 'day');
            dayEnd = dayStart + days(1);
            range = struct('start', dayStart, 'end', dayEnd);
            loader = bms.data.TimeSeriesRangeLoader.vendorLoader(cfg);
            rollingExport = isfield(loader, 'rolling_export') ...
                && bms.config.ConfigReader.boolValue(loader.rolling_export, false);
            useLookahead = rollingExport ...
                && bms.data.DatedFolderAdapter.hasDateFolders(rootDir) ...
                && ~bms.data.DataLayoutResolver.isAbsolutePath(subfolder);
            dateList = {bms.data.TimeRangeResolver.toDateString(dayStart)};
            if useLookahead
                dateList{end+1, 1} = bms.data.TimeRangeResolver.toDateString(dayEnd); %#ok<AGROW>
            end

            rules = bms.data.CleaningPipeline.resolveRules(cfg, sensorType, pointId);
            meta.applied_rules = rules;
            forceDailyCalendar = useLookahead ...
                && isfield(loader, 'calendar_day_use_daily_files') ...
                && bms.config.ConfigReader.boolValue(loader.calendar_day_use_daily_files, false);
            allT = [];
            allV = [];
            usedRangeLoader = false;
            if ~forceDailyCalendar
                [allT, allV, meta, usedRangeLoader] = bms.data.TimeSeriesRangeLoader.tryReadRange( ...
                    loader, rootDir, subfolder, pointId, sensorType, range, meta);
            end
            if ~usedRangeLoader
                [allT, allV, meta] = bms.data.TimeSeriesRangeLoader.readByDay( ...
                    loader, rootDir, subfolder, pointId, sensorType, range, dateList, meta, useLookahead, true);
            end

            meta.calendar_day = dateList{1};
            meta.calendar_day_requested_export_dates = dateList;
            meta.calendar_day_lookahead_requested = useLookahead;
            meta.calendar_day_loader_mode = 'daily_files';
            if usedRangeLoader
                meta.calendar_day_loader_mode = 'range_loader';
            end
            if isempty(allT)
                times = [];
                vals = [];
                meta = bms.data.TimeSeriesRangeLoader.finishCalendarDayMeta( ...
                    meta, times, vals, usedRangeLoader);
                return;
            end

            if usedRangeLoader
                keep = allT >= dayStart & allT < dayEnd;
                allT = allT(keep);
                allV = allV(keep);
            end
            [times, vals, duplicateCount, conflictCount] = ...
                bms.data.TimeSeriesRangeLoader.sortUniqueSeries(allT, allV);
            keep = times >= dayStart & times < dayEnd;
            times = times(keep);
            vals = vals(keep);
            meta.duplicate_timestamp_count = duplicateCount;
            meta.conflicting_timestamp_count = conflictCount;
            [vals, meta] = bms.data.TimeSeriesRangeLoader.applyCleaning( ...
                vals, times, rules, sensorType, pointId, meta);
            meta = bms.data.TimeSeriesRangeLoader.finishCalendarDayMeta( ...
                meta, times, vals, usedRangeLoader);
        end

        function [allT, allV, meta, used] = tryReadRange(loader, rootDir, subfolder, pointId, sensorType, range, meta)
            allT = [];
            allV = [];
            used = false;
            if ~isfield(loader, 'read_range') || ~isa(loader.read_range, 'function_handle')
                return;
            end

            [t, v, used, files] = loader.read_range(rootDir, subfolder, pointId, sensorType, range);
            if ~used
                return;
            end
            if ~isempty(files)
                meta.files = files;
            end
            if ~isempty(v)
                allT = [allT; t]; %#ok<AGROW>
                allV = [allV; v]; %#ok<AGROW>
            end
        end

        function [allT, allV, meta] = readByDay(loader, rootDir, subfolder, pointId, sensorType, range, dateList, meta, strictRollingDates, halfOpenEnd)
            if nargin < 9 || isempty(strictRollingDates)
                strictRollingDates = false;
            end
            if nargin < 10 || isempty(halfOpenEnd)
                halfOpenEnd = false;
            end
            allT = [];
            allV = [];
            seenFiles = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            meta.requested_export_dates = dateList;
            meta.found_export_dates = {};
            meta.missing_export_dates = {};
            meta.empty_export_dates = {};
            meta.noncontributing_export_dates = {};
            meta.contributing_export_dates = {};
            meta.ambiguous_export_dates = {};
            meta.resolved_source_roots = {};
            meta.duplicate_file_count = 0;
            for i = 1:numel(dateList)
                day = dateList{i};
                dayMeta = struct('day', day, 'range', range);
                if strictRollingDates
                    [dirp, dayMeta] = bms.data.TimeSeriesRangeLoader.resolveStrictDatedDayDir( ...
                        rootDir, day, subfolder, dayMeta);
                    if isempty(dirp)
                        [dirp, dayMeta] = bms.data.TimeSeriesRangeLoader.resolveAdjacentPartitionDayDir( ...
                            rootDir, day, subfolder, dayMeta);
                    end
                else
                    [dirp, dayMeta] = bms.data.TimeSeriesRangeLoader.resolveDayDir( ...
                        loader, rootDir, day, subfolder, sensorType, dayMeta);
                end
                if isempty(dirp)
                    meta.missing_export_dates = bms.data.TimeSeriesRangeLoader.appendUniqueText( ...
                        meta.missing_export_dates, day);
                    if isfield(dayMeta, 'adjacent_source_status') ...
                            && strcmp(dayMeta.adjacent_source_status, 'ambiguous')
                        meta.ambiguous_export_dates = bms.data.TimeSeriesRangeLoader.appendUniqueText( ...
                            meta.ambiguous_export_dates, day);
                    end
                    continue;
                end

                fp = loader.find_file(dirp, pointId, sensorType, day, dayMeta);
                if isempty(fp)
                    meta.missing_export_dates = bms.data.TimeSeriesRangeLoader.appendUniqueText( ...
                        meta.missing_export_dates, day);
                    continue;
                end

                fileKey = bms.data.TimeSeriesRangeLoader.canonicalFileKey(fp);
                if isKey(seenFiles, fileKey)
                    meta.duplicate_file_count = meta.duplicate_file_count + 1;
                    continue;
                end
                seenFiles(fileKey) = true;

                [t, v] = loader.read_file(fp, sensorType, pointId, day, dayMeta);
                if isempty(v)
                    meta.empty_export_dates = bms.data.TimeSeriesRangeLoader.appendUniqueText( ...
                        meta.empty_export_dates, day);
                    continue;
                end
                meta.found_export_dates = bms.data.TimeSeriesRangeLoader.appendUniqueText( ...
                    meta.found_export_dates, day);
                if isfield(dayMeta, 'resolved_source_root')
                    meta.resolved_source_roots = bms.data.TimeSeriesRangeLoader.appendUniqueText( ...
                        meta.resolved_source_roots, dayMeta.resolved_source_root);
                end
                if isdatetime(t) && numel(t) == numel(v)
                    if halfOpenEnd
                        keep = t >= range.start & t < range.end;
                    else
                        keep = t >= range.start & t <= range.end;
                    end
                    t = t(keep);
                    v = v(keep);
                end
                if isempty(v)
                    meta.noncontributing_export_dates = bms.data.TimeSeriesRangeLoader.appendUniqueText( ...
                        meta.noncontributing_export_dates, day);
                    meta = bms.data.TimeSeriesRangeLoader.mergeDayMeta(meta, dayMeta);
                    meta.files{end+1} = fp; %#ok<AGROW>
                    continue;
                end
                meta.contributing_export_dates = bms.data.TimeSeriesRangeLoader.appendUniqueText( ...
                    meta.contributing_export_dates, day);
                meta = bms.data.TimeSeriesRangeLoader.mergeDayMeta(meta, dayMeta);
                meta.files{end+1} = fp; %#ok<AGROW>
                allT = [allT; t]; %#ok<AGROW>
                allV = [allV; v]; %#ok<AGROW>
            end
        end

        function [dirp, dayMeta] = resolveDayDir(loader, rootDir, day, subfolder, sensorType, dayMeta)
            if isfield(loader, 'get_day_dir')
                [dirp, dayMeta] = loader.get_day_dir(rootDir, day, subfolder, sensorType, dayMeta);
                return;
            end
            dirp = fullfile(rootDir, day, subfolder);
            if ~exist(dirp, 'dir')
                dirp = '';
            end
        end

        function [dirp, dayMeta] = resolveStrictDatedDayDir(rootDir, day, subfolder, dayMeta)
            dirp = '';
            dateCandidates = bms.data.DatedFolderAdapter.dateFolderCandidates(rootDir, day);
            for i = 1:numel(dateCandidates)
                if ~isfolder(dateCandidates{i})
                    continue;
                end
                nested = fullfile(dateCandidates{i}, char(string(subfolder)));
                if isfolder(nested)
                    dirp = nested;
                else
                    dirp = dateCandidates{i};
                end
                dayMeta.data_source = 'bms.data.DatedFolderAdapter.strict';
                dayMeta.resolved_source_root = char(string(rootDir));
                dayMeta.candidate_dirs = {dirp};
                return;
            end
        end

        function [dirp, dayMeta] = resolveAdjacentPartitionDayDir(rootDir, day, subfolder, dayMeta)
            dirp = '';
            [dirs, roots, status] = bms.data.DatedFolderAdapter.adjacentPartitionCandidateDirs( ...
                rootDir, subfolder, day);
            dayMeta.adjacent_source_status = status;
            dayMeta.adjacent_source_roots = roots;
            if strcmp(status, 'resolved') && numel(dirs) == 1
                dirp = dirs{1};
                dayMeta.data_source = 'bms.data.DatedFolderAdapter.adjacent_partition';
                dayMeta.resolved_source_root = roots{1};
                dayMeta.candidate_dirs = dirs;
            end
        end

        function [times, vals] = sortSeries(allT, allV)
            [times, order] = sort(allT);
            vals = allV(order);
        end

        function [times, vals, duplicateCount, conflictCount] = sortUniqueSeries(allT, allV)
            [times, vals] = bms.data.TimeSeriesRangeLoader.sortSeries(allT, allV);
            duplicateCount = 0;
            conflictCount = 0;
            if numel(times) < 2
                return;
            end
            sameNext = [diff(times) == seconds(0); false];
            duplicateCount = nnz(sameNext);
            if duplicateCount > 0
                left = vals(1:end-1);
                right = vals(2:end);
                equalValue = (left == right) | (isnan(left) & isnan(right));
                conflictCount = nnz(sameNext(1:end-1) & ~equalValue);
                keep = ~sameNext;
                times = times(keep);
                vals = vals(keep);
            end
        end

        function meta = mergeDayMeta(meta, dayMeta)
            if nargin < 1 || isempty(meta)
                meta = struct();
            end
            if nargin < 2 || isempty(dayMeta) || ~isstruct(dayMeta)
                return;
            end
            copyFields = {'data_source', 'candidate_dirs'};
            for i = 1:numel(copyFields)
                field = copyFields{i};
                if ~isfield(meta, field) && isfield(dayMeta, field)
                    meta.(field) = dayMeta.(field);
                end
            end
        end

        function [vals, meta] = applyCleaning(vals, times, rules, sensorType, pointId, meta)
            [vals, cleanLog] = bms.data.CleaningPipeline.apply(vals, times, rules, struct( ...
                'record_offset', true, ...
                'sensor_type', sensorType, ...
                'point_id', pointId, ...
                'files', {meta.files}));
            meta.cleaning_log = cleanLog;
            meta.applied_offset_correction = cleanLog.offset_correction;
        end

        function loader = vendorLoader(cfg)
            vendor = 'default';
            if isstruct(cfg) && isfield(cfg, 'vendor') && ~isempty(cfg.vendor)
                vendor = lower(string(cfg.vendor));
            end
            switch vendor
                case {'donghua'}
                    loader = bms.data.TimeSeriesRangeLoader.donghuaLoader(cfg);
                case {'chongyangxi', 'cyx'}
                    loader = bms.data.TimeSeriesRangeLoader.chongyangxiLoader(cfg);
                case {'hongtang'}
                    loader = bms.data.TimeSeriesRangeLoader.hongtangLoader(cfg);
                case {'jiulongjiang', 'jiulong', 'shuixianhua', 'sxh'}
                    loader = bms.data.TimeSeriesRangeLoader.jiulongjiangLoader(cfg);
                otherwise
                    loader = bms.data.TimeSeriesRangeLoader.donghuaLoader(cfg);
            end
        end

        function loader = donghuaLoader(cfg)
            loader.rolling_export = true;
            loader.get_day_dir = @(rootDir, day, subfolder, sensorType, meta) ...
                bms.data.TimeSeriesRangeLoader.dataSourceDayDir(rootDir, day, subfolder, cfg, meta);
            loader.find_file = @(dirp, pointId, sensorType, varargin) ...
                bms.data.TimeSeriesLoader.findSeriesFileForPoint(dirp, pointId, cfg, sensorType);
            loader.read_file = @(fp, sensorType, varargin) ...
                bms.data.TimeSeriesLoader.readSeriesFile(fp, ...
                    bms.data.TimeSeriesRangeLoader.defaultHeaderMarker(cfg), ...
                    struct('cache_version', bms.data.TimeSeriesLoader.seriesCacheVersion(cfg), ...
                    'require_metadata', bms.data.TimeSeriesLoader.seriesCacheRequireMetadata(cfg))); %#ok<NASGU>
        end

        function loader = chongyangxiLoader(cfg)
            loader = bms.data.TimeSeriesRangeLoader.donghuaLoader(cfg);
            loader.calendar_day_use_daily_files = true;
            loader.read_range = @(rootDir, subfolder, pointId, sensorType, range) ...
                bms.data.TimeSeriesRangeLoader.chongyangxiReadRange(rootDir, subfolder, pointId, sensorType, range, cfg);
        end

        function loader = hongtangLoader(cfg)
            loader = bms.data.TimeSeriesRangeLoader.donghuaLoader(cfg);
            loader.get_day_dir = @(rootDir, day, subfolder, sensorType, meta) ...
                bms.data.TimeSeriesRangeLoader.hongtangDayDir(rootDir, day, subfolder, sensorType, meta, cfg);
            loader.read_range = @(rootDir, subfolder, pointId, sensorType, range) ...
                bms.data.HongtangLowFreqDataSource.readRange(rootDir, pointId, sensorType, range, cfg);
        end

        function loader = jiulongjiangLoader(cfg)
            loader.get_day_dir = @(rootDir, day, subfolder, sensorType, meta) ...
                bms.data.JiulongjiangCsvDataSource.getDayDir(rootDir, day, cfg, meta);
            loader.find_file = @(dirp, pointId, sensorType, varargin) ...
                bms.data.JiulongjiangCsvDataSource.findFile(dirp, pointId, sensorType, cfg);
            loader.read_file = @(fp, sensorType, pointId, varargin) ...
                bms.data.JiulongjiangCsvDataSource.readFile(fp, sensorType, pointId, cfg, varargin{:});
        end

        function marker = defaultHeaderMarker(cfg)
            marker = '[绝对时间]';
            if isstruct(cfg) && isfield(cfg, 'defaults') && isstruct(cfg.defaults) ...
                    && isfield(cfg.defaults, 'header_marker') && ~isempty(cfg.defaults.header_marker)
                marker = cfg.defaults.header_marker;
            end
        end

        function [dirp, meta] = dataSourceDayDir(rootDir, day, subfolder, cfg, meta)
            dirp = '';
            if nargin < 5 || isempty(meta)
                meta = struct();
            end
            if isempty(rootDir) || ~exist(rootDir, 'dir')
                return;
            end
            try
                src = bms.data.DataSourceFactory.create(rootDir, cfg);
                dirs = src.candidateDirs(subfolder, day, day);
                meta.data_source = class(src);
                meta.candidate_dirs = dirs;
                if ~isempty(dirs)
                    dirp = dirs{1};
                end
            catch
                dirp = fullfile(rootDir, day, subfolder);
                if ~exist(dirp, 'dir')
                    dirp = '';
                end
            end
        end

        function [dirp, meta] = hongtangDayDir(rootDir, day, subfolder, sensorType, meta, cfg)
            %#ok<INUSD> sensorType is reserved for future Hongtang layout routing.
            dirp = '';
            if nargin < 5 || isempty(meta)
                meta = struct();
            end
            if nargin < 6
                cfg = struct();
            end
            if isempty(rootDir) || ~exist(rootDir, 'dir')
                return;
            end

            if bms.data.DatedFolderAdapter.hasDateFolders(rootDir)
                dirs = bms.data.DatedFolderAdapter.candidateDirs(rootDir, subfolder, day, day);
                meta.data_source = 'bms.data.DatedFolderAdapter';
                meta.candidate_dirs = dirs;
                if ~isempty(dirs)
                    dirp = dirs{1};
                    return;
                end
            end

            [dirp, meta] = bms.data.TimeSeriesRangeLoader.dataSourceDayDir( ...
                rootDir, day, subfolder, cfg, meta);
        end

        function [t, v, used, files] = chongyangxiReadRange(rootDir, subfolder, pointId, sensorType, range, cfg)
            t = [];
            v = [];
            files = {};
            used = true;
            folders = bms.data.TimeSeriesRangeLoader.chongyangxiCandidateDirs(rootDir, subfolder, range.start, range.end, cfg);
            for i = 1:numel(folders)
                fp = bms.data.TimeSeriesLoader.findSeriesFileForPoint(folders{i}, pointId, cfg, sensorType);
                if isempty(fp)
                    continue;
                end
                [ti, vi] = bms.data.TimeSeriesLoader.readSeriesFile( ...
                    fp, bms.data.TimeSeriesRangeLoader.defaultHeaderMarker(cfg), ...
                    struct('cache_version', bms.data.TimeSeriesLoader.seriesCacheVersion(cfg), ...
                    'require_metadata', bms.data.TimeSeriesLoader.seriesCacheRequireMetadata(cfg)));
                if isempty(vi)
                    continue;
                end
                files{end+1} = fp; %#ok<AGROW>
                t = [t; ti]; %#ok<AGROW>
                v = [v; vi]; %#ok<AGROW>
            end
            if ~isempty(t)
                [t, v] = bms.data.TimeSeriesLoader.clipClosedRange(t, v, range.start, range.end);
            end
        end

        function folders = chongyangxiCandidateDirs(rootDir, subfolder, startDate, endDate, cfg)
            %#ok<INUSD> cfg kept for future layout-specific options.
            rootDir = char(string(rootDir));
            subfolder = char(string(subfolder));
            effectiveStart = bms.data.TimeRangeResolver.parseDate(startDate);
            effectiveEnd = bms.data.TimeRangeResolver.parseDate(endDate);
            if effectiveEnd > effectiveStart ...
                    && effectiveEnd == dateshift(effectiveEnd, 'start', 'day')
                effectiveEnd = effectiveEnd - milliseconds(1);
            end
            daysList = bms.data.TimeRangeResolver.daysBetween(effectiveStart, effectiveEnd);
            candidates = {};
            for i = 1:numel(daysList)
                exportDays = [daysList(i), daysList(i) + days(1)];
                for j = 1:numel(exportDays)
                    dayDir = fullfile(rootDir, datestr(exportDays(j), 'yyyy-mm-dd'));
                    if isempty(subfolder)
                        candidates{end+1} = dayDir; %#ok<AGROW>
                    else
                        candidates{end+1} = fullfile(dayDir, subfolder); %#ok<AGROW>
                    end
                end
            end
            folders = bms.data.BaseDataSource.uniqueExistingFolders(candidates);
        end

        function list = buildDateList(startDate, endDate)
            daysList = bms.data.TimeRangeResolver.daysBetween(startDate, endDate);
            list = cell(numel(daysList), 1);
            for i = 1:numel(daysList)
                list{i} = datestr(daysList(i), 'yyyy-mm-dd');
            end
        end

        function meta = finishCalendarDayMeta(meta, times, vals, usedRangeLoader)
            if nargin < 4
                usedRangeLoader = false;
            end
            meta.calendar_day_input_count = numel(vals);
            meta.calendar_day_finite_count = nnz(isfinite(vals));
            meta.calendar_day_coverage_start = '';
            meta.calendar_day_coverage_end = '';
            if ~isempty(times) && isdatetime(times)
                validTimes = times(~isnat(times));
                if ~isempty(validTimes)
                    firstTime = min(validTimes);
                    lastTime = max(validTimes);
                    firstTime.Format = 'yyyy-MM-dd HH:mm:ss.SSS';
                    lastTime.Format = 'yyyy-MM-dd HH:mm:ss.SSS';
                    meta.calendar_day_coverage_start = char(firstTime);
                    meta.calendar_day_coverage_end = char(lastTime);
                end
            end

            if usedRangeLoader
                meta.calendar_day_source_complete = ~isempty(meta.files) && ~isempty(times);
                meta.calendar_day_required_sources_complete = meta.calendar_day_source_complete;
                meta.calendar_day_internal_gap_coverage_assessed = false;
                meta.calendar_day_completeness_scope = 'range_loader_nonempty_unverified';
                meta.calendar_day_missing_required_sources = {};
                meta.calendar_day_ambiguous_sources = {};
                return;
            end

            requested = bms.data.TimeSeriesRangeLoader.metaTextList(meta, 'requested_export_dates');
            contributing = bms.data.TimeSeriesRangeLoader.metaTextList(meta, 'contributing_export_dates');
            missingContribution = setdiff(requested, contributing, 'stable');
            missing = bms.data.TimeSeriesRangeLoader.metaTextList(meta, 'missing_export_dates');
            empty = bms.data.TimeSeriesRangeLoader.metaTextList(meta, 'empty_export_dates');
            noncontributing = bms.data.TimeSeriesRangeLoader.metaTextList(meta, 'noncontributing_export_dates');
            ambiguous = bms.data.TimeSeriesRangeLoader.metaTextList(meta, 'ambiguous_export_dates');
            meta.calendar_day_missing_required_sources = unique( ...
                [missingContribution(:); missing(:); empty(:); noncontributing(:)], 'stable');
            meta.calendar_day_ambiguous_sources = ambiguous;
            meta.calendar_day_source_complete = isempty(meta.calendar_day_missing_required_sources) ...
                && isempty(ambiguous);
            meta.calendar_day_required_sources_complete = meta.calendar_day_source_complete;
            meta.calendar_day_internal_gap_coverage_assessed = false;
            meta.calendar_day_completeness_scope = 'required_export_contribution';
        end

        function values = metaTextList(meta, fieldName)
            values = {};
            if isstruct(meta) && isfield(meta, fieldName) && ~isempty(meta.(fieldName))
                values = cellstr(string(meta.(fieldName)));
            end
        end

        function items = appendUniqueText(items, value)
            if isempty(items)
                items = {};
            end
            textValue = char(string(value));
            if isempty(textValue) || any(strcmp(items, textValue))
                return;
            end
            items{end+1, 1} = textValue;
        end

        function key = canonicalFileKey(path)
            path = char(string(path));
            try
                key = char(java.io.File(path).getCanonicalPath());
            catch
                key = path;
            end
            if ispc
                key = lower(key);
            end
        end
    end
end
