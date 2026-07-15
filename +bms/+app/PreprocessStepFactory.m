classdef PreprocessStepFactory
    %PREPROCESSSTEPFACTORY Builds preprocessing steps for the legacy plan.

    methods (Static)
        function plan = append(plan, root, startDate, endDate, opts, cfg)
            if nargin < 6, cfg = struct(); end
            L = @(key) bms.module.ModuleRegistry.fromKey(key).isEnabled(opts);
            D = @bms.app.StepDefinition.fromKey;
            streamCleanup = bms.data.VerifiedSourceCsvCleanupService.isEnabled(opts) ...
                && L('unzip') && L('cache_prebuild');
            cleanupSession = [];
            if streamCleanup
                cleanupSession = bms.data.DailyArchiveCacheCleanupSession( ...
                    root, startDate, endDate, cfg, opts);
            end

            if L('zip_precheck')
                plan = plan.addRun(D('zip_precheck'), @() precheck_zip_count(root, startDate, endDate, cfg));
            end
            if L('unzip')
                if streamCleanup
                    plan = plan.addRun(D('unzip'), @() cleanupSession.runExtraction());
                else
                    plan = plan.addRun(D('unzip'), @() batch_unzip_data_parallel(root, startDate, endDate, true, cfg));
                end
            end
            if L('cache_prebuild')
                if streamCleanup
                    plan = plan.addRun(D('cache_prebuild'), @() cleanupSession.cacheResult());
                else
                    plan = plan.addRun(D('cache_prebuild'), ...
                        @() bms.data.CachePrebuildService.run( ...
                            root, startDate, endDate, cfg, opts));
                end
            end
            if L('rename_csv')
                plan = plan.addRun(D('rename_csv'), @() batch_rename_csv(root, startDate, endDate, true));
            end
            if L('remove_header')
                plan = plan.addRun(D('remove_header'), @() batch_remove_header(root, startDate, endDate, true));
            end
            if L('resample')
                plan = plan.addRun(D('resample'), @() batch_resample_data_parallel( ...
                    root, startDate, endDate, 100, true, 'batch_resample_data_parallel_config.csv'));
            end
            if L('lowfreq_sync')
                plan = plan.addRun(D('lowfreq_sync'), ...
                    @() bms.data.HongtangLowFreqSyncService.run(root, startDate, endDate, cfg));
            end
        end
    end
end
