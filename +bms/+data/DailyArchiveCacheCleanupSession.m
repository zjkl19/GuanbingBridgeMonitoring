classdef DailyArchiveCacheCleanupSession < handle
    %DAILYARCHIVECACHECLEANUPSESSION Stream ZIP -> cache -> verified cleanup.
    %   A single task session processes one natural day at a time so a full
    %   month is never extracted before cache cleanup starts.  The session is
    %   shared by the unzip and cache-prebuild plan steps: the first step does
    %   the work, while the second publishes the same durable result as the
    %   cache-prebuild artifact.

    properties (SetAccess = private)
        Root char
        StartDate char
        EndDate char
        Config struct
        TaskOptions struct
        SummaryPath char
        Status char = 'pending'
        Message char = ''
        StartedAt datetime = NaT
        EndedAt datetime = NaT
    end

    methods
        function obj = DailyArchiveCacheCleanupSession( ...
                root, startDate, endDate, cfg, taskOptions)
            if nargin < 4 || isempty(cfg), cfg = struct(); end
            if nargin < 5 || isempty(taskOptions), taskOptions = struct(); end
            cleanup = bms.data.VerifiedSourceCsvCleanupService. ...
                optionsFromTask(taskOptions);
            if ~cleanup.enabled
                error('BMS:DailyArchiveCacheCleanup:CleanupNotEnabled', ...
                    'Daily archive/cache streaming requires explicit CSV cleanup.');
            end
            obj.Root = char(string(root));
            obj.StartDate = bms.data.TimeRangeResolver.toDateString(startDate);
            obj.EndDate = bms.data.TimeRangeResolver.toDateString(endDate);
            obj.Config = cfg;
            obj.TaskOptions = taskOptions;
            archiveOptions = bms.data.ArchiveExtractService.resolvedOptions( ...
                obj.Root, cfg);
            try
                sameOutputRoot = strcmpi( ...
                    char(java.io.File(obj.Root).getCanonicalPath()), ...
                    char(java.io.File(archiveOptions.output_root).getCanonicalPath()));
            catch
                sameOutputRoot = strcmpi(obj.Root, archiveOptions.output_root);
            end
            if ~sameOutputRoot
                error('BMS:DailyArchiveCacheCleanup:SeparateOutputRootUnsupported', ...
                    ['Streaming cleanup requires the task data root to equal the unzip ' ...
                     'output root so later MAT-only analysis reads the committed caches.']);
            end
            cacheOptions = bms.data.JljCachePrebuildService. ...
                optionsFromConfig(obj.Root, cfg);
            bms.data.DataLayoutResolver.ensureDir(cacheOptions.manifest_dir);
            stamp = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
            obj.SummaryPath = fullfile(cacheOptions.manifest_dir, sprintf( ...
                'daily_archive_cache_cleanup_%s_%s_%s_%s.json', ...
                strrep(obj.StartDate, '-', ''), strrep(obj.EndDate, '-', ''), ...
                stamp, char(java.util.UUID.randomUUID())));
        end

        function result = runExtraction(obj)
            if ~strcmp(obj.Status, 'pending')
                result = obj.resultFor('unzip');
                return;
            end
            obj.StartedAt = datetime('now');
            summary = obj.emptySummary();
            obj.Status = 'running';
            bms.core.Logger.writeJson(obj.SummaryPath, summary);
            try
                layout = bms.data.DataLayoutResolver.inferLayout(obj.Root, obj.Config);
                if ~bms.data.CacheSourceCleanupProvider.supportsLayout(layout)
                    error('BMS:DailyArchiveCacheCleanup:UnsupportedLayout', ...
                        ['Daily archive/cache cleanup requires a supported ' ...
                         'archive-backed layout; actual layout is %s.'], ...
                        layout);
                end
                daysList = bms.data.TimeRangeResolver.daysBetween( ...
                    obj.StartDate, obj.EndDate);
                for i = 1:numel(daysList)
                    dayText = datestr(daysList(i), 'yyyy-mm-dd');
                    % Keep extraction, cache publication and verified CSV
                    % cleanup in one cross-process exclusion domain.  The
                    % archive service re-enters this lease in the same MATLAB
                    % process, while an unrelated process fails closed.
                    dayMutationCleanup = ...
                        bms.data.DailyExportMutationLock.acquire(obj.Root, dayText); %#ok<NASGU>
                    row = obj.emptyDay(dayText);
                    row.started_at = obj.formatTime(datetime('now'));
                    try
                        if strcmp(layout, 'jlj_daily_export')
                            committed = ...
                                bms.data.VerifiedSourceCsvCleanupService. ...
                                reconcilePendingDay(obj.Root, dayText, obj.Config, ...
                                obj.TaskOptions);
                        else
                            committed = ...
                                bms.data.StandardVerifiedSourceCsvCleanupService. ...
                                reconcilePendingDay(obj.Root, dayText, obj.Config, ...
                                obj.TaskOptions);
                        end
                        if committed.committed
                            row.cache_status = 'reused_committed_cleanup';
                            row.reused_count = committed.cache_count;
                            row.deleted_count = committed.deleted_count;
                            row.deleted_bytes = committed.deleted_bytes;
                            row.cleanup_receipts = {committed.receipt_path};
                            row.skipped_committed_cleanup = true;
                            row.skip_reason = 'verified_committed_receipt';
                        else
                            extracted = bms.data.ArchiveExtractService.run( ...
                                obj.Root, dayText, dayText, obj.Config);
                            row.archive_count = extracted.archive_count;
                            row.extracted_count = extracted.extracted_count;
                            row.reused_extract_count = extracted.reused_count;
                            row.extract_failed_count = extracted.failed_count;
                            cacheResult = bms.data.CachePrebuildService.run( ...
                                obj.Root, dayText, dayText, obj.Config, obj.TaskOptions);
                            row.cache_status = cacheResult.Status;
                            row.cache_summary_path = cacheResult.StatsPath;
                            if ~strcmp(cacheResult.Status, 'ok')
                                error('BMS:DailyArchiveCacheCleanup:CacheDayFailed', ...
                                    'Cache/cleanup failed for %s: %s', ...
                                    dayText, cacheResult.Message);
                            end
                            cacheSummary = bms.io.JsonFile.read(cacheResult.StatsPath);
                            row.created_count = double(cacheSummary.created_count);
                            row.reused_count = double(cacheSummary.reused_count);
                            row.rebuilt_count = double(cacheSummary.rebuilt_count);
                            row.failed_count = double(cacheSummary.failed_count);
                            if isfield(cacheSummary, 'source_cleanup') ...
                                    && ~isempty(cacheSummary.source_cleanup)
                                cleanupRows = cacheSummary.source_cleanup;
                                row.deleted_count = sum(double([cleanupRows.deleted_count]));
                                row.deleted_bytes = sum(double([cleanupRows.deleted_bytes]));
                                row.cleanup_receipts = cellstr(string( ...
                                    {cleanupRows.receipt_path}));
                            end
                        end
                        row.status = 'ok';
                    catch ME
                        row.status = 'fail';
                        row.error_identifier = ME.identifier;
                        row.error_message = ME.message;
                        row.ended_at = obj.formatTime(datetime('now'));
                        summary.days(end+1) = row; %#ok<AGROW>
                        summary.completed_days = nnz(strcmp( ...
                            cellstr(string({summary.days.status})), 'ok'));
                        summary.status = 'fail';
                        summary.error_identifier = ME.identifier;
                        summary.message = ME.message;
                        summary.ended_at = row.ended_at;
                        summary.elapsed_sec = max(0, seconds( ...
                            datetime('now') - obj.StartedAt));
                        bms.core.Logger.writeJson(obj.SummaryPath, summary);
                        obj.Status = 'fail';
                        obj.Message = ME.message;
                        obj.EndedAt = datetime('now');
                        result = obj.resultFor('unzip');
                        return;
                    end
                    row.ended_at = obj.formatTime(datetime('now'));
                    summary.days(end+1) = row; %#ok<AGROW>
                    summary.completed_days = i;
                    summary.free_bytes_after = obj.freeBytes(obj.Root);
                    summary.elapsed_sec = max(0, seconds( ...
                        datetime('now') - obj.StartedAt));
                    bms.core.Logger.writeJson(obj.SummaryPath, summary);
                    clear dayMutationCleanup;
                end
                obj.Status = 'ok';
                obj.Message = sprintf('Daily ZIP/cache cleanup completed for %d day(s).', ...
                    numel(summary.days));
                obj.EndedAt = datetime('now');
                summary.status = 'ok';
                summary.message = obj.Message;
                summary.ended_at = obj.formatTime(obj.EndedAt);
                summary.free_bytes_after = obj.freeBytes(obj.Root);
                summary.elapsed_sec = max(0, seconds(obj.EndedAt - obj.StartedAt));
                bms.core.Logger.writeJson(obj.SummaryPath, summary);
            catch ME
                obj.Status = 'fail';
                obj.Message = ME.message;
                obj.EndedAt = datetime('now');
                summary.status = 'fail';
                summary.error_identifier = ME.identifier;
                summary.message = ME.message;
                summary.ended_at = obj.formatTime(obj.EndedAt);
                summary.elapsed_sec = max(0, seconds(obj.EndedAt - obj.StartedAt));
                bms.core.Logger.writeJson(obj.SummaryPath, summary);
            end
            result = obj.resultFor('unzip');
        end

        function result = cacheResult(obj)
            if strcmp(obj.Status, 'pending')
                error('BMS:DailyArchiveCacheCleanup:ExtractionNotRun', ...
                    'The daily extraction/cache session has not run yet.');
            end
            if strcmp(obj.Status, 'fail')
                error('BMS:RunStopped', ...
                    ['Daily archive/cache cleanup failed; later analysis modules were ' ...
                     'skipped to prevent use of an incomplete month. See %s'], ...
                    obj.SummaryPath);
            end
            result = obj.resultFor('cache_prebuild');
        end
    end

    methods (Access = private)
        function result = resultFor(obj, key)
            artifacts = {struct('kind', 'manifest', 'path', obj.SummaryPath, ...
                'role', 'daily_archive_cache_cleanup_summary')};
            if strcmp(obj.Status, 'ok')
                result = bms.analyzer.AnalyzerResult.ok( ...
                    key, obj.SummaryPath, artifacts, {}, ...
                    obj.StartedAt, obj.EndedAt, obj.Message);
            else
                result = bms.analyzer.AnalyzerResult.fail( ...
                    key, obj.Message, obj.SummaryPath, obj.StartedAt, obj.EndedAt);
            end
        end

        function summary = emptySummary(obj)
            summary = struct( ...
                'schema_version', 1, ...
                'manifest_type', 'daily_archive_cache_cleanup', ...
                'service', 'bms.data.DailyArchiveCacheCleanupSession', ...
                'status', 'running', ...
                'message', '', ...
                'error_identifier', '', ...
                'data_root', obj.Root, ...
                'start_date', obj.StartDate, ...
                'end_date', obj.EndDate, ...
                'started_at', obj.formatTime(obj.StartedAt), ...
                'ended_at', '', ...
                'elapsed_sec', 0, ...
                'completed_days', 0, ...
                'free_bytes_before', obj.freeBytes(obj.Root), ...
                'free_bytes_after', NaN, ...
                'days', repmat(obj.emptyDay(''), 0, 1));
        end

        function row = emptyDay(~, dayText)
            row = struct('day', char(string(dayText)), 'status', 'pending', ...
                'started_at', '', 'ended_at', '', ...
                'archive_count', 0, 'extracted_count', 0, ...
                'reused_extract_count', 0, 'extract_failed_count', 0, ...
                'cache_status', '', 'cache_summary_path', '', ...
                'created_count', 0, 'reused_count', 0, 'rebuilt_count', 0, ...
                'failed_count', 0, 'deleted_count', 0, 'deleted_bytes', 0, ...
                'skipped_committed_cleanup', false, 'skip_reason', '', ...
                'cleanup_receipts', {{}}, 'error_identifier', '', ...
                'error_message', '');
        end
    end

    methods (Static, Access = private)
        function text = formatTime(value)
            if isempty(value) || isnat(value)
                text = '';
            else
                text = datestr(value, 'yyyy-mm-dd HH:MM:ss');
            end
        end

        function bytes = freeBytes(pathValue)
            try
                bytes = double(java.io.File(char(string(pathValue))).getUsableSpace());
            catch
                bytes = NaN;
            end
        end
    end
end
