classdef test_daily_archive_cleanup_lock_and_recovery < matlab.unittest.TestCase
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
        function dayMutationLeaseIsReentrantButBlocksForeignOwner(tc)
            outer = bms.data.DailyExportMutationLock.acquire( ...
                tc.OutputRoot, tc.Day);
            lockPath = bms.data.DailyExportMutationLock.pathFor( ...
                tc.OutputRoot, tc.Day);
            tc.verifyTrue(isfolder(lockPath));

            nested = bms.data.DailyExportMutationLock.acquire( ...
                tc.OutputRoot, tc.Day);
            delete(nested);
            tc.verifyTrue(isfolder(lockPath));
            tc.verifyError(@() bms.core.DirectoryLeaseLock.acquire( ...
                lockPath, struct(), struct()), ...
                'BMS:DirectoryLeaseLock:Locked');

            delete(outer);
            tc.verifyFalse(isfolder(lockPath));
        end

        function archiveRunHonoursCommonDayMutationLease(tc)
            tc.createDailyZip('POINT-LOCK.csv');
            lockPath = bms.data.DailyExportMutationLock.pathFor( ...
                tc.OutputRoot, tc.Day);
            bms.data.DataLayoutResolver.ensureDir(fileparts(lockPath));
            [foreign, ~] = bms.core.DirectoryLeaseLock.acquire( ...
                lockPath, struct(), struct('purpose', 'test_foreign_owner'));
            tc.verifyError(@() bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config), ...
                'BMS:DirectoryLeaseLock:Locked');
            delete(foreign);

            outer = bms.data.DailyExportMutationLock.acquire( ...
                tc.OutputRoot, tc.Day);
            summary = bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            tc.verifyEqual(summary.status, 'ok');
            delete(outer);
        end

        function cachePrebuildHonoursCommonDayMutationLease(tc)
            tc.createDailyZip('POINT-CACHE-LOCK.csv');
            extracted = bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            tc.assertEqual(extracted.status, 'ok');
            lockPath = bms.data.DailyExportMutationLock.pathFor( ...
                tc.OutputRoot, tc.Day);
            [foreign, ~] = bms.core.DirectoryLeaseLock.acquire( ...
                lockPath, struct(), struct('purpose', 'test_foreign_owner'));

            blocked = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, struct());
            tc.verifyEqual(blocked.Status, 'fail');
            blockedSummary = bms.io.JsonFile.read(blocked.StatsPath);
            tc.verifyEqual(blockedSummary.error_identifier, ...
                'BMS:DirectoryLeaseLock:Locked');
            delete(foreign);

            outer = bms.data.DailyExportMutationLock.acquire( ...
                tc.OutputRoot, tc.Day);
            accepted = bms.data.CachePrebuildService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config, struct());
            tc.verifyEqual(accepted.Status, 'ok');
            delete(outer);
        end

        function recoveryProofStreamsCompressedPayload(tc)
            tc.createDailyZip('POINT-CRC.csv');
            bms.data.ArchiveExtractService.run( ...
                tc.OutputRoot, tc.Day, tc.Day, tc.Config);
            source = fullfile(tc.OutputRoot, ['data_jlj_' tc.Day], ...
                'data', 'jlj', 'csv', 'POINT-CRC.csv');
            proof = bms.data.ArchiveExtractService.verifyRecoveryForFiles( ...
                tc.OutputRoot, tc.Day, tc.Config, {source});
            tc.verifyTrue(bms.data.ArchiveExtractService.verifyArchiveProof(proof));

            zipPath = fullfile(tc.SourceRoot, ['data_jlj_' tc.Day '.zip']);
            modifiedMillis = java.io.File(zipPath).lastModified();
            localCorruptFirstPayloadByte(zipPath);
            tc.assertTrue(java.io.File(zipPath).setLastModified(modifiedMillis));

            % The central directory, archive length and timestamp are still
            % unchanged, so routine MAT-only proof reuse remains cheap.  Only
            % the deletion-time decoded stream/CRC check detects this.
            tc.verifyTrue(bms.data.ArchiveExtractService.verifyArchiveProof(proof));
            tc.verifyFalse(bms.data.ArchiveExtractService.verifyArchiveProof( ...
                proof, true));
        end
    end

    methods (Access = private)
        function createDailyZip(tc, name)
            content = sprintf([ ...
                'ts,value_x,value_y,value_z\n' ...
                '%s 00:00:00.000,1,11,21\n' ...
                '%s 00:00:01.000,2,12,22\n'], tc.Day, tc.Day);
            bytes = unicode2native(content, 'UTF-8');
            zipPath = fullfile(tc.SourceRoot, ['data_jlj_' tc.Day '.zip']);
            stream = java.io.FileOutputStream(zipPath);
            zipStream = java.util.zip.ZipOutputStream(stream);
            cleanup = onCleanup(@() localCloseZip(zipStream, stream)); %#ok<NASGU>
            entry = java.util.zip.ZipEntry(['data/jlj/csv/' name]);
            checksum = java.util.zip.CRC32();
            checksum.update(bytes);
            entry.setMethod(0); % ZipEntry.STORED
            entry.setSize(numel(bytes));
            entry.setCompressedSize(numel(bytes));
            entry.setCrc(checksum.getValue());
            zipStream.putNextEntry(entry);
            zipStream.write(bytes, 0, numel(bytes));
            zipStream.closeEntry();
        end
    end
end

function cfg = localConfig(sourceRoot, outputRoot)
cfg = struct();
cfg.vendor = 'jiulongjiang';
cfg.points = struct('test', {{'POINT-CACHE-LOCK','POINT-CRC','POINT-LOCK'}});
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

function localCloseZip(zipStream, stream)
try, zipStream.close(); catch, end
try, stream.close(); catch, end
end

function localCorruptFirstPayloadByte(path)
fid = fopen(path, 'r+b');
if fid < 0, error('test:zipOpenFailed', 'Unable to open %s', path); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
targetOffset = NaN;
offset = 0;
while true
    fseek(fid, offset, 'bof');
    header = fread(fid, 30, '*uint8');
    if numel(header) < 4 || ~isequal(header(1:4).', uint8([80 75 3 4]))
        break;
    end
    if numel(header) ~= 30
        error('test:zipHeaderInvalid', 'Truncated ZIP local header.');
    end
    compressedBytes = localLittleEndian(header(19:22));
    nameBytes = localLittleEndian(header(27:28));
    extraBytes = localLittleEndian(header(29:30));
    name = char(fread(fid, nameBytes, '*uint8').');
    payloadOffset = offset + 30 + nameBytes + extraBytes;
    if compressedBytes >= 3 && ~endsWith(name, '/') && ~endsWith(name, '\')
        targetOffset = payloadOffset + floor(compressedBytes / 2);
        break;
    end
    offset = payloadOffset + compressedBytes;
end
if ~isfinite(targetOffset)
    error('test:zipPayloadTooSmall', 'No non-empty ZIP payload was found.');
end
fseek(fid, targetOffset, 'bof');
value = fread(fid, 1, '*uint8');
if isempty(value), error('test:zipPayloadMissing', 'ZIP payload byte missing.'); end
fseek(fid, targetOffset, 'bof');
fwrite(fid, bitxor(value, uint8(1)), 'uint8');
end

function value = localLittleEndian(bytes)
bytes = double(bytes(:).');
value = sum(bytes .* (256 .^ (0:numel(bytes)-1)));
end
