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
        function catalogHasAllConfiguredProfiles(tc)
            validation = bms.profile.BridgeProfileRegistry.validateCatalog(tc.ProjectRoot);
            raw = jsondecode(fileread(fullfile(tc.ProjectRoot, 'config', 'bridge_profiles.json')));
            rawProfiles = raw.profiles;
            if iscell(rawProfiles)
                expectedIds = cellfun(@(item) char(string(item.bridge_id)), ...
                    rawProfiles, 'UniformOutput', false);
            else
                expectedIds = arrayfun(@(item) char(string(item.bridge_id)), ...
                    rawProfiles, 'UniformOutput', false);
            end
            tc.verifyEqual(validation.status, 'ok');
            tc.verifyEmpty(validation.errors);
            tc.verifyEmpty(validation.warnings);
            tc.verifyEqual(validation.profile_count, numel(expectedIds));
            tc.verifyEqual(sort(validation.profile_ids(:)), sort(expectedIds(:)));
        end

        function fallbackCatalogKeepsAllConfiguredBridgeIds(tc)
            raw = jsondecode(fileread(fullfile(tc.ProjectRoot, 'config', 'bridge_profiles.json')));
            if iscell(raw.profiles)
                expectedIds = cellfun(@(item) char(string(item.bridge_id)), ...
                    raw.profiles, 'UniformOutput', false);
            else
                expectedIds = arrayfun(@(item) char(string(item.bridge_id)), ...
                    raw.profiles, 'UniformOutput', false);
            end
            fallback = bms.profile.BridgeProfileRegistry.fallback(tc.ProjectRoot);
            actualIds = arrayfun(@(profile) profile.BridgeId, fallback, ...
                'UniformOutput', false);

            tc.verifyEqual(sort(actualIds(:)), sort(expectedIds(:)));
        end

        function moduleAndReportCapabilityMatrixMatchesRuntime(tc)
            profiles = bms.profile.BridgeProfileRegistry.catalog(tc.ProjectRoot);
            specs = bms.module.ModuleRegistry.catalog();
            knownKeys = arrayfun(@(item) item.Key, specs, 'UniformOutput', false);
            raw = jsondecode(fileread(fullfile(tc.ProjectRoot, 'config', 'bridge_profiles.json')));
            reportTypes = {};
            analysisOnly = 0;
            for i = 1:numel(profiles)
                profile = profiles(i);
                tc.verifyTrue(isfile(profile.DefaultConfig), profile.BridgeId);
                tc.verifyTrue(all(ismember(profile.EnabledModuleHints, knownKeys)), profile.BridgeId);
                tc.verifyEqual(profile.OptionalModuleHints, {'cache_prebuild'}, profile.BridgeId);
                tc.verifyTrue(all(ismember(profile.OptionalModuleHints, knownKeys)), profile.BridgeId);
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
            expectedReportTypes = {};
            expectedAnalysisOnly = 0;
            for i = 1:numel(raw.profiles)
                if iscell(raw.profiles)
                    rawProfile = raw.profiles{i};
                else
                    rawProfile = raw.profiles(i);
                end
                if strcmp(char(string(rawProfile.report_type)), 'analysis_only')
                    expectedAnalysisOnly = expectedAnalysisOnly + 1;
                elseif isfield(rawProfile, 'report_gui_type') && ...
                        strlength(string(rawProfile.report_gui_type)) > 0
                    expectedReportTypes{end+1} = char(string(rawProfile.report_gui_type)); %#ok<AGROW>
                end
            end
            tc.verifyEqual(analysisOnly, expectedAnalysisOnly);
            tc.verifyEqual(sort(reportTypes), sort(expectedReportTypes));
        end
    end
end
