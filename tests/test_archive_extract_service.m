classdef test_archive_extract_service < matlab.unittest.TestCase
    properties
        TempRoot
        SourceRoot
        OutputRoot
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TempRoot = tempname;
            tc.SourceRoot = fullfile(tc.TempRoot, 'source');
            tc.OutputRoot = fullfile(tc.TempRoot, 'output');
            mkdir(tc.SourceRoot);
            mkdir(tc.OutputRoot);
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(projectRoot, fullfile(projectRoot, 'scripts'), '-begin');
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            pool = gcp('nocreate');
            if ~isempty(pool), delete(pool); end
            if isfolder(tc.TempRoot), rmdir(tc.TempRoot, 's'); end
        end
    end

    methods (Test)
        function extractsVerifiesPreservesAndReuses(tc)
            day = '2026-05-01';
            zipPath = tc.createDailyZip(day, {'a.csv', 'nested/b.csv'}, {'alpha', 'beta'});
            cfg = tc.config();

            first = bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg);
            tc.verifyEqual(first.status, 'ok');
            tc.verifyEqual(first.extracted_count, 1);
            tc.verifyEqual(first.reused_count, 0);
            tc.verifyTrue(isfile(zipPath), '安全默认值必须保留唯一原始 ZIP。');
            dayRoot = fullfile(tc.OutputRoot, ['data_jlj_' day]);
            tc.verifyTrue(isfile(fullfile(dayRoot, 'data', 'jlj', 'csv', 'a.csv')));
            manifestPath = fullfile(dayRoot, '.bms_extract_manifest.json');
            tc.verifyTrue(isfile(manifestPath));
            manifest = jsondecode(fileread(manifestPath));
            tc.verifyEqual(manifest.schema_version, 4);
            tc.verifyEqual(manifest.status, 'verified');
            tc.verifyTrue(manifest.source_rechecked_after_publish);
            tc.verifyEqual(numel(manifest.output_entries), 2);
            tc.verifyTrue(all([manifest.output_entries.modified_millis] > 0));

            second = bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg);
            tc.verifyEqual(second.extracted_count, 0);
            tc.verifyEqual(second.reused_count, 1);
            tc.verifyTrue(isfile(zipPath));
        end

        function derivedCacheDoesNotInvalidateVerifiedDailyDirectory(tc)
            day = '2026-05-13';
            tc.createDailyZip(day, {'a.csv', 'nested/b.csv'}, {'alpha', 'beta'});
            cfg = tc.config();
            first = bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg);
            tc.assertEqual(first.extracted_count, 1);

            dayRoot = fullfile(tc.OutputRoot, ['data_jlj_' day]);
            cacheDir = fullfile(dayRoot, 'data', 'jlj', 'csv', 'cache');
            mkdir(cacheDir);
            cachePath = fullfile(cacheDir, 'a.mat');
            cacheMetaPath = [cachePath '.meta.json'];
            writeBinaryFile(cachePath, uint8([1 2 3 4]));
            writeBinaryFile(cacheMetaPath, uint8('{"derived":true}'));

            second = bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg);
            tc.verifyEqual(second.extracted_count, 0);
            tc.verifyEqual(second.reused_count, 1);
            tc.verifyTrue(isfile(cachePath));
            tc.verifyTrue(isfile(cacheMetaPath));

            % Extra derived files are allowed, but every source-ZIP entry is
            % still mandatory and byte-size bound.  Removing one must make the
            % existing directory unverified and the safe non-overwrite run fail.
            delete(fullfile(dayRoot, 'data', 'jlj', 'csv', 'nested', 'b.csv'));
            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), ...
                'BMS:ArchiveExtract:ArchiveFailed');
            tc.verifyTrue(isfile(cachePath));

            changedEntry = fullfile(dayRoot, 'data', 'jlj', 'csv', 'nested', 'b.csv');
            writeBinaryFile(changedEntry, uint8('changed-size'));
            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), ...
                'BMS:ArchiveExtract:ArchiveFailed');
            tc.verifyTrue(isfile(cachePath));
        end

        function undeclaredCsvOutsideCacheInvalidatesReuse(tc)
            day = '2026-05-30';
            tc.createDailyZip(day, {'a.csv'}, {'alpha'});
            cfg = tc.config();
            first = bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg);
            tc.assertEqual(first.extracted_count, 1);

            dayRoot = fullfile(tc.OutputRoot, ['data_jlj_' day]);
            extraCsv = fullfile(dayRoot, 'data', 'jlj', 'csv', 'manual-copy.csv');
            writeBinaryFile(extraCsv, uint8('must-not-enter-cache-discovery'));

            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), ...
                'BMS:ArchiveExtract:ArchiveFailed');
            tc.verifyTrue(isfile(extraCsv));

            delete(extraCsv);
            cacheAsFile = fullfile(dayRoot, 'data', 'jlj', 'csv', 'cache');
            writeBinaryFile(cacheAsFile, uint8('not-a-cache-directory'));
            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), ...
                'BMS:ArchiveExtract:ArchiveFailed');
            tc.verifyTrue(isfile(cacheAsFile));
            delete(cacheAsFile);

            wrongCache = fullfile(dayRoot, 'other', 'cache', 'rogue.mat');
            mkdir(fileparts(wrongCache));
            writeBinaryFile(wrongCache, uint8([1 2 3]));
            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), ...
                'BMS:ArchiveExtract:ArchiveFailed');
            tc.verifyTrue(isfile(wrongCache));
        end

        function absoluteSummaryPathIsNotPrefixedByOutputRoot(tc)
            day = '2026-05-14';
            tc.createDailyZip(day, {'a.csv'}, {'alpha'});
            summaryPath = fullfile(tc.TempRoot, 'isolated_run_logs', ...
                'archive_extract_summary.json');
            cfg = tc.config();
            cfg.preprocessing.unzip.summary_file = summaryPath;

            summary = bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg);

            tc.verifyEqual(summary.status, 'ok');
            tc.verifyEqual(summary.summary_path, summaryPath);
            tc.verifyTrue(isfile(summaryPath));
            tc.verifyFalse(contains(summary.summary_path, ...
                [tc.OutputRoot filesep tc.TempRoot]));
        end

        function rejectsExistingDirectoryWithoutVerifiedManifest(tc)
            day = '2026-05-02';
            tc.createDailyZip(day, {'a.csv'}, {'alpha'});
            cfg = tc.config();
            mkdir(fullfile(tc.OutputRoot, ['data_jlj_' day]));

            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), 'BMS:ArchiveExtract:ArchiveFailed');
            tc.verifyTrue(isfile(fullfile(tc.SourceRoot, ['data_jlj_' day '.zip'])));
        end

        function insufficientSpaceIsFatalEvenForSilentWrapper(tc)
            day = '2026-05-03';
            tc.createDailyZip(day, {'a.csv'}, {'alpha'});
            cfg = tc.config();
            cfg.preprocessing.unzip.additional_required_bytes = realmax;

            tc.verifyError(@() batch_unzip_data_parallel( ...
                tc.OutputRoot, day, day, true, cfg), ...
                'BMS:ArchiveExtract:InsufficientSpace');
            tc.verifyTrue(isfile(fullfile(tc.SourceRoot, ['data_jlj_' day '.zip'])));
        end

        function precheckRejectsMissingDailyArchive(tc)
            tc.createDailyZip('2026-05-04', {'a.csv'}, {'alpha'});
            cfg = tc.config();
            tc.verifyError(@() precheck_zip_count( ...
                tc.OutputRoot, '2026-05-04', '2026-05-05', cfg), ...
                'BMS:ArchiveExtract:DailyArchiveCount');
        end

        function changedArchiveCannotReusePublishedDirectory(tc)
            day = '2026-05-06';
            zipPath = tc.createDailyZip(day, {'a.csv'}, {'alpha'});
            cfg = tc.config();
            bms.data.ArchiveExtractService.run(tc.OutputRoot, day, day, cfg);
            delete(zipPath);
            tc.createDailyZip(day, {'a.csv'}, {'changed payload'});

            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), 'BMS:ArchiveExtract:ArchiveFailed');
        end

        function archiveReplacementAfterPlanningIsRejected(tc)
            day = '2026-05-15';
            zipPath = tc.createDailyZip(day, {'a.csv'}, {'alpha'});
            replacementDay = '2026-05-16';
            replacement = tc.createDailyZip( ...
                replacementDay, {'a.csv'}, {'bravo'});
            cfg = tc.config();
            cfg.preprocessing.unzip.test_after_index_hook = ...
                @(target) replaceFile(replacement, target);

            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), ...
                'BMS:ArchiveExtract:ArchiveFailed');
            tc.verifyTrue(isfile(zipPath));
            tc.verifyFalse(isfolder(fullfile(tc.OutputRoot, ['data_jlj_' day])));
            tc.verifyEmpty(dir(fullfile(tc.OutputRoot, ...
                ['data_jlj_' day '.__extracting_*'])));
            summary = jsondecode(fileread(fullfile(tc.OutputRoot, ...
                'run_logs', 'archive_extract_summary.json')));
            tc.verifyThat(summary.results(1).message, ...
                matlab.unittest.constraints.ContainsSubstring('ArchiveChanged'));
        end

        function archiveReplacementImmediatelyBeforePublishIsRejected(tc)
            day = '2026-05-17';
            zipPath = tc.createDailyZip(day, {'a.csv'}, {'alpha'});
            replacement = tc.createDailyZip( ...
                '2026-05-18', {'a.csv'}, {'bravo'});
            cfg = tc.config();
            cfg.preprocessing.unzip.test_before_publish_hook = ...
                @(target) replaceFile(replacement, target);

            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), ...
                'BMS:ArchiveExtract:ArchiveFailed');
            tc.verifyTrue(isfile(zipPath));
            tc.verifyFalse(isfolder(fullfile(tc.OutputRoot, ['data_jlj_' day])));
            tc.verifyEmpty(dir(fullfile(tc.OutputRoot, ...
                ['data_jlj_' day '.__extracting_*'])));
            summary = jsondecode(fileread(fullfile(tc.OutputRoot, ...
                'run_logs', 'archive_extract_summary.json')));
            tc.verifyThat(summary.results(1).message, ...
                matlab.unittest.constraints.ContainsSubstring('ArchiveChanged'));
        end

        function archiveReplacementAfterPublishLeavesNoVerifiedManifest(tc)
            day = '2026-05-29';
            zipPath = tc.createDailyZip(day, {'a.csv'}, {'alpha'});
            replacement = tc.createDailyZip( ...
                '2026-05-28', {'a.csv'}, {'bravo'});
            cfg = tc.config();
            cfg.preprocessing.unzip.test_after_publish_hook = ...
                @(target) replaceFile(replacement, target);

            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), ...
                'BMS:ArchiveExtract:ArchiveFailed');
            tc.verifyTrue(isfile(zipPath));
            dayRoot = fullfile(tc.OutputRoot, ['data_jlj_' day]);
            tc.verifyTrue(isfolder(dayRoot));
            tc.verifyFalse(isfile(fullfile(dayRoot, '.bms_extract_manifest.json')));
            summary = jsondecode(fileread(fullfile(tc.OutputRoot, ...
                'run_logs', 'archive_extract_summary.json')));
            tc.verifyThat(summary.results(1).message, ...
                matlab.unittest.constraints.ContainsSubstring('ArchiveChanged'));
        end

        function sameSizeOutputContentChangeCannotBeReused(tc)
            day = '2026-05-19';
            tc.createDailyZip(day, {'a.csv'}, {'alpha'});
            cfg = tc.config();
            first = bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg);
            tc.assertEqual(first.extracted_count, 1);
            output = fullfile(tc.OutputRoot, ['data_jlj_' day], ...
                'data', 'jlj', 'csv', 'a.csv');
            fileObject = java.io.File(output);
            originalModified = double(fileObject.lastModified());
            writeBinaryFile(output, uint8('omega'));
            tc.assertTrue(fileObject.setLastModified(originalModified + 2000));

            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), ...
                'BMS:ArchiveExtract:ArchiveFailed');
            tc.verifyEqual(fileread(output), 'omega');
            dayRoot = fullfile(tc.OutputRoot, ['data_jlj_' day]);
            manifestPath = fullfile(dayRoot, '.bms_extract_manifest.json');
            manifest = jsondecode(fileread(manifestPath));
            tc.verifyEqual(manifest.status, 'invalidated');
            tc.verifyTrue(isfile([manifestPath '.invalidated.json']));

            metadataCfg = tc.config();
            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, metadataCfg), ...
                'BMS:ArchiveExtract:ArchiveFailed');
        end

        function fullCrcAuditDetectsTamperWithRestoredTimestamp(tc)
            day = '2026-05-27';
            tc.createDailyZip(day, {'a.csv'}, {'alpha'});
            cfg = tc.config();
            first = bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg);
            tc.assertEqual(first.extracted_count, 1);
            output = fullfile(tc.OutputRoot, ['data_jlj_' day], ...
                'data', 'jlj', 'csv', 'a.csv');
            fileObject = java.io.File(output);
            originalModified = double(fileObject.lastModified());
            writeBinaryFile(output, uint8('omega'));
            tc.assertTrue(fileObject.setLastModified(originalModified));

            fast = bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg);
            tc.verifyEqual(fast.reused_count, 1);
            tc.verifyEqual(fast.reuse_validation, 'metadata');

            cfg.preprocessing.unzip.reuse_validation = 'full_crc';
            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), ...
                'BMS:ArchiveExtract:ArchiveFailed');
            tc.verifyEqual(fileread(output), 'omega');

            dayRoot = fullfile(tc.OutputRoot, ['data_jlj_' day]);
            manifestPath = fullfile(dayRoot, '.bms_extract_manifest.json');
            manifest = jsondecode(fileread(manifestPath));
            tc.verifyEqual(manifest.status, 'invalidated');
            tc.verifyTrue(isfile([manifestPath '.invalidated.json']));

            % A later operator must not be able to hide a known CRC failure by
            % switching back to the fast metadata policy.  The independent
            % invalidation marker remains an authoritative fail-closed gate.
            metadataCfg = tc.config();
            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, metadataCfg), ...
                'BMS:ArchiveExtract:ArchiveFailed');
        end

        function invalidReuseValidationIsRejected(tc)
            day = '2026-05-26';
            tc.createDailyZip(day, {'a.csv'}, {'alpha'});
            cfg = tc.config();
            cfg.preprocessing.unzip.reuse_validation = 'size_only';
            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), ...
                'BMS:ArchiveExtract:InvalidReuseValidation');
        end

        function malformedVerifiedManifestCannotAuthorizeReuse(tc)
            day = '2026-05-25';
            tc.createDailyZip(day, {'a.csv'}, {'alpha'});
            cfg = tc.config();
            bms.data.ArchiveExtractService.run(tc.OutputRoot, day, day, cfg);
            manifestPath = fullfile(tc.OutputRoot, ['data_jlj_' day], ...
                '.bms_extract_manifest.json');
            manifest = jsondecode(fileread(manifestPath));
            manifest.status = 'not_verified';
            bms.core.Logger.writeJson(manifestPath, manifest);

            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), ...
                'BMS:ArchiveExtract:ArchiveFailed');
        end

        function legacyDonghuaLayoutPublishesBesideArchiveAndReuses(tc)
            day = '2026-05-07';
            wave = char([0x6CE2 0x5F62]);
            feature = char([0x7279 0x5F81 0x503C]);
            waveZip = fullfile(tc.SourceRoot, day, wave, 'device-a', 'wave.zip');
            featureZip = fullfile(tc.SourceRoot, day, feature, 'device-b', 'feature.zip');
            tc.createSimpleZip(waveZip, 'wave.csv', 'wave-data');
            tc.createSimpleZip(featureZip, 'feature.csv', 'feature-data');
            cfg = tc.config();
            cfg = rmfield(cfg, 'vendor');

            first = bms.data.ArchiveExtractService.run(tc.OutputRoot, day, day, cfg);
            tc.verifyEqual(first.extracted_count, 2);
            tc.verifyTrue(isfile(waveZip));
            tc.verifyTrue(isfile(featureZip));
            tc.verifyTrue(isfile(fullfile(tc.OutputRoot, day, wave, 'device-a', 'wave.csv')));
            tc.verifyTrue(isfile(fullfile(tc.OutputRoot, day, feature, 'device-b', 'feature.csv')));

            second = bms.data.ArchiveExtractService.run(tc.OutputRoot, day, day, cfg);
            tc.verifyEqual(second.reused_count, 2);
        end

        function mergeTamperIsIncludedInCapacityPlan(tc)
            day = '2026-05-31';
            wave = char([0x6CE2 0x5F62]);
            feature = char([0x7279 0x5F81 0x503C]);
            waveZip = fullfile(tc.SourceRoot, day, wave, 'device-a', 'wave.zip');
            featureZip = fullfile(tc.SourceRoot, day, feature, 'device-b', 'feature.zip');
            tc.createSimpleZip(waveZip, 'wave.csv', 'wave-data');
            tc.createSimpleZip(featureZip, 'feature.csv', 'feature-data');
            cfg = tc.config();
            cfg = rmfield(cfg, 'vendor');
            first = bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg);
            tc.assertEqual(first.extracted_count, 2);

            output = fullfile(tc.OutputRoot, day, wave, 'device-a', 'wave.csv');
            writeBinaryFile(output, uint8('tampered!'));
            tc.assertEqual(numel(uint8('tampered!')), numel(uint8('wave-data')));

            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), ...
                'BMS:ArchiveExtract:ArchiveFailed');
            summary = jsondecode(fileread(fullfile(tc.OutputRoot, ...
                'run_logs', 'archive_extract_summary.json')));
            tc.verifyGreaterThan(summary.pending_uncompressed_bytes, 0);
            tc.verifyGreaterThan(summary.pending_file_count, 0);
        end

        function mergeArchiveChangeAfterPublishCannotLeaveVerifiedReceipt(tc)
            day = '2026-05-18';
            wave = char([0x6CE2 0x5F62]);
            feature = char([0x7279 0x5F81 0x503C]);
            waveZip = fullfile(tc.SourceRoot, day, wave, 'device-a', 'wave.zip');
            featureZip = fullfile(tc.SourceRoot, day, feature, 'device-b', 'feature.zip');
            tc.createSimpleZip(waveZip, 'wave.csv', 'wave-data');
            tc.createSimpleZip(featureZip, 'feature.csv', 'feature-data');
            replacement = fullfile(tc.TempRoot, 'replacement.zip');
            tc.createSimpleZip(replacement, 'other.csv', 'changed-data');
            cfg = tc.config();
            cfg = rmfield(cfg, 'vendor');
            cfg.preprocessing.unzip.test_after_publish_hook = ...
                @(target) replaceFile(replacement, target);

            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), ...
                'BMS:ArchiveExtract:ArchiveFailed');
            waveManifest = fullfile(tc.OutputRoot, day, wave, 'device-a', ...
                '.bms_extract_wave.json');
            tc.verifyTrue(isfile(waveManifest));
            receipt = jsondecode(fileread(waveManifest));
            tc.verifyEqual(receipt.status, 'publishing');
            tc.verifyFalse(receipt.source_rechecked_after_publish);
        end

        function outputRootLockRejectsConcurrentRun(tc)
            day = '2026-05-08';
            zipPath = tc.createDailyZip(day, {'a.csv'}, {'alpha'});
            cfg = tc.config();
            mkdir(fullfile(tc.OutputRoot, '.bms_archive_extract.lock'));

            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), 'BMS:ArchiveExtract:Locked');
            tc.verifyTrue(isfile(zipPath));
            tc.verifyFalse(isfolder(fullfile(tc.OutputRoot, ['data_jlj_' day])));
        end

        function unsafeArchiveEntryIsRejectedBeforeWritingOutsideRoot(tc)
            day = '2026-05-09';
            zipPath = fullfile(tc.SourceRoot, ['data_jlj_' day '.zip']);
            tc.createUnsafeZip(zipPath, '../escape.csv', 'do-not-write');
            cfg = tc.config();

            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), 'BMS:ArchiveExtract:UnsafeEntry');
            tc.verifyTrue(isfile(zipPath));
            tc.verifyFalse(isfile(fullfile(tc.TempRoot, 'escape.csv')));
        end

        function acceptsWindowsBackslashDirectoryEntries(tc)
            day = '2026-05-11';
            zipPath = fullfile(tc.SourceRoot, ['data_jlj_' day '.zip']);
            tc.createBackslashDirectoryZip(zipPath);
            cfg = tc.config();

            summary = bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg);

            tc.verifyEqual(summary.status, 'ok');
            tc.verifyEqual(summary.extracted_count, 1);
            tc.verifyTrue(isfile(fullfile(tc.OutputRoot, ['data_jlj_' day], ...
                'data', 'jlj', 'csv', 'POINT-01.csv')));
            tc.verifyTrue(isfile(zipPath));
        end

        function relativeRootIsNotDuplicated(tc)
            day = '2026-05-10';
            original = pwd;
            cleanup = onCleanup(@() cd(original)); %#ok<NASGU>
            cd(tc.TempRoot);
            tc.createDailyZip(day, {'a.csv'}, {'alpha'});
            copyfile(fullfile(tc.SourceRoot, ['data_jlj_' day '.zip']), tc.OutputRoot);
            cfg = struct('vendor', 'jiulongjiang', 'preprocessing', struct( ...
                'unzip', struct('min_free_gib', 0, 'min_free_fraction', 0, 'max_workers', 1)));

            summary = bms.data.ArchiveExtractService.run('output', day, day, cfg);
            tc.verifyEqual(summary.output_root, tc.OutputRoot);
            tc.verifyFalse(contains(summary.output_root, fullfile('output', 'output')));
        end

        function rejectsUnknownUnzipOptionsInsteadOfSilentlyUsingDefaults(tc)
            day = '2026-05-12';
            tc.createDailyZip(day, {'a.csv'}, {'alpha'});
            cfg = tc.config();
            cfg.preprocessing.unzip.safety_factor = 1.10;

            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, day, day, cfg), ...
                'BMS:ArchiveExtract:UnknownOption');
            tc.verifyFalse(isfolder(fullfile(tc.OutputRoot, ['data_jlj_' day])));
        end

        function workerContractMatchesSharedPythonFixture(tc)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            expected = jsondecode(fileread(fullfile(projectRoot, 'tests', ...
                'fixtures', 'unzip_worker_contract.json')));
            actual = bms.data.ArchiveExtractService.workerContract();

            tc.verifyEqual(actual.schema_version, expected.schema_version);
            tc.verifyEqual(actual.default_workers, expected.default_workers);
            tc.verifyEqual(actual.auto_token, expected.auto_token);
            tc.verifyEqual(actual.auto_max_workers, expected.auto_max_workers);
            tc.verifyEqual(actual.max_custom_workers, expected.max_custom_workers);
            tc.verifyEqual(actual.preset_workers, expected.preset_workers(:).');
            tc.verifyEqual(actual.summary_fields(:), expected.summary_fields(:));
        end

        function workerSettingPreservesLegacyNumericAndSafeDefault(tc)
            historical = bms.data.ArchiveExtractService.workerPlan([], 31);
            tc.verifyEqual(historical.mode, 'fixed');
            tc.verifyEqual(historical.requested_workers, 1);
            tc.verifyEqual(historical.resolved_workers, 1);

            automatic = bms.data.ArchiveExtractService.workerPlan('auto', 31);
            tc.verifyEqual(automatic.mode, 'auto');
            tc.verifyEqual(automatic.requested_workers, 'auto');
            tc.verifyEqual(automatic.worker_limit, 2);
            tc.verifyEqual(automatic.resolved_workers, 2);

            custom = bms.data.ArchiveExtractService.workerPlan(7, 3);
            tc.verifyEqual(custom.mode, 'fixed');
            tc.verifyEqual(custom.requested_workers, 7);
            tc.verifyEqual(custom.worker_limit, 7);
            tc.verifyEqual(custom.resolved_workers, 3);
        end

        function invalidWorkerSettingsAreRejectedWithoutTruncation(tc)
            invalid = {0, -1, 1.5, 65, inf, true, '2', 'parallel', [1 2]};
            for i = 1:numel(invalid)
                value = invalid{i};
                tc.verifyError(@() ...
                    bms.data.ArchiveExtractService.normalizeWorkerSetting(value), ...
                    'BMS:ArchiveExtract:InvalidMaxWorkers');
            end
        end

        function serialAndParallelExtractionResultsAreEquivalent(tc)
            days = {'2026-05-20', '2026-05-21', '2026-05-22'};
            for i = 1:numel(days)
                tc.createDailyZip(days{i}, {'a.csv', 'nested/b.csv'}, ...
                    {sprintf('alpha-%d', i), sprintf('beta-%d', i)});
            end
            serialRoot = fullfile(tc.TempRoot, 'serial_output');
            parallelRoot = fullfile(tc.TempRoot, 'parallel_output');
            serialCfg = tc.config();
            serialCfg.preprocessing.unzip.output_root = serialRoot;
            serialCfg.preprocessing.unzip.max_workers = 1;
            serialCfg.preprocessing.unzip.summary_file = fullfile( ...
                tc.TempRoot, 'serial_summary.json');
            parallelCfg = tc.config();
            parallelCfg.preprocessing.unzip.output_root = parallelRoot;
            parallelCfg.preprocessing.unzip.max_workers = 2;
            parallelCfg.preprocessing.unzip.summary_file = fullfile( ...
                tc.TempRoot, 'parallel_summary.json');

            serial = bms.data.ArchiveExtractService.run( ...
                serialRoot, days{1}, days{end}, serialCfg);
            parallel = bms.data.ArchiveExtractService.run( ...
                parallelRoot, days{1}, days{end}, parallelCfg);

            tc.verifyEqual(serial.worker_mode, 'fixed');
            tc.verifyEqual(serial.requested_workers, 1);
            tc.verifyEqual(serial.resolved_workers, 1);
            tc.verifyEqual(serial.effective_workers, 1);
            tc.verifyFalse(serial.parallel_fallback);
            tc.verifyEmpty(serial.parallel_fallback_reason);
            tc.verifyEqual(parallel.worker_mode, 'fixed');
            tc.verifyEqual(parallel.requested_workers, 2);
            tc.verifyEqual(parallel.resolved_workers, 2);
            tc.verifyTrue(ismember(parallel.effective_workers, [1 2]));
            tc.verifyEqual(parallel.parallel_fallback, ...
                parallel.effective_workers < parallel.resolved_workers);
            if parallel.parallel_fallback
                tc.verifyNotEmpty(parallel.parallel_fallback_reason);
            end
            tc.verifyEqual({serial.results.status}, {parallel.results.status});
            tc.verifyEqual({serial.results.archive_index_sha256}, ...
                {parallel.results.archive_index_sha256});
            tc.verifyEqual({serial.results.output_index_sha256}, ...
                {parallel.results.output_index_sha256});
            tc.verifyEqual([serial.results.expected_files], ...
                [parallel.results.expected_files]);
            tc.verifyEqual([serial.results.expected_bytes], ...
                [parallel.results.expected_bytes]);
            tc.verifyEqual([serial.results.actual_files], ...
                [parallel.results.actual_files]);
            tc.verifyEqual([serial.results.actual_bytes], ...
                [parallel.results.actual_bytes]);
        end

        function parallelRuntimeFailureFallsBackAndIsRecorded(tc)
            days = {'2026-05-23', '2026-05-24'};
            for i = 1:numel(days)
                tc.createDailyZip(days{i}, {'a.csv'}, {sprintf('payload-%d', i)});
            end
            shadowDir = fullfile(tc.TempRoot, 'parallel_shadow');
            mkdir(shadowDir);
            shadowPath = fullfile(shadowDir, 'parcluster.m');
            writeBinaryFile(shadowPath, unicode2native(sprintf([ ...
                'function cluster = parcluster(varargin)\n' ...
                'error(''TEST:ParallelUnavailable'', ''forced parallel failure'');\n' ...
                'cluster = []; %%#ok<NASGU>\n' ...
                'end\n']), 'UTF-8'));
            addpath(shadowDir, '-begin');
            clear parcluster;
            cleanup = onCleanup(@() removeParallelShadow(shadowDir)); %#ok<NASGU>
            tc.assertEqual(which('parcluster'), shadowPath);
            warningState = warning('off', 'BMS:ArchiveExtract:ParallelUnavailable');
            warningCleanup = onCleanup(@() warning(warningState)); %#ok<NASGU>

            cfg = tc.config();
            cfg.preprocessing.unzip.max_workers = 2;
            summary = bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, days{1}, days{end}, cfg);

            tc.verifyEqual(summary.status, 'ok');
            tc.verifyEqual(summary.requested_workers, 2);
            tc.verifyEqual(summary.resolved_workers, 2);
            tc.verifyEqual(summary.effective_workers, 1);
            tc.verifyTrue(summary.parallel_fallback);
            tc.verifyThat(summary.parallel_fallback_reason, ...
                matlab.unittest.constraints.ContainsSubstring('forced parallel failure'));
            tc.verifyEqual(summary.extracted_count, 2);
            tc.verifyEqual(summary.failed_count, 0);
        end

        function syntheticBenchmarkEntryIsBoundedAndSelfCleaning(tc)
            benchmark = benchmark_archive_extract_workers( ...
                'ArchiveCount', 2, ...
                'FilesPerArchive', 1, ...
                'PayloadBytes', 256, ...
                'WorkerSettings', {1, 'auto'}, ...
                'KeepArtifacts', false);

            tc.verifyEqual(benchmark.scope, 'local_synthetic_zip_only');
            tc.verifyEqual(benchmark.archive_count, 2);
            tc.verifyEqual(numel(benchmark.runs), 2);
            tc.verifyTrue(benchmark.all_outputs_consistent);
            tc.verifyTrue(benchmark.all_runs_passed);
            tc.verifyFalse(benchmark.artifacts_preserved);
            tc.verifyFalse(isfolder(benchmark.benchmark_root));
            tc.verifyTrue(startsWith(benchmark.benchmark_root, tempdir));
        end

        function fourTiBVolumeBudgetUsesExactByteScale(tc)
            GiB = 1024^3;
            TiB = 1024^4;
            plan = bms.data.ArchiveExtractService.evaluateCapacity( ...
                1.2 * TiB, 4 * TiB, 600 * GiB, 5387, 300 * GiB, ...
                200, 0.05, 1.03, 4096);
            tc.verifyEqual(plan.total_bytes, 4 * TiB);
            tc.verifyEqual(plan.reserve_bytes, 0.2 * TiB, 'AbsTol', 1);
            tc.verifyTrue(plan.passed);

            blocked = bms.data.ArchiveExtractService.evaluateCapacity( ...
                1.0 * TiB, 4 * TiB, 700 * GiB, 5387, 300 * GiB, ...
                200, 0.05, 1.03, 4096);
            tc.verifyFalse(blocked.passed);
        end
    end

    methods (Access = private)
        function cfg = config(tc)
            cfg = struct();
            cfg.vendor = 'jiulongjiang';
            cfg.preprocessing = struct();
            cfg.preprocessing.unzip = struct( ...
                'source_root', tc.SourceRoot, ...
                'output_root', tc.OutputRoot, ...
                'max_workers', 1, ...
                'min_free_gib', 0, ...
                'min_free_fraction', 0, ...
                'delete_archives_after_verify', false, ...
                'overwrite_existing', false, ...
                'summary_file', fullfile('run_logs', 'archive_extract_summary.json'));
        end

        function zipPath = createDailyZip(tc, day, relativeFiles, contents)
            stage = fullfile(tc.TempRoot, ['stage_' strrep(day, '-', '')]);
            payloadRoot = fullfile(stage, 'data', 'jlj', 'csv');
            mkdir(payloadRoot);
            for i = 1:numel(relativeFiles)
                path = fullfile(payloadRoot, strrep(relativeFiles{i}, '/', filesep));
                parent = fileparts(path);
                if ~isfolder(parent), mkdir(parent); end
                fid = fopen(path, 'wt');
                assert(fid > 0);
                cleanup = onCleanup(@() fclose(fid));
                fwrite(fid, contents{i}, 'char');
                delete(cleanup);
            end
            zipPath = fullfile(tc.SourceRoot, ['data_jlj_' day '.zip']);
            zip(zipPath, 'data', stage);
            rmdir(stage, 's');
        end


        function createSimpleZip(tc, zipPath, fileName, content)
            stage = tempname(tc.TempRoot);
            mkdir(stage);
            filePath = fullfile(stage, fileName);
            fid = fopen(filePath, 'wt');
            assert(fid > 0);
            cleanup = onCleanup(@() fclose(fid));
            fwrite(fid, content, 'char');
            delete(cleanup);
            parent = fileparts(zipPath);
            if ~isfolder(parent), mkdir(parent); end
            zip(zipPath, fileName, stage);
            rmdir(stage, 's');
        end

        function createUnsafeZip(~, zipPath, entryName, content)
            parent = fileparts(zipPath);
            if ~isfolder(parent), mkdir(parent); end
            stream = java.io.FileOutputStream(zipPath);
            zipStream = java.util.zip.ZipOutputStream(stream);
            cleanup = onCleanup(@() closeZipStreams(zipStream, stream)); %#ok<NASGU>
            entry = java.util.zip.ZipEntry(entryName);
            zipStream.putNextEntry(entry);
            bytes = unicode2native(content, 'UTF-8');
            zipStream.write(bytes, 0, numel(bytes));
            zipStream.closeEntry();
        end

        function createBackslashDirectoryZip(~, zipPath)
            parent = fileparts(zipPath);
            if ~isfolder(parent), mkdir(parent); end
            stream = java.io.FileOutputStream(zipPath);
            zipStream = java.util.zip.ZipOutputStream(stream);
            cleanup = onCleanup(@() closeZipStreams(zipStream, stream)); %#ok<NASGU>
            directories = {'data\', 'data\jlj\', 'data\jlj\csv\'};
            for i = 1:numel(directories)
                entry = java.util.zip.ZipEntry(directories{i});
                zipStream.putNextEntry(entry);
                zipStream.closeEntry();
            end
            entry = java.util.zip.ZipEntry('data\jlj\csv\POINT-01.csv');
            zipStream.putNextEntry(entry);
            bytes = unicode2native(sprintf(['ts,value_x,value_y,value_z\n' ...
                '2026-05-11 00:00:00.000,1,2,3\n']), 'UTF-8');
            zipStream.write(bytes, 0, numel(bytes));
            zipStream.closeEntry();
        end
    end
end

function closeZipStreams(zipStream, stream)
try, zipStream.close(); catch, end
try, stream.close(); catch, end
end

function writeBinaryFile(path, bytes)
fid = fopen(path, 'wb');
assert(fid > 0);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, bytes, 'uint8');
end

function removeParallelShadow(path)
try, rmpath(path); catch, end
clear parcluster;
end

function replaceFile(source, destination)
[ok, message] = copyfile(source, destination, 'f');
assert(ok, message);
end
