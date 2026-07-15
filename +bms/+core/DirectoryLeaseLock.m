classdef DirectoryLeaseLock
    %DIRECTORYLEASELOCK Token-safe lease for an atomically-created directory.
    %   The directory itself is the atomic lock. owner.json records a UUID,
    %   host and PID so opt-in stale-lock recovery never steals a live
    %   same-host lease, and cleanup only removes the lease it acquired.

    methods (Static)
        function [cleanup, lease] = acquire(lockPath, options, ownerExtra)
            if nargin < 2 || isempty(options), options = struct(); end
            if nargin < 3 || isempty(ownerExtra), ownerExtra = struct(); end
            lockPath = char(string(lockPath));
            recoverStale = logical(bms.core.DirectoryLeaseLock.getFieldDefault( ...
                options, 'recover_stale', false));
            staleHours = max(0, double(bms.core.DirectoryLeaseLock.getFieldDefault( ...
                options, 'stale_hours', 24)));
            token = char(java.util.UUID.randomUUID());

            acquired = false;
            for attempt = 1:2
                acquired = logical(java.io.File(lockPath).mkdir());
                if acquired
                    break;
                end
                if attempt == 1 && recoverStale
                    observation = bms.core.DirectoryLeaseLock.inspect(lockPath, staleHours);
                    if observation.stale
                        bms.core.DirectoryLeaseLock.removeObservedStaleLock( ...
                            lockPath, observation, staleHours);
                        continue;
                    end
                end
            end
            if ~acquired
                error('BMS:DirectoryLeaseLock:Locked', ...
                    'Another task owns the directory lease: %s', lockPath);
            end

            lease = ownerExtra;
            lease.schema_version = 1;
            lease.token = token;
            lease.created_at = char(datetime('now', ...
                'Format', 'yyyy-MM-dd HH:mm:ss'));
            lease.host = bms.core.DirectoryLeaseLock.localHostName();
            lease.pid = bms.core.DirectoryLeaseLock.currentPid();
            lease.lock_path = lockPath;
            try
                bms.core.Logger.writeJson(fullfile(lockPath, 'owner.json'), lease);
            catch ME
                % We created this directory and no valid owner was published.
                % Remove it so a transient owner-write error cannot wedge all
                % future runs.
                try
                    if isfolder(lockPath), rmdir(lockPath, 's'); end
                catch
                end
                rethrow(ME);
            end
            cleanup = onCleanup(@() ...
                bms.core.DirectoryLeaseLock.release(lockPath, token));
        end

        function release(lockPath, token)
            %RELEASE Fail closed unless owner.json still names this token.
            lockPath = char(string(lockPath));
            if ~isfolder(lockPath), return; end
            try
                ownerPath = fullfile(lockPath, 'owner.json');
                if ~isfile(ownerPath), return; end
                owner = jsondecode(fileread(ownerPath));
                if ~isfield(owner, 'token') ...
                        || ~strcmp(char(string(owner.token)), char(string(token)))
                    return;
                end
                rmdir(lockPath, 's');
            catch
                % Cleanup is best effort. A mismatched or unreadable owner is
                % deliberately preserved instead of risking another task.
            end
        end

        function observation = inspect(lockPath, staleHours)
            if nargin < 2, staleHours = 24; end
            lockPath = char(string(lockPath));
            observation = struct( ...
                'stale', false, ...
                'owner_signature', bms.core.DirectoryLeaseLock.ownerSignature(lockPath), ...
                'reason', 'active_or_recent');
            if ~isfolder(lockPath)
                observation.reason = 'missing';
                return;
            end

            ownerPath = fullfile(lockPath, 'owner.json');
            try
                owner = jsondecode(fileread(ownerPath));
                sameHost = isfield(owner, 'host') && strcmpi( ...
                    char(string(owner.host)), ...
                    bms.core.DirectoryLeaseLock.localHostName());
                validPid = isfield(owner, 'pid') && isscalar(owner.pid) ...
                    && isfinite(double(owner.pid)) && double(owner.pid) > 0 ...
                    && double(owner.pid) == floor(double(owner.pid));
                if sameHost && validPid
                    pid = double(owner.pid);
                    if pid == bms.core.DirectoryLeaseLock.currentPid()
                        observation.stale = false;
                        observation.reason = 'same_host_live_pid';
                        return;
                    elseif ispc
                        observation.stale = ...
                            ~bms.core.DirectoryLeaseLock.isProcessAlive(pid);
                        if observation.stale
                            observation.reason = 'same_host_dead_pid';
                        else
                            observation.reason = 'same_host_live_pid';
                        end
                        return;
                    else
                        % On platforms where this helper has no reliable PID
                        % probe, a valid same-host owner fails closed instead of
                        % becoming reclaimable merely because it is old.
                        observation.reason = 'same_host_pid_unverifiable';
                        return;
                    end
                end
            catch
                % Missing/malformed and foreign-host owners are handled by the
                % explicit age policy below.
            end

            ageHours = bms.core.DirectoryLeaseLock.lockAgeHours(lockPath);
            observation.stale = ageHours >= max(0, double(staleHours));
            if observation.stale
                observation.reason = 'old_unknown_owner';
            end
        end

        function alive = isProcessAlive(pid)
            alive = false;
            if ~isfinite(pid) || pid <= 0 || pid ~= floor(pid)
                return;
            end
            if pid == bms.core.DirectoryLeaseLock.currentPid()
                alive = true;
                return;
            end
            if ispc
                try
                    process = System.Diagnostics.Process.GetProcessById(int32(pid));
                    alive = ~logical(process.HasExited);
                catch
                    alive = false;
                end
            end
        end

        function pid = currentPid()
            try
                pid = double(feature('getpid'));
            catch
                pid = NaN;
            end
        end

        function host = localHostName()
            try
                host = char(java.net.InetAddress.getLocalHost().getHostName());
            catch
                host = char(string(getenv('COMPUTERNAME')));
            end
        end
    end

    methods (Static, Access = private)
        function removeObservedStaleLock(lockPath, observation, staleHours)
            % Re-inspect immediately before removal. This is not an atomic
            % compare-and-delete primitive, but the owner signature plus the
            % second liveness decision closes stale observations and keeps the
            % operation fail closed when ownership changes.
            guardPath = [char(string(lockPath)) '.recovery_guard'];
            guardFile = java.io.File(guardPath);
            if ~logical(guardFile.createNewFile())
                return;
            end
            guardCleanup = onCleanup(@() ...
                bms.core.DirectoryLeaseLock.deleteRecoveryGuard(guardPath)); %#ok<NASGU>
            current = bms.core.DirectoryLeaseLock.inspect(lockPath, staleHours);
            if current.stale ...
                    && strcmp(current.owner_signature, observation.owner_signature)
                try
                    rmdir(lockPath, 's');
                catch
                end
            end
        end

        function deleteRecoveryGuard(guardPath)
            if isfile(guardPath)
                try
                    delete(guardPath);
                catch
                end
            end
        end

        function signature = ownerSignature(lockPath)
            ownerPath = fullfile(char(string(lockPath)), 'owner.json');
            if ~isfile(ownerPath)
                signature = '<missing>';
                return;
            end
            try
                raw = fileread(ownerPath);
                bytes = uint8(unicode2native(raw, 'UTF-8'));
                md = java.security.MessageDigest.getInstance('SHA-256');
                md.update(bytes);
                digest = typecast(md.digest(), 'uint8');
                signature = lower(reshape(dec2hex(digest, 2).', 1, []));
            catch
                signature = '<unreadable>';
            end
        end

        function ageHours = lockAgeHours(lockPath)
            info = dir(char(string(lockPath)));
            if isempty(info)
                ageHours = 0;
                return;
            end
            ageHours = hours(datetime('now') - ...
                datetime(info(1).datenum, 'ConvertFrom', 'datenum'));
        end

        function value = getFieldDefault(s, name, defaultValue)
            if isstruct(s) && isfield(s, name)
                value = s.(name);
            else
                value = defaultValue;
            end
        end
    end
end
