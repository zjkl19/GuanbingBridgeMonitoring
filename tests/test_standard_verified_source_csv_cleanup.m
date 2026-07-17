classdef test_standard_verified_source_csv_cleanup < matlab.unittest.TestCase
    properties
        TempRoot
        Day = '2026-05-01'
    end

    methods (TestMethodSetup)
        function setup(tc)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(projectRoot, fullfile(projectRoot, 'config'), ...
                fullfile(projectRoot, 'pipeline'), fullfile(projectRoot, 'analysis'));
            tc.TempRoot = tempname;
            mkdir(tc.TempRoot);
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if isfolder(tc.TempRoot), rmdir(tc.TempRoot, 's'); end
        end
    end

    methods (Test)
        function providerResolvesAllCurrentBridgeLayoutsOnNeutralRoot(tc)
            fixtures = { ...
                struct('vendor','donghua'), 'dated_folders'; ...
                struct('vendor','hongtang'), 'hongtang_period'; ...
                struct('vendor','jiulongjiang'), 'jlj_daily_export'; ...
                struct('vendor','shuixianhua'), 'jlj_daily_export'; ...
                struct('vendor','chongyangxi','data_layout','dated_folders'), 'dated_folders'; ...
                struct('vendor','zhishan','data_layout','dated_folders'), 'dated_folders'};
            for i = 1:size(fixtures, 1)
                provider = bms.data.CacheSourceCleanupProvider.resolve( ...
                    tc.TempRoot, fixtures{i, 1});
                tc.verifyEqual(provider.layout, fixtures{i, 2});
            end
        end

        function datedFolderSingleZipDeletesConfiguredCsvOnly(tc)
            cfg = localTemperatureConfig('guanbing');
            folder = tc.waveFolder('feature');
            zipPath = fullfile(folder, 'temperature.zip');
            configured = localSeries(tc.Day, [11 12]);
            tc.createZip(zipPath, {'TEMP01.csv','UNCONFIGURED.csv'}, ...
                {configured, localSeries(tc.Day, [91 92])});
            localWrite(fullfile(folder, 'keep.xlsx'), 'workbook');
            localWrite(fullfile(folder, 'DTCZ-01.csv'), 'wim-like,not-configured');
            tc.extract(cfg);
            source = fullfile(folder, 'TEMP01.csv');
            unconfigured = fullfile(folder, 'UNCONFIGURED.csv');

            result = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());

            tc.verifyEqual(result.Status, 'ok');
            tc.verifyFalse(isfile(source));
            tc.verifyTrue(isfile(unconfigured));
            tc.verifyTrue(isfile(fullfile(folder, 'keep.xlsx')));
            tc.verifyTrue(isfile(fullfile(folder, 'DTCZ-01.csv')));
            tc.verifyTrue(isfile(zipPath));
            cachePath = localCachePath(source);
            tc.verifyTrue(isfile(cachePath));
            [times, values, loaded] = bms.data.TimeSeriesLoader.readMatSeries( ...
                cachePath, struct('cache_version', 'csv_timeseries_v2', ...
                'require_metadata', true));
            tc.verifyTrue(loaded.read_ok);
            tc.verifyEqual(numel(times), 2);
            tc.verifyEqual(values(:), [11;12]);
            receipt = jsondecode(fileread(tc.receiptPath()));
            tc.verifyEqual(receipt.status, 'committed');
            tc.verifyEqual(receipt.deleted_count, 1);
            tc.verifyEqual(receipt.provider_id, 'standard_timeseries_v1');
            tc.verifyEqual(receipt.layout, 'dated_folders');
            authorization = localVerifyCleanupAuthorization(tc, receipt, 1);
            authorizationText = fileread(receipt.authorization_path);
            authorizationInfo = dir(receipt.authorization_path);
            tc.verifyEqual(receipt.files(1).pair_id, ...
                jsondecode(fileread(bms.data.CacheManager.metadataPath(cachePath))).pair_id);

            beforeMat = dir(cachePath);
            beforeMeta = dir(bms.data.CacheManager.metadataPath(cachePath));
            second = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());
            tc.verifyEqual(second.Status, 'ok');
            afterMat = dir(cachePath);
            afterMeta = dir(bms.data.CacheManager.metadataPath(cachePath));
            tc.verifyEqual(afterMat.bytes, beforeMat.bytes);
            tc.verifyEqual(afterMat.datenum, beforeMat.datenum);
            tc.verifyEqual(afterMeta.bytes, beforeMeta.bytes);
            tc.verifyEqual(afterMeta.datenum, beforeMeta.datenum);
            receiptAfterRerun = jsondecode(fileread(tc.receiptPath()));
            localVerifyCleanupAuthorization(tc, receiptAfterRerun, 1);
            authorizationInfoAfter = dir(receipt.authorization_path);
            tc.verifyEqual(fileread(receipt.authorization_path), ...
                authorizationText);
            tc.verifyEqual(authorizationInfoAfter.bytes, ...
                authorizationInfo.bytes);
            tc.verifyEqual(authorizationInfoAfter.datenum, ...
                authorizationInfo.datenum);
            tc.verifyEqual(authorization.authorization_hash, ...
                receiptAfterRerun.authorization_hash);
        end

        function receiptPublishingUsesChunkCheckpoints(tc)
            fileCount = 65;
            ids = arrayfun(@(i) sprintf('T%03d', i), 1:fileCount, ...
                'UniformOutput', false);
            bases = arrayfun(@(i) sprintf('TEMP%03d', i), 1:fileCount, ...
                'UniformOutput', false);
            names = strcat(bases, '.csv');
            cfg = localBaseConfig('guanbing');
            cfg.subfolders.temperature = ...
                fullfile(char([27874 24418]), 'feature');
            cfg.points.temperature = ids;
            cfg.file_patterns.temperature.default = '{file_id}.csv';
            for i = 1:fileCount
                cfg.per_point.temperature.(ids{i}) = ...
                    struct('file_id', bases{i});
            end
            folder = tc.waveFolder('feature');
            tc.createZip(fullfile(folder, 'temperature.zip'), names, ...
                repmat({localSeries(tc.Day, [11 12])}, 1, fileCount));
            tc.extract(cfg);

            result = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());

            tc.verifyEqual(result.Status, 'ok', result.Message);
            receipt = jsondecode(fileread(tc.receiptPath()));
            interval = bms.data.VerifiedSourceCsvCleanupService. ...
                receiptCheckpointInterval();
            expectedPublishes = 4 + 2 * ceil(fileCount / interval);
            tc.verifyEqual(double(receipt.checkpoint_interval), interval);
            tc.verifyEqual(double(receipt.receipt_publish_count), ...
                expectedPublishes);
            tc.verifyEqual(receipt.commit_validation_mode, ...
                'batch_authorized_fastpath');
            tc.verifyLessThan(double(receipt.receipt_publish_count), fileCount);
            tc.verifyEqual(double(receipt.deleted_count), fileCount);
            localVerifyCleanupAuthorization(tc, receipt, fileCount);
        end

        function committedRerunRejectsSameSizeSameMtimeAuthorizationTamper(tc)
            cfg = localTemperatureConfig('guanbing');
            folder = tc.waveFolder('feature');
            tc.createZip(fullfile(folder, 'temperature.zip'), ...
                {'TEMP01.csv'}, {localSeries(tc.Day, [11 12])});
            tc.extract(cfg);
            first = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());
            tc.assertEqual(first.Status, 'ok', first.Message);
            receipt = jsondecode(fileread(tc.receiptPath()));
            authorization = localVerifyCleanupAuthorization(tc, receipt, 1);
            oldPairId = char(authorization.files(1).pair_id);
            newPairId = oldPairId;
            if oldPairId(1) == '0'
                newPairId(1) = '1';
            else
                newPairId(1) = '0';
            end
            localOverwriteTokenPreservingFingerprint(tc, ...
                receipt.authorization_path, oldPairId, newPairId);

            second = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());

            tc.verifyEqual(second.Status, 'fail');
            summary = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary.error_identifier, ...
                'BMS:CacheSourceCleanup:AuthorizationHashMismatch');
            source = fullfile(folder, 'TEMP01.csv');
            tc.verifyFalse(isfile(source));
            tc.verifyTrue(isfile(localCachePath(source)));
        end

        function extractorAndCleanupShareNaturalDayMutationLease(tc)
            cfg = localTemperatureConfig('guanbing');
            waveFolder = tc.waveFolder('feature');
            featureFolder = tc.featureFolder('unused');
            tc.createZip(fullfile(waveFolder, 'temperature.zip'), ...
                {'TEMP01.csv'}, {localSeries(tc.Day, [11 12])});
            tc.createZip(fullfile(featureFolder, 'feature.zip'), ...
                {'unused.txt'}, {'not configured'});
            cfg.preprocessing = struct('unzip', struct( ...
                'max_workers', 1, 'min_free_gib', 0, ...
                'min_free_fraction', 0, 'additional_required_bytes', 0, ...
                'reuse_validation', 'full_crc', ...
                'summary_file', fullfile('run_logs', 'extract.json')));
            lockPath = bms.data.DailyExportMutationLock.pathFor( ...
                tc.TempRoot, tc.Day);
            bms.data.DataLayoutResolver.ensureDir(fileparts(lockPath));
            [foreignExtract, ~] = bms.core.DirectoryLeaseLock.acquire( ...
                lockPath, struct(), struct('purpose', 'test_foreign_extract'));

            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg), ...
                'BMS:DirectoryLeaseLock:Locked');
            source = fullfile(waveFolder, 'TEMP01.csv');
            tc.verifyFalse(isfile(source));
            delete(foreignExtract);

            extracted = bms.data.ArchiveExtractService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg);
            tc.assertEqual(extracted.status, 'ok');
            tc.assertTrue(isfile(source));
            [foreignCleanup, ~] = bms.core.DirectoryLeaseLock.acquire( ...
                lockPath, struct(), struct('purpose', 'test_foreign_cleanup'));

            blocked = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());
            tc.verifyEqual(blocked.Status, 'fail');
            blockedSummary = jsondecode(fileread(blocked.StatsPath));
            tc.verifyEqual(blockedSummary.error_identifier, ...
                'BMS:DirectoryLeaseLock:Locked');
            tc.verifyTrue(isfile(source));
            tc.verifyFalse(isfile(tc.receiptPath()));
            delete(foreignCleanup);

            accepted = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());
            tc.verifyEqual(accepted.Status, 'ok', accepted.Message);
            tc.verifyFalse(isfile(source));
            receipt = jsondecode(fileread(tc.receiptPath()));
            tc.verifyEqual(receipt.cleanup_lock_path, lockPath);
        end

        function hongtangMultipleZipsMapEachCsvUniquely(tc)
            mkdir(fullfile(tc.TempRoot, 'lowfreq'));
            cfg = localHongtangMultiModuleConfig();
            waveFolder = tc.waveFolder('wave');
            featureFolder = tc.featureFolder('feature');
            accelerationZip = fullfile(waveFolder, 'acceleration.zip');
            extraWaveZip = fullfile(waveFolder, 'acceleration-extra.zip');
            temperatureZip = fullfile(featureFolder, 'temperature.zip');
            tc.createZip(accelerationZip, {'ACC01.csv'}, ...
                {localSeries(tc.Day, [3 4])});
            tc.createZip(extraWaveZip, {'WAVE-NOISE.csv'}, ...
                {localSeries(tc.Day, [31 32])});
            tc.createZip(temperatureZip, {'TEMP01.csv','NOISE.csv'}, ...
                {localSeries(tc.Day, [21 22]), localSeries(tc.Day, [7 8])});
            tc.extract(cfg);
            acceleration = fullfile(waveFolder, 'ACC01.csv');
            temperature = fullfile(featureFolder, 'TEMP01.csv');

            result = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());

            tc.verifyEqual(result.Status, 'ok');
            tc.verifyFalse(isfile(acceleration));
            tc.verifyFalse(isfile(temperature));
            tc.verifyTrue(isfile(fullfile(featureFolder, 'NOISE.csv')));
            tc.verifyTrue(isfile(fullfile(waveFolder, 'WAVE-NOISE.csv')));
            tc.verifyTrue(isfile(accelerationZip));
            tc.verifyTrue(isfile(extraWaveZip));
            tc.verifyTrue(isfile(temperatureZip));
            receipt = jsondecode(fileread(tc.receiptPath()));
            tc.verifyEqual(receipt.layout, 'hongtang_period');
            tc.verifyEqual(receipt.deleted_count, 2);
            tc.verifyEqual(numel(receipt.archive_proofs), 2);
        end

        function duplicateArchiveOwnershipFailsWithZeroDeletion(tc)
            folder = tc.waveFolder('feature');
            source = fullfile(folder, 'TEMP01.csv');
            localWrite(source, localSeries(tc.Day, [1 2]));
            info = dir(source);
            entry = struct('path', 'TEMP01.csv', ...
                'bytes', double(info.bytes), 'crc32', localCrc32(source));
            targets = repmat(struct('zip', '', 'out_dir', folder), 1, 2);
            targets(1).zip = fullfile(folder, 'a.zip');
            targets(2).zip = fullfile(folder, 'b.zip');
            indexes = {struct('entries', entry), struct('entries', entry)};

            tc.verifyError(@() bms.data.ArchiveExtractService. ...
                matchUniqueRecoverySource(source, targets, indexes, [true true]), ...
                'BMS:ArchiveExtract:RecoveryArchiveAmbiguous');
            tc.verifyTrue(isfile(source));

            indexes{2}.entries.path = 'different.csv';
            [selected, row] = bms.data.ArchiveExtractService. ...
                matchUniqueRecoverySource(source, targets, indexes, [true true]);
            tc.verifyEqual(selected, 1);
            tc.verifyEqual(row.relative_path, 'TEMP01.csv');
            tc.verifyEqual(row.bytes, double(info.bytes));
            tc.verifyEqual(row.crc32, localCrc32(source));
        end

        function oneUnprovenConfiguredCsvRetainsWholeDay(tc)
            cfg = localTemperatureConfig('guanbing');
            cfg.points.temperature = {'T1','T2'};
            cfg.per_point.temperature.T2 = struct('file_id', 'TEMP02');
            folder = tc.waveFolder('feature');
            tc.createZip(fullfile(folder, 'temperature.zip'), ...
                {'TEMP01.csv'}, {localSeries(tc.Day, [1 2])});
            tc.extract(cfg);
            first = fullfile(folder, 'TEMP01.csv');
            second = fullfile(folder, 'TEMP02.csv');
            localWrite(second, localSeries(tc.Day, [3 4]));

            result = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());

            tc.verifyEqual(result.Status, 'fail');
            tc.verifyTrue(isfile(first));
            tc.verifyTrue(isfile(second));
            tc.verifyTrue(isfile(localCachePath(first)));
            tc.verifyTrue(isfile(localCachePath(second)));
            tc.verifyFalse(isfile(tc.receiptPath()));
        end

        function changedSourceAndBrokenCachePairBothFailClosed(tc)
            cfg = localTemperatureConfig('guanbing');
            folder = tc.waveFolder('feature');
            tc.createZip(fullfile(folder, 'temperature.zip'), ...
                {'TEMP01.csv'}, {localSeries(tc.Day, [1 2])});
            tc.extract(cfg);
            source = fullfile(folder, 'TEMP01.csv');
            build = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg);
            tc.assertEqual(build.Status, 'ok');
            records = jsondecode(fileread(build.StatsPath)).files;
            sourceInfo = dir(source);
            localWrite(source, localSeries(tc.Day, [9 8]));
            localSetModified(source, sourceInfo.datenum);

            tc.verifyError(@() ...
                bms.data.StandardVerifiedSourceCsvCleanupService.commitDay( ...
                    tc.TempRoot, tc.Day, records, cfg, localCleanupOptions()), ...
                'BMS:CacheSourceCleanup:CacheValidationFailed');
            tc.verifyTrue(isfile(source));
            tc.verifyFalse(isfile(tc.receiptPath()));

            % Restore exactly from the archive, rebuild, then corrupt only the
            % metadata pair identity. This must also fail before any rename.
            delete(source);
            tc.extract(cfg);
            build = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg);
            tc.assertEqual(build.Status, 'ok');
            records = jsondecode(fileread(build.StatsPath)).files;
            metaPath = bms.data.CacheManager.metadataPath(records.cache_path);
            meta = jsondecode(fileread(metaPath));
            meta.pair_id = 'tampered-pair';
            bms.core.Logger.writeJson(metaPath, meta);
            tc.verifyError(@() ...
                bms.data.StandardVerifiedSourceCsvCleanupService.commitDay( ...
                    tc.TempRoot, tc.Day, records, cfg, localCleanupOptions()), ...
                'BMS:CacheSourceCleanup:CacheValidationFailed');
            tc.verifyTrue(isfile(source));
        end

        function partialReceiptIsReconciledWithoutReextracting(tc)
            cfg = localTemperatureConfig('guanbing');
            folder = tc.waveFolder('feature');
            payload = localSeries(tc.Day, [1 2]);
            tc.createZip(fullfile(folder, 'temperature.zip'), ...
                {'TEMP01.csv'}, {payload});
            tc.extract(cfg);
            backup = fullfile(tc.TempRoot, 'source.backup');
            copyfile(fullfile(folder, 'TEMP01.csv'), backup);
            first = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());
            tc.assertEqual(first.Status, 'ok', first.Message);
            receipt = jsondecode(fileread(tc.receiptPath()));
            staged = char(receipt.files(1).temporary_path);
            copyfile(backup, staged);
            receipt.status = 'partial';
            receipt.committed_at = '';
            receipt.deleted_count = 0;
            receipt.deleted_bytes = 0;
            receipt.files(1).state = 'renamed';
            receipt.files(1).deleted_at = '';
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            session = bms.data.DailyArchiveCacheCleanupSession( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());
            result = session.runExtraction();

            tc.verifyEqual(result.Status, 'ok');
            tc.verifyFalse(isfile(staged));
            tc.verifyFalse(isfile(fullfile(folder, 'TEMP01.csv')));
            final = jsondecode(fileread(tc.receiptPath()));
            tc.verifyEqual(final.status, 'committed');
            tc.verifyEqual(final.commit_validation_mode, 'strict_recovery');
            tc.verifyEqual(final.deleted_count, 1);
            summary = jsondecode(fileread(session.SummaryPath));
            tc.verifyTrue(summary.days(1).skipped_committed_cleanup);
            tc.verifyEqual(summary.days(1).archive_count, 0);
        end

        function renameBeforeReceiptWriteIsReconciled(tc)
            cfg = localTemperatureConfig('guanbing');
            folder = tc.waveFolder('feature');
            payload = localSeries(tc.Day, [1 2]);
            tc.createZip(fullfile(folder, 'temperature.zip'), ...
                {'TEMP01.csv'}, {payload});
            tc.extract(cfg);
            source = fullfile(folder, 'TEMP01.csv');
            backup = fullfile(tc.TempRoot, 'source-before-rename.backup');
            copyfile(source, backup);
            first = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());
            tc.assertEqual(first.Status, 'ok', first.Message);
            receipt = jsondecode(fileread(tc.receiptPath()));
            staged = char(receipt.files(1).temporary_path);
            copyfile(backup, staged);
            receipt.status = 'renaming';
            receipt.committed_at = '';
            receipt.deleted_count = 0;
            receipt.deleted_bytes = 0;
            receipt.files(1).state = 'pending';
            receipt.files(1).deleted_at = '';
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            verification = bms.data.StandardVerifiedSourceCsvCleanupService. ...
                reconcilePendingDay(tc.TempRoot, tc.Day, cfg, ...
                    localCleanupOptions());

            tc.verifyTrue(verification.committed);
            tc.verifyFalse(isfile(source));
            tc.verifyFalse(isfile(staged));
            final = jsondecode(fileread(tc.receiptPath()));
            tc.verifyEqual(final.status, 'committed');
            tc.verifyEqual(final.deleted_count, 1);
        end

        function deleteBeforeReceiptWriteIsReconciled(tc)
            cfg = localTemperatureConfig('guanbing');
            folder = tc.waveFolder('feature');
            tc.createZip(fullfile(folder, 'temperature.zip'), ...
                {'TEMP01.csv'}, {localSeries(tc.Day, [1 2])});
            tc.extract(cfg);
            first = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());
            tc.assertEqual(first.Status, 'ok', first.Message);
            receipt = jsondecode(fileread(tc.receiptPath()));
            source = char(receipt.files(1).source_path);
            staged = char(receipt.files(1).temporary_path);
            tc.assertFalse(isfile(source));
            tc.assertFalse(isfile(staged));
            receipt.status = 'deleting';
            receipt.committed_at = '';
            receipt.deleted_count = 0;
            receipt.deleted_bytes = 0;
            receipt.files(1).state = 'renamed';
            receipt.files(1).deleted_at = '';
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            verification = bms.data.StandardVerifiedSourceCsvCleanupService. ...
                reconcilePendingDay(tc.TempRoot, tc.Day, cfg, ...
                    localCleanupOptions());

            tc.verifyTrue(verification.committed);
            tc.verifyFalse(isfile(source));
            tc.verifyFalse(isfile(staged));
            final = jsondecode(fileread(tc.receiptPath()));
            tc.verifyEqual(final.status, 'committed');
            tc.verifyEqual(final.commit_validation_mode, 'strict_recovery');
            tc.verifyEqual(double(final.deleted_count), 1);
        end

        function strictRecoveryRejectsSameSizeSameMtimeStagedTamper(tc)
            cfg = localTemperatureConfig('guanbing');
            folder = tc.waveFolder('feature');
            original = localSeries(tc.Day, [1 2]);
            tampered = localSeries(tc.Day, [9 2]);
            tc.assertEqual(strlength(string(tampered)), ...
                strlength(string(original)));
            tc.createZip(fullfile(folder, 'temperature.zip'), ...
                {'TEMP01.csv'}, {original});
            tc.extract(cfg);
            source = fullfile(folder, 'TEMP01.csv');
            backup = fullfile(tc.TempRoot, 'strict-gate.backup.csv');
            copyfile(source, backup);
            first = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());
            tc.assertEqual(first.Status, 'ok', first.Message);
            receipt = jsondecode(fileread(tc.receiptPath()));
            staged = char(receipt.files(1).temporary_path);
            copyfile(backup, staged);
            tc.assertTrue(java.io.File(staged).setLastModified( ...
                int64(receipt.files(1).source_modified_millis)));
            metadataPath = char(receipt.files(1).metadata_path);
            originalMetadata = fileread(metadataPath);
            pairId = char(receipt.files(1).pair_id);
            changedPairId = pairId;
            changedPairId(1) = char(double(changedPairId(1)) ...
                + 1 + (changedPairId(1) == 'z'));
            tamperedMetadata = strrep(originalMetadata, pairId, changedPairId);
            metadataInfo = dir(metadataPath);
            localWrite(metadataPath, tamperedMetadata);
            tc.assertTrue(java.io.File(metadataPath).setLastModified( ...
                int64(receipt.files(1).metadata_modified_millis)));
            tamperedMetadataInfo = dir(metadataPath);
            tc.assertEqual(double(tamperedMetadataInfo.bytes), ...
                double(metadataInfo.bytes));
            freshReceipt = receipt;
            freshReceipt.status = 'deleting';
            freshReceipt.files(1).state = 'renamed';
            tc.verifyError(@() ...
                bms.data.StandardVerifiedSourceCsvCleanupService. ...
                    validateFreshDeletionEntry( ...
                        freshReceipt, freshReceipt.files(1), cfg), ...
                'BMS:CacheSourceCleanup:ArchivedCacheInvalid');
            tc.verifyTrue(isfile(staged));
            localWrite(metadataPath, originalMetadata);
            tc.assertTrue(java.io.File(metadataPath).setLastModified( ...
                int64(receipt.files(1).metadata_modified_millis)));
            localWrite(staged, tampered);
            ok = java.io.File(staged).setLastModified( ...
                int64(receipt.files(1).source_modified_millis));
            tc.assertTrue(ok);
            stagedInfo = dir(staged);
            tc.assertEqual(double(stagedInfo.bytes), ...
                double(receipt.files(1).source_bytes));
            freshReceipt = receipt;
            freshReceipt.status = 'deleting';
            freshReceipt.files(1).state = 'renamed';
            tc.verifyError(@() ...
                bms.data.StandardVerifiedSourceCsvCleanupService. ...
                    validateFreshDeletionEntry( ...
                        freshReceipt, freshReceipt.files(1), cfg), ...
                'BMS:ArchiveExtract:RecoverySourceContentMismatch');
            receipt.status = 'partial';
            receipt.committed_at = '';
            receipt.deleted_count = 0;
            receipt.deleted_bytes = 0;
            receipt.files(1).state = 'renamed';
            receipt.files(1).deleted_at = '';
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            tc.verifyError(@() ...
                bms.data.StandardVerifiedSourceCsvCleanupService. ...
                    reconcilePendingDay(tc.TempRoot, tc.Day, cfg, ...
                        localCleanupOptions()), ...
                'BMS:ArchiveExtract:RecoverySourceContentMismatch');

            tc.verifyTrue(isfile(staged));
            failed = jsondecode(fileread(tc.receiptPath()));
            tc.verifyEqual(failed.commit_validation_mode, 'strict_recovery');
            tc.verifyEqual(failed.status, ...
                'rename_failed_rollback_incomplete');
        end

        function durableDeletedStateRejectsSourceAndStagingBothPresent(tc)
            cfg = localTemperatureConfig('guanbing');
            folder = tc.waveFolder('feature');
            payload = localSeries(tc.Day, [1 2]);
            tc.createZip(fullfile(folder, 'temperature.zip'), ...
                {'TEMP01.csv'}, {payload});
            tc.extract(cfg);
            source = fullfile(folder, 'TEMP01.csv');
            backup = fullfile(tc.TempRoot, 'both-present.backup.csv');
            copyfile(source, backup);
            first = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());
            tc.assertEqual(first.Status, 'ok', first.Message);
            receipt = jsondecode(fileread(tc.receiptPath()));
            staged = char(receipt.files(1).temporary_path);
            copyfile(backup, source);
            copyfile(backup, staged);
            receipt.status = 'deleting';
            receipt.committed_at = '';
            receipt.files(1).state = 'deleted';
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            tc.verifyError(@() ...
                bms.data.StandardVerifiedSourceCsvCleanupService. ...
                    reconcilePendingDay(tc.TempRoot, tc.Day, cfg, ...
                        localCleanupOptions()), ...
                'BMS:CacheSourceCleanup:DuplicatePendingSource');

            tc.verifyTrue(isfile(source));
            tc.verifyTrue(isfile(staged));
        end

        function renamingStateRejectsSourceAndStagingBothMissing(tc)
            cfg = localTemperatureConfig('guanbing');
            folder = tc.waveFolder('feature');
            tc.createZip(fullfile(folder, 'temperature.zip'), ...
                {'TEMP01.csv'}, {localSeries(tc.Day, [1 2])});
            tc.extract(cfg);
            first = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());
            tc.assertEqual(first.Status, 'ok', first.Message);
            receipt = jsondecode(fileread(tc.receiptPath()));
            source = char(receipt.files(1).source_path);
            staged = char(receipt.files(1).temporary_path);
            tc.assertFalse(isfile(source));
            tc.assertFalse(isfile(staged));
            receipt.status = 'renaming';
            receipt.committed_at = '';
            receipt.deleted_count = 0;
            receipt.deleted_bytes = 0;
            receipt.files(1).state = 'renamed';
            receipt.files(1).deleted_at = '';
            bms.core.Logger.writeJson(tc.receiptPath(), receipt);

            tc.verifyError(@() ...
                bms.data.StandardVerifiedSourceCsvCleanupService. ...
                    reconcilePendingDay(tc.TempRoot, tc.Day, cfg, ...
                        localCleanupOptions()), ...
                'BMS:CacheSourceCleanup:SourceDisappearedBeforeDelete');

            tc.verifyFalse(isfile(source));
            tc.verifyFalse(isfile(staged));
        end

        function committedReceiptRejectsChangedSourceResolutionConfig(tc)
            cfg = localTemperatureConfig('guanbing');
            folder = tc.waveFolder('feature');
            tc.createZip(fullfile(folder, 'temperature.zip'), ...
                {'TEMP01.csv'}, {localSeries(tc.Day, [1 2])});
            tc.extract(cfg);
            first = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg, localCleanupOptions());
            tc.assertEqual(first.Status, 'ok');

            changed = cfg;
            changed.per_point.temperature.T1.file_id = 'TEMP02';
            tc.verifyError(@() ...
                bms.data.StandardVerifiedSourceCsvCleanupService.archivedRecords( ...
                    tc.TempRoot, tc.Day, tc.Day, changed), ...
                'BMS:CacheSourceCleanup:ReceiptBindingMismatch');
        end
    end

    methods
        function folder = waveFolder(tc, subfolder)
            folder = fullfile(tc.TempRoot, tc.Day, char([27874 24418]), subfolder);
            if ~isfolder(folder), mkdir(folder); end
        end

        function folder = featureFolder(tc, subfolder)
            folder = fullfile(tc.TempRoot, tc.Day, char([29305 24449 20540]), subfolder);
            if ~isfolder(folder), mkdir(folder); end
        end

        function createZip(tc, zipPath, names, contents)
            stage = tempname(tc.TempRoot);
            mkdir(stage);
            for i = 1:numel(names)
                localWrite(fullfile(stage, names{i}), contents{i});
            end
            parent = fileparts(zipPath);
            if ~isfolder(parent), mkdir(parent); end
            zip(zipPath, names, stage);
            rmdir(stage, 's');
        end

        function extract(tc, cfg)
            % Donghua's day preflight requires at least one waveform and one
            % feature archive. Tests that exercise only one configured family
            % add an unrelated complementary archive; it must never become
            % cleanup eligible.
            waveRoot = fullfile(tc.TempRoot, tc.Day, char([27874 24418]));
            featureRoot = fullfile(tc.TempRoot, tc.Day, char([29305 24449 20540]));
            waveZips = dir(fullfile(waveRoot, '**', '*.zip'));
            featureZips = dir(fullfile(featureRoot, '**', '*.zip'));
            if isempty(waveZips)
                tc.createZip(fullfile(waveRoot, 'unused', 'wave.zip'), ...
                    {'unused.txt'}, {'not configured'});
            end
            if isempty(featureZips)
                tc.createZip(fullfile(featureRoot, 'unused', 'feature.zip'), ...
                    {'unused.txt'}, {'not configured'});
            end
            cfg.preprocessing = struct('unzip', struct( ...
                'max_workers', 1, 'min_free_gib', 0, ...
                'min_free_fraction', 0, 'additional_required_bytes', 0, ...
                'reuse_validation', 'full_crc', ...
                'summary_file', fullfile('run_logs', 'extract.json')));
            summary = bms.data.ArchiveExtractService.run( ...
                tc.TempRoot, tc.Day, tc.Day, cfg);
            tc.assertEqual(summary.failed_count, 0);
        end

        function path = receiptPath(tc)
            path = bms.data.CacheSourceCleanupProvider.standardReceiptPath( ...
                tc.TempRoot, tc.Day);
        end
    end
end

function cfg = localTemperatureConfig(vendor)
cfg = localBaseConfig(vendor);
cfg.subfolders.temperature = fullfile(char([27874 24418]), 'feature');
cfg.points.temperature = {'T1'};
cfg.file_patterns.temperature.default = '{file_id}.csv';
cfg.per_point.temperature.T1 = struct('file_id', 'TEMP01');
end

function cfg = localHongtangMultiModuleConfig()
cfg = localBaseConfig('hongtang');
cfg.subfolders.acceleration_raw = fullfile(char([27874 24418]), 'wave');
cfg.subfolders.temperature = fullfile(char([29305 24449 20540]), 'feature');
cfg.points.acceleration = {'A1'};
cfg.points.temperature = {'T1'};
cfg.file_patterns.acceleration.default = '{file_id}.csv';
cfg.file_patterns.temperature.default = '{file_id}.csv';
cfg.per_point.acceleration.A1 = struct('file_id', 'ACC01');
cfg.per_point.temperature.T1 = struct('file_id', 'TEMP01');
end

function cfg = localBaseConfig(vendor)
cfg = struct('vendor', vendor, ...
    'defaults', struct('header_marker', '[missing]'), ...
    'subfolders', struct(), 'points', struct(), ...
    'file_patterns', struct(), 'per_point', struct(), ...
    'time_series', struct('source_mode', 'auto', ...
        'cache_version', 'csv_timeseries_v2', 'require_metadata', true), ...
    'cache_prebuild', struct('manifest_dir', 'run_logs', ...
        'force_rebuild', false, 'min_free_gib', 0, ...
        'min_free_fraction', 0, 'estimated_cache_ratio', 1.25, ...
        'max_workers', 1));
end

function options = localCleanupOptions()
options = struct('cache_source_cleanup', struct( ...
    'enabled', true, 'mode', 'verified_extracted_csv', ...
    'commit_scope', 'day', 'recovery_policy', 'verified_archive', ...
    'confirmation', 'DELETE_VERIFIED_EXTRACTED_CSV', ...
    'confirmed_at', '2026-07-16T00:00:00+08:00'));
end

function content = localSeries(day, values)
content = sprintf(['ignored header\n' ...
    '%s 00:00:00.000,%.6f\n' ...
    '%s 00:00:01.000,%.6f\n'], ...
    day, values(1), day, values(2));
end

function localWrite(path, content)
parent = fileparts(path);
if ~isfolder(parent), mkdir(parent); end
fid = fopen(path, 'wt', 'n', 'UTF-8');
assert(fid > 0);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, content, 'char');
end

function path = localCachePath(sourcePath)
[folder, base] = fileparts(sourcePath);
path = fullfile(folder, 'cache', [base '.mat']);
end

function value = localCrc32(path)
checksum = java.util.zip.CRC32();
fid = fopen(path, 'rb');
assert(fid > 0);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, Inf, '*uint8');
checksum.update(typecast(bytes(:), 'int8'));
value = double(checksum.getValue());
end

function localSetModified(path, datenumValue)
millis = int64(round((double(datenumValue) - 719529) * 86400000));
ok = java.io.File(path).setLastModified(millis);
assert(ok);
end

function authorization = localVerifyCleanupAuthorization(tc, receipt, expectedCount)
tc.assertTrue(isfield(receipt, 'authorization_path'));
tc.assertTrue(isfile(receipt.authorization_path));
authorization = jsondecode(fileread(receipt.authorization_path));
tc.verifyEqual(double(receipt.authorization_schema_version), 1);
tc.verifyEqual(receipt.authorization_id, receipt.receipt_id);
tc.verifyEqual(authorization.authorization_id, receipt.receipt_id);
tc.verifyEqual(authorization.status, 'authorized');
tc.verifyEqual(double(authorization.file_count), expectedCount);
tc.verifyEqual(numel(authorization.files), expectedCount);
tc.verifyEqual(authorization.authorization_hash, ...
    receipt.authorization_hash);
tc.verifyEqual(authorization.authorization_path, ...
    receipt.authorization_path);
tc.verifyEqual(authorization.lock_path, receipt.cleanup_lock_path);
payload = rmfield(authorization, 'authorization_hash');
tc.verifyEqual(bms.data.CacheManager.configHash(payload), ...
    authorization.authorization_hash);
required = {'source_path','temporary_path','source_bytes', ...
    'source_crc32','cache_path','metadata_path','pair_id', ...
    'mat_bytes','cache_bytes'};
tc.verifyTrue(all(isfield(authorization.files, required)));
crcValues = double([authorization.files.source_crc32]);
tc.verifyTrue(all(isfinite(crcValues) & crcValues >= 0 ...
    & crcValues <= double(intmax('uint32'))));
end

function localOverwriteTokenPreservingFingerprint(tc, path, oldToken, newToken)
oldBytes = uint8(unicode2native(char(oldToken), 'UTF-8'));
newBytes = uint8(unicode2native(char(newToken), 'UTF-8'));
tc.assertEqual(numel(newBytes), numel(oldBytes));
before = dir(path);
beforeMillis = java.io.File(path).lastModified();
fid = fopen(path, 'rb');
tc.assertGreaterThanOrEqual(fid, 0);
raw = fread(fid, Inf, '*uint8').';
fclose(fid);
locations = strfind(raw, oldBytes);
tc.assertEqual(numel(locations), 1);
fid = fopen(path, 'r+b');
tc.assertGreaterThanOrEqual(fid, 0);
tc.assertEqual(fseek(fid, locations(1) - 1, 'bof'), 0);
written = fwrite(fid, newBytes, 'uint8');
tc.assertEqual(written, numel(newBytes));
tc.assertEqual(fclose(fid), 0);
tc.assertTrue(java.io.File(path).setLastModified(beforeMillis));
after = dir(path);
tc.assertEqual(double(after.bytes), double(before.bytes));
tc.assertEqual(java.io.File(path).lastModified(), beforeMillis);
end
