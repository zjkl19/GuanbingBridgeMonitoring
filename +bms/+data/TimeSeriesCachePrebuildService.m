classdef TimeSeriesCachePrebuildService
    %TIMESERIESCACHEPREBUILDSERVICE Prebuild configured two-column CSV caches.
    %   Discovery is deliberately configuration-scoped.  Only CSV files
    %   reachable from configured analysis points are eligible; WIM, ZIP,
    %   Hongtang low-frequency workbooks and unrelated CSV files are not
    %   scanned or converted.

    methods (Static)
        function result = run(root, startDate, endDate, cfg, taskOptions)
            if nargin < 4, cfg = struct(); end
            if nargin < 5, taskOptions = struct(); end
            startedAt = datetime('now');
            summary = bms.data.TimeSeriesCachePrebuildService.emptySummary( ...
                root, startDate, endDate);
            options = struct('manifest_dir', fullfile(char(string(root)), 'run_logs'), ...
                'manifest_path', '');

            try
                options = bms.data.JljCachePrebuildService.optionsFromConfig(root, cfg);
                cleanupOptions = ...
                    bms.data.VerifiedSourceCsvCleanupService.optionsFromTask(taskOptions);
                if cleanupOptions.enabled
                    error('BMS:CacheSourceCleanup:LayoutNotYetSupported', ...
                        ['Verified CSV deletion currently requires the archive-backed ' ...
                         'jlj_daily_export layout. This cache build retained every CSV.']);
                end
                bms.data.TimeSeriesCachePrebuildService.validateOptions(options);
                if ~isfolder(root)
                    error('BMS:TimeSeriesCachePrebuild:RootMissing', ...
                        'Data root does not exist: %s', char(string(root)));
                end

                layout = char(string(bms.data.DataLayoutResolver.inferLayout(root, cfg)));
                summary.layout = layout;
                if ~any(strcmp(layout, {'dated_folders', 'hongtang_period'}))
                    error('BMS:TimeSeriesCachePrebuild:UnsupportedLayout', ...
                        'Standard CSV cache pre-generation does not support layout: %s', layout);
                end
                summary.cache_version = bms.data.TimeSeriesLoader.seriesCacheVersion(cfg);
                summary.requested_workers = options.max_workers;

                lockOwner = struct('service', 'bms.data.TimeSeriesCachePrebuildService', ...
                    'root', char(string(root)), 'layout', layout);
                lockPath = fullfile(char(string(root)), '.bms_timeseries_cache_prebuild.lock');
                lockOptions = struct('recover_stale', true, 'stale_hours', 24);
                lockCleanup = bms.core.DirectoryLeaseLock.acquire( ...
                    lockPath, lockOptions, lockOwner); %#ok<NASGU>

                discovery = bms.data.TimeSeriesCachePrebuildService.discoverSources( ...
                    root, startDate, endDate, cfg);
                summary.discovered_count = numel(discovery);
                summary.discovered_file_count = summary.discovered_count;
                summary.eligible_count = summary.discovered_count;
                summary.source_file_count = summary.discovered_count;
                if isempty(discovery)
                    error('BMS:TimeSeriesCachePrebuild:NoConfiguredCsv', ...
                        ['No configured two-column time-series CSV files were found. ' ...
                         'Unconfigured CSV, WIM, ZIP and low-frequency workbooks are excluded.']);
                end

                summary.source_bytes = sum(double([discovery.source_bytes]));
                summary.eligible_source_bytes = summary.source_bytes;
                [pendingCount, pendingBytes, pendingBackupBytes] = ...
                    bms.data.TimeSeriesCachePrebuildService.pendingBuildBytes( ...
                        discovery, summary.cache_version, options.force_rebuild);
                summary.pending_file_count = pendingCount;
                summary.pending_source_bytes = pendingBytes;
                summary.pending_backup_bytes = pendingBackupBytes;

                [freeBefore, totalBytes] = ...
                    bms.data.TimeSeriesCachePrebuildService.diskCapacity(root);
                summary.free_bytes_before = freeBefore;
                summary.volume_total_bytes = totalBytes;
                summary.min_free_gib = options.min_free_gib;
                summary.min_free_fraction = options.min_free_fraction;
                summary.estimated_cache_ratio = options.estimated_cache_ratio;
                if ~isfinite(freeBefore) || ~isfinite(totalBytes) || totalBytes <= 0
                    error('BMS:TimeSeriesCachePrebuild:DiskInfoUnavailable', ...
                        'Unable to determine free and total space for data root: %s', root);
                end
                capacity = bms.data.JljCachePrebuildService.evaluateCapacity( ...
                    freeBefore, totalBytes, pendingBytes, pendingBackupBytes, ...
                    options.min_free_gib, options.min_free_fraction, ...
                    options.estimated_cache_ratio);
                fields = fieldnames(capacity);
                for i = 1:numel(fields)
                    summary.(fields{i}) = capacity.(fields{i});
                end
                if ~capacity.allowed
                    error('BMS:TimeSeriesCachePrebuild:InsufficientDisk', ...
                        ['Cache pre-generation requires %.3f GiB projected writes and ' ...
                         '%.3f GiB reserve; only %.3f GiB is currently free.'], ...
                        capacity.projected_write_bytes / 1024^3, ...
                        capacity.reserve_bytes / 1024^3, freeBefore / 1024^3);
                end

                workers = min(options.max_workers, numel(discovery));
                if workers > 1
                    workers = bms.data.TimeSeriesCachePrebuildService.ensurePool(workers);
                end
                summary.workers_used = workers;
                summary.parallel_used = workers > 1;
                records = cell(1, numel(discovery));
                forceRebuild = options.force_rebuild;
                cacheVersion = summary.cache_version;
                marker = bms.data.TimeSeriesRangeLoader.defaultHeaderMarker(cfg);
                if workers > 1
                    parfor (i = 1:numel(discovery), workers)
                        records{i} = bms.data.TimeSeriesCachePrebuildService.processSource( ...
                            discovery(i), marker, cacheVersion, forceRebuild);
                    end
                else
                    for i = 1:numel(discovery)
                        records{i} = bms.data.TimeSeriesCachePrebuildService.processSource( ...
                            discovery(i), marker, cacheVersion, forceRebuild);
                    end
                end
                summary.files = [records{:}];
                summary = bms.data.TimeSeriesCachePrebuildService.finalizeSummary( ...
                    summary, summary.files);
                summary.free_bytes_after = ...
                    bms.data.TimeSeriesCachePrebuildService.freeBytes(root);
                summary.ended_at = bms.data.TimeSeriesCachePrebuildService.formatTime(datetime('now'));
                summary.elapsed_sec = max(0, seconds(datetime('now') - startedAt));
                if summary.failed_count > 0
                    summary.status = 'fail';
                    summary.message = sprintf( ...
                        'configured=%d; created=%d; reused=%d; rebuilt=%d; failed=%d', ...
                        summary.eligible_count, summary.created_count, summary.reused_count, ...
                        summary.rebuilt_count, summary.failed_count);
                else
                    summary.status = 'ok';
                    summary.message = sprintf( ...
                        'configured=%d; created=%d; reused=%d; rebuilt=%d; failed=0', ...
                        summary.eligible_count, summary.created_count, summary.reused_count, ...
                        summary.rebuilt_count);
                end
                manifestPath = bms.data.TimeSeriesCachePrebuildService.writeSummary( ...
                    options, summary);
                if summary.failed_count > 0
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
                summary.free_bytes_after = ...
                    bms.data.TimeSeriesCachePrebuildService.freeBytes(root);
                summary.ended_at = bms.data.TimeSeriesCachePrebuildService.formatTime(endedAt);
                summary.elapsed_sec = max(0, seconds(endedAt - startedAt));
                try
                    manifestPath = bms.data.TimeSeriesCachePrebuildService.writeSummary( ...
                        options, summary);
                catch
                    manifestPath = '';
                end
                result = bms.analyzer.AnalyzerResult.fail( ...
                    'cache_prebuild', ME.message, manifestPath, startedAt, endedAt, ME.identifier);
            end
        end

        function discovery = discoverSources(root, startDate, endDate, cfg)
            csvCfg = bms.data.TimeSeriesCachePrebuildService.forceCsvMode(cfg);
            source = bms.data.DataSourceFactory.create(root, csvCfg);
            specs = bms.module.ModuleRegistry.forCategory('analysis');
            rows = {};
            for i = 1:numel(specs)
                spec = specs(i);
                if strcmp(spec.Key, 'wim') || isempty(spec.SubfolderKey)
                    continue;
                end
                [hasSubfolder, subfolder] = bms.app.RunPreflight.resolveSubfolder( ...
                    csvCfg, spec.SubfolderKey);
                if ~hasSubfolder
                    continue;
                end
                points = bms.app.RunPreflight.configuredPoints(csvCfg, spec.Key);
                requests = bms.data.TimeSeriesCachePrebuildService.sourceRequests( ...
                    spec.Key, points, csvCfg);
                for j = 1:numel(requests)
                    req = requests(j);
                    % Use the same directory and point-to-file resolution as
                    % TimeSeriesRangeLoader.  This matters for Hongtang: its
                    % low-frequency period root coexists with dated waveform
                    % folders, so BaseDataSource.findPointFiles alone would
                    % search only the period root and miss the real CSVs.
                    dirs = bms.data.DataIndex.candidateDirs( ...
                        source, subfolder, startDate, endDate, csvCfg, ...
                        req.sensor_type);
                    files = {};
                    for d = 1:numel(dirs)
                        fp = bms.data.TimeSeriesLoader.findCsvForPoint( ...
                            dirs{d}, req.point_id, csvCfg, req.sensor_type);
                        if ~isempty(fp)
                            files{end+1} = fp; %#ok<AGROW>
                        end
                    end
                    files = bms.data.BaseDataSource.uniqueExistingFiles(files);
                    for k = 1:numel(files)
                        [~, ~, ext] = fileparts(files{k});
                        if ~strcmpi(ext, '.csv')
                            continue;
                        end
                        d = dir(files{k});
                        if isempty(d), continue; end
                        rows{end+1} = struct( ... %#ok<AGROW>
                            'path', char(string(files{k})), ...
                            'canonical_path', ...
                                bms.data.TimeSeriesCachePrebuildService.canonicalPath(files{k}), ...
                            'source_bytes', double(d(1).bytes), ...
                            'module', spec.Key, ...
                            'point_id', req.point_id, ...
                            'sensor_type', req.sensor_type);
                    end
                end
            end
            discovery = bms.data.TimeSeriesCachePrebuildService.mergeDiscovery(rows);
        end

        function tf = isReusable(cachePath, sourcePath, cacheVersion)
            tf = false;
            if ~isfile(cachePath) || ~isfile(sourcePath)
                return;
            end
            if ~bms.data.CacheManager.metadataMatchesFull( ...
                    cachePath, {sourcePath}, struct(), cacheVersion)
                return;
            end
            opts = struct('cache_version', cacheVersion, 'require_metadata', true);
            [times, vals, meta] = bms.data.TimeSeriesLoader.readMatSeries(cachePath, opts);
            tf = logical(meta.read_ok) && ~isempty(times) && numel(times) == numel(vals);
        end
    end

    methods (Static, Access = private)
        function validateOptions(options)
            if ~isfinite(options.min_free_gib) || options.min_free_gib < 0 ...
                    || ~isfinite(options.min_free_fraction) || options.min_free_fraction < 0 ...
                    || options.min_free_fraction > 1 ...
                    || ~isfinite(options.estimated_cache_ratio) ...
                    || options.estimated_cache_ratio <= 0
                error('BMS:TimeSeriesCachePrebuild:InvalidDiskPolicy', ...
                    'Invalid min_free_gib, min_free_fraction or estimated_cache_ratio.');
            end
            if ~isfinite(options.max_workers) || options.max_workers < 1 ...
                    || options.max_workers ~= floor(options.max_workers)
                error('BMS:TimeSeriesCachePrebuild:InvalidWorkers', ...
                    'cache_prebuild.max_workers must be a positive integer.');
            end
        end

        function cfg = forceCsvMode(cfg)
            if ~isstruct(cfg), cfg = struct(); end
            if ~isfield(cfg, 'time_series') || ~isstruct(cfg.time_series)
                cfg.time_series = struct();
            end
            cfg.time_series.source_mode = 'csv_cache';
            if ~isfield(cfg, 'series_source') || ~isstruct(cfg.series_source)
                cfg.series_source = struct();
            end
            cfg.series_source.mode = 'csv_cache';
            if ~isfield(cfg, 'data_adapter') || ~isstruct(cfg.data_adapter)
                cfg.data_adapter = struct();
            end
            if ~isfield(cfg.data_adapter, 'time_series') ...
                    || ~isstruct(cfg.data_adapter.time_series)
                cfg.data_adapter.time_series = struct();
            end
            cfg.data_adapter.time_series.source_mode = 'csv_cache';
        end

        function requests = sourceRequests(moduleKey, points, cfg)
            requests = bms.data.DataIndex.sourceRequestsForModule( ...
                moduleKey, points, cfg);
        end

        function discovery = mergeDiscovery(rows)
            if isempty(rows)
                discovery = struct([]);
                return;
            end
            keys = containers.Map('KeyType', 'char', 'ValueType', 'double');
            merged = {};
            for i = 1:numel(rows)
                row = rows{i};
                key = lower(row.canonical_path);
                if isKey(keys, key)
                    index = keys(key);
                    rec = merged{index};
                    rec.modules = unique([rec.modules, {row.module}], 'stable');
                    rec.point_ids = unique([rec.point_ids, {row.point_id}], 'stable');
                    rec.sensor_types = unique([rec.sensor_types, {row.sensor_type}], 'stable');
                    merged{index} = rec;
                else
                    rec = struct( ...
                        'path', row.path, ...
                        'source_bytes', row.source_bytes, ...
                        'modules', {{row.module}}, ...
                        'point_ids', {{row.point_id}}, ...
                        'sensor_types', {{row.sensor_type}});
                    merged{end+1} = rec; %#ok<AGROW>
                    keys(key) = numel(merged);
                end
            end
            discovery = [merged{:}];
            [~, order] = sort(lower(string({discovery.path})));
            discovery = discovery(order);
        end

        function [count, sourceBytes, backupBytes] = pendingBuildBytes( ...
                discovery, cacheVersion, forceRebuild)
            count = 0;
            sourceBytes = 0;
            backupBytes = 0;
            for i = 1:numel(discovery)
                cachePath = bms.data.TimeSeriesCachePrebuildService.cachePath( ...
                    discovery(i).path);
                reusable = ~logical(forceRebuild) ...
                    && bms.data.TimeSeriesCachePrebuildService.isReusable( ...
                        cachePath, discovery(i).path, cacheVersion);
                if reusable, continue; end
                count = count + 1;
                sourceBytes = sourceBytes + discovery(i).source_bytes;
                backupBytes = backupBytes + ...
                    bms.data.TimeSeriesCachePrebuildService.cachePairBytes(cachePath);
            end
        end

        function rec = processSource(discovery, headerMarker, cacheVersion, forceRebuild)
            startedAt = datetime('now');
            sourcePath = discovery.path;
            cachePath = bms.data.TimeSeriesCachePrebuildService.cachePath(sourcePath);
            metaPath = bms.data.CacheManager.metadataPath(cachePath);
            rec = struct( ...
                'path', sourcePath, ...
                'cache_path', cachePath, ...
                'metadata_path', metaPath, ...
                'status', 'failed', ...
                'source_bytes', discovery.source_bytes, ...
                'cache_bytes', 0, ...
                'modules', {discovery.modules}, ...
                'point_ids', {discovery.point_ids}, ...
                'sensor_types', {discovery.sensor_types}, ...
                'error_identifier', '', ...
                'error_message', '', ...
                'started_at', '', ...
                'ended_at', '', ...
                'elapsed_sec', 0);
            try
                cacheDir = fileparts(cachePath);
                bms.data.DataLayoutResolver.ensureDir(cacheDir);
                fileLock = [cachePath '.build.lock'];
                lockOwner = struct('service', 'TimeSeriesCachePrebuildService', ...
                    'source_path', sourcePath, 'cache_path', cachePath);
                lockCleanup = bms.core.DirectoryLeaseLock.acquire( ...
                    fileLock, struct('recover_stale', true, 'stale_hours', 24), ...
                    lockOwner); %#ok<NASGU>

                reusable = bms.data.TimeSeriesCachePrebuildService.isReusable( ...
                    cachePath, sourcePath, cacheVersion);
                if reusable && ~logical(forceRebuild)
                    rec.status = 'reused';
                else
                    pairExisted = isfile(cachePath) || isfile(metaPath);
                    bms.data.TimeSeriesCachePrebuildService.buildAndPublish( ...
                        sourcePath, cachePath, headerMarker, cacheVersion);
                    if pairExisted
                        rec.status = 'rebuilt';
                    else
                        rec.status = 'created';
                    end
                end
                rec.cache_bytes = ...
                    bms.data.TimeSeriesCachePrebuildService.cachePairBytes(cachePath);
            catch ME
                rec.status = 'failed';
                rec.error_identifier = ME.identifier;
                rec.error_message = ME.message;
                rec.cache_bytes = ...
                    bms.data.TimeSeriesCachePrebuildService.cachePairBytes(cachePath);
            end
            endedAt = datetime('now');
            rec.started_at = bms.data.TimeSeriesCachePrebuildService.formatTime(startedAt);
            rec.ended_at = bms.data.TimeSeriesCachePrebuildService.formatTime(endedAt);
            rec.elapsed_sec = max(0, seconds(endedAt - startedAt));
        end

        function buildAndPublish(sourcePath, cachePath, headerMarker, cacheVersion)
            cacheDir = fileparts(cachePath);
            [~, base, ~] = fileparts(cachePath);
            token = char(java.util.UUID.randomUUID());
            txnDir = fullfile(cacheDir, ['.' base '.cacheprebuild.' token]);
            newDir = fullfile(txnDir, 'new');
            backupDir = fullfile(txnDir, 'backup');
            mkdir(newDir);
            txnCleanup = onCleanup(@() ...
                bms.data.TimeSeriesCachePrebuildService.removeTree(txnDir)); %#ok<NASGU>

            opts = struct('cache_dir', newDir, 'cache_version', cacheVersion);
            [times, vals, meta] = bms.data.TimeSeriesLoader.readCachedCsvSeries( ...
                sourcePath, headerMarker, opts); %#ok<ASGLU>
            stagePath = fullfile(newDir, [base '.mat']);
            stageMeta = bms.data.CacheManager.metadataPath(stagePath);
            if ~logical(meta.read_ok) || isempty(times) || numel(times) ~= numel(vals) ...
                    || ~bms.data.TimeSeriesCachePrebuildService.isReusable( ...
                        stagePath, sourcePath, cacheVersion)
                error('BMS:TimeSeriesCachePrebuild:InvalidCsv', ...
                    'CSV could not produce a validated two-column MAT cache: %s', sourcePath);
            end

            targetMeta = bms.data.CacheManager.metadataPath(cachePath);
            mkdir(backupDir);
            backupMat = fullfile(backupDir, [base '.mat']);
            backupMeta = bms.data.CacheManager.metadataPath(backupMat);
            hadMat = isfile(cachePath);
            hadMeta = isfile(targetMeta);
            publishedMat = false;
            publishedMeta = false;
            try
                if hadMat
                    bms.data.TimeSeriesCachePrebuildService.mustMove( ...
                        cachePath, backupMat, 'backup MAT cache');
                end
                if hadMeta
                    bms.data.TimeSeriesCachePrebuildService.mustMove( ...
                        targetMeta, backupMeta, 'backup cache metadata');
                end
                bms.data.TimeSeriesCachePrebuildService.mustMove( ...
                    stagePath, cachePath, 'publish MAT cache');
                publishedMat = true;
                bms.data.TimeSeriesCachePrebuildService.mustMove( ...
                    stageMeta, targetMeta, 'publish cache metadata');
                publishedMeta = true;
                if ~bms.data.TimeSeriesCachePrebuildService.isReusable( ...
                        cachePath, sourcePath, cacheVersion)
                    error('BMS:TimeSeriesCachePrebuild:PublishedPairInvalid', ...
                        'Published cache pair failed validation: %s', cachePath);
                end
            catch ME
                if publishedMeta && isfile(targetMeta), delete(targetMeta); end
                if publishedMat && isfile(cachePath), delete(cachePath); end
                if hadMat && isfile(backupMat)
                    bms.data.TimeSeriesCachePrebuildService.mustMove( ...
                        backupMat, cachePath, 'restore MAT cache');
                end
                if hadMeta && isfile(backupMeta)
                    bms.data.TimeSeriesCachePrebuildService.mustMove( ...
                        backupMeta, targetMeta, 'restore cache metadata');
                end
                rethrow(ME);
            end
        end

        function mustMove(sourcePath, targetPath, operation)
            [ok, message] = movefile(sourcePath, targetPath, 'f');
            if ~ok
                error('BMS:TimeSeriesCachePrebuild:PublishFailed', ...
                    '%s failed: %s -> %s (%s)', operation, sourcePath, targetPath, message);
            end
        end

        function path = cachePath(sourcePath)
            [folder, base, ~] = fileparts(char(string(sourcePath)));
            path = fullfile(bms.data.CacheManager.cacheDir(folder), [base '.mat']);
        end

        function bytes = cachePairBytes(cachePath)
            bytes = 0;
            paths = {cachePath, bms.data.CacheManager.metadataPath(cachePath)};
            for i = 1:numel(paths)
                d = dir(paths{i});
                if ~isempty(d), bytes = bytes + double(d(1).bytes); end
            end
        end

        function summary = finalizeSummary(summary, records)
            if isempty(records), return; end
            statuses = cellstr(string({records.status}));
            summary.created_count = sum(strcmp(statuses, 'created'));
            summary.reused_count = sum(strcmp(statuses, 'reused'));
            summary.rebuilt_count = sum(strcmp(statuses, 'rebuilt'));
            summary.failed_count = sum(strcmp(statuses, 'failed'));
            summary.cache_file_count = summary.created_count + ...
                summary.reused_count + summary.rebuilt_count;
            summary.cache_bytes = sum(double([records.cache_bytes]));
        end

        function summary = emptySummary(root, startDate, endDate)
            summary = struct( ...
                'schema_version', 1, ...
                'manifest_type', 'timeseries_cache_prebuild', ...
                'service', 'bms.data.TimeSeriesCachePrebuildService', ...
                'status', 'running', ...
                'message', '', ...
                'error_identifier', '', ...
                'data_root', char(string(root)), ...
                'start_date', bms.data.TimeRangeResolver.toDateString(startDate), ...
                'end_date', bms.data.TimeRangeResolver.toDateString(endDate), ...
                'started_at', bms.data.TimeSeriesCachePrebuildService.formatTime(datetime('now')), ...
                'ended_at', '', ...
                'elapsed_sec', 0, ...
                'layout', '', ...
                'cache_version', '', ...
                'discovery_scope', 'configured_analysis_timeseries_csv_only', ...
                'explicit_exclusions', {{'wim', 'lowfreq_workbook', 'zip', 'unconfigured_csv'}}, ...
                'discovered_count', 0, ...
                'discovered_file_count', 0, ...
                'eligible_count', 0, ...
                'skipped_count', 0, ...
                'invalid_count', 0, ...
                'source_file_count', 0, ...
                'source_bytes', 0, ...
                'eligible_source_bytes', 0, ...
                'cache_file_count', 0, ...
                'cache_bytes', 0, ...
                'created_count', 0, ...
                'reused_count', 0, ...
                'rebuilt_count', 0, ...
                'failed_count', 0, ...
                'pending_file_count', 0, ...
                'pending_source_bytes', 0, ...
                'pending_backup_bytes', 0, ...
                'projected_cache_bytes', 0, ...
                'projected_write_bytes', 0, ...
                'reserve_bytes', 0, ...
                'projected_free_bytes', NaN, ...
                'free_bytes_before', NaN, ...
                'free_bytes_after', NaN, ...
                'volume_total_bytes', NaN, ...
                'estimated_cache_ratio', NaN, ...
                'min_free_gib', NaN, ...
                'min_free_fraction', NaN, ...
                'requested_workers', 1, ...
                'workers_used', 0, ...
                'parallel_used', false, ...
                'files', struct([]));
        end

        function path = writeSummary(options, summary)
            bms.data.DataLayoutResolver.ensureDir(options.manifest_dir);
            path = options.manifest_path;
            if isempty(path)
                stamp = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
                path = fullfile(options.manifest_dir, sprintf( ...
                    'timeseries_cache_prebuild_%s_%06d.json', stamp, randi(999999)));
            end
            bms.core.Logger.writeJson(path, summary);
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

        function bytes = freeBytes(root)
            [bytes, ~] = bms.data.TimeSeriesCachePrebuildService.diskCapacity(root);
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
                warning('BMS:TimeSeriesCachePrebuild:ParallelUnavailable', ...
                    'Parallel cache pre-generation is unavailable; using serial mode: %s', ME.message);
                workers = 1;
            end
        end

        function path = canonicalPath(path)
            try
                path = char(java.io.File(char(string(path))).getCanonicalPath());
            catch
                path = char(string(path));
            end
        end

        function removeTree(path)
            try
                if isfolder(path), rmdir(path, 's'); end
            catch
            end
        end

        function text = formatTime(value)
            if isempty(value) || (isa(value, 'datetime') && isnat(value))
                text = '';
            else
                text = datestr(value, 'yyyy-mm-dd HH:MM:SS');
            end
        end
    end
end
