classdef DailyExportMutationLock
    %DAILYEXPORTMUTATIONLOCK Re-entrant, cross-process lock for one data day.
    %   Extraction, cache publication and verified source cleanup all mutate
    %   the same daily-export directory.  This lock gives those operations a
    %   common exclusion domain.  Re-entry is allowed only inside the current
    %   MATLAB process so a streaming session can call ArchiveExtractService
    %   while retaining its outer day lease.

    methods (Static)
        function cleanup = acquire(outputRoot, day)
            outputRoot = bms.data.DailyExportMutationLock.canonicalPath(outputRoot);
            dayText = bms.data.TimeRangeResolver.toDateString(day);
            lockPath = bms.data.DailyExportMutationLock.pathFor(outputRoot, dayText);
            bms.data.DataLayoutResolver.ensureDir(fileparts(lockPath));
            key = lower(lockPath);
            bms.data.DailyExportMutationLock.registry( ...
                'acquire', key, lockPath, outputRoot, dayText);
            cleanup = onCleanup(@() ...
                bms.data.DailyExportMutationLock.registry( ...
                'release', key, lockPath, outputRoot, dayText));
        end

        function lockPath = pathFor(outputRoot, day)
            outputRoot = bms.data.DailyExportMutationLock.canonicalPath(outputRoot);
            dayText = bms.data.TimeRangeResolver.toDateString(day);
            safeDay = regexprep(dayText, '[^0-9]', '');
            lockPath = fullfile(outputRoot, ...
                '.bms_daily_export_mutation_locks', [safeDay '.lock']);
        end
    end

    methods (Static, Access = private)
        function registry(action, key, lockPath, outputRoot, dayText)
            persistent leases
            if isempty(leases)
                leases = containers.Map('KeyType', 'char', 'ValueType', 'any');
            end
            switch action
                case 'acquire'
                    if isKey(leases, key)
                        state = leases(key);
                        state.depth = state.depth + 1;
                        leases(key) = state;
                        return;
                    end
                    [underlying, lease] = bms.core.DirectoryLeaseLock.acquire( ...
                        lockPath, struct('recover_stale', true, ...
                        'stale_hours', 24), struct( ...
                        'service', 'bms.data.DailyExportMutationLock', ...
                        'purpose', 'daily_export_extract_cache_cleanup', ...
                        'output_root', outputRoot, 'day', dayText));
                    leases(key) = struct('depth', 1, ...
                        'cleanup', underlying, 'lease', lease);
                case 'release'
                    if ~isKey(leases, key), return; end
                    state = leases(key);
                    state.depth = state.depth - 1;
                    if state.depth > 0
                        leases(key) = state;
                        return;
                    end
                    remove(leases, key);
                    delete(state.cleanup);
                otherwise
                    error('BMS:DailyExportMutationLock:UnknownAction', ...
                        'Unknown lock registry action: %s', action);
            end
        end

        function value = canonicalPath(pathValue)
            try
                value = char(java.io.File(char(string(pathValue))).getCanonicalPath());
            catch
                value = char(string(pathValue));
            end
        end
    end
end
