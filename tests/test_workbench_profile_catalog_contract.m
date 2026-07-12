classdef test_workbench_profile_catalog_contract < matlab.unittest.TestCase
    properties
        ProjectRoot
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(tc.ProjectRoot, fullfile(tc.ProjectRoot, 'config'), ...
                fullfile(tc.ProjectRoot, 'pipeline'), fullfile(tc.ProjectRoot, 'analysis'));
        end
    end

    methods (Test)
        function catalogHasSixClosedProfiles(tc)
            validation = bms.profile.BridgeProfileRegistry.validateCatalog(tc.ProjectRoot);
            tc.verifyEqual(validation.status, 'ok');
            tc.verifyEmpty(validation.errors);
            tc.verifyEmpty(validation.warnings);
            tc.verifyEqual(validation.profile_count, 6);
            tc.verifyEqual(validation.profile_ids, ...
                {'guanbing','hongtang','jiulongjiang','shuixianhua','chongyangxi','zhishan'});
        end

        function moduleAndReportCapabilityMatrixMatchesRuntime(tc)
            profiles = bms.profile.BridgeProfileRegistry.catalog(tc.ProjectRoot);
            specs = bms.module.ModuleRegistry.catalog();
            knownKeys = arrayfun(@(item) item.Key, specs, 'UniformOutput', false);
            reportTypes = {};
            analysisOnly = 0;
            for i = 1:numel(profiles)
                profile = profiles(i);
                tc.verifyTrue(isfile(profile.DefaultConfig), profile.BridgeId);
                tc.verifyTrue(all(ismember(profile.EnabledModuleHints, knownKeys)), profile.BridgeId);
                if strcmp(profile.DefaultReportType, 'analysis_only')
                    analysisOnly = analysisOnly + 1;
                    tc.verifyEmpty(profile.ReportGuiType);
                    tc.verifyEmpty(profile.DefaultReportTemplate);
                else
                    tc.verifyTrue(isfile(profile.DefaultReportTemplate), profile.BridgeId);
                    tc.verifyNotEmpty(profile.ReportGuiType);
                    reportTypes{end+1} = profile.ReportGuiType; %#ok<AGROW>
                end
            end
            tc.verifyEqual(analysisOnly, 1);
            tc.verifyEqual(sort(reportTypes), sort({ ...
                'guanbing_monthly','hongtang_period_wim','jlj_monthly', ...
                'shuixianhua_monthly','zhishan_monthly'}));
        end
    end
end
