classdef test_verified_source_csv_cleanup < matlab.unittest.TestCase
    properties
        TempRoot
        SourceRoot
        OutputRoot
        Config
        Day = '2026-06-01'
    end

    methods (TestMethodSetup)
        function setup(tc)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(projectRoot, fullfile(projectRoot, 'config'), ...
                fullfile(projectRoot, 'pipeline'), fullfile(projectRoot, 'analysis'));
            tc.TempRoot = tempname;
            tc.SourceRoot = fullfile(tc.TempRoot, 'source');
            tc.OutputRoot = fullfile(tc.TempRoot, 'output');
            mkdir(tc.SourceRoot);
            mkdir(tc.OutputRoot);
            tc.Config = localConfig(tc.SourceRoot, tc.OutputRoot);
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if isfolder(tc.TempRoot), rmdir(tc.TempRoot, 's'); end
        end
    end

    methods (Test)
        function defaultCacheBuildRetainsEverySource(tc)
            tc.createDailyZip({'POINT-01.csv', 'DTCZ-01.csv'}, ...
                {localSeries(tc.Day), localWim(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);

            result = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);

            tc.verifyEqual(result.Status, 'ok');
            tc.verifyTrue(isfile(tc.csvPath('POINT-01.csv')));
            tc.verifyTrue(isfile(tc.csvPath('DTCZ-01.csv')));
            tc.verifyFalse(isfile(tc.receiptPath()));
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyFalse(summary.source_cleanup_enabled);
            tc.verifyEqual(summary.created_count, 1);
            tc.verifyEqual(summary.skipped_count, 1);
        end

        function verifiedDayCommitDeletesOnlyEligibleCsvAndRerunsFromReceipt(tc)
            tc.createDailyZip({'POINT-02.csv', 'DTCZ-02.csv'}, ...
                {localSeries(tc.Day), localWim(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            taskOptions = localCleanupOptions();

            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);

            tc.verifyEqual(first.Status, 'ok');
            sourcePath = tc.csvPath('POINT-02.csv');
            cachePath = tc.cachePath('POINT-02');
            metadataPath = bms.data.CacheManager.metadataPath(cachePath);
            tc.verifyFalse(isfile(sourcePath));
            tc.verifyTrue(isfile(tc.csvPath('DTCZ-02.csv')));
            tc.verifyTrue(isfile(cachePath));
            tc.verifyTrue(isfile(metadataPath));
            tc.verifyTrue(isfile(fullfile(tc.SourceRoot, ...
                ['data_jlj_' tc.Day '.zip'])));
            receipt = jsondecode(fileread(tc.receiptPath()));
            tc.verifyEqual(receipt.status, 'committed');
            tc.verifyEqual(receipt.deleted_count, 1);
            tc.verifyTrue(receipt.archive_proof.source_archive_preserved);
            tc.verifyTrue(bms.data.ArchiveExtractService.verifyArchiveProof( ...
                receipt.archive_proof));
            tc.verifyTrue(bms.data.JiulongjiangCsvDataSource. ...
                validateStandaloneRawCache(cachePath, tc.Config));

            csvDir = fileparts(sourcePath);
            found = bms.data.JiulongjiangCsvDataSource.findFile( ...
                csvDir, 'POINT-02', 'generic', tc.Config);
            tc.verifyEqual(found, cachePath);
            [times, values] = bms.data.JiulongjiangCsvDataSource.readFile( ...
                found, 'generic', 'POINT-02', tc.Config);
            tc.verifyEqual(numel(times), 2);
            tc.verifyEqual(values(:), [1; 2]);

            beforeMat = dir(cachePath);
            beforeMeta = dir(metadataPath);
            second = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            tc.verifyEqual(second.Status, 'ok');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.created_count, 0);
            tc.verifyEqual(summary.rebuilt_count, 0);
            tc.verifyEqual(summary.reused_count, 1);
            afterMat = dir(cachePath);
            afterMeta = dir(metadataPath);
            tc.verifyEqual(afterMat.bytes, beforeMat.bytes);
            tc.verifyEqual(afterMat.datenum, beforeMat.datenum);
            tc.verifyEqual(afterMeta.bytes, beforeMeta.bytes);
            tc.verifyEqual(afterMeta.datenum, beforeMeta.datenum);
            tc.verifyFalse(isfile(sourcePath));
        end

        function cleanupRetainsUnconfiguredSameSchemaCsv(tc)
            tc.createDailyZip({'POINT-SAFE.csv', 'UNCONFIGURED.csv'}, ...
                {localSeries(tc.Day), localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);

            result = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, localCleanupOptions());

            tc.verifyEqual(result.Status, 'ok');
            tc.verifyFalse(isfile(tc.csvPath('POINT-SAFE.csv')));
            tc.verifyTrue(isfile(tc.cachePath('POINT-SAFE')));
            tc.verifyTrue(isfile(tc.csvPath('UNCONFIGURED.csv')));
            tc.verifyFalse(isfile(tc.cachePath('UNCONFIGURED')));
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyEqual(summary.eligible_count, 1);
            tc.verifyEqual(summary.skipped_count, 1);
            tc.verifyEqual(summary.skipped_files(1).reason, ...
                'unconfigured_timeseries_csv');
            receipt = jsondecode(fileread(tc.receiptPath()));
            tc.verifyEqual(receipt.deleted_count, 1);
            tc.verifyTrue(endsWith(lower(string(receipt.files(1).source_path)), ...
                lower('POINT-SAFE.csv')));
        end

        function cleanupUsesAxisCollapsedRuntimeSourceOnly(tc)
            cfg = tc.Config;
            cfg.points.earthquake = {'EQ-1-X', 'EQ-1-Y', 'EQ-1-Z'};
            tc.createDailyZip({'EQ-1.csv', 'EQ-1-X.csv'}, ...
                {localSeries(tc.Day), localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, cfg);

            result = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, cfg, localCleanupOptions());

            tc.verifyEqual(result.Status, 'ok');
            tc.verifyFalse(isfile(tc.csvPath('EQ-1.csv')));
            tc.verifyTrue(isfile(tc.cachePath('EQ-1')));
            tc.verifyTrue(isfile(tc.csvPath('EQ-1-X.csv')));
            tc.verifyFalse(isfile(tc.cachePath('EQ-1-X')));
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyEqual(summary.eligible_count, 1);
            tc.verifyEqual(summary.skipped_count, 1);
            tc.verifyEqual(summary.skipped_files(1).reason, ...
                'unconfigured_timeseries_csv');
        end

        function cleanupIncludesGroupOnlyConfiguredPoint(tc)
            cfg = tc.Config;
            cfg.groups = struct('strain', struct( ...
                'GROUP_A', {{'GROUP-ONLY'}}));
            tc.createDailyZip({'GROUP-ONLY.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, cfg);

            result = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, cfg, localCleanupOptions());

            tc.verifyEqual(result.Status, 'ok');
            tc.verifyFalse(isfile(tc.csvPath('GROUP-ONLY.csv')));
            tc.verifyTrue(isfile(tc.cachePath('GROUP-ONLY')));
            receipt = jsondecode(fileread(tc.receiptPath()));
            tc.verifyTrue(any(strcmp(receipt.cleanup_scope_ids, ...
                lower('GROUP-ONLY'))));
        end

        function cleanupIncludesEveryRuntimeWindSource(tc)
            cfg = tc.Config;
            cfg.points.wind = {'WIND-PAIR'};
            cfg.per_point.wind = struct('WIND_PAIR', struct( ...
                'speed_point_id', 'WIND-SPEED-FILE', ...
                'dir_point_id', 'WIND-DIRECTION-FILE'));
            tc.createDailyZip( ...
                {'WIND-SPEED-FILE.csv', 'WIND-DIRECTION-FILE.csv'}, ...
                {localSeries(tc.Day), localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, cfg);

            result = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, cfg, localCleanupOptions());

            tc.verifyEqual(result.Status, 'ok');
            tc.verifyFalse(isfile(tc.csvPath('WIND-SPEED-FILE.csv')));
            tc.verifyFalse(isfile(tc.csvPath('WIND-DIRECTION-FILE.csv')));
            tc.verifyTrue(isfile(tc.cachePath('WIND-SPEED-FILE')));
            tc.verifyTrue(isfile(tc.cachePath('WIND-DIRECTION-FILE')));
        end

        function committedContainsFallbackSourceRemainsReusable(tc)
            cfg = tc.Config;
            cfg.points.temperature{end+1} = 'POINT-FUZZY';
            sourceName = 'vendor-POINT-FUZZY-export.csv';
            tc.createDailyZip({sourceName}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, cfg);
            taskOptions = localCleanupOptions();

            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, cfg, taskOptions);
            tc.assertEqual(first.Status, 'ok');
            tc.verifyFalse(isfile(tc.csvPath(sourceName)));
            cachePath = tc.cachePath('vendor-POINT-FUZZY-export');
            tc.verifyTrue(isfile(cachePath));
            before = dir(cachePath);

            second = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, cfg, taskOptions);

            tc.verifyEqual(second.Status, 'ok');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.created_count, 0);
            tc.verifyEqual(summary.rebuilt_count, 0);
            tc.verifyEqual(summary.reused_count, 1);
            after = dir(cachePath);
            tc.verifyEqual(after.bytes, before.bytes);
            tc.verifyEqual(after.datenum, before.datenum);
        end

        function exactConfirmationIsRequiredBeforeAnyDeletion(tc)
            tc.createDailyZip({'POINT-03.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            sourcePath = tc.csvPath('POINT-03.csv');
            taskOptions = localCleanupOptions();
            taskOptions.cache_source_cleanup.confirmation = 'delete';

            result = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);

            tc.verifyEqual(result.Status, 'fail');
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyEqual(summary.error_identifier, ...
                'BMS:CacheSourceCleanup:ConfirmationRequired');
            tc.verifyTrue(isfile(sourcePath));
            tc.verifyFalse(isfile(tc.receiptPath()));
        end

        function nonBooleanEnabledValuesFailClosed(tc)
            tc.createDailyZip({'POINT-FLAG.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            invalid = {'0', 'false', 2, [true false]};
            for i = 1:numel(invalid)
                taskOptions = localCleanupOptions();
                taskOptions.cache_source_cleanup.enabled = invalid{i};
                result = bms.data.CachePrebuildService.run( ...
                    tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
                tc.verifyEqual(result.Status, 'fail');
                summary = jsondecode(fileread(result.StatsPath));
                tc.verifyEqual(summary.error_identifier, ...
                    'BMS:CacheSourceCleanup:InvalidEnabledFlag');
                tc.verifyTrue(isfile(tc.csvPath('POINT-FLAG.csv')));
                tc.verifyFalse(isfile(tc.receiptPath()));
            end
        end

        function confirmationTimestampIsRequired(tc)
            tc.createDailyZip({'POINT-TIME.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            taskOptions = localCleanupOptions();
            taskOptions.cache_source_cleanup.confirmed_at = '';

            result = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);

            tc.verifyEqual(result.Status, 'fail');
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyEqual(summary.error_identifier, ...
                'BMS:CacheSourceCleanup:ConfirmationTimeRequired');
            tc.verifyTrue(isfile(tc.csvPath('POINT-TIME.csv')));
        end

        function changedRecoveryZipBlocksCleanupAndRetainsCsv(tc)
            tc.createDailyZip({'POINT-04.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            zipPath = fullfile(tc.SourceRoot, ['data_jlj_' tc.Day '.zip']);
            fid = fopen(zipPath, 'ab');
            tc.assertGreaterThan(fid, 0);
            fwrite(fid, uint8(0), 'uint8');
            fclose(fid);

            result = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, localCleanupOptions());

            tc.verifyEqual(result.Status, 'fail');
            tc.verifyTrue(isfile(tc.csvPath('POINT-04.csv')));
            if isfile(tc.receiptPath())
                receipt = jsondecode(fileread(tc.receiptPath()));
                tc.verifyNotEqual(receipt.status, 'committed');
            end
        end

        function pairMismatchBlocksStandaloneUse(tc)
            tc.createDailyZip({'POINT-05.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            tc.assertEqual(first.Status, 'ok');
            cachePath = tc.cachePath('POINT-05');
            metadataPath = bms.data.CacheManager.metadataPath(cachePath);
            meta = jsondecode(fileread(metadataPath));
            meta.pair_id = 'wrong-pair';
            bms.core.Logger.writeJson(metadataPath, meta);

            tc.verifyFalse(bms.data.CacheManager.cachePairIntegrityMatches(cachePath));
            tc.verifyFalse(bms.data.JiulongjiangCsvDataSource. ...
                validateStandaloneRawCache(cachePath, tc.Config));
        end

        function tamperedReceiptCannotReachOutsidePartition(tc)
            tc.createDailyZip({'POINT-SAFE.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            taskOptions = localCleanupOptions();
            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            tc.assertEqual(first.Status, 'ok');
            outside = fullfile(tc.TempRoot, 'must_survive.csv');
            localWrite(outside, 'sentinel');
            receipt = jsondecode(fileread(tc.receiptPath()));
            receipt.files(1).source_path = outside;
            receipt.files(1).temporary_path = [outside '.bmsdelete.' receipt.receipt_id];
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            second = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);

            tc.verifyEqual(second.Status, 'fail');
            tc.verifyTrue(isfile(outside));
            tc.verifyEqual(fileread(outside), 'sentinel');
            tc.verifyTrue(isfile(tc.cachePath('POINT-SAFE')));
        end

        function truncatedReceiptCannotSilentlyDropArchivedCache(tc)
            tc.createDailyZip({'POINT-A.csv', 'POINT-B.csv'}, ...
                {localSeries(tc.Day), localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            taskOptions = localCleanupOptions();
            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            tc.assertEqual(first.Status, 'ok');
            receipt = jsondecode(fileread(tc.receiptPath()));
            receipt.files = receipt.files(1);
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            second = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);

            tc.verifyEqual(second.Status, 'fail');
            tc.verifyTrue(isfile(tc.cachePath('POINT-A')));
            tc.verifyTrue(isfile(tc.cachePath('POINT-B')));
        end

        function committedReceiptCannotBeOverwrittenByNewSameDayCsv(tc)
            tc.createDailyZip({'POINT-OLD.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            taskOptions = localCleanupOptions();
            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            tc.assertEqual(first.Status, 'ok');
            receiptBefore = fileread(tc.receiptPath());
            newSource = tc.csvPath('POINT-NEW.csv');
            localWrite(newSource, localSeries(tc.Day));

            second = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);

            tc.verifyEqual(second.Status, 'fail');
            tc.verifyTrue(isfile(newSource));
            tc.verifyEqual(fileread(tc.receiptPath()), receiptBefore);
            tc.verifyTrue(isfile(tc.cachePath('POINT-OLD')));
        end

        function missingExtractionManifestIsExplicitFailure(tc)
            tc.createDailyZip({'POINT-MANIFEST.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            taskOptions = localCleanupOptions();
            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            tc.assertEqual(first.Status, 'ok');
            delete(fullfile(tc.dayRoot(), '.bms_extract_manifest.json'));

            second = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);

            tc.verifyEqual(second.Status, 'fail');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.error_identifier, ...
                'BMS:CacheSourceCleanup:ExtractionManifestLost');
            tc.verifyTrue(isfile(tc.cachePath('POINT-MANIFEST')));
        end

        function standardLayoutCleanupFailsWithoutDeletingCsv(tc)
            standardRoot = fullfile(tc.TempRoot, 'standard');
            featureDir = fullfile(standardRoot, tc.Day, 'feature');
            mkdir(featureDir);
            source = fullfile(featureDir, 'TEMP01.csv');
            localWrite(source, sprintf([ ...
                'header\n%s 00:00:00.000,1\n%s 00:00:01.000,2\n'], ...
                tc.Day, tc.Day));
            cfg = struct('vendor', 'guanbing', ...
                'defaults', struct('header_marker', '[missing]'), ...
                'subfolders', struct('temperature', 'feature'), ...
                'points', struct('temperature', {{'T1'}}), ...
                'file_patterns', struct('temperature', ...
                    struct('default', '{file_id}.csv')), ...
                'per_point', struct('temperature', ...
                    struct('T1', struct('file_id', 'TEMP01'))), ...
                'time_series', struct('source_mode', 'auto', ...
                    'cache_version', 'csv_timeseries_v2', ...
                    'require_metadata', true), ...
                'cache_prebuild', struct('manifest_dir', 'run_logs', ...
                    'force_rebuild', false, 'min_free_gib', 0, ...
                    'min_free_fraction', 0, 'estimated_cache_ratio', 1.25, ...
                    'max_workers', 1));

            result = bms.data.CachePrebuildService.run( ...
                standardRoot, tc.Day, tc.Day, cfg, localCleanupOptions());

            tc.verifyEqual(result.Status, 'fail');
            tc.verifyTrue(isfile(source));
            tc.verifyFalse(isfile(fullfile(featureDir, 'cache', 'TEMP01.mat')));
        end

        function streamingSessionProcessesAndCleansOneNaturalDayAtATime(tc)
            day2 = '2026-06-02';
            tc.createDailyZip({'POINT-D1.csv'}, {localSeries(tc.Day)}, tc.Day);
            tc.createDailyZip({'POINT-D2.csv'}, {localSeries(day2)}, day2);
            taskOptions = localCleanupOptions();
            session = bms.data.DailyArchiveCacheCleanupSession( ...
                tc.OutputRoot, tc.Day, day2, tc.Config, taskOptions);

            unzipResult = session.runExtraction();
            cacheResult = session.cacheResult();

            tc.verifyEqual(unzipResult.Status, 'ok');
            tc.verifyEqual(cacheResult.Status, 'ok');
            tc.verifyEqual(unzipResult.StatsPath, cacheResult.StatsPath);
            tc.verifyFalse(isfile(tc.csvPathForDay(tc.Day, 'POINT-D1.csv')));
            tc.verifyFalse(isfile(tc.csvPathForDay(day2, 'POINT-D2.csv')));
            tc.verifyTrue(isfile(fullfile(tc.SourceRoot, ...
                ['data_jlj_' tc.Day '.zip'])));
            tc.verifyTrue(isfile(fullfile(tc.SourceRoot, ...
                ['data_jlj_' day2 '.zip'])));
            summary = jsondecode(fileread(session.SummaryPath));
            tc.verifyEqual(summary.status, 'ok');
            tc.verifyEqual(summary.completed_days, 2);
            tc.verifyEqual(numel(summary.days), 2);
            tc.verifyEqual([summary.days.deleted_count], [1 1]);
        end

        function preprocessFactoryUsesSharedDailyCleanupSession(tc)
            tc.createDailyZip({'POINT-PLAN.csv'}, {localSeries(tc.Day)});
            taskOptions = localCleanupOptions();
            taskOptions.doUnzip = true;
            taskOptions.doCachePrebuild = true;
            plan = bms.app.PreprocessStepFactory.append( ...
                bms.app.StepPlan(), tc.OutputRoot, tc.Day, tc.Day, ...
                taskOptions, tc.Config);

            definitions = plan.definitions();
            tc.verifyEqual({definitions.Key}, {'unzip', 'cache_prebuild'});
            results = plan.execute(@() false);

            tc.verifyEqual(numel(results), 2);
            tc.verifyEqual(results{1}.Status, 'ok');
            tc.verifyEqual(results{2}.Status, 'ok');
            tc.verifyEqual(results{1}.StatsPath, results{2}.StatsPath);
            tc.verifyFalse(isfile(tc.csvPath('POINT-PLAN.csv')));
            tc.verifyTrue(isfile(tc.cachePath('POINT-PLAN')));
            tc.verifyTrue(isfile(tc.receiptPath()));
        end

        function newStreamingSessionSkipsStrictlyVerifiedCommittedDay(tc)
            tc.createDailyZip({'POINT-RESUME.csv'}, {localSeries(tc.Day)});
            taskOptions = localCleanupOptions();
            first = bms.data.DailyArchiveCacheCleanupSession( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            firstResult = first.runExtraction();
            tc.assertEqual(firstResult.Status, 'ok');
            cachePath = tc.cachePath('POINT-RESUME');
            cacheBefore = dir(cachePath);

            resumed = bms.data.DailyArchiveCacheCleanupSession( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            resumedResult = resumed.runExtraction();

            tc.verifyEqual(resumedResult.Status, 'ok');
            tc.verifyFalse(isfile(tc.csvPath('POINT-RESUME.csv')));
            cacheAfter = dir(cachePath);
            tc.verifyEqual(cacheAfter.bytes, cacheBefore.bytes);
            tc.verifyEqual(cacheAfter.datenum, cacheBefore.datenum);
            summary = jsondecode(fileread(resumed.SummaryPath));
            tc.verifyEqual(summary.completed_days, 1);
            tc.verifyTrue(summary.days(1).skipped_committed_cleanup);
            tc.verifyEqual(summary.days(1).skip_reason, ...
                'verified_committed_receipt');
            tc.verifyEqual(summary.days(1).cache_status, ...
                'reused_committed_cleanup');
            tc.verifyEqual(summary.days(1).reused_count, 1);
            tc.verifyEqual(summary.days(1).archive_count, 0);
        end

        function newStreamingSessionReconcilesPartialReceiptBeforeExtraction(tc)
            tc.createDailyZip({'POINT-CRASH-A.csv', 'POINT-CRASH-B.csv'}, ...
                {localSeries(tc.Day), localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            backup = fullfile(tc.TempRoot, 'POINT-CRASH-B.backup.csv');
            copyfile(tc.csvPath('POINT-CRASH-B.csv'), backup);
            taskOptions = localCleanupOptions();
            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            tc.assertEqual(first.Status, 'ok');
            receipt = jsondecode(fileread(tc.receiptPath()));
            names = cellstr(string({receipt.files.source_path}));
            index = find(endsWith(lower(string(names)), ...
                lower('POINT-CRASH-B.csv')), 1);
            staged = char(receipt.files(index).temporary_path);
            copyfile(backup, staged);
            localSetModified(staged, char(receipt.files(index).source_modified_at));
            receipt.status = 'partial';
            receipt.committed_at = '';
            receipt.files(index).state = 'renamed';
            receipt.files(index).deleted_at = '';
            receipt.deleted_count = numel(receipt.files) - 1;
            receipt.deleted_bytes = sum(double([receipt.files.source_bytes])) ...
                - double(receipt.files(index).source_bytes);
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            resumed = bms.data.DailyArchiveCacheCleanupSession( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            result = resumed.runExtraction();

            tc.verifyEqual(result.Status, 'ok');
            tc.verifyFalse(isfile(staged));
            tc.verifyFalse(isfile(tc.csvPath('POINT-CRASH-A.csv')));
            tc.verifyFalse(isfile(tc.csvPath('POINT-CRASH-B.csv')));
            summary = jsondecode(fileread(resumed.SummaryPath));
            tc.verifyEqual(summary.days(1).extracted_count, 0);
            tc.verifyTrue(summary.days(1).skipped_committed_cleanup);
            finalReceipt = jsondecode(fileread(tc.receiptPath()));
            tc.verifyEqual(finalReceipt.status, 'committed');
            tc.verifyEqual(finalReceipt.deleted_count, 2);
        end

        function sameDirectoryTamperedTemporaryPathCannotDeleteVictim(tc)
            tc.createDailyZip({'POINT-TEMP.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            taskOptions = localCleanupOptions();
            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            tc.assertEqual(first.Status, 'ok');
            receipt = jsondecode(fileread(tc.receiptPath()));
            victim = fullfile(char(receipt.csv_dir), ...
                ['.unrelated.csv.bmsdelete.' char(receipt.receipt_id)]);
            localWrite(victim, 'must survive');
            receipt.files(1).temporary_path = victim;
            receipt.status = 'deleting';
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            second = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);

            tc.verifyEqual(second.Status, 'fail');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.error_identifier, ...
                'BMS:CacheSourceCleanup:UnsafeReceiptPath');
            tc.verifyTrue(isfile(victim));
            tc.verifyEqual(fileread(victim), 'must survive');
        end

        function changedExactStagingFileFailsClosed(tc)
            tc.createDailyZip({'POINT-STAGE.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            taskOptions = localCleanupOptions();
            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            tc.assertEqual(first.Status, 'ok');
            receipt = jsondecode(fileread(tc.receiptPath()));
            staged = char(receipt.files(1).temporary_path);
            localWrite(staged, 'unrelated replacement');
            receipt.status = 'partial';
            receipt.files(1).state = 'renamed';
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            second = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);

            tc.verifyEqual(second.Status, 'fail');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.error_identifier, ...
                'BMS:CacheSourceCleanup:StagedSourceChanged');
            tc.verifyTrue(isfile(staged));
            tc.verifyEqual(fileread(staged), 'unrelated replacement');
        end

        function sameSizeSameMtimeStagedTamperFailsCrcGate(tc)
            original = localSeries(tc.Day);
            alternate = strrep(original, ',1,11,21', ',9,11,21');
            tc.assertEqual(strlength(string(alternate)), strlength(string(original)));
            tc.createDailyZip({'POINT-TIME.csv'}, {original});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            taskOptions = localCleanupOptions();
            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            tc.assertEqual(first.Status, 'ok');
            receipt = jsondecode(fileread(tc.receiptPath()));
            staged = char(receipt.files(1).temporary_path);
            localWrite(staged, alternate);
            localSetModified(staged, char(receipt.files(1).source_modified_at));
            stagedInfo = dir(staged);
            tc.assertEqual(double(stagedInfo.bytes), ...
                double(receipt.files(1).source_bytes));
            receipt.status = 'partial';
            receipt.committed_at = '';
            receipt.deleted_count = 0;
            receipt.deleted_bytes = 0;
            receipt.files(1).state = 'renamed';
            receipt.files(1).deleted_at = '';
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            second = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);

            tc.verifyEqual(second.Status, 'fail');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.error_identifier, ...
                'BMS:CacheSourceCleanup:StagedSourceContentChanged');
            tc.verifyTrue(isfile(staged));
            actual = strrep(fileread(staged), sprintf('\r\n'), sprintf('\n'));
            expected = strrep(alternate, sprintf('\r\n'), sprintf('\n'));
            tc.verifyEqual(actual, expected);
        end

        function pendingReceiptRejectsChangedConfiguredCleanupScope(tc)
            source = tc.csvPath('POINT-POLICY.csv');
            backup = fullfile(tc.TempRoot, 'POINT-POLICY.scope.backup.csv');
            tc.createDailyZip({'POINT-POLICY.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            copyfile(source, backup);
            taskOptions = localCleanupOptions();
            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            tc.assertEqual(first.Status, 'ok');
            receipt = jsondecode(fileread(tc.receiptPath()));
            staged = char(receipt.files(1).temporary_path);
            copyfile(backup, staged);
            localSetModified(staged, char(receipt.files(1).source_modified_at));
            receipt.status = 'partial';
            receipt.committed_at = '';
            receipt.deleted_count = 0;
            receipt.deleted_bytes = 0;
            receipt.files(1).state = 'renamed';
            receipt.files(1).deleted_at = '';
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);
            changed = tc.Config;
            changed.points.temperature = setdiff( ...
                changed.points.temperature, {'POINT-POLICY'}, 'stable');

            second = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, changed, taskOptions);

            tc.verifyEqual(second.Status, 'fail');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.error_identifier, ...
                'BMS:CacheSourceCleanup:ReceiptBindingMismatch');
            tc.verifyTrue(isfile(staged));
            tc.verifyFalse(isfile(source));
        end

        function partialDeleteReceiptResumesIdempotently(tc)
            tc.createDailyZip({'POINT-PART-A.csv', 'POINT-PART-B.csv'}, ...
                {localSeries(tc.Day), localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            backup = fullfile(tc.TempRoot, 'POINT-PART-B.backup.csv');
            copyfile(tc.csvPath('POINT-PART-B.csv'), backup);
            taskOptions = localCleanupOptions();
            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            tc.assertEqual(first.Status, 'ok');
            receipt = jsondecode(fileread(tc.receiptPath()));
            names = cellstr(string({receipt.files.source_path}));
            index = find(endsWith(lower(string(names)), ...
                lower('POINT-PART-B.csv')), 1);
            tc.assertNotEmpty(index);
            staged = char(receipt.files(index).temporary_path);
            copyfile(backup, staged);
            localSetModified(staged, char(receipt.files(index).source_modified_at));
            receipt.status = 'partial';
            receipt.files(index).state = 'renamed';
            receipt.files(index).deleted_at = '';
            receipt.deleted_count = numel(receipt.files) - 1;
            receipt.deleted_bytes = sum(double([receipt.files.source_bytes])) ...
                - double(receipt.files(index).source_bytes);
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            second = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);

            tc.verifyEqual(second.Status, 'ok');
            tc.verifyFalse(isfile(staged));
            resumed = jsondecode(fileread(tc.receiptPath()));
            tc.verifyEqual(resumed.status, 'committed');
            tc.verifyEqual(resumed.deleted_count, 2);
            tc.verifyTrue(all(ismember({resumed.files.state}, ...
                {'deleted', 'deleted_reconciled'})));
        end

        function tamperedCacheSourceIdentityFailsClosed(tc)
            tc.createDailyZip({'POINT-IDENTITY.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            taskOptions = localCleanupOptions();
            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            tc.assertEqual(first.Status, 'ok');
            metadataPath = bms.data.CacheManager.metadataPath( ...
                tc.cachePath('POINT-IDENTITY'));
            metadata = jsondecode(fileread(metadataPath));
            metadata.source_records(1).path = fullfile(tc.TempRoot, 'other.csv');
            bms.core.Logger.writeJson(metadataPath, metadata);

            second = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);

            tc.verifyEqual(second.Status, 'fail');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.error_identifier, ...
                'BMS:CacheSourceCleanup:CacheSourceIdentityMismatch');
            tc.verifyFalse(isfile(tc.csvPath('POINT-IDENTITY.csv')));
        end

        function tamperedCachePathInsidePartitionFailsClosed(tc)
            tc.createDailyZip({'POINT-PATH.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            taskOptions = localCleanupOptions();
            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            tc.assertEqual(first.Status, 'ok');
            receipt = jsondecode(fileread(tc.receiptPath()));
            alternateDir = fullfile(tc.dayRoot(), 'alternate_cache');
            mkdir(alternateDir);
            alternateMat = fullfile(alternateDir, 'POINT-PATH.mat');
            alternateMeta = bms.data.CacheManager.metadataPath(alternateMat);
            copyfile(tc.cachePath('POINT-PATH'), alternateMat);
            copyfile(bms.data.CacheManager.metadataPath( ...
                tc.cachePath('POINT-PATH')), alternateMeta);
            receipt.files(1).cache_path = alternateMat;
            receipt.files(1).metadata_path = alternateMeta;
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            second = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);

            tc.verifyEqual(second.Status, 'fail');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.error_identifier, ...
                'BMS:CacheSourceCleanup:UnexpectedCachePath');
            tc.verifyTrue(isfile(alternateMat));
        end

        function tamperedCommittedReceiptCountersFailClosed(tc)
            tc.createDailyZip({'POINT-COUNT.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            taskOptions = localCleanupOptions();
            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            tc.assertEqual(first.Status, 'ok');
            receipt = jsondecode(fileread(tc.receiptPath()));
            receipt.deleted_count = 0;
            receipt.files(1).state = 'pending';
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            second = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);

            tc.verifyEqual(second.Status, 'fail');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.error_identifier, ...
                'BMS:CacheSourceCleanup:CommittedReceiptInvalid');
        end

        function tamperedReceiptPolicyFailsClosed(tc)
            tc.createDailyZip({'POINT-POLICY.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            taskOptions = localCleanupOptions();
            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            tc.assertEqual(first.Status, 'ok');
            receipt = jsondecode(fileread(tc.receiptPath()));
            receipt.confirmation = 'DELETE_ANYTHING';
            receipt.commit_scope = 'file';
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            second = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);

            tc.verifyEqual(second.Status, 'fail');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.error_identifier, ...
                'BMS:CacheSourceCleanup:ReceiptBindingMismatch');
        end

        function tamperedReceiptCacheBytesFailClosed(tc)
            tc.createDailyZip({'POINT-BYTES.csv'}, {localSeries(tc.Day)});
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            taskOptions = localCleanupOptions();
            first = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);
            tc.assertEqual(first.Status, 'ok');
            receipt = jsondecode(fileread(tc.receiptPath()));
            receipt.files(1).cache_bytes = receipt.files(1).cache_bytes + 1;
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            second = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, taskOptions);

            tc.verifyEqual(second.Status, 'fail');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.error_identifier, ...
                'BMS:CacheSourceCleanup:CachePairChanged');
        end
    end

    methods (Access = private)
        function createDailyZip(tc, names, contents, dayText)
            if nargin < 4, dayText = tc.Day; end
            stage = fullfile(tc.TempRoot, ['stage_' strrep(dayText, '-', '')]);
            payloadRoot = fullfile(stage, 'data', 'jlj', 'csv');
            mkdir(payloadRoot);
            for i = 1:numel(names)
                localWrite(fullfile(payloadRoot, names{i}), contents{i});
            end
            zip(fullfile(tc.SourceRoot, ['data_jlj_' dayText '.zip']), ...
                'data', stage);
            rmdir(stage, 's');
        end

        function path = dayRoot(tc)
            path = fullfile(tc.OutputRoot, ['data_jlj_' tc.Day]);
        end

        function path = csvPath(tc, name)
            path = tc.csvPathForDay(tc.Day, name);
        end

        function path = csvPathForDay(tc, dayText, name)
            path = fullfile(tc.OutputRoot, ['data_jlj_' dayText], ...
                'data', 'jlj', 'csv', name);
        end

        function path = cachePath(tc, base)
            path = fullfile(tc.dayRoot(), 'data', 'jlj', 'csv', ...
                'cache', [base '.mat']);
        end

        function path = receiptPath(tc)
            path = fullfile(tc.dayRoot(), ...
                '.bms_cache_source_cleanup_receipt.json');
        end
    end
end

function cfg = localConfig(sourceRoot, outputRoot)
cfg = struct();
cfg.vendor = 'jiulongjiang';
cfg.points = struct('temperature', {{ ...
    'POINT-01','POINT-02','POINT-03','POINT-04','POINT-05', ...
    'POINT-A','POINT-B','POINT-BYTES','POINT-COUNT', ...
    'POINT-CRASH-A','POINT-CRASH-B','POINT-D1','POINT-D2', ...
    'POINT-FLAG','POINT-IDENTITY','POINT-MANIFEST','POINT-NEW', ...
    'POINT-OLD','POINT-PART-A','POINT-PART-B','POINT-PATH', ...
    'POINT-PLAN','POINT-POLICY','POINT-RESUME','POINT-SAFE', ...
    'POINT-STAGE','POINT-TEMP','POINT-TIME'}});
cfg.data_adapter = struct('vendor', 'jiulongjiang', ...
    'cache', struct('enabled', true, 'dir', 'cache', ...
    'validate', 'mtime_size'));
cfg.preprocessing = struct('unzip', struct( ...
    'source_root', sourceRoot, 'output_root', outputRoot, ...
    'max_workers', 1, 'min_free_gib', 0, 'min_free_fraction', 0, ...
    'delete_archives_after_verify', false, 'overwrite_existing', false, ...
    'summary_file', fullfile('run_logs', 'archive_extract_summary.json')));
cfg.cache_prebuild = struct('manifest_dir', 'run_logs', ...
    'force_rebuild', false, 'max_workers', 1, ...
    'min_free_gib', 0, 'min_free_fraction', 0, ...
    'estimated_cache_ratio', 1.25);
end

function opts = localCleanupOptions()
opts = struct('cache_source_cleanup', struct( ...
    'enabled', true, ...
    'mode', 'verified_extracted_csv', ...
    'commit_scope', 'day', ...
    'recovery_policy', 'verified_archive', ...
    'confirmation', 'DELETE_VERIFIED_EXTRACTED_CSV', ...
    'confirmed_at', '2026-07-16 00:00:00'));
end

function text = localSeries(day)
text = sprintf([ ...
    'ts,value_x,value_y,value_z\n' ...
    '%s 00:00:00.000,1,11,21\n' ...
    '%s 00:00:01.000,2,12,22\n'], day, day);
end

function text = localWim(day)
text = sprintf([ ...
    'ts,axles_number,total_weight,vehicle_speed\n' ...
    '%s 00:00:00.000,4,32000,68\n'], day);
end

function localWrite(path, text)
parent = fileparts(path);
if ~isfolder(parent), mkdir(parent); end
fid = fopen(path, 'wt', 'n', 'UTF-8');
if fid < 0, error('test:writeFailed', 'Unable to write %s', path); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, text, 'char');
end

function localSetModified(path, timestamp)
value = datetime(timestamp, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', ...
    'TimeZone', 'local');
ok = java.io.File(path).setLastModified(int64(round(posixtime(value) * 1000)));
if ~ok
    error('test:setModifiedFailed', 'Unable to set modified time for %s', path);
end
end
