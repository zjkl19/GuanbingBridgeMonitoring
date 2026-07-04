classdef PreprocessStepFactory
    %PREPROCESSSTEPFACTORY Builds preprocessing steps for the legacy plan.

    methods (Static)
        function plan = append(plan, root, startDate, endDate, opts, cfg)
            if nargin < 6, cfg = struct(); end
            L = @(key) bms.module.ModuleRegistry.fromKey(key).isEnabled(opts);
            D = @bms.app.StepDefinition.fromKey;

            if L('zip_precheck')
                plan = plan.addRun(D('zip_precheck'), @() precheck_zip_count(root, startDate, endDate));
            end
            if L('unzip')
                plan = plan.addRun(D('unzip'), @() batch_unzip_data_parallel(root, startDate, endDate, true));
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
