classdef test_jlj_cache_prebuild < matlab.unittest.TestCase
    properties
        TempDir
        Config
    end

    methods (TestMethodSetup)
        function setup(tc)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(projectRoot, fullfile(projectRoot, 'config'), ...
                fullfile(projectRoot, 'pipeline'), fullfile(projectRoot, 'analysis'));
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            tc.Config = minimalJljConfig();
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if isfolder(tc.TempDir)
                rmdir(tc.TempDir, 's');
            end
        end
    end

    methods (Test)
        function firstRunCreatesRawCacheWithoutChangingCsv(tc)
            [sourcePath, originalText] = writeValidCsv(tc.TempDir, 'POINT-01');

            result = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);

            tc.verifyEqual(result.Status, 'ok');
            tc.verifyTrue(isfile(result.StatsPath));
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyEqual(summary.source_file_count, 1);
            tc.verifyEqual(summary.discovered_count, 1);
            tc.verifyEqual(summary.eligible_count, 1);
            tc.verifyEqual(summary.skipped_count, 0);
            tc.verifyEqual(summary.cache_file_count, 1);
            tc.verifyEqual(summary.created_count, 1);
            tc.verifyEqual(summary.failed_count, 0);
            tc.verifyGreaterThan(summary.source_bytes, 0);
            tc.verifyGreaterThan(summary.cache_bytes, 0);
            tc.verifyEqual(fileread(sourcePath), originalText);

            cachePath = expectedCachePath(sourcePath);
            tc.verifyTrue(isfile(cachePath));
            tc.verifyTrue(isfile(bms.data.CacheManager.metadataPath(cachePath)));
            S = load(cachePath, 'ts', 'valx', 'valy', 'valz', 'meta');
            tc.verifyEqual(numel(S.ts), 2);
            tc.verifyEqual(S.valx(:), [1; 2]);
            tc.verifyEqual(S.valy(:), [11; 12]);
            tc.verifyEqual(S.valz(:), [21; 22]);
            tc.verifyTrue(isstruct(S.meta));
        end

        function secondRunReusesValidatedCache(tc)
            [sourcePath, originalText] = writeValidCsv(tc.TempDir, 'POINT-02');
            first = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);
            tc.assertEqual(first.Status, 'ok');
            cachePath = expectedCachePath(sourcePath);
            before = dir(cachePath);

            second = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);

            tc.verifyEqual(second.Status, 'ok');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.discovered_count, 1);
            tc.verifyEqual(summary.eligible_count, 1);
            tc.verifyEqual(summary.skipped_count, 0);
            tc.verifyEqual(summary.reused_count, 1);
            tc.verifyEqual(summary.created_count, 0);
            tc.verifyEqual(summary.rebuilt_count, 0);
            after = dir(cachePath);
            tc.verifyEqual(after.datenum, before.datenum);
            tc.verifyEqual(after.bytes, before.bytes);
            tc.verifyEqual(fileread(sourcePath), originalText);
        end

        function changedCsvRebuildsCache(tc)
            [sourcePath, ~] = writeValidCsv(tc.TempDir, 'POINT-03');
            first = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);
            tc.assertEqual(first.Status, 'ok');

            fid = fopen(sourcePath, 'at');
            tc.assertGreaterThan(fid, 0);
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, '2026-05-01 00:00:02.000,3,13,23\n');
            clear cleanup;
            modifiedText = fileread(sourcePath);

            second = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);

            tc.verifyEqual(second.Status, 'ok');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.rebuilt_count, 1);
            tc.verifyEqual(summary.reused_count, 0);
            S = load(expectedCachePath(sourcePath), 'ts', 'valx', 'valy', 'valz');
            tc.verifyEqual(numel(S.ts), 3);
            tc.verifyEqual(S.valx(:), [1; 2; 3]);
            tc.verifyEqual(S.valy(:), [11; 12; 13]);
            tc.verifyEqual(S.valz(:), [21; 22; 23]);
            tc.verifyEqual(fileread(sourcePath), modifiedText);
        end

        function malformedCsvIsReportedAndFailsModule(tc)
            csvDir = jljCsvDir(tc.TempDir);
            if ~isfolder(csvDir), mkdir(csvDir); end
            sourcePath = fullfile(csvDir, 'BROKEN.csv');
            originalText = sprintf('ts,value_x\nnot-a-time,1\n');
            writeText(sourcePath, originalText);
            originalText = fileread(sourcePath);

            result = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);

            tc.verifyEqual(result.Status, 'fail');
            tc.verifyTrue(isfile(result.StatsPath));
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyEqual(summary.source_file_count, 1);
            tc.verifyEqual(summary.discovered_count, 1);
            tc.verifyEqual(summary.eligible_count, 1);
            tc.verifyEqual(summary.skipped_count, 0);
            tc.verifyEqual(summary.failed_count, 1);
            tc.verifyEqual(summary.cache_file_count, 0);
            tc.verifyEqual(summary.files.status, 'failed');
            tc.verifyEqual(summary.files.error_identifier, ...
                'BMS:JljCachePrebuild:InvalidTime');
            tc.verifyEqual(fileread(sourcePath), originalText);
            tc.verifyFalse(isfile(expectedCachePath(sourcePath)));
        end

        function nonTimeseriesCsvIsExplicitlySkipped(tc)
            [sourcePath, sourceText] = writeValidCsv(tc.TempDir, 'POINT-WITH-WIM');
            csvDir = jljCsvDir(tc.TempDir);
            wimPath = fullfile(csvDir, 'DTCZ-01.csv');
            wimText = sprintf([ ...
                'ts,axles_number,total_weight,vehicle_speed\n' ...
                '2026-05-01 00:00:00.000,4,32000,68\n']);
            writeText(wimPath, wimText);
            wimText = fileread(wimPath);

            result = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);

            tc.verifyEqual(result.Status, 'ok');
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyEqual(summary.discovered_count, 2);
            tc.verifyEqual(summary.discovered_file_count, 2);
            tc.verifyEqual(summary.source_file_count, 1);
            tc.verifyEqual(summary.eligible_count, 1);
            tc.verifyEqual(summary.skipped_count, 1);
            tc.verifyEqual(summary.invalid_count, 0);
            tc.verifyEqual(summary.cache_file_count, 1);
            tc.verifyEqual(summary.created_count, 1);
            tc.verifyEqual(summary.failed_count, 0);
            tc.verifyGreaterThan(summary.skipped_source_bytes, 0);
            tc.verifyEqual(summary.source_bytes, summary.eligible_source_bytes);
            tc.verifyEqual(summary.discovered_source_bytes, ...
                summary.source_bytes + summary.skipped_source_bytes);
            tc.verifyEqual(summary.skipped_files.path, wimPath);
            tc.verifyEqual(summary.skipped_files.reason, ...
                'known_wim_filename_prefix');
            tc.verifyTrue(any(strcmp(summary.skipped_files.header, 'axles_number')));
            tc.verifyTrue(isfile(expectedCachePath(sourcePath)));
            tc.verifyFalse(isfile(expectedCachePath(wimPath)));
            tc.verifyEqual(fileread(sourcePath), sourceText);
            tc.verifyEqual(fileread(wimPath), wimText);
        end

        function unknownSensorSchemaIsInvalidNotSkipped(tc)
            csvDir = jljCsvDir(tc.TempDir);
            if ~isfolder(csvDir), mkdir(csvDir); end
            sourcePath = fullfile(csvDir, 'SENSOR-BAD.csv');
            sourceText = sprintf('ts,reading\n2026-05-01 00:00:00.000,12.5\n');
            writeText(sourcePath, sourceText);
            sourceText = fileread(sourcePath);

            result = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);

            tc.verifyEqual(result.Status, 'fail');
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyEqual(summary.discovered_file_count, 1);
            tc.verifyEqual(summary.eligible_count, 0);
            tc.verifyEqual(summary.source_file_count, 0);
            tc.verifyEqual(summary.source_bytes, 0);
            tc.verifyEqual(summary.skipped_count, 0);
            tc.verifyEqual(summary.invalid_count, 1);
            tc.verifyEqual(summary.failed_count, 1);
            tc.verifyEqual(summary.files.error_identifier, ...
                'BMS:JljCachePrebuild:UnexpectedCsvSchema');
            tc.verifyEqual(fileread(sourcePath), sourceText);
            tc.verifyFalse(isfile(expectedCachePath(sourcePath)));
        end

        function allWimWithZeroEligibleFails(tc)
            [wimPath, wimText] = writeWimCsv(tc.TempDir, 'DTCZ-ONLY');

            result = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);

            tc.verifyEqual(result.Status, 'fail');
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyEqual(summary.error_identifier, ...
                'BMS:JljCachePrebuild:NoEligibleTimeSeriesCsv');
            tc.verifyTrue(summary.no_eligible_timeseries);
            tc.verifyEqual(summary.discovered_file_count, 1);
            tc.verifyEqual(summary.eligible_count, 0);
            tc.verifyEqual(summary.source_file_count, 0);
            tc.verifyEqual(summary.source_bytes, 0);
            tc.verifyEqual(summary.skipped_count, 1);
            tc.verifyEqual(summary.failed_count, 0);
            tc.verifyEqual(fileread(wimPath), wimText);
            tc.verifyFalse(isfile(expectedCachePath(wimPath)));
        end

        function insufficientDiskFailsBeforeAnyCacheWrite(tc)
            [sourcePath, originalText] = writeValidCsv(tc.TempDir, 'POINT-DISK');
            cfg = tc.Config;
            cfg.preprocessing.cache_prebuild = struct( ...
                'min_free_gib', 1e9, ...
                'min_free_fraction', 0, ...
                'estimated_cache_ratio', 1.5);

            result = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', cfg);

            tc.verifyEqual(result.Status, 'fail');
            tc.verifyTrue(isfile(result.StatsPath));
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyEqual(summary.error_identifier, 'BMS:JljCachePrebuild:InsufficientDisk');
            tc.verifyEqual(summary.pending_file_count, 1);
            tc.verifyGreaterThan(summary.pending_source_bytes, 0);
            tc.verifyEqual(summary.projected_cache_bytes, ...
                ceil(summary.pending_source_bytes * 1.5));
            tc.verifyEqual(summary.pending_backup_bytes, 0);
            tc.verifyEqual(summary.projected_write_bytes, summary.projected_cache_bytes);
            tc.verifyGreaterThan(summary.reserve_bytes, summary.free_bytes_before);
            tc.verifyGreaterThan(summary.volume_total_bytes, 0);
            tc.verifyEqual(summary.projected_free_bytes, ...
                summary.free_bytes_before - summary.projected_cache_bytes);
            tc.verifyFalse(isfile(expectedCachePath(sourcePath)));
            tc.verifyEqual(fileread(sourcePath), originalText);
        end

        function forceRebuildDiskProjectionIncludesRollbackBackup(tc)
            [sourcePath, originalText] = writeValidCsv(tc.TempDir, 'POINT-BACKUP-BUDGET');
            first = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);
            tc.assertEqual(first.Status, 'ok');
            cachePath = expectedCachePath(sourcePath);
            existingPairBytes = bms.data.JiulongjiangCsvDataSource.cachePairBytes(cachePath);

            cfg = tc.Config;
            cfg.cache_prebuild.force_rebuild = true;
            second = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', cfg);

            tc.verifyEqual(second.Status, 'ok');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.pending_backup_bytes, existingPairBytes);
            tc.verifyEqual(summary.projected_write_bytes, ...
                summary.projected_cache_bytes + existingPairBytes);
            tc.verifyEqual(summary.projected_free_bytes, ...
                summary.free_bytes_before - summary.projected_write_bytes);
            tc.verifyEqual(summary.rebuilt_count, 1);
            tc.verifyEqual(fileread(sourcePath), originalText);
        end

        function serialAndParallelResultsMatchWithoutNameCollisions(tc)
            existingPool = gcp('nocreate');
            hadPool = ~isempty(existingPool);
            poolCleanup = onCleanup(@() cleanupCreatedPool(hadPool)); %#ok<NASGU>
            cluster = parcluster('local');
            expectedWorkers = min(2, cluster.NumWorkers);
            tc.assumeGreaterThan(expectedWorkers, 1, ...
                'Parallel consistency test requires at least two local workers.');
            if hadPool
                tc.assumeGreaterThan(existingPool.NumWorkers, 1, ...
                    'Existing pool has only one worker.');
            end

            serialRoot = fullfile(tc.TempDir, 'serial');
            parallelRoot = fullfile(tc.TempDir, 'parallel');
            days = {'2026-05-01', '2026-05-02'};
            serialSources = cell(1, numel(days));
            parallelSources = cell(1, numel(days));
            serialTexts = cell(1, numel(days));
            parallelTexts = cell(1, numel(days));
            for i = 1:numel(days)
                [serialSources{i}, serialTexts{i}] = writeValidCsv( ...
                    serialRoot, 'SAME-POINT', days{i});
                [parallelSources{i}, parallelTexts{i}] = writeValidCsv( ...
                    parallelRoot, 'SAME-POINT', days{i});
            end

            serialCfg = tc.Config;
            serialCfg.cache_prebuild.max_workers = 1;
            parallelCfg = tc.Config;
            parallelCfg.cache_prebuild.max_workers = 2;
            serialResult = bms.data.JljCachePrebuildService.run( ...
                serialRoot, days{1}, days{2}, serialCfg);
            parallelResult = bms.data.JljCachePrebuildService.run( ...
                parallelRoot, days{1}, days{2}, parallelCfg);

            tc.verifyEqual(serialResult.Status, 'ok');
            tc.verifyEqual(parallelResult.Status, 'ok');
            serialSummary = jsondecode(fileread(serialResult.StatsPath));
            parallelSummary = jsondecode(fileread(parallelResult.StatsPath));
            tc.verifyEqual(serialSummary.created_count, 2);
            tc.verifyEqual(parallelSummary.created_count, 2);
            tc.verifyEqual(serialSummary.failed_count, 0);
            tc.verifyEqual(parallelSummary.failed_count, 0);
            tc.verifyEqual(serialSummary.workers_used, 1);
            tc.verifyEqual(parallelSummary.workers_used, expectedWorkers);
            tc.verifyTrue(parallelSummary.parallel_used);

            serialCaches = cellfun(@expectedCachePath, serialSources, 'UniformOutput', false);
            parallelCaches = cellfun(@expectedCachePath, parallelSources, 'UniformOutput', false);
            tc.verifyNotEqual(lower(serialCaches{1}), lower(serialCaches{2}));
            tc.verifyNotEqual(lower(parallelCaches{1}), lower(parallelCaches{2}));
            for i = 1:numel(days)
                tc.verifyTrue(isfile(serialCaches{i}));
                tc.verifyTrue(isfile(parallelCaches{i}));
                serialCache = load(serialCaches{i}, 'ts', 'valx', 'valy', 'valz');
                parallelCache = load(parallelCaches{i}, 'ts', 'valx', 'valy', 'valz');
                tc.verifyEqual(parallelCache.ts, serialCache.ts);
                tc.verifyEqual(parallelCache.valx, serialCache.valx);
                tc.verifyEqual(parallelCache.valy, serialCache.valy);
                tc.verifyEqual(parallelCache.valz, serialCache.valz);
                tc.verifyEqual(fileread(serialSources{i}), serialTexts{i});
                tc.verifyEqual(fileread(parallelSources{i}), parallelTexts{i});
            end
        end

        function invalidWorkerCountFailsBeforeCacheWrite(tc)
            [sourcePath, originalText] = writeValidCsv(tc.TempDir, 'POINT-WORKERS');
            cfg = tc.Config;
            cfg.cache_prebuild.max_workers = 1.5;

            result = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', cfg);

            tc.verifyEqual(result.Status, 'fail');
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyEqual(summary.error_identifier, 'BMS:JljCachePrebuild:InvalidWorkers');
            tc.verifyFalse(isfile(expectedCachePath(sourcePath)));
            tc.verifyEqual(fileread(sourcePath), originalText);
        end

        function misspelledOptionsFailBeforeCacheWrite(tc)
            [sourcePath, originalText] = writeValidCsv(tc.TempDir, 'POINT-TYPO');
            cfg = tc.Config;
            cfg.cache_prebuild.estmated_cache_ratio = 2;
            cfg.cache_prebuild.max_worker = 2;

            result = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', cfg);

            tc.verifyEqual(result.Status, 'fail');
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyEqual(summary.error_identifier, 'BMS:JljCachePrebuild:UnknownOption');
            tc.verifyTrue(contains(summary.message, 'estmated_cache_ratio'));
            tc.verifyTrue(contains(summary.message, 'max_worker'));
            tc.verifyFalse(isfile(expectedCachePath(sourcePath)));
            tc.verifyEqual(fileread(sourcePath), originalText);
        end

        function secondFileCommitFailureRollsBackOldPair(tc)
            [sourcePath, sourceText] = writeValidCsv(tc.TempDir, 'POINT-ROLLBACK');
            first = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);
            tc.assertEqual(first.Status, 'ok');
            cachePath = expectedCachePath(sourcePath);
            metadataPath = bms.data.CacheManager.metadataPath(cachePath);
            matBefore = readBinary(cachePath);
            metadataBefore = readBinary(metadataPath);

            tc.verifyError(@() bms.data.JiulongjiangCsvDataSource.buildCacheForFile( ...
                sourcePath, tc.Config, '', true, 'after_mat_publish'), ...
                'BMS:JljCachePrebuild:InjectedCommitFailure');

            tc.verifyEqual(readBinary(cachePath), matBefore);
            tc.verifyEqual(readBinary(metadataPath), metadataBefore);
            adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(tc.Config);
            tc.verifyTrue(bms.data.JiulongjiangCsvDataSource.isReusableRawCache( ...
                cachePath, sourcePath, adapter));
            tc.verifyEqual(fileread(sourcePath), sourceText);
            tc.verifyEmpty(dir(fullfile(fileparts(cachePath), '*.backup.*')));
        end

        function pairIdentityMismatchFailsClosed(tc)
            [sourcePath, sourceText] = writeValidCsv(tc.TempDir, 'POINT-PAIR');
            first = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);
            tc.assertEqual(first.Status, 'ok');
            cachePath = expectedCachePath(sourcePath);
            metadataPath = bms.data.CacheManager.metadataPath(cachePath);
            originalMetadata = fileread(metadataPath);
            metadata = jsondecode(originalMetadata);
            metadata.pair_id = 'mismatched-pair-id';
            bms.core.Logger.writeJson(metadataPath, metadata);
            adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(tc.Config);

            tc.verifyFalse(bms.data.JiulongjiangCsvDataSource.isReusableRawCache( ...
                cachePath, sourcePath, adapter));

            writeText(metadataPath, originalMetadata);
            tc.verifyTrue(bms.data.JiulongjiangCsvDataSource.isReusableRawCache( ...
                cachePath, sourcePath, adapter));
            tc.verifyEqual(fileread(sourcePath), sourceText);
        end

        function matOnlyHalfPairIsRebuiltAndClosed(tc)
            [sourcePath, sourceText] = writeValidCsv(tc.TempDir, 'POINT-HALF-MAT');
            first = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);
            tc.assertEqual(first.Status, 'ok');
            cachePath = expectedCachePath(sourcePath);
            metadataPath = bms.data.CacheManager.metadataPath(cachePath);
            delete(metadataPath);

            second = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);

            tc.verifyEqual(second.Status, 'ok');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.rebuilt_count, 1);
            tc.verifyEqual(summary.reused_count, 0);
            tc.verifyTrue(isfile(cachePath));
            tc.verifyTrue(isfile(metadataPath));
            adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(tc.Config);
            tc.verifyTrue(bms.data.JiulongjiangCsvDataSource.isReusableRawCache( ...
                cachePath, sourcePath, adapter));
            tc.verifyEqual(fileread(sourcePath), sourceText);
        end

        function metadataOnlyHalfPairIsReportedAsRebuilt(tc)
            [sourcePath, sourceText] = writeValidCsv(tc.TempDir, 'POINT-HALF-META');
            first = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);
            tc.assertEqual(first.Status, 'ok');
            cachePath = expectedCachePath(sourcePath);
            metadataPath = bms.data.CacheManager.metadataPath(cachePath);
            delete(cachePath);

            second = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);

            tc.verifyEqual(second.Status, 'ok');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.rebuilt_count, 1);
            tc.verifyEqual(summary.created_count, 0);
            tc.verifyTrue(isfile(cachePath));
            tc.verifyTrue(isfile(metadataPath));
            tc.verifyEqual(fileread(sourcePath), sourceText);
        end

        function validPairCleansAbandonedTransactionArtifacts(tc)
            [sourcePath, sourceText] = writeValidCsv(tc.TempDir, 'POINT-ORPHAN');
            first = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);
            tc.assertEqual(first.Status, 'ok');
            cachePath = expectedCachePath(sourcePath);
            [cacheDir, base, ~] = fileparts(cachePath);
            orphan = fullfile(cacheDir, ['.' base '.cachetxn.abandoned']);
            mkdir(orphan);
            writeText(fullfile(orphan, 'new.mat.meta.json'), '{"incomplete":true}');
            writeText(fullfile(orphan, 'backup.mat'), 'not-a-mat-file');

            second = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);

            tc.verifyEqual(second.Status, 'ok');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.reused_count, 1);
            tc.verifyFalse(isfolder(orphan));
            tc.verifyEqual(fileread(sourcePath), sourceText);
        end

        function abruptExistingPairPublishRestoresBackupAndReuses(tc)
            [sourcePath, sourceText] = writeValidCsv(tc.TempDir, 'POINT-ABRUPT-OLD');
            first = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);
            tc.assertEqual(first.Status, 'ok');
            cachePath = expectedCachePath(sourcePath);
            metadataPath = bms.data.CacheManager.metadataPath(cachePath);
            matBefore = readBinary(cachePath);
            metadataBefore = readBinary(metadataPath);

            tc.verifyError(@() bms.data.JiulongjiangCsvDataSource.buildCacheForFile( ...
                sourcePath, tc.Config, '', true, 'after_mat_publish_abrupt'), ...
                'BMS:JljCachePrebuild:InjectedAbruptCommitFailure');
            adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(tc.Config);
            tc.verifyFalse(bms.data.JiulongjiangCsvDataSource.isReusableRawCache( ...
                cachePath, sourcePath, adapter));
            [cacheDir, base, ~] = fileparts(cachePath);
            tc.verifyNotEmpty(dir(fullfile(cacheDir, ['.' base '.cachetxn.*'])));

            recovered = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);

            tc.verifyEqual(recovered.Status, 'ok');
            summary = jsondecode(fileread(recovered.StatsPath));
            tc.verifyEqual(summary.reused_count, 1);
            tc.verifyEqual(summary.rebuilt_count, 0);
            tc.verifyEqual(readBinary(cachePath), matBefore);
            tc.verifyEqual(readBinary(metadataPath), metadataBefore);
            tc.verifyTrue(bms.data.JiulongjiangCsvDataSource.isReusableRawCache( ...
                cachePath, sourcePath, adapter));
            tc.verifyEmpty(dir(fullfile(cacheDir, ['.' base '.cachetxn.*'])));
            tc.verifyFalse(isfile([cachePath '.build.lock']));
            tc.verifyEqual(fileread(sourcePath), sourceText);
        end

        function abruptFirstPublishIsRemovedAndRecreated(tc)
            [sourcePath, sourceText] = writeValidCsv(tc.TempDir, 'POINT-ABRUPT-NEW');
            cachePath = expectedCachePath(sourcePath);

            tc.verifyError(@() bms.data.JiulongjiangCsvDataSource.buildCacheForFile( ...
                sourcePath, tc.Config, '', false, 'after_mat_publish_abrupt'), ...
                'BMS:JljCachePrebuild:InjectedAbruptCommitFailure');
            tc.verifyTrue(isfile(cachePath));
            tc.verifyFalse(isfile(bms.data.CacheManager.metadataPath(cachePath)));

            recovered = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);

            tc.verifyEqual(recovered.Status, 'ok');
            summary = jsondecode(fileread(recovered.StatsPath));
            tc.verifyEqual(summary.created_count, 1);
            tc.verifyEqual(summary.failed_count, 0);
            adapter = bms.data.JiulongjiangCsvDataSource.adapterFromConfig(tc.Config);
            tc.verifyTrue(bms.data.JiulongjiangCsvDataSource.isReusableRawCache( ...
                cachePath, sourcePath, adapter));
            [cacheDir, base, ~] = fileparts(cachePath);
            tc.verifyEmpty(dir(fullfile(cacheDir, ['.' base '.cachetxn.*'])));
            tc.verifyEqual(fileread(sourcePath), sourceText);
        end

        function activeServiceLockRejectsConcurrentRun(tc)
            [sourcePath, sourceText] = writeValidCsv(tc.TempDir, 'POINT-LOCKED');
            lockPath = fullfile(tc.TempDir, '.bms_jlj_cache_prebuild.lock');
            lockCleanup = bms.data.JiulongjiangCsvDataSource.acquireBuildLock(lockPath); %#ok<NASGU>

            result = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);

            tc.verifyEqual(result.Status, 'fail');
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyEqual(summary.error_identifier, 'BMS:JljCachePrebuild:Locked');
            tc.verifyFalse(isfile(expectedCachePath(sourcePath)));
            tc.verifyEqual(fileread(sourcePath), sourceText);
        end

        function deadOwnerLockIsReclaimedImmediately(tc)
            [sourcePath, sourceText] = writeValidCsv(tc.TempDir, 'POINT-STALE-LOCK');
            lockPath = fullfile(tc.TempDir, '.bms_jlj_cache_prebuild.lock');
            owner = struct('token', 'dead-owner', ...
                'created_at', char(datetime('now', ...
                    'Format', 'yyyy-MM-dd HH:mm:ss')), ...
                'host', bms.data.JiulongjiangCsvDataSource.localHostName(), ...
                'pid', double(intmax('int32')));
            bms.core.Logger.writeJson(lockPath, owner);

            result = bms.data.JljCachePrebuildService.run( ...
                tc.TempDir, '2026-05-01', '2026-05-01', tc.Config);

            tc.verifyEqual(result.Status, 'ok');
            tc.verifyFalse(isfile(lockPath));
            tc.verifyTrue(isfile(expectedCachePath(sourcePath)));
            tc.verifyEqual(fileread(sourcePath), sourceText);
        end

        function activePerFileLockRejectsDirectWriter(tc)
            [sourcePath, sourceText] = writeValidCsv(tc.TempDir, 'POINT-FILE-LOCK');
            cachePath = expectedCachePath(sourcePath);
            cacheDir = fileparts(cachePath);
            if ~isfolder(cacheDir), mkdir(cacheDir); end
            lockPath = [cachePath '.build.lock'];
            lockCleanup = bms.data.JiulongjiangCsvDataSource.acquireBuildLock(lockPath); %#ok<NASGU>

            tc.verifyError(@() bms.data.JiulongjiangCsvDataSource.buildCacheForFile( ...
                sourcePath, tc.Config, '', false), 'BMS:JljCachePrebuild:Locked');
            tc.verifyFalse(isfile(cachePath));
            tc.verifyEqual(fileread(sourcePath), sourceText);
        end

        function capacityBoundaryAllowsEqualityAndRejectsOneByteLess(tc)
            equalPlan = bms.data.JljCachePrebuildService.evaluateCapacity( ...
                1000, 1000, 400, 100, 0, 0.5, 1);
            blockedPlan = bms.data.JljCachePrebuildService.evaluateCapacity( ...
                999, 1000, 400, 100, 0, 0.5, 1);

            tc.verifyEqual(equalPlan.projected_write_bytes, 500);
            tc.verifyEqual(equalPlan.projected_free_bytes, 500);
            tc.verifyEqual(equalPlan.reserve_bytes, 500);
            tc.verifyTrue(equalPlan.allowed);
            tc.verifyEqual(blockedPlan.projected_free_bytes, 499);
            tc.verifyFalse(blockedPlan.allowed);
        end
    end
end

function cfg = minimalJljConfig()
cfg = struct();
cfg.vendor = 'jiulongjiang';
cfg.data_adapter = struct();
cfg.data_adapter.vendor = 'jiulongjiang';
cfg.data_adapter.cache = struct('enabled', true, 'dir', 'cache', 'validate', 'mtime_size');
cfg.cache_prebuild = struct( ...
    'manifest_dir', 'run_logs', ...
    'force_rebuild', false, ...
    'min_free_gib', 0, ...
    'min_free_fraction', 0, ...
    'estimated_cache_ratio', 1.25);
end

function [sourcePath, content] = writeValidCsv(root, pointId, dayText)
if nargin < 3, dayText = '2026-05-01'; end
csvDir = jljCsvDir(root, dayText);
if ~isfolder(csvDir), mkdir(csvDir); end
sourcePath = fullfile(csvDir, [pointId '.csv']);
content = sprintf([ ...
    'ts,value_x,value_y,value_z\n' ...
    '%s 00:00:00.000,1,11,21\n' ...
    '%s 00:00:01.000,2,12,22\n'], dayText, dayText);
writeText(sourcePath, content);
content = fileread(sourcePath);
end

function [sourcePath, content] = writeWimCsv(root, baseName, dayText)
if nargin < 3, dayText = '2026-05-01'; end
csvDir = jljCsvDir(root, dayText);
if ~isfolder(csvDir), mkdir(csvDir); end
sourcePath = fullfile(csvDir, [baseName '.csv']);
content = sprintf([ ...
    'ts,axles_number,total_weight,vehicle_speed\n' ...
    '%s 00:00:00.000,4,32000,68\n'], dayText);
writeText(sourcePath, content);
content = fileread(sourcePath);
end

function csvDir = jljCsvDir(root, dayText)
if nargin < 2, dayText = '2026-05-01'; end
csvDir = fullfile(root, ['data_jlj_' dayText], 'data', 'jlj', 'csv');
end

function cachePath = expectedCachePath(sourcePath)
[folder, base, ~] = fileparts(sourcePath);
cachePath = fullfile(folder, 'cache', [base '.mat']);
end

function writeText(path, content)
fid = fopen(path, 'wt', 'n', 'UTF-8');
if fid < 0
    error('test:writeFailed', 'Unable to write %s', path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, content, 'char');
end

function bytes = readBinary(path)
fid = fopen(path, 'rb');
if fid < 0
    error('test:readFailed', 'Unable to read %s', path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, Inf, '*uint8');
end

function cleanupCreatedPool(hadPool)
if hadPool, return; end
pool = gcp('nocreate');
if ~isempty(pool)
    delete(pool);
end
end
