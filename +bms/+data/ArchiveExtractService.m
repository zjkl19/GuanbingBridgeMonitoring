classdef ArchiveExtractService
    %ARCHIVEEXTRACTSERVICE Safe, resumable extraction of monitoring ZIP files.
    %   The service preserves source archives by default, rejects unsafe ZIP
    %   paths, enforces a destination-volume reserve, extracts each archive to
    %   a staging directory, verifies file count/bytes, and only then publishes
    %   the completed daily directory atomically.

    methods (Static)
        function summary = precheck(rootDir, startDate, endDate, cfg)
            if nargin < 4, cfg = struct(); end
            options = bms.data.ArchiveExtractService.options(rootDir, cfg);
            targets = bms.data.ArchiveExtractService.discoverTargets( ...
                options.source_root, options.output_root, startDate, endDate, cfg);

            if isempty(targets)
                error('BMS:ArchiveExtract:NoArchives', ...
                    '在 %s 的 %s 至 %s 范围内未找到可解压的监测 ZIP。', ...
                    options.source_root, char(string(startDate)), char(string(endDate)));
            end

            mode = targets(1).layout;
            if strcmp(mode, 'daily_export')
                expectedDays = bms.data.TimeRangeResolver.daysBetween(startDate, endDate);
                expected = cellstr(datestr(expectedDays, 'yyyy-mm-dd'));
                actual = {targets.day};
                missing = setdiff(expected, actual, 'stable');
                duplicate = bms.data.ArchiveExtractService.duplicateValues(actual);
                if ~isempty(missing) || ~isempty(duplicate)
                    error('BMS:ArchiveExtract:DailyArchiveCount', ...
                        '每日 ZIP 检查失败。缺少日期：%s；重复日期：%s。', ...
                        strjoin(missing, ', '), strjoin(duplicate, ', '));
                end
            else
                expectedKinds = {char([0x6CE2 0x5F62]), char([0x7279 0x5F81 0x503C])};
                daysFound = unique({targets.day}, 'stable');
                bad = {};
                expectedDays = bms.data.TimeRangeResolver.daysBetween(startDate, endDate);
                expected = cellstr(datestr(expectedDays, 'yyyy-mm-dd'));
                missing = setdiff(expected, daysFound, 'stable');
                for m = 1:numel(missing)
                    bad{end+1} = sprintf('%s/整日缺失', missing{m}); %#ok<AGROW>
                end
                for d = 1:numel(daysFound)
                    for k = 1:numel(expectedKinds)
                        count = nnz(strcmp({targets.day}, daysFound{d}) ...
                            & strcmp({targets.kind}, expectedKinds{k}));
                        if count < 1
                            bad{end+1} = sprintf('%s/%s=%d', ... %#ok<AGROW>
                                daysFound{d}, expectedKinds{k}, count);
                        end
                    end
                end
                if ~isempty(bad)
                    error('BMS:ArchiveExtract:DonghuaArchiveCount', ...
                        '波形/特征值 ZIP 检查失败（每个已有日期的每类至少需要 1 个）：%s', ...
                        strjoin(bad, ', '));
                end
            end

            % Count alone is not a safety preflight. Read every central
            % directory now so corrupt archives, unsafe paths, Windows path
            % collisions and unknown entry sizes fail before extraction or
            % destructive cache cleanup starts. Several ZIPs per kind are
            % valid; later publication is deterministically serialized when
            % they share an output directory, and cleanup binds each CSV to
            % exactly one path/size/CRC archive entry.
            for i = 1:numel(targets)
                index = bms.data.ArchiveExtractService. ...
                    readArchiveIndex(targets(i).zip);
                if index.file_count < 1
                    error('BMS:ArchiveExtract:EmptyArchive', ...
                        'ZIP 不含可恢复文件：%s', targets(i).zip);
                end
            end

            summary = struct();
            summary.status = 'ok';
            summary.source_root = options.source_root;
            summary.output_root = options.output_root;
            summary.layout = mode;
            summary.archive_count = numel(targets);
            summary.archives = {targets.zip};
            summary.days = unique({targets.day}, 'stable');
        end

        function summary = run(rootDir, startDate, endDate, cfg)
            if nargin < 4, cfg = struct(); end
            options = bms.data.ArchiveExtractService.options(rootDir, cfg);
            preflight = bms.data.ArchiveExtractService.precheck(rootDir, startDate, endDate, cfg);
            targets = bms.data.ArchiveExtractService.discoverTargets( ...
                options.source_root, options.output_root, startDate, endDate, cfg);

            if ~isfolder(options.output_root)
                [ok, msg] = mkdir(options.output_root);
                if ~ok
                    error('BMS:ArchiveExtract:CreateOutputRoot', ...
                        '无法创建解压输出目录 %s：%s', options.output_root, msg);
                end
            end
            % Coordinate with cache publication and verified source cleanup,
            % not only with other extraction runs.  Acquire in stable day
            % order; the lock is re-entrant when a streaming daily session
            % already owns it in this MATLAB process.
            dailyTargets = targets(strcmp({targets.layout}, 'daily_export'));
            dailyDays = sort(unique(cellstr(string({dailyTargets.day}))));
            dayMutationCleanups = cell(1, numel(dailyDays)); %#ok<NASGU>
            for dayIndex = 1:numel(dailyDays)
                dayMutationCleanups{dayIndex} = ...
                    bms.data.DailyExportMutationLock.acquire( ...
                    options.output_root, dailyDays{dayIndex});
            end
            % Always acquire locks in day -> archive-root order.  A streaming
            % cleanup already owns one day lease and re-enters it here; using
            % the inverse order in a standalone extractor would create a
            % needless lock inversion (both leases fail fast, but both tasks
            % could otherwise abort).
            lockCleanup = bms.data.ArchiveExtractService.acquireLock(options); %#ok<NASGU>

            indexes = repmat(bms.data.ArchiveExtractService.emptyIndex(), 1, numel(targets));
            capacityBudgeted = false(1, numel(targets));
            pendingBytes = 0;
            pendingFileCount = 0;
            for i = 1:numel(targets)
                indexes(i) = bms.data.ArchiveExtractService.readArchiveIndex(targets(i).zip);
                [isReusable, ~] = bms.data.ArchiveExtractService.isReusableTarget( ...
                    targets(i), indexes(i), false);
                % A merge target shares its output directory with other ZIPs;
                % reserve a complete staging copy even when it currently looks
                % reusable.  This prevents a later CRC mismatch from bypassing
                % the capacity gate.  Directory targets are budgeted only when
                % the planning snapshot is not reusable.
                capacityBudgeted(i) = ~isReusable ...
                    || strcmp(targets(i).publish_mode, 'merge');
                if capacityBudgeted(i)
                    pendingBytes = pendingBytes + indexes(i).uncompressed_bytes;
                    pendingFileCount = pendingFileCount + indexes(i).file_count;
                end
            end

            [freeBefore, totalSpace] = bms.data.ArchiveExtractService.volumeSpace(options.output_root);
            capacity = bms.data.ArchiveExtractService.evaluateCapacity( ...
                freeBefore, totalSpace, pendingBytes, pendingFileCount, ...
                options.additional_required_bytes, options.min_free_gib, ...
                options.min_free_fraction, options.uncompressed_safety_factor, ...
                options.metadata_bytes_per_file);
            if ~capacity.passed
                error('BMS:ArchiveExtract:InsufficientSpace', ...
                    ['解压空间门槛未通过：当前可用 %.2f GiB，待解压预算 %.2f GiB，' ...
                     '额外预留任务 %.2f GiB，要求完成后至少保留 %.2f GiB。'], ...
                    freeBefore / 1024^3, capacity.pending_budget_bytes / 1024^3, ...
                    options.additional_required_bytes / 1024^3, capacity.reserve_bytes / 1024^3);
            end

            startedAt = datetime('now');
            results = repmat(bms.data.ArchiveExtractService.emptyResult(), 1, numel(targets));
            workerPlan = bms.data.ArchiveExtractService.workerPlan( ...
                options.requested_workers, numel(targets));
            workers = workerPlan.resolved_workers;
            fallbackReason = '';
            if workers > 1 && bms.data.ArchiveExtractService.hasSharedOutputDirectories(targets)
                fallbackReason = ['多个 ZIP 共享同一输出目录；为避免并发发布竞争，' ...
                    '本次安全回退为串行解压。'];
                workers = 1;
            elseif workers > 1
                [workers, fallbackReason] = ...
                    bms.data.ArchiveExtractService.ensurePool(workers);
            end
            if workers > 1
                parfor (i = 1:numel(targets), workers)
                    results(i) = bms.data.ArchiveExtractService.extractOne( ...
                        targets(i), indexes(i), options, capacityBudgeted(i));
                end
            else
                for i = 1:numel(targets)
                    results(i) = bms.data.ArchiveExtractService.extractOne( ...
                        targets(i), indexes(i), options, capacityBudgeted(i));
                end
            end

            failed = results(strcmp({results.status}, 'failed'));
            [freeAfter, ~] = bms.data.ArchiveExtractService.volumeSpace(options.output_root);
            summary = struct();
            summary.schema_version = 1;
            summary.status = 'ok';
            summary.started_at = char(startedAt, 'yyyy-MM-dd HH:mm:ss');
            summary.completed_at = char(datetime('now'), 'yyyy-MM-dd HH:mm:ss');
            summary.source_root = options.source_root;
            summary.output_root = options.output_root;
            summary.layout = preflight.layout;
            summary.preserve_archives = ~options.delete_archives_after_verify;
            summary.worker_mode = workerPlan.mode;
            summary.requested_workers = workerPlan.requested_workers;
            summary.resolved_workers = workerPlan.resolved_workers;
            summary.effective_workers = workers;
            summary.parallel_fallback = workers < workerPlan.resolved_workers;
            summary.parallel_fallback_reason = fallbackReason;
            summary.reuse_validation = options.reuse_validation;
            summary.capacity_budgeted_archive_count = nnz(capacityBudgeted);
            summary.archive_count = numel(results);
            summary.extracted_count = nnz(strcmp({results.status}, 'extracted'));
            summary.reused_count = nnz(strcmp({results.status}, 'reused'));
            summary.failed_count = numel(failed);
            summary.pending_uncompressed_bytes = pendingBytes;
            summary.pending_budget_bytes = capacity.pending_budget_bytes;
            summary.pending_file_count = pendingFileCount;
            summary.free_bytes_before = freeBefore;
            summary.free_bytes_after = freeAfter;
            summary.reserve_bytes = capacity.reserve_bytes;
            summary.projected_free_bytes = capacity.projected_free_bytes;
            summary.results = results;
            if ~isempty(failed)
                summary.status = 'failed';
            end

            % ``summary_file`` is a path option, not merely a leaf name.  A
            % caller may pin the receipt in an isolated run-log directory.
            % Resolve relative values below output_root while preserving an
            % absolute drive/UNC path; blindly passing an absolute Windows
            % path as the second fullfile component creates an invalid value
            % such as ``F:\output\F:\run_logs\summary.json``.
            manifestPath = bms.data.ArchiveExtractService.absolutePath( ...
                options.summary_file, options.output_root);
            summary.summary_path = manifestPath;
            bms.core.Logger.writeJson(manifestPath, summary);
            if ~isempty(failed)
                messages = arrayfun(@(r) sprintf('%s: %s', r.archive, r.message), ...
                    failed, 'UniformOutput', false);
                error('BMS:ArchiveExtract:ArchiveFailed', ...
                    '有 %d 个 ZIP 解压或校验失败：%s', numel(failed), strjoin(messages, ' | '));
            end
        end

        function targets = discoverTargets(sourceRoot, outputRoot, startDate, endDate, cfg)
            if nargin < 5, cfg = struct(); end
            sourceRoot = char(string(sourceRoot));
            outputRoot = char(string(outputRoot));
            adapter = bms.data.ZipDailyExportAdapter.resolve(cfg);
            allowedExtraRoots = {};
            if logical(adapter.cache.enabled) ...
                    && ~bms.data.DataLayoutResolver.isAbsolutePath(adapter.cache.dir) ...
                    && ~bms.data.DataLayoutResolver.isAbsolutePath(adapter.zip.subdir)
                cacheRoot = fullfile(char(string(adapter.zip.subdir)), ...
                    char(string(adapter.cache.dir)));
                cacheRoot = strrep(cacheRoot, '\', '/');
                cacheRoot = regexprep(cacheRoot, '^/+|/+$', '');
                if ~isempty(cacheRoot)
                    allowedExtraRoots = {cacheRoot};
                end
            end
            daily = bms.data.ZipDailyExportAdapter.dailyZipTargets( ...
                sourceRoot, startDate, endDate, cfg);
            targets = struct('zip', {}, 'out_dir', {}, 'day', {}, 'kind', {}, ...
                'layout', {}, 'publish_mode', {}, 'allowed_extra_roots', {});
            for i = 1:numel(daily)
                [~, folderName] = fileparts(daily(i).out_dir);
                targets(end+1) = struct( ... %#ok<AGROW>
                    'zip', daily(i).zip, ...
                    'out_dir', fullfile(outputRoot, folderName), ...
                    'day', daily(i).day, ...
                    'kind', daily(i).prefix, ...
                    'layout', 'daily_export', ...
                    'publish_mode', 'directory', ...
                    'allowed_extra_roots', {allowedExtraRoots});
            end
            if ~isempty(targets)
                targets = bms.data.ArchiveExtractService.sortTargets(targets);
                return;
            end

            dn0 = datenum(startDate, 'yyyy-mm-dd');
            dn1 = datenum(endDate, 'yyyy-mm-dd');
            dayDirs = dir(fullfile(sourceRoot, '20??-??-??'));
            dayDirs = dayDirs([dayDirs.isdir]);
            kinds = {char([0x6CE2 0x5F62]), char([0x7279 0x5F81 0x503C])};
            for d = 1:numel(dayDirs)
                day = dayDirs(d).name;
                try
                    dn = datenum(day, 'yyyy-mm-dd');
                catch
                    continue;
                end
                if dn < dn0 || dn > dn1, continue; end
                for k = 1:numel(kinds)
                    folder = fullfile(sourceRoot, day, kinds{k});
                    files = dir(fullfile(folder, '**', '*.zip'));
                    files = files(~[files.isdir]);
                    for z = 1:numel(files)
                        relativeParent = bms.data.ArchiveExtractService.relativePath(files(z).folder, sourceRoot);
                        targets(end+1) = struct( ... %#ok<AGROW>
                            'zip', fullfile(files(z).folder, files(z).name), ...
                            'out_dir', fullfile(outputRoot, relativeParent), ...
                            'day', day, ...
                            'kind', kinds{k}, ...
                            'layout', 'donghua_export', ...
                            'publish_mode', 'merge', ...
                            'allowed_extra_roots', {{}});
                    end
                end
            end
            targets = bms.data.ArchiveExtractService.sortTargets(targets);
        end

        function plan = evaluateCapacity(freeBytes, totalBytes, pendingBytes, ...
                pendingFileCount, additionalBytes, minFreeGiB, minFreeFraction, ...
                safetyFactor, metadataBytesPerFile)
            %EVALUATECAPACITY Pure numeric disk-budget calculation (bytes).
            values = double([freeBytes, totalBytes, pendingBytes, pendingFileCount, ...
                additionalBytes, minFreeGiB, minFreeFraction, safetyFactor, metadataBytesPerFile]);
            if any(~isfinite(values)) || any(values(1:6) < 0) ...
                    || minFreeFraction < 0 || minFreeFraction > 0.95 ...
                    || safetyFactor < 1 || metadataBytesPerFile < 0
                error('BMS:ArchiveExtract:InvalidCapacityInput', ...
                    '磁盘预算参数无效。');
            end
            plan = struct();
            plan.free_bytes = double(freeBytes);
            plan.total_bytes = double(totalBytes);
            plan.pending_uncompressed_bytes = double(pendingBytes);
            plan.pending_file_count = double(pendingFileCount);
            plan.pending_budget_bytes = ceil(double(pendingBytes) * double(safetyFactor)) ...
                + double(pendingFileCount) * double(metadataBytesPerFile);
            plan.additional_required_bytes = double(additionalBytes);
            plan.reserve_bytes = max(double(minFreeGiB) * 1024^3, ...
                double(minFreeFraction) * double(totalBytes));
            plan.projected_free_bytes = double(freeBytes) ...
                - plan.pending_budget_bytes - double(additionalBytes);
            plan.passed = plan.projected_free_bytes >= plan.reserve_bytes;
        end

        function contract = workerContract()
            %WORKERCONTRACT Cross-language contract for unzip concurrency.
            % Missing/empty values retain the historical serial default.  The
            % explicit ``auto`` token is deliberately capped at two MATLAB
            % workers because process-based pools have a meaningful memory
            % footprint on smaller field laptops and new machines.
            contract = struct();
            contract.schema_version = 1;
            contract.default_workers = 1;
            contract.auto_token = 'auto';
            contract.auto_max_workers = 2;
            contract.max_custom_workers = 64;
            contract.preset_workers = [1 2 4];
            contract.summary_fields = { ...
                'worker_mode', 'requested_workers', 'resolved_workers', ...
                'effective_workers', 'parallel_fallback', ...
                'parallel_fallback_reason'};
        end

        function setting = normalizeWorkerSetting(value)
            %NORMALIZEWORKERSETTING Validate numeric legacy and auto values.
            contract = bms.data.ArchiveExtractService.workerContract();
            if nargin < 1 || isempty(value)
                value = contract.default_workers;
            end
            setting = struct('mode', '', 'requested_workers', [], 'worker_limit', 1);
            if (ischar(value) || (isstring(value) && isscalar(value))) ...
                    && strcmpi(strtrim(char(string(value))), contract.auto_token)
                setting.mode = 'auto';
                setting.requested_workers = contract.auto_token;
                setting.worker_limit = contract.auto_max_workers;
                return;
            end
            if ~isnumeric(value) || islogical(value) || ~isscalar(value) ...
                    || ~isfinite(double(value)) || double(value) ~= floor(double(value)) ...
                    || double(value) < 1 || double(value) > contract.max_custom_workers
                error('BMS:ArchiveExtract:InvalidMaxWorkers', ...
                    ['preprocessing.unzip.max_workers 必须是 "auto"，或 1 至 %d ' ...
                     '之间的正整数；缺失/空值继续使用安全串行默认值 1。'], ...
                    contract.max_custom_workers);
            end
            setting.mode = 'fixed';
            setting.requested_workers = double(value);
            setting.worker_limit = double(value);
        end

        function plan = workerPlan(value, archiveCount)
            setting = bms.data.ArchiveExtractService.normalizeWorkerSetting(value);
            if ~isnumeric(archiveCount) || ~isscalar(archiveCount) ...
                    || ~isfinite(double(archiveCount)) || archiveCount < 1 ...
                    || archiveCount ~= floor(archiveCount)
                error('BMS:ArchiveExtract:InvalidArchiveCount', ...
                    'archiveCount 必须是正整数。');
            end
            plan = setting;
            plan.resolved_workers = min(setting.worker_limit, double(archiveCount));
        end

        function proof = verifyRecoveryForFiles(rootDir, day, cfg, sourceFiles)
            %VERIFYRECOVERYFORFILES Prove deleted CSVs can be restored from ZIP.
            %   This deliberately performs full content validation before a
            %   destructive cache-cleanup commit. The original extraction
            %   manifest remains immutable; callers store this returned proof
            %   in a separate cleanup receipt.
            if nargin < 4 || isempty(sourceFiles)
                error('BMS:ArchiveExtract:RecoveryFilesMissing', ...
                    'At least one extracted source file is required.');
            end
            if ischar(sourceFiles) || isstring(sourceFiles)
                sourceFiles = cellstr(string(sourceFiles));
            end
            options = bms.data.ArchiveExtractService.options(rootDir, cfg);
            targets = bms.data.ArchiveExtractService.discoverTargets( ...
                options.source_root, options.output_root, day, day, cfg);
            if isempty(targets)
                error('BMS:ArchiveExtract:RecoveryArchiveMissing', ...
                    'No recovery ZIP was found for %s.', char(string(day)));
            end
            matching = false(1, numel(targets));
            for i = 1:numel(targets)
                matching(i) = all(cellfun(@(path) ...
                    bms.data.ArchiveExtractService.isPathInside(path, targets(i).out_dir), ...
                    sourceFiles));
            end
            targets = targets(matching);
            if numel(targets) ~= 1 || ~strcmp(targets(1).layout, 'daily_export')
                error('BMS:ArchiveExtract:RecoveryArchiveAmbiguous', ...
                    ['Verified CSV cleanup currently requires exactly one daily-export ' ...
                     'ZIP whose published directory owns every selected CSV.']);
            end
            target = targets(1);
            index = bms.data.ArchiveExtractService.readArchiveIndex(target.zip);
            [reusable, ~] = bms.data.ArchiveExtractService.isReusableTarget( ...
                target, index, true);
            if ~reusable
                error('BMS:ArchiveExtract:RecoveryVerificationFailed', ...
                    ['The recovery ZIP, extraction manifest and published files no longer ' ...
                     'form a fully verified set: %s'], target.out_dir);
            end
            expected = cellstr(string({index.entries.path}));
            entries = repmat(struct('path', '', 'relative_path', '', ...
                'bytes', 0, 'crc32', 0, 'modified_at', ''), ...
                1, numel(sourceFiles));
            for i = 1:numel(sourceFiles)
                source = char(string(sourceFiles{i}));
                if ~isfile(source)
                    error('BMS:ArchiveExtract:RecoverySourceMissing', ...
                        'Extracted CSV disappeared before cleanup authorisation: %s', source);
                end
                relative = strrep(bms.data.ArchiveExtractService.relativePath( ...
                    source, target.out_dir), char(92), '/');
                entryIndex = find(strcmp(expected, relative), 1);
                if isempty(entryIndex)
                    error('BMS:ArchiveExtract:RecoverySourceUndeclared', ...
                        'CSV is not an entry of the verified recovery ZIP: %s', source);
                end
                info = dir(source);
                sourceCrc = bms.data.ArchiveExtractService.fileCrc32(source);
                if double(info(1).bytes) ~= double(index.entries(entryIndex).bytes) ...
                        || sourceCrc ~= double(index.entries(entryIndex).crc32)
                    error('BMS:ArchiveExtract:RecoverySourceContentMismatch', ...
                        'Extracted CSV does not match its recovery ZIP entry: %s', source);
                end
                entries(i) = struct('path', source, 'relative_path', relative, ...
                    'bytes', double(info(1).bytes), ...
                    'crc32', sourceCrc, ...
                    'modified_at', datestr(info(1).datenum, 'yyyy-mm-dd HH:MM:ss'));
            end
            proof = struct( ...
                'schema_version', 2, ...
                'verified_at', datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss'), ...
                'day', char(string(day)), ...
                'archive_path', target.zip, ...
                'archive_bytes', index.archive_bytes, ...
                'archive_modified_millis', index.archive_modified_millis, ...
                'archive_index_sha256', index.index_sha256, ...
                'archive_entry_count', index.file_count, ...
                'archive_uncompressed_bytes', index.uncompressed_bytes, ...
                'extraction_manifest_path', ...
                    bms.data.ArchiveExtractService.manifestPath(target), ...
                'output_root', target.out_dir, ...
                'source_archive_preserved', true, ...
                'files', entries);
            % Reading only the central directory is insufficient recovery
            % evidence: compressed entry bytes can be damaged while names,
            % sizes and declared CRCs remain unchanged.  Stream every source
            % that will be deleted and verify its actual decoded length/CRC.
            bms.data.ArchiveExtractService.verifyProofEntriesReadable( ...
                target.zip, entries);
        end

        function proofs = verifyRecoveryGroupsForFiles(rootDir, day, cfg, sourceFiles)
            %VERIFYRECOVERYGROUPSFORFILES Map each CSV to exactly one ZIP entry.
            %   Standard dated exports can place several ZIP files in one
            %   output directory. Directory ownership alone is therefore not
            %   recovery evidence. This method matches the exact relative
            %   entry path, byte count and CRC, requires one and only one
            %   verified archive, then streams every selected ZIP entry before
            %   returning a destructive-cleanup proof.
            if nargin < 4 || isempty(sourceFiles)
                error('BMS:ArchiveExtract:RecoveryFilesMissing', ...
                    'At least one extracted source file is required.');
            end
            sourceFiles = unique(cellstr(string(sourceFiles)), 'stable');
            options = bms.data.ArchiveExtractService.options(rootDir, cfg);
            targets = bms.data.ArchiveExtractService.discoverTargets( ...
                options.source_root, options.output_root, day, day, cfg);
            if isempty(targets)
                error('BMS:ArchiveExtract:RecoveryArchiveMissing', ...
                    'No recovery ZIP was found for %s.', char(string(day)));
            end

            targetIndexes = cell(1, numel(targets));
            targetValid = false(1, numel(targets));
            for targetIndex = 1:numel(targets)
                try
                    archiveIndex = bms.data.ArchiveExtractService. ...
                        readArchiveIndex(targets(targetIndex).zip);
                    [reusable, ~] = bms.data.ArchiveExtractService. ...
                        isReusableTarget(targets(targetIndex), archiveIndex, true);
                    if reusable
                        targetIndexes{targetIndex} = archiveIndex;
                        targetValid(targetIndex) = true;
                    end
                catch
                    targetValid(targetIndex) = false;
                end
            end

            assignments = zeros(1, numel(sourceFiles));
            sourceRows = repmat(struct('path', '', 'relative_path', '', ...
                'bytes', 0, 'crc32', 0, 'modified_at', ''), ...
                1, numel(sourceFiles));
            for sourceIndex = 1:numel(sourceFiles)
                source = char(string(sourceFiles{sourceIndex}));
                [assignments(sourceIndex), sourceRows(sourceIndex)] = ...
                    bms.data.ArchiveExtractService.matchUniqueRecoverySource( ...
                        source, targets, targetIndexes, targetValid);
            end

            assignedTargets = unique(assignments, 'stable');
            proofs = repmat(struct( ...
                'schema_version', 3, 'verified_at', '', 'day', '', ...
                'archive_path', '', 'archive_bytes', 0, ...
                'archive_modified_millis', 0, 'archive_index_sha256', '', ...
                'archive_entry_count', 0, 'archive_uncompressed_bytes', 0, ...
                'extraction_manifest_path', '', 'output_root', '', ...
                'target_layout', '', 'publish_mode', '', ...
                'source_archive_preserved', true, ...
                'files', struct('path', {}, 'relative_path', {}, ...
                    'bytes', {}, 'crc32', {}, 'modified_at', {})), ...
                1, numel(assignedTargets));
            for groupIndex = 1:numel(assignedTargets)
                targetIndex = assignedTargets(groupIndex);
                target = targets(targetIndex);
                archiveIndex = targetIndexes{targetIndex};
                files = sourceRows(assignments == targetIndex);
                bms.data.ArchiveExtractService.verifyProofEntriesReadable( ...
                    target.zip, files);
                proofs(groupIndex) = struct( ...
                    'schema_version', 3, ...
                    'verified_at', datestr(datetime('now'), ...
                        'yyyy-mm-dd HH:MM:ss'), ...
                    'day', char(string(day)), ...
                    'archive_path', target.zip, ...
                    'archive_bytes', archiveIndex.archive_bytes, ...
                    'archive_modified_millis', ...
                        archiveIndex.archive_modified_millis, ...
                    'archive_index_sha256', archiveIndex.index_sha256, ...
                    'archive_entry_count', archiveIndex.file_count, ...
                    'archive_uncompressed_bytes', ...
                        archiveIndex.uncompressed_bytes, ...
                    'extraction_manifest_path', ...
                        bms.data.ArchiveExtractService.manifestPath(target), ...
                    'output_root', target.out_dir, ...
                    'target_layout', target.layout, ...
                    'publish_mode', target.publish_mode, ...
                    'source_archive_preserved', true, ...
                    'files', files);
            end
            [~, order] = sort(lower(string({proofs.archive_path})));
            proofs = proofs(order);
        end

        function [selectedIndex, row] = matchUniqueRecoverySource( ...
                source, targets, targetIndexes, targetValid)
            %MATCHUNIQUERECOVERYSOURCE Pure candidate gate used by cleanup.
            %   A target owns SOURCE only when SOURCE is within its published
            %   root and one declared ZIP entry matches the exact relative
            %   path, byte count and CRC. More than one owner is ambiguous and
            %   therefore authorises no deletion.
            source = char(string(source));
            if ~isfile(source)
                error('BMS:ArchiveExtract:RecoverySourceMissing', ...
                    'Extracted CSV disappeared before cleanup authorisation: %s', ...
                    source);
            end
            if nargin < 4 || numel(targetIndexes) ~= numel(targets) ...
                    || numel(targetValid) ~= numel(targets)
                error('BMS:ArchiveExtract:RecoveryCandidateSetInvalid', ...
                    'Recovery candidate indexes do not match the target set.');
            end
            info = dir(source);
            sourceBytes = double(info(1).bytes);
            sourceCrc = bms.data.ArchiveExtractService.fileCrc32(source);
            candidates = [];
            relativeByTarget = cell(1, numel(targets));
            for targetIndex = find(logical(targetValid))
                target = targets(targetIndex);
                if ~bms.data.ArchiveExtractService.isPathInside( ...
                        source, target.out_dir)
                    continue;
                end
                relative = strrep(bms.data.ArchiveExtractService. ...
                    relativePath(source, target.out_dir), char(92), '/');
                archiveIndex = targetIndexes{targetIndex};
                if ~isstruct(archiveIndex) || ~isscalar(archiveIndex) ...
                        || ~isfield(archiveIndex, 'entries')
                    continue;
                end
                entryIndex = find(strcmp( ...
                    cellstr(string({archiveIndex.entries.path})), relative));
                if numel(entryIndex) ~= 1
                    continue;
                end
                entry = archiveIndex.entries(entryIndex);
                if double(entry.bytes) == sourceBytes ...
                        && double(entry.crc32) == sourceCrc
                    candidates(end+1) = targetIndex; %#ok<AGROW>
                    relativeByTarget{targetIndex} = relative;
                end
            end
            if isempty(candidates)
                error('BMS:ArchiveExtract:RecoverySourceUnproven', ...
                    ['Configured CSV does not match any fully verified ZIP ' ...
                     'entry by path, size and CRC: %s'], source);
            end
            if numel(candidates) ~= 1
                paths = cellstr(string({targets(candidates).zip}));
                error('BMS:ArchiveExtract:RecoveryArchiveAmbiguous', ...
                    ['Configured CSV matches more than one verified ZIP entry; ' ...
                     'no deletion is authorised: %s (%s)'], ...
                    source, strjoin(paths, ' | '));
            end
            selectedIndex = candidates(1);
            row = struct('path', source, ...
                'relative_path', relativeByTarget{selectedIndex}, ...
                'bytes', sourceBytes, 'crc32', sourceCrc, ...
                'modified_at', datestr(info(1).datenum, ...
                    'yyyy-mm-dd HH:MM:ss'));
        end

        function ok = verifyArchiveProof(proof, deepPayload)
            %VERIFYARCHIVEPROOF Recheck a previously committed recovery proof.
            %   The default is intentionally metadata-only so MAT-only reuse
            %   does not decompress every archived CSV again.  Destructive
            %   commit code must pass deepPayload=true immediately before
            %   deletion; initial proof creation always performs that deep
            %   check as well.
            if nargin < 2, deepPayload = false; end
            ok = false;
            required = {'schema_version','archive_path','archive_bytes','archive_modified_millis', ...
                'archive_index_sha256','archive_entry_count','archive_uncompressed_bytes', ...
                'source_archive_preserved','files'};
            if ~isstruct(proof) || ~isscalar(proof) || ~all(isfield(proof, required)) ...
                    || ~isnumeric(proof.schema_version) || ~isscalar(proof.schema_version) ...
                    || double(proof.schema_version) < 2 ...
                    || ~islogical(proof.source_archive_preserved) ...
                    || ~isscalar(proof.source_archive_preserved) ...
                    || ~proof.source_archive_preserved ...
                    || ~isfile(char(string(proof.archive_path)))
                return;
            end
            try
                actual = bms.data.ArchiveExtractService.readArchiveIndex( ...
                    char(string(proof.archive_path)));
                ok = double(actual.archive_bytes) == double(proof.archive_bytes) ...
                    && double(actual.archive_modified_millis) == double(proof.archive_modified_millis) ...
                    && double(actual.file_count) == double(proof.archive_entry_count) ...
                    && double(actual.uncompressed_bytes) == double(proof.archive_uncompressed_bytes) ...
                    && strcmp(actual.index_sha256, char(string(proof.archive_index_sha256)));
                if ok
                    bms.data.ArchiveExtractService.verifyProofEntryDeclarations( ...
                        actual, proof.files);
                    if logical(deepPayload)
                        bms.data.ArchiveExtractService.verifyProofEntriesReadable( ...
                            char(string(proof.archive_path)), proof.files);
                    end
                end
            catch
                ok = false;
            end
        end

        function verifyFileAgainstProofEntry(pathValue, proofEntry)
            %VERIFYFILEAGAINSTPROOFENTRY Recheck current bytes against ZIP proof.
            %   Destructive cleanup calls this immediately before staging and
            %   deleting a CSV.  Size and mtime alone are not sufficient: an
            %   external writer can replace a file with same-size content and
            %   restore its timestamp after the original recovery proof was
            %   created.
            required = {'bytes','crc32'};
            if ~isstruct(proofEntry) || ~isscalar(proofEntry) ...
                    || ~all(isfield(proofEntry, required))
                error('BMS:ArchiveExtract:RecoveryProofEntryInvalid', ...
                    'Recovery proof entry is missing bytes/CRC declarations.');
            end
            pathValue = char(string(pathValue));
            if ~isfile(pathValue)
                error('BMS:ArchiveExtract:RecoverySourceMissing', ...
                    'Recovery-bound source file is missing: %s', pathValue);
            end
            expectedBytes = double(proofEntry.bytes);
            expectedCrc = double(proofEntry.crc32);
            if ~isfinite(expectedBytes) || expectedBytes < 0 ...
                    || ~isfinite(expectedCrc) || expectedCrc < 0
                error('BMS:ArchiveExtract:RecoveryProofEntryInvalid', ...
                    'Recovery proof entry has invalid bytes/CRC declarations.');
            end
            info = dir(pathValue);
            actualCrc = bms.data.ArchiveExtractService.fileCrc32(pathValue);
            if double(info(1).bytes) ~= expectedBytes || actualCrc ~= expectedCrc
                error('BMS:ArchiveExtract:RecoverySourceContentMismatch', ...
                    'Current file content no longer matches its recovery ZIP entry: %s', ...
                    pathValue);
            end
        end

        function resolved = resolvedOptions(rootDir, cfg)
            %RESOLVEDOPTIONS Read-only view used by composite workflows.
            if nargin < 2, cfg = struct(); end
            resolved = bms.data.ArchiveExtractService.options(rootDir, cfg);
        end
    end

    methods (Static, Access = private)
        function options = options(rootDir, cfg)
            options = struct();
            options.source_root = char(string(rootDir));
            options.output_root = char(string(rootDir));
            options.max_workers = 1;
            options.min_free_gib = 20;
            options.min_free_fraction = 0.05;
            options.additional_required_bytes = 0;
            options.delete_archives_after_verify = false;
            options.overwrite_existing = false;
            options.uncompressed_safety_factor = 1.03;
            options.metadata_bytes_per_file = 4096;
            options.lock_stale_hours = 24;
            options.recover_stale_lock = false;
            % Use an extraction-time path/size/mtime snapshot for ordinary
            % reuse so a verified 600 GB month is not reread byte-for-byte.
            % Operators can still request ``full_crc`` for a deliberate deep
            % content audit.
            options.reuse_validation = 'metadata';
            % Unit-test-only callback invoked after the planning index has
            % been captured and before an archive is opened for extraction.
            % JSON configurations cannot encode a function handle.
            options.test_after_index_hook = [];
            options.test_before_publish_hook = [];
            options.test_after_publish_hook = [];
            options.summary_file = fullfile('run_logs', 'archive_extract_summary.json');
            section = struct();
            if isstruct(cfg) && isfield(cfg, 'preprocessing') && isstruct(cfg.preprocessing) ...
                    && isfield(cfg.preprocessing, 'unzip') && isstruct(cfg.preprocessing.unzip)
                section = cfg.preprocessing.unzip;
            end
            names = fieldnames(options);
            unknown = setdiff(fieldnames(section), names);
            if ~isempty(unknown)
                error('BMS:ArchiveExtract:UnknownOption', ...
                    'Unknown preprocessing.unzip option(s): %s', ...
                    strjoin(sort(unknown), ', '));
            end
            for i = 1:numel(names)
                name = names{i};
                if isfield(section, name) && ~isempty(section.(name))
                    options.(name) = section.(name);
                end
            end
            baseRoot = bms.data.ArchiveExtractService.absolutePath(rootDir, pwd);
            if ~isfield(section, 'source_root') || isempty(section.source_root)
                options.source_root = baseRoot;
            else
                options.source_root = bms.data.ArchiveExtractService.absolutePath(options.source_root, baseRoot);
            end
            if ~isfield(section, 'output_root') || isempty(section.output_root)
                options.output_root = baseRoot;
            else
                options.output_root = bms.data.ArchiveExtractService.absolutePath(options.output_root, baseRoot);
            end
            workerSetting = bms.data.ArchiveExtractService.normalizeWorkerSetting( ...
                options.max_workers);
            options.requested_workers = workerSetting.requested_workers;
            options.worker_mode = workerSetting.mode;
            options.max_workers = workerSetting.worker_limit;
            options.min_free_gib = max(0, double(options.min_free_gib));
            options.min_free_fraction = max(0, min(0.95, double(options.min_free_fraction)));
            options.additional_required_bytes = max(0, double(options.additional_required_bytes));
            options.uncompressed_safety_factor = max(1, double(options.uncompressed_safety_factor));
            options.metadata_bytes_per_file = max(0, double(options.metadata_bytes_per_file));
            options.lock_stale_hours = max(1, double(options.lock_stale_hours));
            options.recover_stale_lock = logical(options.recover_stale_lock);
            if ~isempty(options.test_after_index_hook) ...
                    && ~isa(options.test_after_index_hook, 'function_handle')
                error('BMS:ArchiveExtract:InvalidTestHook', ...
                    'preprocessing.unzip.test_after_index_hook must be a function handle.');
            end
            if ~isempty(options.test_before_publish_hook) ...
                    && ~isa(options.test_before_publish_hook, 'function_handle')
                error('BMS:ArchiveExtract:InvalidTestHook', ...
                    'preprocessing.unzip.test_before_publish_hook must be a function handle.');
            end
            if ~isempty(options.test_after_publish_hook) ...
                    && ~isa(options.test_after_publish_hook, 'function_handle')
                error('BMS:ArchiveExtract:InvalidTestHook', ...
                    'preprocessing.unzip.test_after_publish_hook must be a function handle.');
            end
            if ~(ischar(options.reuse_validation) ...
                    || (isstring(options.reuse_validation) ...
                        && isscalar(options.reuse_validation)))
                error('BMS:ArchiveExtract:InvalidReuseValidation', ...
                    'preprocessing.unzip.reuse_validation must be metadata or full_crc.');
            end
            options.reuse_validation = lower(strtrim(char(string( ...
                options.reuse_validation))));
            if ~ismember(options.reuse_validation, {'metadata', 'full_crc'})
                error('BMS:ArchiveExtract:InvalidReuseValidation', ...
                    'preprocessing.unzip.reuse_validation must be metadata or full_crc.');
            end
            options.delete_archives_after_verify = logical(options.delete_archives_after_verify);
            options.overwrite_existing = logical(options.overwrite_existing);
            if options.delete_archives_after_verify
                error('BMS:ArchiveExtract:ArchiveDeletionDisabled', ...
                    '安全解压不允许自动删除源 ZIP；请保留原始归档。');
            end
            if options.overwrite_existing
                error('BMS:ArchiveExtract:OverwriteDisabled', ...
                    '安全解压不允许原地覆盖未验证目录；请使用新的隔离输出目录。');
            end
            options.summary_file = char(string(options.summary_file));
        end

        function result = extractOne(target, index, options, capacityBudgeted)
            result = bms.data.ArchiveExtractService.emptyResult();
            result.archive = target.zip;
            result.output_dir = target.out_dir;
            result.day = target.day;
            result.kind = target.kind;
            result.expected_files = index.file_count;
            result.expected_bytes = index.uncompressed_bytes;
            result.archive_index_sha256 = index.index_sha256;
            started = tic;
            try
                if ~isempty(options.test_after_index_hook)
                    options.test_after_index_hook(target.zip);
                end
                % Bind the capacity-planning snapshot to the exact archive
                % that is about to be reused or extracted. A same-path ZIP
                % replacement must never be published under the old index.
                index = bms.data.ArchiveExtractService.assertArchiveSnapshot( ...
                    target.zip, index);
                verifyReusableContent = strcmp(options.reuse_validation, 'full_crc');
                [reusable, existing] = bms.data.ArchiveExtractService.isReusableTarget( ...
                    target, index, verifyReusableContent);
                if reusable
                    bms.data.ArchiveExtractService.assertArchiveSnapshot( ...
                        target.zip, index);
                    result.status = 'reused';
                    result.actual_files = existing.file_count;
                    result.actual_bytes = existing.total_bytes;
                    result.output_index_sha256 = existing.index_sha256;
                    result.elapsed_seconds = toc(started);
                    result.message = '已存在并通过清单复核，跳过重复解压。';
                    return;
                end
                if isfile(bms.data.ArchiveExtractService.manifestPath(target))
                    bms.data.ArchiveExtractService.invalidateTarget( ...
                        target, 'reuse_validation_failed');
                end
                if ~capacityBudgeted
                    error('BMS:ArchiveExtract:ReuseChangedAfterPlanning', ...
                        ['An output that was reusable during capacity planning ' ...
                         'changed before execution; no unbudgeted extraction was started: %s'], ...
                        target.out_dir);
                end
                if isfolder(target.out_dir) && strcmp(target.publish_mode, 'directory')
                    if ~options.overwrite_existing
                        error('BMS:ArchiveExtract:UnverifiedExistingOutput', ...
                            '目标目录已存在但不能由有效解压清单证明完整：%s', target.out_dir);
                    end
                    rmdir(target.out_dir, 's');
                end

                stageDir = sprintf('%s.__extracting_%s', target.out_dir, ...
                    char(java.util.UUID.randomUUID()));
                if isfolder(stageDir), rmdir(stageDir, 's'); end
                mkdir(stageDir);
                cleanup = onCleanup(@() bms.data.ArchiveExtractService.cleanupStage(stageDir)); %#ok<NASGU>
                bms.data.ArchiveExtractService.extractArchive( ...
                    target.zip, stageDir, index);
                bms.data.ArchiveExtractService.assertArchiveSnapshot( ...
                    target.zip, index);

                actual = bms.data.ArchiveExtractService.scanOutput(stageDir);
                expectedActual = bms.data.ArchiveExtractService.scanEntries( ...
                    stageDir, index.entries, true, false);
                if actual.file_count ~= index.file_count ...
                        || actual.total_bytes ~= index.uncompressed_bytes ...
                        || expectedActual.file_count ~= index.file_count ...
                        || expectedActual.total_bytes ~= index.uncompressed_bytes ...
                        || ~strcmp(actual.index_sha256, expectedActual.index_sha256)
                    error('BMS:ArchiveExtract:VerificationFailed', ...
                        '解压校验不闭合：期望 %d 文件/%g 字节，实际 %d 文件/%g 字节，或相对路径不一致。', ...
                        index.file_count, index.uncompressed_bytes, actual.file_count, actual.total_bytes);
                end

                if ~isempty(options.test_before_publish_hook)
                    options.test_before_publish_hook(target.zip);
                end
                bms.data.ArchiveExtractService.assertArchiveSnapshot( ...
                    target.zip, index);
                manifest = struct();
                manifest.schema_version = 4;
                manifest.status = 'publishing';
                manifest.archive_path = target.zip;
                manifest.archive_bytes = index.archive_bytes;
                archiveModified = datetime(index.archive_modified_millis / 1000, ...
                    'ConvertFrom', 'posixtime', 'TimeZone', 'local');
                manifest.archive_modified_at = datestr( ...
                    archiveModified, 'yyyy-mm-dd HH:MM:ss.FFF');
                manifest.archive_modified_millis = index.archive_modified_millis;
                manifest.archive_index_sha256 = index.index_sha256;
                manifest.expected_file_count = index.file_count;
                manifest.expected_uncompressed_bytes = index.uncompressed_bytes;
                manifest.output_file_count = actual.file_count;
                manifest.output_bytes = actual.total_bytes;
                manifest.output_index_sha256 = actual.index_sha256;
                manifest.output_entries = struct('path', {}, 'bytes', {}, ...
                    'modified_millis', {});
                manifest.verified_at = '';
                manifest.source_rechecked_after_publish = false;
                manifest.source_rechecked_at = '';
                manifest.source_archive_preserved = true;

                if strcmp(target.publish_mode, 'directory')
                    bms.data.ArchiveExtractService.assertArchiveSnapshot( ...
                        target.zip, index);
                    [ok, msg] = movefile(stageDir, target.out_dir);
                    if ~ok
                        error('BMS:ArchiveExtract:PublishFailed', ...
                            '无法发布已校验目录 %s：%s', target.out_dir, msg);
                    end
                else
                    bms.data.ArchiveExtractService.assertArchiveSnapshot( ...
                        target.zip, index);
                    % Revoke any older verified merge receipt before changing
                    % files in a shared output directory.
                    bms.core.Logger.writeJson( ...
                        bms.data.ArchiveExtractService.manifestPath(target), manifest);
                    bms.data.ArchiveExtractService.publishMerged( ...
                        stageDir, target.out_dir, index.entries, options.overwrite_existing);
                end

                % Capture metadata from the *published* files.  In merge mode
                % an already-identical destination may have been retained, so
                % its timestamp can legitimately differ from the staging copy.
                manifest.output_entries = ...
                    bms.data.ArchiveExtractService.captureEntryMetadata( ...
                        target.out_dir, index.entries);

                % Published bytes are not reusable until the source is checked
                % again and a verified manifest is committed.
                if ~isempty(options.test_after_publish_hook)
                    options.test_after_publish_hook(target.zip);
                end
                manifestPath = bms.data.ArchiveExtractService.manifestPath(target);
                bms.data.ArchiveExtractService.assertArchiveSnapshot( ...
                    target.zip, index);
                recheckedAt = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss');
                manifest.status = 'verified';
                manifest.source_rechecked_after_publish = true;
                manifest.source_rechecked_at = recheckedAt;
                manifest.verified_at = recheckedAt;
                % This atomic write is the sole authorisation point.  All
                % source checks happen first; no later failure path needs to
                % delete or roll back a verified receipt.
                invalidationPath = ...
                    bms.data.ArchiveExtractService.invalidationPath(target);
                if isfile(invalidationPath), delete(invalidationPath); end
                bms.core.Logger.writeJson(manifestPath, manifest);

                result.status = 'extracted';
                result.actual_files = actual.file_count;
                result.actual_bytes = actual.total_bytes;
                result.output_index_sha256 = actual.index_sha256;
                result.message = '解压、条目校验和原子发布均完成。';
            catch ME
                result.status = 'failed';
                result.message = sprintf('%s: %s', ME.identifier, ME.message);
            end
            result.elapsed_seconds = toc(started);
        end

        function [tf, scan] = isReusableTarget(target, index, verifyContent)
            if nargin < 3, verifyContent = true; end
            tf = false;
            scan = bms.data.ArchiveExtractService.emptyScan();
            manifestPath = bms.data.ArchiveExtractService.manifestPath(target);
            if ~isfolder(target.out_dir) || ~isfile(manifestPath) ...
                    || isfile(bms.data.ArchiveExtractService.invalidationPath(target))
                return;
            end
            try
                manifest = jsondecode(fileread(manifestPath));
                required = {'schema_version','status','archive_path','archive_bytes', ...
                    'archive_index_sha256','expected_file_count', ...
                    'expected_uncompressed_bytes','output_index_sha256'};
                if ~all(isfield(manifest, required)) ...
                        || ~isscalar(manifest.schema_version) ...
                        || ~isnumeric(manifest.schema_version) ...
                        || ~isfinite(double(manifest.schema_version)) ...
                        || double(manifest.schema_version) < 2 ...
                        || ~strcmp(char(string(manifest.status)), 'verified') ...
                        || ~strcmpi(char(java.io.File(char(string(manifest.archive_path))).getCanonicalPath()), ...
                            char(java.io.File(target.zip).getCanonicalPath())) ...
                        || double(manifest.archive_bytes) ~= index.archive_bytes ...
                        || double(manifest.expected_file_count) ~= index.file_count ...
                        || double(manifest.expected_uncompressed_bytes) ~= index.uncompressed_bytes ...
                        || ~strcmp(char(string(manifest.archive_index_sha256)), index.index_sha256)
                    return;
                end
                if double(manifest.schema_version) >= 3 ...
                        && (~isfield(manifest, 'archive_modified_millis') ...
                            || double(manifest.archive_modified_millis) ...
                                ~= index.archive_modified_millis)
                    return;
                end
                effectiveVerifyContent = verifyContent;
                outputEntries = struct('path', {}, 'bytes', {}, ...
                    'modified_millis', {});
                if double(manifest.schema_version) >= 4
                    if ~isfield(manifest, 'output_entries') ...
                            || ~isfield(manifest, 'source_rechecked_after_publish') ...
                            || ~islogical(manifest.source_rechecked_after_publish) ...
                            || ~isscalar(manifest.source_rechecked_after_publish) ...
                            || ~manifest.source_rechecked_after_publish ...
                            || ~bms.data.ArchiveExtractService.validEntryMetadata( ...
                                manifest.output_entries, index.entries)
                        return;
                    end
                    outputEntries = manifest.output_entries;
                else
                    % Legacy manifests predate the per-file mtime snapshot.
                    % Metadata mode preserves their historical path/size fast
                    % path; explicit full_crc remains the deep-audit option.
                    effectiveVerifyContent = verifyContent;
                end
                scan = bms.data.ArchiveExtractService.scanTarget( ...
                    target, index, effectiveVerifyContent, outputEntries);
                tf = scan.file_count == index.file_count ...
                    && scan.total_bytes == index.uncompressed_bytes ...
                    && isfield(manifest, 'output_index_sha256') ...
                    && strcmp(char(string(manifest.output_index_sha256)), scan.index_sha256);
            catch
                tf = false;
            end
        end

        function index = readArchiveIndex(zipPath)
            index = bms.data.ArchiveExtractService.emptyIndex();
            before = bms.data.ArchiveExtractService.archiveFingerprint(zipPath);
            jz = java.util.zip.ZipFile(zipPath);
            cleanup = onCleanup(@() jz.close()); %#ok<NASGU>
            entries = jz.entries();
            rows = {};
            seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            while entries.hasMoreElements()
                entry = entries.nextElement();
                name = char(entry.getName());
                % ZipEntry.isDirectory recognises only a trailing forward
                % slash. Windows ZIP writers may emit directory records with
                % a trailing backslash, so recognise both separators.
                isDirectory = entry.isDirectory() || endsWith(name, '/') || endsWith(name, '\');
                if isDirectory
                    name = regexprep(name, '[\\/]+$', '');
                    if ~isempty(name)
                        bms.data.ArchiveExtractService.normalizeEntry(name);
                    end
                    continue;
                end
                normalized = bms.data.ArchiveExtractService.normalizeEntry(name);
                collisionKey = lower(normalized);
                if isKey(seen, collisionKey)
                    error('BMS:ArchiveExtract:DuplicateEntry', ...
                        'ZIP 含 Windows 下会发生冲突的重复路径：%s', normalized);
                end
                seen(collisionKey) = true;
                bytes = double(entry.getSize());
                if bytes < 0
                    error('BMS:ArchiveExtract:UnknownEntrySize', ...
                        'ZIP 条目大小未知，无法执行空间门槛：%s (%s)', name, zipPath);
                end
                crc = double(entry.getCrc());
                index.file_count = index.file_count + 1;
                index.uncompressed_bytes = index.uncompressed_bytes + bytes;
                index.entries(end+1) = struct( ... %#ok<AGROW>
                    'path', normalized, 'bytes', bytes, 'crc32', crc);
                rows{end+1} = sprintf('%s\t%.0f\t%.0f', normalized, bytes, crc); %#ok<AGROW>
            end
            index.index_sha256 = bms.data.ArchiveExtractService.sha256Text(strjoin(sort(rows), newline));
            delete(cleanup);
            after = bms.data.ArchiveExtractService.archiveFingerprint(zipPath);
            if before.bytes ~= after.bytes ...
                    || before.modified_millis ~= after.modified_millis
                error('BMS:ArchiveExtract:ArchiveChanged', ...
                    'Archive changed while its index was being read: %s', zipPath);
            end
            index.archive_bytes = after.bytes;
            index.archive_modified_millis = after.modified_millis;
        end

        function extractArchive(zipPath, stageDir, expectedIndex)
            jz = java.util.zip.ZipFile(zipPath);
            cleanupZip = onCleanup(@() jz.close()); %#ok<NASGU>
            entries = jz.entries();
            expectedByPath = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for i = 1:numel(expectedIndex.entries)
                expectedByPath(lower(expectedIndex.entries(i).path)) = expectedIndex.entries(i);
            end
            seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            stageCanonical = char(java.io.File(stageDir).getCanonicalPath());
            prefix = [stageCanonical char(java.io.File.separatorChar)];
            while entries.hasMoreElements()
                entry = entries.nextElement();
                rawName = char(entry.getName());
                isDirectory = entry.isDirectory() || endsWith(rawName, '/') || endsWith(rawName, '\');
                if isDirectory
                    rawName = regexprep(rawName, '[\\/]+$', '');
                    if isempty(rawName), continue; end
                end
                normalized = bms.data.ArchiveExtractService.normalizeEntry(rawName);
                destination = fullfile(stageDir, strrep(normalized, '/', filesep));
                canonical = char(java.io.File(destination).getCanonicalPath());
                if ~startsWith(lower(canonical), lower(prefix))
                    error('BMS:ArchiveExtract:UnsafeDestination', ...
                        'ZIP 条目解析后超出暂存目录：%s', normalized);
                end
                if isDirectory
                    if ~isfolder(canonical), mkdir(canonical); end
                    continue;
                end
                key = lower(normalized);
                if ~isKey(expectedByPath, key) || isKey(seen, key)
                    error('BMS:ArchiveExtract:ArchiveChanged', ...
                        'Archive entry set changed after planning: %s (%s)', ...
                        normalized, zipPath);
                end
                expectedEntry = expectedByPath(key);
                if ~strcmp(normalized, expectedEntry.path) ...
                        || double(entry.getSize()) ~= expectedEntry.bytes ...
                        || double(entry.getCrc()) ~= expectedEntry.crc32
                    error('BMS:ArchiveExtract:ArchiveChanged', ...
                        'Archive entry metadata changed after planning: %s (%s)', ...
                        normalized, zipPath);
                end
                seen(key) = true;
                parent = fileparts(canonical);
                if ~isfolder(parent), mkdir(parent); end
                bms.data.ArchiveExtractService.copyEntryWithCrc(jz, entry, canonical);
            end
            if seen.Count ~= expectedIndex.file_count
                error('BMS:ArchiveExtract:ArchiveChanged', ...
                    'Archive file count changed after planning: %s', zipPath);
            end
        end

        function copyEntryWithCrc(zipFile, entry, destination)
            checksum = java.util.zip.CRC32();
            input = java.util.zip.CheckedInputStream(zipFile.getInputStream(entry), checksum);
            readable = java.nio.channels.Channels.newChannel(input);
            output = java.io.FileOutputStream(destination);
            writable = output.getChannel();
            cleanup = onCleanup(@() bms.data.ArchiveExtractService.closeJavaStreams( ...
                writable, output, readable, input)); %#ok<NASGU>
            expected = double(entry.getSize());
            position = 0;
            while position < expected
                transferred = double(writable.transferFrom(readable, position, expected - position));
                if transferred <= 0
                    break;
                end
                position = position + transferred;
            end
            % Consume a zero-length entry and ensure the checked stream reaches EOF.
            if expected == 0
                readable.read(java.nio.ByteBuffer.allocate(1));
            end
            writable.force(true);
            if position ~= expected
                error('BMS:ArchiveExtract:EntryLengthMismatch', ...
                    'ZIP 条目写入长度不符：%s，期望 %.0f，实际 %.0f。', ...
                    char(entry.getName()), expected, position);
            end
            actualCrc = double(checksum.getValue());
            expectedCrc = double(entry.getCrc());
            if expectedCrc >= 0 && actualCrc ~= expectedCrc
                error('BMS:ArchiveExtract:CrcMismatch', ...
                    'ZIP 条目 CRC 校验失败：%s。', char(entry.getName()));
            end
        end

        function verifyProofEntriesReadable(zipPath, proofFiles)
            required = {'relative_path','bytes','crc32'};
            if ~isstruct(proofFiles) || isempty(proofFiles) ...
                    || ~all(isfield(proofFiles, required))
                error('BMS:ArchiveExtract:RecoveryProofFilesInvalid', ...
                    'Recovery proof has no stream-verifiable ZIP entries.');
            end
            zipFile = java.util.zip.ZipFile(char(string(zipPath)));
            zipCleanup = onCleanup(@() zipFile.close()); %#ok<NASGU>
            byPath = containers.Map('KeyType', 'char', 'ValueType', 'any');
            enumeration = zipFile.entries();
            while enumeration.hasMoreElements()
                entry = enumeration.nextElement();
                rawName = char(entry.getName());
                if entry.isDirectory() || endsWith(rawName, '/') || endsWith(rawName, '\')
                    continue;
                end
                normalized = bms.data.ArchiveExtractService.normalizeEntry(rawName);
                byPath(lower(normalized)) = entry;
            end
            seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            for i = 1:numel(proofFiles)
                relative = bms.data.ArchiveExtractService.normalizeEntry( ...
                    char(string(proofFiles(i).relative_path)));
                key = lower(relative);
                expectedBytes = double(proofFiles(i).bytes);
                expectedCrc = double(proofFiles(i).crc32);
                if isKey(seen, key) || ~isKey(byPath, key) ...
                        || ~isfinite(expectedBytes) || expectedBytes < 0 ...
                        || ~isfinite(expectedCrc) || expectedCrc < 0
                    error('BMS:ArchiveExtract:RecoveryProofEntryInvalid', ...
                        'Recovery proof entry is missing, duplicated or malformed: %s', relative);
                end
                seen(key) = true;
                entry = byPath(key);
                if double(entry.getSize()) ~= expectedBytes ...
                        || double(entry.getCrc()) ~= expectedCrc
                    error('BMS:ArchiveExtract:RecoveryProofEntryChanged', ...
                        'Recovery ZIP entry metadata changed: %s', relative);
                end
                checksum = java.util.zip.CRC32();
                input = java.util.zip.CheckedInputStream( ...
                    zipFile.getInputStream(entry), checksum);
                readable = java.nio.channels.Channels.newChannel(input);
                streamCleanup = onCleanup(@() ...
                    bms.data.ArchiveExtractService.closeJavaStreams(readable, input));
                buffer = java.nio.ByteBuffer.allocate(1024 * 1024);
                actualBytes = 0;
                while true
                    buffer.clear();
                    count = double(readable.read(buffer));
                    if count < 0, break; end
                    if count == 0, continue; end
                    actualBytes = actualBytes + count;
                    if actualBytes > expectedBytes
                        error('BMS:ArchiveExtract:RecoveryEntryLengthMismatch', ...
                            'Recovery ZIP entry exceeds its declared length: %s', relative);
                    end
                end
                actualCrc = double(checksum.getValue());
                delete(streamCleanup);
                if actualBytes ~= expectedBytes || actualCrc ~= expectedCrc
                    error('BMS:ArchiveExtract:RecoveryEntryCrcMismatch', ...
                        ['Recovery ZIP entry cannot be decoded to its verified ' ...
                         'length/CRC: %s'], relative);
                end
            end
        end

        function verifyProofEntryDeclarations(index, proofFiles)
            required = {'relative_path','bytes','crc32'};
            if ~isstruct(proofFiles) || isempty(proofFiles) ...
                    || ~all(isfield(proofFiles, required))
                error('BMS:ArchiveExtract:RecoveryProofFilesInvalid', ...
                    'Recovery proof has no declared ZIP entries.');
            end
            indexPaths = lower(string({index.entries.path}));
            proofPaths = strings(1, numel(proofFiles));
            for i = 1:numel(proofFiles)
                relative = bms.data.ArchiveExtractService.normalizeEntry( ...
                    char(string(proofFiles(i).relative_path)));
                proofPaths(i) = lower(string(relative));
                match = find(indexPaths == proofPaths(i), 1);
                expectedBytes = double(proofFiles(i).bytes);
                expectedCrc = double(proofFiles(i).crc32);
                if isempty(match) || ~isfinite(expectedBytes) || expectedBytes < 0 ...
                        || ~isfinite(expectedCrc) || expectedCrc < 0 ...
                        || double(index.entries(match).bytes) ~= expectedBytes ...
                        || double(index.entries(match).crc32) ~= expectedCrc
                    error('BMS:ArchiveExtract:RecoveryProofEntryChanged', ...
                        'Recovery ZIP entry declaration changed: %s', relative);
                end
            end
            if numel(unique(proofPaths)) ~= numel(proofPaths)
                error('BMS:ArchiveExtract:RecoveryProofEntryInvalid', ...
                    'Recovery proof contains duplicate ZIP entries.');
            end
        end

        function closeJavaStreams(varargin)
            for i = 1:numel(varargin)
                try
                    varargin{i}.close();
                catch
                end
            end
        end

        function scan = scanOutput(folder)
            scan = bms.data.ArchiveExtractService.emptyScan();
            files = dir(fullfile(folder, '**', '*'));
            files = files(~[files.isdir]);
            rows = {};
            for i = 1:numel(files)
                if strcmp(files(i).name, '.bms_extract_manifest.json'), continue; end
                fullPath = fullfile(files(i).folder, files(i).name);
                rel = bms.data.ArchiveExtractService.relativePath(fullPath, folder);
                scan.file_count = scan.file_count + 1;
                scan.total_bytes = scan.total_bytes + double(files(i).bytes);
                rows{end+1} = sprintf('%s\t%.0f', strrep(rel, '\', '/'), double(files(i).bytes)); %#ok<AGROW>
            end
            scan.index_sha256 = bms.data.ArchiveExtractService.sha256Text(strjoin(sort(rows), newline));
        end

        function scan = scanTarget(target, index, verifyContent, outputEntries)
            if nargin < 3, verifyContent = false; end
            if nargin < 4
                outputEntries = struct('path', {}, 'bytes', {}, ...
                    'modified_millis', {});
            end
            if strcmp(target.publish_mode, 'directory')
                % A verified daily export is also the home of derived cache
                % artifacts created after extraction (for example
                % data/jlj/csv/cache/*.mat).  Reuse validation must therefore
                % permit that explicit cache subtree while rejecting every
                % other undeclared file.  In particular, a manually copied CSV
                % must never leak into later cache discovery.
                bms.data.ArchiveExtractService.assertNoUnexpectedDirectoryFiles( ...
                    target.out_dir, index.entries, target.allowed_extra_roots);
                scan = bms.data.ArchiveExtractService.scanEntries( ...
                    target.out_dir, index.entries, false, verifyContent, ...
                    outputEntries);
                return;
            end
            scan = bms.data.ArchiveExtractService.scanEntries( ...
                target.out_dir, index.entries, false, verifyContent, ...
                outputEntries);
        end

        function scan = scanEntries(folder, entries, requireAll, verifyContent, outputEntries)
            if nargin < 3, requireAll = false; end
            if nargin < 4, verifyContent = false; end
            if nargin < 5
                outputEntries = struct('path', {}, 'bytes', {}, ...
                    'modified_millis', {});
            end
            scan = bms.data.ArchiveExtractService.emptyScan();
            rows = {};
            metadataByPath = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for metadataIndex = 1:numel(outputEntries)
                metadataByPath(lower(char(string(outputEntries(metadataIndex).path)))) = ...
                    outputEntries(metadataIndex);
            end
            for i = 1:numel(entries)
                rel = strrep(entries(i).path, '/', filesep);
                pathValue = fullfile(folder, rel);
                if ~isfile(pathValue)
                    if requireAll
                        error('BMS:ArchiveExtract:MissingOutputEntry', ...
                            '已解压目录缺少 ZIP 条目：%s', entries(i).path);
                    end
                    return;
                end
                info = dir(pathValue);
                if double(info.bytes) ~= entries(i).bytes
                    if requireAll
                        error('BMS:ArchiveExtract:OutputEntrySizeMismatch', ...
                            '已解压条目大小不符：%s', entries(i).path);
                    end
                    return;
                end
                if verifyContent ...
                        && bms.data.ArchiveExtractService.fileCrc32(pathValue) ...
                            ~= entries(i).crc32
                    if requireAll
                        error('BMS:ArchiveExtract:OutputEntryCrcMismatch', ...
                            'Extracted entry content does not match ZIP CRC: %s', ...
                            entries(i).path);
                    end
                    return;
                end
                if ~verifyContent && ~isempty(outputEntries)
                    key = lower(entries(i).path);
                    if ~isKey(metadataByPath, key)
                        if requireAll
                            error('BMS:ArchiveExtract:MissingOutputMetadata', ...
                                'Extraction metadata is missing for: %s', entries(i).path);
                        end
                        return;
                    end
                    metadata = metadataByPath(key);
                    actualModifiedMillis = double(java.io.File(pathValue).lastModified());
                    if double(metadata.bytes) ~= double(info.bytes) ...
                            || double(metadata.modified_millis) ~= actualModifiedMillis
                        if requireAll
                            error('BMS:ArchiveExtract:OutputMetadataMismatch', ...
                                'Extracted entry metadata changed: %s', entries(i).path);
                        end
                        return;
                    end
                end
                scan.file_count = scan.file_count + 1;
                scan.total_bytes = scan.total_bytes + double(info.bytes);
                rows{end+1} = sprintf('%s\t%.0f', ... %#ok<AGROW>
                    entries(i).path, double(info.bytes));
            end
            scan.index_sha256 = bms.data.ArchiveExtractService.sha256Text( ...
                strjoin(sort(rows), newline));
        end

        function assertNoUnexpectedDirectoryFiles(folder, entries, allowedExtraRoots)
            if nargin < 3, allowedExtraRoots = {}; end
            declared = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            for i = 1:numel(entries)
                declared(lower(strrep(entries(i).path, '\', '/'))) = true;
            end
            files = dir(fullfile(folder, '**', '*'));
            files = files(~[files.isdir]);
            for i = 1:numel(files)
                fullPath = fullfile(files(i).folder, files(i).name);
                relative = strrep( ...
                    bms.data.ArchiveExtractService.relativePath(fullPath, folder), ...
                    '\', '/');
                if strcmp(relative, '.bms_extract_manifest.json')
                    continue;
                end
                allowed = false;
                for rootIndex = 1:numel(allowedExtraRoots)
                    allowedRoot = strrep(char(string( ...
                        allowedExtraRoots{rootIndex})), '\', '/');
                    allowedRoot = regexprep(allowedRoot, '^/+|/+$', '');
                    if ~isempty(allowedRoot) ...
                            && startsWith(lower(relative), ...
                                [lower(allowedRoot) '/'])
                        allowed = true;
                        break;
                    end
                end
                if allowed
                    continue;
                end
                if ~isKey(declared, lower(relative))
                    error('BMS:ArchiveExtract:UnexpectedOutputEntry', ...
                        'Verified extraction contains an undeclared file: %s', relative);
                end
            end
        end

        function metadata = captureEntryMetadata(folder, entries)
            metadata = repmat(struct('path', '', 'bytes', 0, ...
                'modified_millis', 0), 1, numel(entries));
            for i = 1:numel(entries)
                pathValue = fullfile(folder, strrep(entries(i).path, '/', filesep));
                info = dir(pathValue);
                if isempty(info) || ~isfile(pathValue)
                    error('BMS:ArchiveExtract:MissingOutputEntry', ...
                        'Cannot capture extraction metadata for: %s', entries(i).path);
                end
                metadata(i).path = entries(i).path;
                metadata(i).bytes = double(info.bytes);
                metadata(i).modified_millis = ...
                    double(java.io.File(pathValue).lastModified());
            end
        end

        function tf = validEntryMetadata(metadata, entries)
            tf = isstruct(metadata) && numel(metadata) == numel(entries) ...
                && all(isfield(metadata, {'path', 'bytes', 'modified_millis'}));
            if ~tf, return; end
            expected = sort(lower(string({entries.path})));
            actual = strings(1, numel(metadata));
            for i = 1:numel(metadata)
                if ~(ischar(metadata(i).path) ...
                        || (isstring(metadata(i).path) && isscalar(metadata(i).path))) ...
                        || ~isnumeric(metadata(i).bytes) ...
                        || ~isscalar(metadata(i).bytes) ...
                        || ~isfinite(double(metadata(i).bytes)) ...
                        || double(metadata(i).bytes) < 0 ...
                        || ~isnumeric(metadata(i).modified_millis) ...
                        || ~isscalar(metadata(i).modified_millis) ...
                        || ~isfinite(double(metadata(i).modified_millis)) ...
                        || double(metadata(i).modified_millis) < 0
                    tf = false;
                    return;
                end
                actual(i) = lower(string(metadata(i).path));
            end
            tf = isequal(sort(actual), expected);
        end

        function publishMerged(stageDir, outputDir, entries, overwriteExisting)
            if ~isfolder(outputDir), mkdir(outputDir); end
            for i = 1:numel(entries)
                rel = strrep(entries(i).path, '/', filesep);
                source = fullfile(stageDir, rel);
                destination = fullfile(outputDir, rel);
                parent = fileparts(destination);
                if ~isfolder(parent), mkdir(parent); end
                if isfile(destination)
                    info = dir(destination);
                    if double(info.bytes) == entries(i).bytes ...
                            && bms.data.ArchiveExtractService.fileCrc32(destination) == entries(i).crc32
                        continue;
                    end
                    error('BMS:ArchiveExtract:MergeCollision', ...
                        '目标文件已存在但与 ZIP 条目不一致：%s', destination);
                end
                [ok, msg] = movefile(source, destination);
                if ~ok
                    error('BMS:ArchiveExtract:MergePublishFailed', ...
                        '无法发布已校验文件 %s：%s', destination, msg);
                end
            end
        end

        function value = fileCrc32(pathValue)
            checksum = java.util.zip.CRC32();
            input = java.io.BufferedInputStream(java.io.FileInputStream(pathValue));
            checked = java.util.zip.CheckedInputStream(input, checksum);
            channel = java.nio.channels.Channels.newChannel(checked);
            cleanup = onCleanup(@() bms.data.ArchiveExtractService.closeJavaStreams( ...
                channel, checked, input)); %#ok<NASGU>
            buffer = java.nio.ByteBuffer.allocate(1024 * 1024);
            while channel.read(buffer) >= 0
                buffer.clear();
            end
            value = double(checksum.getValue());
        end

        function pathValue = manifestPath(target)
            if strcmp(target.publish_mode, 'directory')
                name = '.bms_extract_manifest.json';
            else
                [~, base] = fileparts(target.zip);
                safe = regexprep(base, '[^A-Za-z0-9_.-]', '_');
                name = ['.bms_extract_' safe '.json'];
            end
            pathValue = fullfile(target.out_dir, name);
        end

        function pathValue = invalidationPath(target)
            manifestPath = bms.data.ArchiveExtractService.manifestPath(target);
            pathValue = [manifestPath '.invalidated.json'];
        end

        function invalidateTarget(target, reason)
            invalidatedAt = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss');
            marker = struct( ...
                'schema_version', 1, ...
                'status', 'invalidated', ...
                'reason', char(string(reason)), ...
                'invalidated_at', invalidatedAt);
            markerPath = bms.data.ArchiveExtractService.invalidationPath(target);
            bms.core.Logger.writeJson(markerPath, marker);

            manifestPath = bms.data.ArchiveExtractService.manifestPath(target);
            try
                manifest = jsondecode(fileread(manifestPath));
                if isstruct(manifest) && isscalar(manifest)
                    manifest.status = 'invalidated';
                    manifest.invalidation_reason = char(string(reason));
                    manifest.invalidated_at = invalidatedAt;
                    bms.core.Logger.writeJson(manifestPath, manifest);
                end
            catch
                % The independently committed invalidation marker is the
                % authoritative fail-closed gate even if an old receipt is
                % malformed and cannot be annotated.
            end
        end

        function normalized = normalizeEntry(name)
            normalized = strrep(char(name), '\', '/');
            while startsWith(normalized, './')
                normalized = normalized(3:end);
            end
            parts = strsplit(normalized, '/');
            if isempty(normalized) || startsWith(normalized, '/') ...
                    || ~isempty(regexp(normalized, '^[A-Za-z]:', 'once')) ...
                    || any(strcmp(parts, '..')) || any(strcmp(parts, '.')) ...
                    || contains(normalized, ':') || any(uint16(normalized) < 32)
                error('BMS:ArchiveExtract:UnsafeEntry', 'ZIP 含不安全路径：%s', name);
            end
            reserved = {'CON','PRN','AUX','NUL', ...
                'COM1','COM2','COM3','COM4','COM5','COM6','COM7','COM8','COM9', ...
                'LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9'};
            for i = 1:numel(parts)
                part = parts{i};
                if isempty(part) || ~strcmp(part, regexprep(part, '[\. ]+$', ''))
                    error('BMS:ArchiveExtract:UnsafeEntry', ...
                        'ZIP 路径含空段或 Windows 尾随点/空格：%s', name);
                end
                base = upper(regexp(part, '^[^.]*', 'match', 'once'));
                if any(strcmp(base, reserved))
                    error('BMS:ArchiveExtract:UnsafeEntry', ...
                        'ZIP 路径使用 Windows 保留设备名：%s', name);
                end
            end
        end

        function [freeBytes, totalBytes] = volumeSpace(pathValue)
            existing = char(pathValue);
            while ~isfolder(existing)
                parent = fileparts(existing);
                if isempty(parent) || strcmp(parent, existing), break; end
                existing = parent;
            end
            obj = java.io.File(existing);
            freeBytes = double(obj.getUsableSpace());
            totalBytes = double(obj.getTotalSpace());
            if totalBytes <= 0
                error('BMS:ArchiveExtract:VolumeSpaceUnavailable', ...
                    '无法读取目标卷空间：%s', pathValue);
            end
        end

        function [workers, fallbackReason] = ensurePool(requested)
            workers = 1;
            fallbackReason = '';
            try
                cluster = parcluster('local');
                clusterLimit = double(cluster.NumWorkers);
                target = min(requested, clusterLimit);
                if target < requested
                    fallbackReason = sprintf( ...
                        '本机并行配置最多提供 %d 个工作进程；已从 %d 调整为 %d。', ...
                        clusterLimit, requested, target);
                end
                pool = gcp('nocreate');
                if isempty(pool)
                    pool = parpool(cluster, target);
                end
                workers = min(double(pool.NumWorkers), target);
                if workers < requested && isempty(fallbackReason)
                    fallbackReason = sprintf( ...
                        '当前并行池仅提供 %d 个工作进程；请求值为 %d。', ...
                        workers, requested);
                end
            catch ME
                warning('BMS:ArchiveExtract:ParallelUnavailable', ...
                    '并行解压不可用，将改为串行：%s', ME.message);
                workers = 1;
                fallbackReason = sprintf('并行运行环境不可用，已安全回退为串行：%s', ME.message);
            end
        end

        function tf = hasSharedOutputDirectories(targets)
            if numel(targets) < 2
                tf = false;
                return;
            end
            paths = cellfun(@(value) lower(char(java.io.File(value).getCanonicalPath())), ...
                {targets.out_dir}, 'UniformOutput', false);
            tf = numel(unique(paths)) ~= numel(paths);
        end

        function cleanupStage(stageDir)
            if isfolder(stageDir)
                try
                    rmdir(stageDir, 's');
                catch
                end
            end
        end

        function value = absolutePath(value, base)
            value = char(string(value));
            if isempty(value), value = char(string(base)); end
            if isempty(regexp(value, '^[A-Za-z]:[\\/]|^\\\\', 'once'))
                value = fullfile(char(string(base)), value);
            end
            value = char(java.io.File(value).getCanonicalPath());
        end

        function cleanup = acquireLock(options)
            lockPath = fullfile(options.output_root, '.bms_archive_extract.lock');
            try
                cleanup = bms.core.DirectoryLeaseLock.acquire( ...
                    lockPath, ...
                    struct('recover_stale', options.recover_stale_lock, ...
                        'stale_hours', options.lock_stale_hours), ...
                    struct('output_root', options.output_root, ...
                        'purpose', 'archive_extract'));
            catch ME
                if strcmp(ME.identifier, 'BMS:DirectoryLeaseLock:Locked')
                    error('BMS:ArchiveExtract:Locked', ...
                        ['Archive output is owned by another task, or an ' ...
                         'unrecoverable lock remains: %s'], lockPath);
                end
                rethrow(ME);
            end
        end

        function actual = assertArchiveSnapshot(zipPath, expected)
            actual = bms.data.ArchiveExtractService.readArchiveIndex(zipPath);
            same = actual.file_count == expected.file_count ...
                && actual.uncompressed_bytes == expected.uncompressed_bytes ...
                && actual.archive_bytes == expected.archive_bytes ...
                && actual.archive_modified_millis == expected.archive_modified_millis ...
                && strcmp(actual.index_sha256, expected.index_sha256);
            if ~same
                error('BMS:ArchiveExtract:ArchiveChanged', ...
                    'Archive changed after capacity planning: %s', zipPath);
            end
        end

        function fingerprint = archiveFingerprint(zipPath)
            archiveFile = java.io.File(char(string(zipPath)));
            if ~archiveFile.isFile()
                error('BMS:ArchiveExtract:ArchiveMissing', ...
                    'Archive does not exist: %s', zipPath);
            end
            fingerprint = struct( ...
                'bytes', double(archiveFile.length()), ...
                'modified_millis', double(archiveFile.lastModified()));
        end

        function rel = relativePath(pathValue, root)
            pathValue = char(pathValue);
            root = char(root);
            prefix = [regexprep(root, '[\\/]+$', '') filesep];
            if startsWith(lower(pathValue), lower(prefix))
                rel = pathValue(numel(prefix)+1:end);
            elseif strcmpi(pathValue, regexprep(root, '[\\/]+$', ''))
                rel = '';
            else
                rel = pathValue;
            end
        end

        function tf = isPathInside(pathValue, root)
            try
                pathValue = char(java.io.File(char(string(pathValue))).getCanonicalPath());
                root = char(java.io.File(char(string(root))).getCanonicalPath());
            catch
                pathValue = char(string(pathValue));
                root = char(string(root));
            end
            root = regexprep(root, '[\\/]+$', '');
            tf = strcmpi(pathValue, root) || startsWith(lower(pathValue), ...
                lower([root filesep]));
        end

        function values = duplicateValues(values)
            duplicate = {};
            for i = 1:numel(values)
                if nnz(strcmp(values, values{i})) > 1 && ~any(strcmp(duplicate, values{i}))
                    duplicate{end+1} = values{i}; %#ok<AGROW>
                end
            end
            values = duplicate;
        end

        function targets = sortTargets(targets)
            if isempty(targets), return; end
            [~, order] = sort(strcat({targets.day}, '|', {targets.kind}, '|', {targets.zip}));
            targets = targets(order);
        end

        function hash = sha256Text(textValue)
            md = java.security.MessageDigest.getInstance('SHA-256');
            md.update(uint8(unicode2native(char(textValue), 'UTF-8')));
            bytes = typecast(md.digest(), 'uint8');
            hash = lower(reshape(dec2hex(bytes, 2).', 1, []));
        end

        function index = emptyIndex()
            index = struct('file_count', 0, 'uncompressed_bytes', 0, ...
                'index_sha256', '', 'archive_bytes', 0, ...
                'archive_modified_millis', 0, ...
                'entries', struct('path', {}, 'bytes', {}, 'crc32', {}));
        end

        function scan = emptyScan()
            scan = struct('file_count', 0, 'total_bytes', 0, 'index_sha256', '');
        end

        function result = emptyResult()
            result = struct( ...
                'archive', '', 'output_dir', '', 'day', '', 'kind', '', ...
                'status', '', 'message', '', 'expected_files', 0, ...
                'expected_bytes', 0, 'actual_files', 0, 'actual_bytes', 0, ...
                'archive_index_sha256', '', 'output_index_sha256', '', ...
                'elapsed_seconds', 0);
        end
    end
end
