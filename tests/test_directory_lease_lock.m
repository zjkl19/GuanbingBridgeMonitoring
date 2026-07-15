classdef test_directory_lease_lock < matlab.unittest.TestCase
    properties
        TempRoot
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TempRoot = tempname;
            mkdir(tc.TempRoot);
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(projectRoot, '-begin');
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if isfolder(tc.TempRoot), rmdir(tc.TempRoot, 's'); end
        end
    end

    methods (Test)
        function normalCleanupRemovesOwnedLease(tc)
            lockPath = fullfile(tc.TempRoot, 'normal.lock');
            [cleanup, lease] = bms.core.DirectoryLeaseLock.acquire( ...
                lockPath, struct(), struct('purpose', 'test'));
            tc.verifyTrue(isfolder(lockPath));
            tc.verifyNotEmpty(lease.token);
            delete(cleanup);
            tc.verifyFalse(isfolder(lockPath));
        end

        function mismatchedCleanupTokenPreservesNewOwner(tc)
            lockPath = fullfile(tc.TempRoot, 'token.lock');
            mkdir(lockPath);
            owner = struct('token', 'new-owner', 'host', ...
                bms.core.DirectoryLeaseLock.localHostName(), 'pid', ...
                bms.core.DirectoryLeaseLock.currentPid());
            bms.core.Logger.writeJson(fullfile(lockPath, 'owner.json'), owner);

            bms.core.DirectoryLeaseLock.release(lockPath, 'old-owner');
            tc.verifyTrue(isfolder(lockPath));
            bms.core.DirectoryLeaseLock.release(lockPath, 'new-owner');
            tc.verifyFalse(isfolder(lockPath));
        end

        function liveSameHostLeaseIsNeverRecoveredByAge(tc)
            lockPath = fullfile(tc.TempRoot, 'live.lock');
            [cleanup, ~] = bms.core.DirectoryLeaseLock.acquire(lockPath);
            setDirectoryAge(lockPath, 48);
            options = struct('recover_stale', true, 'stale_hours', 1);

            tc.verifyError(@() bms.core.DirectoryLeaseLock.acquire( ...
                lockPath, options), 'BMS:DirectoryLeaseLock:Locked');
            tc.verifyTrue(isfolder(lockPath));
            delete(cleanup);
        end

        function deadSameHostPidIsRecoveredImmediately(tc)
            lockPath = fullfile(tc.TempRoot, 'dead.lock');
            mkdir(lockPath);
            owner = struct('token', 'dead-owner', 'host', ...
                bms.core.DirectoryLeaseLock.localHostName(), ...
                'pid', double(intmax('int32')));
            bms.core.Logger.writeJson(fullfile(lockPath, 'owner.json'), owner);
            options = struct('recover_stale', true, 'stale_hours', 24);

            [cleanup, lease] = bms.core.DirectoryLeaseLock.acquire(lockPath, options);
            tc.verifyNotEqual(lease.token, 'dead-owner');
            tc.verifyTrue(isfolder(lockPath));
            delete(cleanup);
            tc.verifyFalse(isfolder(lockPath));
        end

        function recentMalformedOwnerFailsClosed(tc)
            lockPath = fullfile(tc.TempRoot, 'recent-malformed.lock');
            mkdir(lockPath);
            writeText(fullfile(lockPath, 'owner.json'), '{not-json');
            options = struct('recover_stale', true, 'stale_hours', 24);

            tc.verifyError(@() bms.core.DirectoryLeaseLock.acquire( ...
                lockPath, options), 'BMS:DirectoryLeaseLock:Locked');
            tc.verifyTrue(isfolder(lockPath));
        end

        function oldMalformedOwnerRequiresExplicitRecovery(tc)
            lockPath = fullfile(tc.TempRoot, 'old-malformed.lock');
            mkdir(lockPath);
            writeText(fullfile(lockPath, 'owner.json'), '{not-json');
            setDirectoryAge(lockPath, 48);

            tc.verifyError(@() bms.core.DirectoryLeaseLock.acquire( ...
                lockPath, struct('recover_stale', false, 'stale_hours', 1)), ...
                'BMS:DirectoryLeaseLock:Locked');
            [cleanup, ~] = bms.core.DirectoryLeaseLock.acquire( ...
                lockPath, struct('recover_stale', true, 'stale_hours', 1));
            tc.verifyTrue(isfolder(lockPath));
            delete(cleanup);
            tc.verifyFalse(isfolder(lockPath));
        end

        function recoveryArbiterPreventsTwoStaleRemovers(tc)
            lockPath = fullfile(tc.TempRoot, 'guarded-dead.lock');
            mkdir(lockPath);
            owner = struct('token', 'dead-owner', 'host', ...
                bms.core.DirectoryLeaseLock.localHostName(), ...
                'pid', double(intmax('int32')));
            bms.core.Logger.writeJson(fullfile(lockPath, 'owner.json'), owner);
            guardPath = [lockPath '.recovery_guard'];
            writeText(guardPath, 'other-recovery-owner');
            cleanup = onCleanup(@() deleteIfFile(guardPath)); %#ok<NASGU>

            tc.verifyError(@() bms.core.DirectoryLeaseLock.acquire( ...
                lockPath, struct('recover_stale', true, 'stale_hours', 0)), ...
                'BMS:DirectoryLeaseLock:Locked');
            tc.verifyTrue(isfolder(lockPath));
            tc.verifyTrue(isfile(guardPath));
        end
    end
end

function setDirectoryAge(pathValue, ageHours)
timestamp = datetime('now', 'TimeZone', 'UTC') - hours(ageHours);
java.io.File(pathValue).setLastModified(int64(posixtime(timestamp) * 1000));
end

function writeText(pathValue, textValue)
fid = fopen(pathValue, 'wt');
assert(fid > 0);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, textValue, 'char');
end

function deleteIfFile(pathValue)
if isfile(pathValue), delete(pathValue); end
end
