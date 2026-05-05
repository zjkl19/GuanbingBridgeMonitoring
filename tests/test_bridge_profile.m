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

            p = bms.profile.BridgeProfileRegistry.fromId('hongtang');
            tc.verifyEqual(p.DataLayout, 'hongtang_period');
            tc.verifyTrue(p.configExists());
        end

        function registryInfersFromConfigSource(tc)
            cfg = struct('source', fullfile('D:', 'repo', 'config', 'jiulongjiang_config.json'));
            p = bms.profile.BridgeProfileRegistry.infer(cfg, 'E:\data');
            tc.verifyEqual(p.BridgeId, 'jiulongjiang');
        end
    end
end
