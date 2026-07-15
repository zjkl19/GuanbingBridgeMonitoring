classdef test_bridge_profile < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj);
        end
    end

    methods (Test)
        function registryReturnsKnownProfiles(tc)
            profiles = bms.profile.BridgeProfileRegistry.catalog();
            ids = arrayfun(@(p) p.BridgeId, profiles, 'UniformOutput', false);
            tc.verifyTrue(ismember('guanbing', ids));
            tc.verifyTrue(ismember('hongtang', ids));
            tc.verifyTrue(ismember('jiulongjiang', ids));
            tc.verifyTrue(ismember('zhishan', ids));

            p = bms.profile.BridgeProfileRegistry.fromId('hongtang');
            tc.verifyEqual(p.DataLayout, 'hongtang_period');
            tc.verifyTrue(p.configExists());
            tc.verifyEqual(p.BridgeName, '洪塘大桥');
            tc.verifyNotEmpty(p.DefaultDataRoot);
            tc.verifyTrue(contains(p.wimDirForRoot('E:\洪塘大桥数据\2026年1-3月'), 'WIM'));

            z = bms.profile.BridgeProfileRegistry.fromId('zhishan');
            tc.verifyEqual(z.DataLayout, 'dated_folders');
            tc.verifyEqual(z.DefaultReportType, 'monthly');
            tc.verifyTrue(contains(z.DefaultReportTemplate, '0609_1652'));
            tc.verifyTrue(contains(z.DefaultDataRoot, '2026年3月'));
            tc.verifyFalse(contains(z.DefaultDataRoot, '2026年1-3月'));
            tc.verifyTrue(z.configExists());
            tc.verifyTrue(ismember('cable_accel_spectrum', z.EnabledModuleHints));
            tc.verifyTrue(ismember('dynamic_strain_lowpass', z.EnabledModuleHints));
            tc.verifyFalse(ismember('cable_force', z.EnabledModuleHints));
            tc.verifyEqual(z.OptionalModuleHints, {'cache_prebuild'});
        end

        function registryInfersFromConfigSource(tc)
            cfg = struct('source', fullfile('D:', 'repo', 'config', 'jiulongjiang_config.json'));
            p = bms.profile.BridgeProfileRegistry.infer(cfg, 'E:\data');
            tc.verifyEqual(p.BridgeId, 'jiulongjiang');

            cfg = struct('vendor', 'zhishan');
            p = bms.profile.BridgeProfileRegistry.infer(cfg, 'D:\芝山大桥数据\2026年3月');
            tc.verifyEqual(p.BridgeId, 'zhishan');
        end

        function registryInfersJiulongjiangFromVendor(tc)
            cfg = struct('vendor', 'jiulongjiang');
            p = bms.profile.BridgeProfileRegistry.infer(cfg, 'E:\isolated-candidate');
            tc.verifyEqual(p.BridgeId, 'jiulongjiang');
        end

        function legacyMachineConfigPatternCannotOverrideCanonicalConfig(tc)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
            canonical = fullfile(root, 'canonical.json');
            legacy = fullfile(root, 'legacy_HOST.json');
            fclose(fopen(canonical, 'w'));
            fclose(fopen(legacy, 'w'));
            raw = struct( ...
                'bridge_id', 'demo', ...
                'bridge_name', 'Demo', ...
                'default_config', 'canonical.json', ...
                'machine_config_pattern', 'legacy_HOST.json');

            profile = bms.profile.BridgeProfile.fromStruct(raw, root);

            tc.verifyEqual(profile.DefaultConfig, canonical);
            tc.verifyFalse(isfield(profile.toStruct(), 'machine_config_pattern'));
        end
    end
end
