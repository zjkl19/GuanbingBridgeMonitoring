classdef JljCachePrebuildService
    %JLJCACHEPREBUILDSERVICE Pre-generates raw MAT caches for daily ZIP exports.
    %   This service supports only the jlj_daily_export layout shared by
    %   Jiulongjiang and Shuixianhua. Cache workers never delete source data;
    %   the parent process may commit an explicitly confirmed, verified daily
    %   CSV cleanup after every cache and recovery proof closes. ZIP archives,
    %   WIM/Excel and unconfigured CSV files are always retained.

    methods (Static)
        function result = run(root, startDate, endDate, cfg, taskOptions)
            if nargin < 4, cfg = struct(); end
            if nargin < 5, taskOptions = struct(); end
            startedAt = datetime('now');
            summary = bms.data.JljCachePrebuildService.emptySummary(root, startDate, endDate);
            options = struct('manifest_dir', fullfile(char(string(root)), 'run_logs'), ...
                'manifest_path', '');

            try
                options = bms.data.JljCachePrebuildService.optionsFromConfig(root, cfg);
                cleanupOptions = ...
                    bms.data.VerifiedSourceCsvCleanupService.optionsFromTask(taskOptions);
                summary.source_cleanup_enabled = cleanupOptions.enabled;
                if ~isfolder(root)
                    error('BMS:JljCachePrebuild:RootMissing', ...
                        'Data root does not exist: %s', char(string(root)));
                end
                daysList = bms.data.TimeRangeResolver.daysBetween(startDate, endDate);
                dayMutationCleanups = cell(1, numel(daysList)); %#ok<NASGU>
                for dayIndex = 1:numel(daysList)
                    dayMutationCleanups{dayIndex} = ...
                        bms.data.DailyExportMutationLock.acquire( ...
                        root, datestr(daysList(dayIndex), 'yyyy-mm-dd'));
                end
                runLock = bms.data.JiulongjiangCsvDataSource.acquireBuildLock( ...
                    fullfile(char(string(root)), '.bms_jlj_cache_prebuild.lock')); %#ok<NASGU>
                layout = char(string(bms.data.DataLayoutResolver.inferLayout(root, cfg)));
                summary.layout = layout;
                if ~strcmp(layout, 'jlj_daily_export')
                    error('BMS:JljCachePrebuild:UnsupportedLayout', ...
                        'Cache pre-generation supports only jlj_daily_export; actual layout is %s.', layout);
                end

                adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(cfg);
                if ~adapter.cache.enabled
                    error('BMS:JljCachePrebuild:CacheDisabled', ...
                        'The jlj_daily_export cache is disabled by configuration.');
                end
                if bms.data.DataLayoutResolver.isAbsolutePath(adapter.cache.dir)
                    error('BMS:JljCachePrebuild:AbsoluteCacheDirUnsupported', ...
                        ['Cache pre-generation requires a per-day relative cache directory. ' ...
                         'An absolute cache.dir would collide across daily files: %s'], adapter.cache.dir);
                end
                if ~isfinite(options.min_free_gib) || options.min_free_gib < 0 ...
                        || ~isfinite(options.min_free_fraction) || options.min_free_fraction < 0 ...
                        || options.min_free_fraction > 1 ...
                        || ~isfinite(options.estimated_cache_ratio) || options.estimated_cache_ratio <= 0
                    error('BMS:JljCachePrebuild:InvalidDiskPolicy', ...
                        'Invalid min_free_gib, min_free_fraction or estimated_cache_ratio.');
                end
                summary.requested_workers = options.max_workers;
                if ~isfinite(options.max_workers) || options.max_workers < 1 ...
                        || options.max_workers ~= floor(options.max_workers)
                    error('BMS:JljCachePrebuild:InvalidWorkers', ...
                        'cache_prebuild.max_workers must be a positive integer.');
                end
                summary.vendor = bms.data.JljCachePrebuildService.vendorText(cfg, adapter);
                summary.cache_version = 'jlj_csv_v2';
                summary.config_hash = bms.data.CacheManager.configHash(adapter);

                [csvDirs, discovery] = bms.data.JljCachePrebuildService.discoverCsvFiles( ...
                    root, startDate, endDate, cfg, taskOptions, ...
                    summary.cache_version, summary.config_hash);
                if cleanupOptions.enabled
                    discovery = bms.data.JljCachePrebuildService. ...
                        applyCleanupConfigurationWhitelist(discovery, cfg);
                end
                summary.csv_dirs = csvDirs;
                summary.csv_dir_count = numel(csvDirs);
                summary.discovered_count = numel(discovery);
                summary.discovered_file_count = summary.discovered_count;
                if isempty(discovery)
                    error('BMS:JljCachePrebuild:NoCsvFiles', ...
                        'No extracted CSV files were found in the requested date range.');
                end

                classifications = cellstr(string({discovery.classification}));
                eligibleRecords = discovery(strcmp(classifications, 'eligible'));
                skippedRecords = discovery(strcmp(classifications, 'skipped'));
                invalidRecords = discovery(strcmp(classifications, 'invalid'));
                summary.eligible_count = numel(eligibleRecords);
                summary.skipped_count = numel(skippedRecords);
                summary.invalid_count = numel(invalidRecords);
                summary.discovered_source_bytes = sum(double([discovery.source_bytes]));
                summary.eligible_source_bytes = bms.data.JljCachePrebuildService.discoveryBytes(eligibleRecords);
                summary.skipped_source_bytes = bms.data.JljCachePrebuildService.discoveryBytes(skippedRecords);
                summary.invalid_source_bytes = bms.data.JljCachePrebuildService.discoveryBytes(invalidRecords);
                summary.source_file_count = summary.eligible_count;
                summary.source_bytes = summary.eligible_source_bytes;
                summary.skipped_files = skippedRecords;
                eligibleFiles = cellstr(string({eligibleRecords.path}));
                bms.data.JljCachePrebuildService.assertUniqueCachePaths(eligibleFiles, cfg);

                [freeBefore, volumeTotal] = bms.data.JljCachePrebuildService.diskCapacity(root);
                summary.free_bytes_before = freeBefore;
                summary.volume_total_bytes = volumeTotal;
                [summary.pending_file_count, summary.pending_source_bytes, ...
                    summary.pending_backup_bytes] = ...
                    bms.data.JljCachePrebuildService.pendingBuildBytes(eligibleFiles, cfg, options.force_rebuild);
                summary.estimated_cache_ratio = options.estimated_cache_ratio;
                summary.min_free_gib = options.min_free_gib;
                summary.min_free_fraction = options.min_free_fraction;
                if ~isfinite(summary.free_bytes_before) || summary.free_bytes_before < 0 ...
                        || ~isfinite(summary.volume_total_bytes) || summary.volume_total_bytes <= 0
                    error('BMS:JljCachePrebuild:DiskInfoUnavailable', ...
                        'Unable to determine free and total space for data root: %s', root);
                end
                capacity = bms.data.JljCachePrebuildService.evaluateCapacity( ...
                    summary.free_bytes_before, summary.volume_total_bytes, ...
                    summary.pending_source_bytes, summary.pending_backup_bytes, ...
                    options.min_free_gib, options.min_free_fraction, ...
                    options.estimated_cache_ratio);
                summary.projected_cache_bytes = capacity.projected_cache_bytes;
                summary.projected_write_bytes = capacity.projected_write_bytes;
                summary.reserve_bytes = capacity.reserve_bytes;
                summary.projected_free_bytes = capacity.projected_free_bytes;
                if ~capacity.allowed
                    error('BMS:JljCachePrebuild:InsufficientDisk', ...
                        ['Cache pre-generation requires %.3f GiB projected writes and %.3f GiB reserve; ' ...
                         'only %.3f GiB is currently free. No cache files were written.'], ...
                        summary.projected_write_bytes / 1024^3, ...
                        summary.reserve_bytes / 1024^3, ...
                        summary.free_bytes_before / 1024^3);
                end

                recordCells = cell(1, numel(invalidRecords) + numel(eligibleRecords));
                recordIndex = 0;
                for i = 1:numel(invalidRecords)
                    recordIndex = recordIndex + 1;
                    fileStartedAt = datetime('now');
                    ME = MException(invalidRecords(i).error_identifier, ...
                        '%s', invalidRecords(i).error_message);
                    rec = bms.data.JljCachePrebuildService.failureRecord( ...
                        invalidRecords(i).path, cfg, ME);
                    rec = bms.data.JljCachePrebuildService.decorateRecord( ...
                        rec, invalidRecords(i));
                    fileEndedAt = datetime('now');
                    rec.started_at = bms.data.JljCachePrebuildService.formatTime(fileStartedAt);
                    rec.ended_at = bms.data.JljCachePrebuildService.formatTime(fileEndedAt);
                    rec.elapsed_sec = max(0, seconds(fileEndedAt - fileStartedAt));
                    recordCells{recordIndex} = rec;
                end
                workers = min(options.max_workers, numel(eligibleRecords));
                if workers > 1
                    workers = bms.data.JljCachePrebuildService.ensurePool(workers);
                end
                summary.workers_used = workers;
                summary.parallel_used = workers > 1;
                eligibleCells = cell(1, numel(eligibleRecords));
                cleanupCells = {};
                forceRebuild = options.force_rebuild;
                if cleanupOptions.enabled
                    groupKeys = unique(cellstr(string({eligibleRecords.csv_dir})), 'stable');
                    for g = 1:numel(groupKeys)
                        indexes = find(strcmp(cellstr(string({eligibleRecords.csv_dir})), groupKeys{g}));
                        groupCells = cell(1, numel(indexes));
                        if workers > 1
                            parfor (j = 1:numel(indexes), workers)
                                groupCells{j} = bms.data.JljCachePrebuildService.processEligibleRecord( ...
                                    eligibleRecords(indexes(j)), cfg, forceRebuild);
                            end
                        else
                            for j = 1:numel(indexes)
                                groupCells{j} = bms.data.JljCachePrebuildService.processEligibleRecord( ...
                                    eligibleRecords(indexes(j)), cfg, forceRebuild);
                            end
                        end
                        for j = 1:numel(indexes)
                            eligibleCells{indexes(j)} = groupCells{j};
                        end
                        invalidHere = ~isempty(invalidRecords) && any(strcmp( ...
                            cellstr(string({invalidRecords.csv_dir})), groupKeys{g}));
                        if ~invalidHere
                            partitionRoot = bms.data.VerifiedSourceCsvCleanupService.partitionRoot( ...
                                groupKeys{g});
                            dayText = bms.data.JljCachePrebuildService.dayForPartition( ...
                                partitionRoot, startDate, endDate);
                            cleanupCells{end+1} = ... %#ok<AGROW>
                                bms.data.VerifiedSourceCsvCleanupService.commitJljPartition( ...
                                    root, dayText, groupKeys{g}, [groupCells{:}], cfg, ...
                                    taskOptions, summary.cache_version, summary.config_hash);
                        end
                    end
                elseif workers > 1
                    parfor (i = 1:numel(eligibleRecords), workers)
                        eligibleCells{i} = bms.data.JljCachePrebuildService.processEligibleRecord( ...
                            eligibleRecords(i), cfg, forceRebuild);
                    end
                else
                    for i = 1:numel(eligibleRecords)
                        eligibleCells{i} = bms.data.JljCachePrebuildService.processEligibleRecord( ...
                            eligibleRecords(i), cfg, forceRebuild);
                    end
                end
                for i = 1:numel(eligibleCells)
                    recordIndex = recordIndex + 1;
                    recordCells{recordIndex} = eligibleCells{i};
                end
                if isempty(recordCells)
                    records = struct([]);
                else
                    records = [recordCells{:}];
                end

                summary.files = records;
                if isempty(cleanupCells)
                    summary.source_cleanup = struct([]);
                else
                    summary.source_cleanup = [cleanupCells{:}];
                end
                summary = bms.data.JljCachePrebuildService.finalizeSummary(summary, records);
                summary.free_bytes_after = bms.data.JljCachePrebuildService.freeBytes(root);
                summary.ended_at = bms.data.JljCachePrebuildService.formatTime(datetime('now'));
                summary.elapsed_sec = max(0, seconds(datetime('now') - startedAt));

                noEligible = summary.eligible_count == 0;
                summary.no_eligible_timeseries = noEligible;
                if noEligible
                    summary.error_identifier = 'BMS:JljCachePrebuild:NoEligibleTimeSeriesCsv';
                end
                if summary.failed_count > 0 || noEligible
                    summary.status = 'fail';
                    summary.message = sprintf( ...
                        ['discovered=%d; eligible=%d; skipped=%d; created=%d; ' ...
                         'reused=%d; rebuilt=%d; failed=%d; no_eligible=%d'], ...
                        summary.discovered_count, summary.eligible_count, summary.skipped_count, ...
                        summary.created_count, summary.reused_count, ...
                        summary.rebuilt_count, summary.failed_count, noEligible);
                else
                    summary.status = 'ok';
                    summary.message = sprintf( ...
                        ['discovered=%d; eligible=%d; skipped=%d; created=%d; ' ...
                         'reused=%d; rebuilt=%d; failed=0'], ...
                        summary.discovered_count, summary.eligible_count, summary.skipped_count, ...
                        summary.created_count, summary.reused_count, ...
                        summary.rebuilt_count);
                end
                manifestPath = bms.data.JljCachePrebuildService.writeSummary(options, summary);

                if summary.failed_count > 0 || noEligible
                    result = bms.analyzer.AnalyzerResult.fail( ...
                        'cache_prebuild', summary.message, manifestPath, startedAt, datetime('now'));
                else
                    artifacts = {struct('kind', 'manifest', 'path', manifestPath, ...
                        'role', 'cache_prebuild_summary')};
                    result = bms.analyzer.AnalyzerResult.ok( ...
                        'cache_prebuild', manifestPath, artifacts, {}, ...
                        startedAt, datetime('now'), summary.message);
                end
            catch ME
                endedAt = datetime('now');
                summary.status = 'fail';
                summary.message = ME.message;
                summary.error_identifier = ME.identifier;
                summary.free_bytes_after = bms.data.JljCachePrebuildService.freeBytes(root);
                summary.ended_at = bms.data.JljCachePrebuildService.formatTime(endedAt);
                summary.elapsed_sec = max(0, seconds(endedAt - startedAt));
                try
                    manifestPath = bms.data.JljCachePrebuildService.writeSummary(options, summary);
                catch
                    manifestPath = '';
                end
                result = bms.analyzer.AnalyzerResult.fail( ...
                    'cache_prebuild', ME.message, manifestPath, startedAt, endedAt);
            end
        end

        function options = optionsFromConfig(root, cfg)
            section = struct();
            if isstruct(cfg) && isfield(cfg, 'cache_prebuild') && isstruct(cfg.cache_prebuild)
                section = cfg.cache_prebuild;
            end
            if isstruct(cfg) && isfield(cfg, 'preprocess') && isstruct(cfg.preprocess) ...
                    && isfield(cfg.preprocess, 'cache_prebuild') ...
                    && isstruct(cfg.preprocess.cache_prebuild)
                section = bms.data.JljCachePrebuildService.overlay( ...
                    section, cfg.preprocess.cache_prebuild);
            end
            if isstruct(cfg) && isfield(cfg, 'preprocessing') && isstruct(cfg.preprocessing) ...
                    && isfield(cfg.preprocessing, 'cache_prebuild') ...
                    && isstruct(cfg.preprocessing.cache_prebuild)
                section = bms.data.JljCachePrebuildService.overlay( ...
                    section, cfg.preprocessing.cache_prebuild);
            end
            bms.data.JljCachePrebuildService.rejectUnknownOptions(section);

            options = struct();
            options.force_rebuild = bms.data.JljCachePrebuildService.fieldBool( ...
                section, 'force_rebuild', false);
            options.min_free_gib = bms.data.JljCachePrebuildService.fieldDouble( ...
                section, 'min_free_gib', 20);
            options.min_free_fraction = bms.data.JljCachePrebuildService.fieldDouble( ...
                section, 'min_free_fraction', 0.15);
            options.estimated_cache_ratio = bms.data.JljCachePrebuildService.fieldDouble( ...
                section, 'estimated_cache_ratio', 1.25);
            options.max_workers = bms.data.JljCachePrebuildService.fieldDouble( ...
                section, 'max_workers', 1);
            manifestDir = bms.data.JljCachePrebuildService.fieldText( ...
                section, 'manifest_dir', 'run_logs');
            options.manifest_dir = bms.data.JljCachePrebuildService.resolvePath(root, manifestDir);
            options.manifest_file = bms.data.JljCachePrebuildService.fieldText( ...
                section, 'manifest_file', '');
            if ~isempty(options.manifest_file)
                if bms.data.DataLayoutResolver.isAbsolutePath(options.manifest_file)
                    options.manifest_path = options.manifest_file;
                else
                    options.manifest_path = fullfile(options.manifest_dir, options.manifest_file);
                end
            else
                options.manifest_path = '';
            end
        end

        function plan = evaluateCapacity(freeBytes, totalBytes, pendingSourceBytes, ...
                pendingBackupBytes, minFreeGiB, minFreeFraction, estimatedCacheRatio)
            %EVALUATECAPACITY Pure boundary calculation used by the write gate.
            plan = struct();
            plan.projected_cache_bytes = ceil( ...
                double(pendingSourceBytes) * double(estimatedCacheRatio));
            plan.projected_write_bytes = plan.projected_cache_bytes + ...
                double(pendingBackupBytes);
            plan.reserve_bytes = max(double(minFreeGiB) * 1024^3, ...
                double(minFreeFraction) * double(totalBytes));
            plan.projected_free_bytes = double(freeBytes) - plan.projected_write_bytes;
            % Equality is intentionally allowed: the configured reserve is a
            % lower bound, not an extra byte that must remain unused.
            plan.allowed = plan.projected_free_bytes >= plan.reserve_bytes;
        end
    end

    methods (Static, Access = private)
        function summary = emptySummary(root, startDate, endDate)
            summary = struct();
            summary.schema_version = 1;
            summary.manifest_type = 'jlj_cache_prebuild';
            summary.service = 'bms.data.JljCachePrebuildService';
            summary.status = 'running';
            summary.message = '';
            summary.error_identifier = '';
            summary.data_root = char(string(root));
            summary.start_date = bms.data.TimeRangeResolver.toDateString(startDate);
            summary.end_date = bms.data.TimeRangeResolver.toDateString(endDate);
            summary.started_at = bms.data.JljCachePrebuildService.formatTime(datetime('now'));
            summary.ended_at = '';
            summary.elapsed_sec = 0;
            summary.layout = '';
            summary.vendor = '';
            summary.cache_version = '';
            summary.config_hash = '';
            summary.csv_dirs = {};
            summary.csv_dir_count = 0;
            summary.discovered_count = 0;
            summary.discovered_file_count = 0;
            summary.eligible_count = 0;
            summary.skipped_count = 0;
            summary.invalid_count = 0;
            summary.source_file_count = 0;
            summary.cache_file_count = 0;
            summary.created_count = 0;
            summary.reused_count = 0;
            summary.rebuilt_count = 0;
            summary.failed_count = 0;
            summary.eligible_failed_count = 0;
            summary.created_source_bytes = 0;
            summary.reused_source_bytes = 0;
            summary.rebuilt_source_bytes = 0;
            summary.failed_source_bytes = 0;
            summary.created_cache_bytes = 0;
            summary.reused_cache_bytes = 0;
            summary.rebuilt_cache_bytes = 0;
            summary.failed_cache_bytes = 0;
            summary.source_bytes = 0;
            summary.discovered_source_bytes = 0;
            summary.eligible_source_bytes = 0;
            summary.skipped_source_bytes = 0;
            summary.invalid_source_bytes = 0;
            summary.cache_bytes = 0;
            summary.pending_file_count = 0;
            summary.pending_source_bytes = 0;
            summary.pending_backup_bytes = 0;
            summary.projected_cache_bytes = 0;
            summary.projected_write_bytes = 0;
            summary.reserve_bytes = 0;
            summary.projected_free_bytes = NaN;
            summary.free_bytes_before = NaN;
            summary.free_bytes_after = NaN;
            summary.volume_total_bytes = NaN;
            summary.estimated_cache_ratio = NaN;
            summary.min_free_gib = NaN;
            summary.min_free_fraction = NaN;
            summary.requested_workers = 1;
            summary.workers_used = 0;
            summary.parallel_used = false;
            summary.source_cleanup_enabled = false;
            summary.source_cleanup = struct([]);
            summary.no_eligible_timeseries = false;
            summary.files = struct([]);
            summary.skipped_files = struct([]);
        end

        function [csvDirs, discovery] = discoverCsvFiles(root, startDate, endDate, cfg, ...
            taskOptions, cacheVersion, configHash)
            if nargin < 5, taskOptions = struct(); end
            if nargin < 6, cacheVersion = 'jlj_csv_v2'; end
            if nargin < 7, configHash = ''; end
            csvDirs = bms.data.ZipDailyExportAdapter.csvDirs(root, startDate, endDate, cfg);
            csvDirs = sort(unique(cellstr(string(csvDirs)), 'stable'));
            cleanupOptions = ...
                bms.data.VerifiedSourceCsvCleanupService.optionsFromTask(taskOptions);
            if cleanupOptions.enabled
                % The destructive contract is one transaction per natural
                % day.  ZipDailyExportAdapter deliberately recognises both
                % the current data_<bridge>_YYYY-MM-DD folder and the legacy
                % jljDataYYYYMMDD-YYYYMMDD folder.  If both are present for
                % one day, processing them as independent partitions could
                % commit the first cleanup before the second fails.  Reject
                % the complete day before resuming receipts, building a
                % cache, renaming a source, or deleting anything.
                bms.data.JljCachePrebuildService. ...
                    assertOneCleanupPartitionPerDay( ...
                        csvDirs, startDate, endDate);
            end
            bms.data.VerifiedSourceCsvCleanupService.resumePending( ...
                csvDirs, cfg, taskOptions, cacheVersion, configHash);
            files = {};
            for i = 1:numel(csvDirs)
                items = dir(fullfile(csvDirs{i}, '*.csv'));
                for j = 1:numel(items)
                    if ~items(j).isdir
                        files{end+1} = fullfile(items(j).folder, items(j).name); %#ok<AGROW>
                    end
                end
            end
            files = sort(unique(cellstr(string(files)), 'stable'));
            adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(cfg);
            records = cell(1, numel(files));
            for i = 1:numel(files)
                records{i} = bms.data.JljCachePrebuildService.classifyCsvHeader( ...
                    files{i}, adapter);
            end
            if isempty(records), discovery = struct([]); else, discovery = [records{:}]; end
            archived = bms.data.VerifiedSourceCsvCleanupService.archivedDiscovery( ...
                csvDirs, cfg, cacheVersion, configHash);
            if isempty(discovery)
                discovery = archived;
            elseif ~isempty(archived)
                discovery = [discovery, archived];
            end
        end

        function rec = classifyCsvHeader(sourcePath, adapter)
            rec = struct( ...
                'path', char(string(sourcePath)), ...
                'source_bytes', 0, ...
                'source_modified_at', '', ...
                'header', {{}}, ...
                'classification', 'invalid', ...
                'reason', 'header_read_failed', ...
                'error_identifier', 'BMS:JljCachePrebuild:HeaderReadFailed', ...
                'error_message', '', ...
                'source_present', true, ...
                'cache_path', '', ...
                'metadata_path', '', ...
                'cleanup_receipt_path', '', ...
                'csv_dir', fileparts(char(string(sourcePath))), ...
                'partition_root', '');
            d = dir(sourcePath);
            if ~isempty(d)
                rec.source_bytes = double(d(1).bytes);
                rec.source_modified_at = datestr(d(1).datenum, 'yyyy-mm-dd HH:MM:ss');
            end
            try
                headers = bms.data.JljCachePrebuildService.readCsvHeader(sourcePath, adapter);
                rec.header = headers;
                normalized = lower(strtrim(string(headers)));
                hasTime = any(normalized == lower(string(adapter.csv.time_column)));
                hasValues = any(ismember(normalized, ["value_x", "value_y", "value_z"]));
                [knownWim, wimReason] = bms.data.JljCachePrebuildService.isKnownWimCsv( ...
                    sourcePath, normalized, hasTime);
                if hasTime && hasValues
                    rec.classification = 'eligible';
                    rec.reason = 'timeseries_contract_match';
                    rec.error_identifier = '';
                    rec.error_message = '';
                elseif hasValues
                    rec.classification = 'invalid';
                    rec.reason = 'timeseries_missing_time_column';
                    rec.error_identifier = 'BMS:JljCachePrebuild:MissingTimeColumn';
                    rec.error_message = sprintf( ...
                        'CSV has value channels but no required time column "%s": %s', ...
                        adapter.csv.time_column, sourcePath);
                elseif knownWim
                    rec.classification = 'skipped';
                    rec.reason = wimReason;
                    rec.error_identifier = '';
                    rec.error_message = '';
                else
                    rec.classification = 'invalid';
                    rec.reason = 'unexpected_csv_schema';
                    rec.error_identifier = 'BMS:JljCachePrebuild:UnexpectedCsvSchema';
                    rec.error_message = sprintf( ...
                        ['CSV is neither a ts/value_x|value_y|value_z time series nor an explicitly ' ...
                         'identified DTCZ/WIM export: %s'], sourcePath);
                end
            catch ME
                rec.error_identifier = ME.identifier;
                rec.error_message = ME.message;
            end
        end

        function discovery = applyCleanupConfigurationWhitelist(discovery, cfg)
            % Only configured point sources may enter the destructive path.
            % Ordinary cache prebuild intentionally remains schema-based; the
            % whitelist is an additional fail-closed gate used only when the
            % operator explicitly enables verified source cleanup.
            if isempty(discovery), return; end
            selectedByDir = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for i = 1:numel(discovery)
                if ~strcmp(char(string(discovery(i).classification)), 'eligible')
                    continue;
                end
                sourcePath = char(string(discovery(i).path));
                sourcePresent = isfield(discovery, 'source_present') ...
                    && logical(discovery(i).source_present);
                allowed = false;
                if sourcePresent
                    csvDir = char(string(discovery(i).csv_dir));
                    dirKey = lower(char(java.io.File(csvDir).getCanonicalPath()));
                    if ~isKey(selectedByDir, dirKey)
                        selected = bms.data.JiulongjiangCsvDataSource. ...
                            configuredCleanupCsvPaths(csvDir, cfg);
                        selectedByDir(dirKey) = lower(string(cellfun(@(p) ...
                            char(java.io.File(p).getCanonicalPath()), selected, ...
                            'UniformOutput', false)));
                    end
                    sourceKey = lower(string(char(java.io.File(sourcePath).getCanonicalPath())));
                    allowed = any(sourceKey == selectedByDir(dirKey));
                else
                    % Archived discovery already validates the committed
                    % receipt, current cleanup scope, recovery ZIP and cache.
                    % Compare the exact original path recorded by that receipt
                    % so a legitimate runtime contains-fallback filename can
                    % be reused even when its stem differs from the point ID.
                    receiptPath = char(string(discovery(i).cleanup_receipt_path));
                    if ~isempty(receiptPath) && isfile(receiptPath)
                        receipt = bms.io.JsonFile.read(receiptPath);
                        receiptSources = cellstr(string({receipt.files.source_path}));
                        receiptKeys = lower(string(cellfun(@(p) ...
                            char(java.io.File(p).getCanonicalPath()), ...
                            receiptSources, 'UniformOutput', false)));
                        sourceKey = lower(string(char(java.io.File( ...
                            sourcePath).getCanonicalPath())));
                        allowed = any(sourceKey == receiptKeys);
                    end
                end
                if ~allowed
                    discovery(i).classification = 'skipped';
                    discovery(i).reason = 'unconfigured_timeseries_csv';
                    discovery(i).error_identifier = '';
                    discovery(i).error_message = '';
                end
            end
        end

        function headers = readCsvHeader(sourcePath, adapter)
            fid = fopen(sourcePath, 'rt', 'n', adapter.csv.encoding);
            if fid < 0
                error('BMS:JljCachePrebuild:HeaderReadFailed', ...
                    'Unable to open CSV header: %s', sourcePath);
            end
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            line = fgetl(fid);
            if ~ischar(line)
                error('BMS:JljCachePrebuild:HeaderReadFailed', ...
                    'CSV has no readable header row: %s', sourcePath);
            end
            if ~isempty(line) && double(line(1)) == 65279
                line = line(2:end);
            end
            delimiter = char(string(adapter.csv.delimiter));
            if isempty(delimiter), delimiter = ','; end
            raw = strsplit(line, delimiter);
            headers = cell(1, numel(raw));
            for i = 1:numel(raw)
                item = strtrim(raw{i});
                if numel(item) >= 2 && item(1) == '"' && item(end) == '"'
                    item = item(2:end-1);
                end
                headers{i} = strtrim(item);
            end
        end

        function [tf, reason] = isKnownWimCsv(sourcePath, normalizedHeaders, hasTime)
            [~, base, ~] = fileparts(sourcePath);
            upperBase = upper(char(string(base)));
            if startsWith(upperBase, 'DTCZ') || startsWith(upperBase, 'WIM')
                tf = true;
                reason = 'known_wim_filename_prefix';
                return;
            end
            hasAxles = any(normalizedHeaders == "axles_number");
            if hasTime && hasAxles
                tf = true;
                reason = 'known_wim_header_contract';
            else
                tf = false;
                reason = '';
            end
        end

        function rec = failureRecord(sourcePath, cfg, ME)
            rec = bms.data.JiulongjiangCsvDataSource.emptyCacheBuildInfo(sourcePath);
            sourceRecords = bms.data.CacheManager.buildSourceRecords({sourcePath});
            if ~isempty(sourceRecords)
                rec.source_bytes = sourceRecords(1).bytes;
                rec.source_modified_at = sourceRecords(1).modified_at;
            end
            try
                adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(cfg);
                cacheDir = bms.data.JiulongjiangCsvDataSource.resolveCacheDir( ...
                    fileparts(sourcePath), adapter);
                [~, base, ~] = fileparts(sourcePath);
                rec.cache_path = fullfile(cacheDir, [base '.mat']);
                rec.metadata_path = bms.data.CacheManager.metadataPath(rec.cache_path);
                rec.cache_bytes = bms.data.JiulongjiangCsvDataSource.cachePairBytes(rec.cache_path);
            catch
            end
            rec.status = 'failed';
            rec.error_identifier = ME.identifier;
            rec.error_message = ME.message;
        end

        function rec = processEligibleRecord(discovery, cfg, forceRebuild)
            startedAt = datetime('now');
            try
                if isfield(discovery, 'source_present') && ~logical(discovery.source_present)
                    if ~bms.data.JiulongjiangCsvDataSource.validateStandaloneRawCache( ...
                            discovery.cache_path, cfg)
                        error('BMS:JljCachePrebuild:ArchivedCacheInvalid', ...
                            'Archived-source cache is invalid: %s', discovery.cache_path);
                    end
                    rec = bms.data.JiulongjiangCsvDataSource.emptyCacheBuildInfo( ...
                        discovery.path);
                    rec.source_bytes = discovery.source_bytes;
                    rec.source_modified_at = discovery.source_modified_at;
                    rec.cache_path = discovery.cache_path;
                    rec.metadata_path = discovery.metadata_path;
                    rec.cache_bytes = ...
                        bms.data.JiulongjiangCsvDataSource.cachePairBytes( ...
                            discovery.cache_path);
                    rec.status = 'reused';
                else
                    rec = bms.data.JiulongjiangCsvDataSource.buildCacheForFile( ...
                        discovery.path, cfg, '', forceRebuild);
                end
            catch ME
                rec = bms.data.JljCachePrebuildService.failureRecord( ...
                    discovery.path, cfg, ME);
            end
            rec = bms.data.JljCachePrebuildService.decorateRecord(rec, discovery);
            endedAt = datetime('now');
            rec.started_at = bms.data.JljCachePrebuildService.formatTime(startedAt);
            rec.ended_at = bms.data.JljCachePrebuildService.formatTime(endedAt);
            rec.elapsed_sec = max(0, seconds(endedAt - startedAt));
        end

        function rec = decorateRecord(rec, discovery)
            rec.source_bytes = discovery.source_bytes;
            rec.source_modified_at = discovery.source_modified_at;
            rec.classification = discovery.classification;
            rec.reason = discovery.reason;
            rec.header = discovery.header;
            rec.source_present = discovery.source_present;
            rec.cleanup_receipt_path = discovery.cleanup_receipt_path;
            rec.csv_dir = discovery.csv_dir;
            rec.partition_root = discovery.partition_root;
        end

        function bytes = discoveryBytes(records)
            if isempty(records)
                bytes = 0;
            else
                bytes = sum(double([records.source_bytes]));
            end
        end

        function assertUniqueCachePaths(files, cfg)
            if isempty(files), return; end
            adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(cfg);
            seen = containers.Map('KeyType', 'char', 'ValueType', 'char');
            for i = 1:numel(files)
                sourcePath = char(string(files{i}));
                cacheDir = bms.data.JiulongjiangCsvDataSource.resolveCacheDir( ...
                    fileparts(sourcePath), adapter);
                [~, base, ~] = fileparts(sourcePath);
                cachePath = fullfile(cacheDir, [base '.mat']);
                try
                    key = lower(char(java.io.File(cachePath).getCanonicalPath()));
                catch
                    key = lower(cachePath);
                end
                if isKey(seen, key)
                    error('BMS:JljCachePrebuild:CachePathCollision', ...
                        'Two CSV sources resolve to the same cache path: %s | %s -> %s', ...
                        seen(key), sourcePath, cachePath);
                end
                seen(key) = sourcePath;
            end
        end

        function [pendingCount, pendingBytes, pendingBackupBytes] = pendingBuildBytes( ...
                files, cfg, forceRebuild)
            adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(cfg);
            pendingCount = 0;
            pendingBytes = 0;
            pendingBackupBytes = 0;
            for i = 1:numel(files)
                sourcePath = files{i};
                cacheDir = bms.data.JiulongjiangCsvDataSource.resolveCacheDir( ...
                    fileparts(sourcePath), adapter);
                [~, base, ~] = fileparts(sourcePath);
                cachePath = fullfile(cacheDir, [base '.mat']);
                if ~isfile(sourcePath) ...
                        && bms.data.JiulongjiangCsvDataSource.validateStandaloneRawCache( ...
                            cachePath, cfg)
                    continue;
                end
                reusable = ~logical(forceRebuild) ...
                    && bms.data.JiulongjiangCsvDataSource.isReusableRawCache( ...
                        cachePath, sourcePath, adapter);
                if ~reusable
                    d = dir(sourcePath);
                    pendingCount = pendingCount + 1;
                    if ~isempty(d)
                        pendingBytes = pendingBytes + double(d(1).bytes);
                    end
                    pendingBackupBytes = pendingBackupBytes + ...
                        bms.data.JiulongjiangCsvDataSource.cachePairBytes(cachePath);
                end
            end
        end

        function summary = finalizeSummary(summary, records)
            if isempty(records)
                return;
            end
            statuses = cellstr(string({records.status}));
            summary.created_count = sum(strcmp(statuses, 'created'));
            summary.reused_count = sum(strcmp(statuses, 'reused'));
            summary.rebuilt_count = sum(strcmp(statuses, 'rebuilt'));
            summary.failed_count = sum(strcmp(statuses, 'failed'));
            classifications = cellstr(string({records.classification}));
            summary.eligible_failed_count = sum( ...
                strcmp(statuses, 'failed') & strcmp(classifications, 'eligible'));
            summary.cache_file_count = summary.created_count + summary.reused_count + summary.rebuilt_count;
            summary.cache_bytes = sum(double([records.cache_bytes]));
            summary.created_source_bytes = bms.data.JljCachePrebuildService.sumStatusBytes( ...
                records, statuses, 'created', 'source_bytes');
            summary.reused_source_bytes = bms.data.JljCachePrebuildService.sumStatusBytes( ...
                records, statuses, 'reused', 'source_bytes');
            summary.rebuilt_source_bytes = bms.data.JljCachePrebuildService.sumStatusBytes( ...
                records, statuses, 'rebuilt', 'source_bytes');
            summary.failed_source_bytes = bms.data.JljCachePrebuildService.sumStatusBytes( ...
                records, statuses, 'failed', 'source_bytes');
            summary.created_cache_bytes = bms.data.JljCachePrebuildService.sumStatusBytes( ...
                records, statuses, 'created', 'cache_bytes');
            summary.reused_cache_bytes = bms.data.JljCachePrebuildService.sumStatusBytes( ...
                records, statuses, 'reused', 'cache_bytes');
            summary.rebuilt_cache_bytes = bms.data.JljCachePrebuildService.sumStatusBytes( ...
                records, statuses, 'rebuilt', 'cache_bytes');
            summary.failed_cache_bytes = bms.data.JljCachePrebuildService.sumStatusBytes( ...
                records, statuses, 'failed', 'cache_bytes');
        end

        function total = sumStatusBytes(records, statuses, status, fieldName)
            mask = strcmp(statuses, status);
            if any(mask)
                values = [records.(fieldName)];
                total = sum(double(values(mask)));
            else
                total = 0;
            end
        end

        function dayText = dayForPartition(partitionRoot, startDate, endDate)
            [~, name] = fileparts(char(string(partitionRoot)));
            token = regexp(name, '(20\d{2}-\d{2}-\d{2})', 'tokens', 'once');
            if isempty(token)
                legacy = regexpi(name, ...
                    '^jljData(20\d{2})(\d{2})(\d{2})-\d{8}$', ...
                    'tokens', 'once');
                if ~isempty(legacy)
                    token = {sprintf('%s-%s-%s', legacy{:})};
                end
            end
            if isempty(token)
                days = bms.data.TimeRangeResolver.daysBetween(startDate, endDate);
                if numel(days) ~= 1
                    error('BMS:CacheSourceCleanup:PartitionDateUnknown', ...
                        'Cannot bind cleanup partition to one natural day: %s', partitionRoot);
                end
                dayText = datestr(days(1), 'yyyy-mm-dd');
            else
                dayText = token{1};
            end
        end

        function assertOneCleanupPartitionPerDay(csvDirs, startDate, endDate)
            requested = bms.data.TimeRangeResolver.daysBetween( ...
                startDate, endDate);
            requestedDays = cellstr(datestr(requested, 'yyyy-mm-dd'));
            partitionDays = cell(1, numel(csvDirs));
            partitionRoots = cell(1, numel(csvDirs));
            for i = 1:numel(csvDirs)
                partitionRoots{i} = ...
                    bms.data.JljCachePrebuildService. ...
                        cleanupPartitionRoot(csvDirs{i});
                partitionDays{i} = ...
                    bms.data.JljCachePrebuildService.dayForPartition( ...
                        partitionRoots{i}, startDate, endDate);
            end

            issues = {};
            outside = setdiff(unique(partitionDays, 'stable'), ...
                requestedDays, 'stable');
            if ~isempty(outside)
                issues{end+1} = sprintf('date outside request: %s', ... %#ok<AGROW>
                    strjoin(outside, ', '));
            end
            for dayIndex = 1:numel(requestedDays)
                dayText = requestedDays{dayIndex};
                indexes = find(strcmp(partitionDays, dayText));
                if numel(indexes) ~= 1
                    paths = partitionRoots(indexes);
                    if isempty(paths), paths = {'<none>'}; end
                    issues{end+1} = sprintf('%s has %d partition(s): %s', ... %#ok<AGROW>
                        dayText, numel(indexes), strjoin(paths, ' | '));
                    continue;
                end
                manifestPath = fullfile(partitionRoots{indexes}, ...
                    '.bms_extract_manifest.json');
                if ~isfile(manifestPath)
                    issues{end+1} = sprintf( ... %#ok<AGROW>
                        '%s partition has no verified extraction manifest: %s', ...
                        dayText, partitionRoots{indexes});
                end
            end
            if ~isempty(issues)
                error('BMS:CacheSourceCleanup:DailyPartitionCount', ...
                    ['Verified jlj_daily_export cleanup requires exactly one ' ...
                     'valid CSV partition for every natural day. No cache or ' ...
                     'source cleanup was started: %s'], strjoin(issues, '; '));
            end
        end

        function root = cleanupPartitionRoot(csvDir)
            try
                root = bms.data.VerifiedSourceCsvCleanupService. ...
                    partitionRoot(csvDir);
            catch ME
                % Preserve the stronger existing diagnostic for a committed
                % or interrupted cleanup whose extraction evidence was later
                % removed.  The uniqueness gate runs before resumePending(),
                % so it must not downgrade this to a generic missing-manifest
                % error.
                candidate = char(string(csvDir));
                for i = 1:12
                    receiptPath = fullfile(candidate, ...
                        '.bms_cache_source_cleanup_receipt.json');
                    if isfile(receiptPath)
                        error('BMS:CacheSourceCleanup:ExtractionManifestLost', ...
                            ['A cleanup receipt exists but its verified extraction ' ...
                             'manifest is missing: %s'], receiptPath);
                    end
                    parent = fileparts(candidate);
                    if isempty(parent) || strcmp(parent, candidate), break; end
                    candidate = parent;
                end
                rethrow(ME);
            end
        end

        function path = writeSummary(options, summary)
            bms.data.DataLayoutResolver.ensureDir(options.manifest_dir);
            path = options.manifest_path;
            if isempty(path)
                stamp = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
                path = fullfile(options.manifest_dir, sprintf( ...
                    'jlj_cache_prebuild_%s_%06d.json', stamp, randi(999999)));
            end
            bms.core.Logger.writeJson(path, summary);
        end

        function text = vendorText(cfg, adapter)
            text = '';
            if isstruct(cfg) && isfield(cfg, 'vendor') && ~isempty(cfg.vendor)
                text = char(string(cfg.vendor));
            elseif isfield(adapter, 'prefixes') && ~isempty(adapter.prefixes)
                text = strjoin(cellstr(string(adapter.prefixes)), ',');
            end
        end

        function [freeBytes, totalBytes] = diskCapacity(root)
            freeBytes = NaN;
            totalBytes = NaN;
            try
                fileObj = javaObject('java.io.File', char(string(root)));
                freeBytes = double(fileObj.getFreeSpace());
                totalBytes = double(fileObj.getTotalSpace());
            catch
            end
        end

        function workers = ensurePool(requested)
            try
                cluster = parcluster('local');
                requested = min(requested, cluster.NumWorkers);
                pool = gcp('nocreate');
                if isempty(pool)
                    pool = parpool(cluster, requested);
                end
                workers = min(pool.NumWorkers, requested);
            catch ME
                warning('BMS:JljCachePrebuild:ParallelUnavailable', ...
                    'Parallel cache pre-generation is unavailable; using serial mode: %s', ME.message);
                workers = 1;
            end
        end

        function bytes = freeBytes(root)
            [bytes, ~] = bms.data.JljCachePrebuildService.diskCapacity(root);
        end

        function text = formatTime(value)
            if isempty(value) || (isa(value, 'datetime') && isnat(value))
                text = '';
            else
                text = datestr(value, 'yyyy-mm-dd HH:MM:SS');
            end
        end

        function out = overlay(base, patch)
            out = base;
            fields = fieldnames(patch);
            for i = 1:numel(fields)
                out.(fields{i}) = patch.(fields{i});
            end
        end

        function rejectUnknownOptions(section)
            allowed = {'force_rebuild', 'min_free_gib', 'min_free_fraction', ...
                'estimated_cache_ratio', 'max_workers', 'manifest_dir', 'manifest_file'};
            unknown = setdiff(fieldnames(section), allowed, 'stable');
            if ~isempty(unknown)
                error('BMS:JljCachePrebuild:UnknownOption', ...
                    'Unknown cache_prebuild option(s): %s', strjoin(unknown, ', '));
            end
        end

        function value = fieldText(section, name, fallback)
            value = fallback;
            if isstruct(section) && isfield(section, name) && ~isempty(section.(name))
                value = char(string(section.(name)));
            end
        end

        function value = fieldBool(section, name, fallback)
            value = fallback;
            if isstruct(section) && isfield(section, name) && ~isempty(section.(name))
                raw = section.(name);
                if islogical(raw) || isnumeric(raw)
                    value = logical(raw(1));
                else
                    value = any(strcmpi(strtrim(char(string(raw))), {'1','true','yes','on'}));
                end
            end
        end

        function value = fieldDouble(section, name, fallback)
            value = fallback;
            if isstruct(section) && isfield(section, name) && ~isempty(section.(name))
                raw = section.(name);
                if ischar(raw) || isstring(raw)
                    if ~isscalar(string(raw))
                        value = NaN;
                    else
                        value = str2double(char(string(raw)));
                    end
                else
                    if ~isscalar(raw)
                        value = NaN;
                    else
                        value = double(raw);
                    end
                end
            end
        end

        function path = resolvePath(root, value)
            path = char(string(value));
            if ~bms.data.DataLayoutResolver.isAbsolutePath(path)
                path = fullfile(char(string(root)), path);
            end
        end
    end
end
