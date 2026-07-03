classdef test_path_profile_resolver < matlab.unittest.TestCase
    properties
        TempRoot
        OldEnv
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TempRoot = tempname;
            mkdir(fullfile(tc.TempRoot, 'config'));
            tc.OldEnv = getenv('GUANBING_PATH_PROFILE');
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'config'), fullfile(proj, 'pipeline'), ...
                fullfile(proj, 'analysis'));
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            setenv('GUANBING_PATH_PROFILE', tc.OldEnv);
            if exist(tc.TempRoot, 'dir')
                rmdir(tc.TempRoot, 's');
            end
        end
    end

    methods (Test)
        function envSelectedProfileOverridesBridgeRoot(tc)
            tc.writeProfiles(struct( ...
                'profile_id', 'unit_remote', ...
                'hostnames', {{'UNIT-HOST'}}, ...
                'data_roots', struct('zhishan', 'X:/Zhishan/2026'), ...
                'path_replacements', struct('from', 'D:/Source', 'to', 'F:/Source'), ...
                'ignored_extra_field', 'ignored'));
            setenv('GUANBING_PATH_PROFILE', 'unit_remote');

            root = bms.profile.PathProfileResolver.resolveDataRoot('zhishan', 'D:/Source/old', tc.TempRoot);

            tc.verifyEqual(root, fullfile('X:', 'Zhishan', '2026'));
        end

        function replacementUsesPathBoundary(tc)
            tc.writeProfiles(struct( ...
                'profile_id', 'unit_remote', ...
                'hostnames', {{'UNIT-HOST'}}, ...
                'data_roots', struct(), ...
                'path_replacements', struct('from', 'D:/Source', 'to', 'F:/Source')));
            setenv('GUANBING_PATH_PROFILE', 'unit_remote');

            replaced = bms.profile.PathProfileResolver.resolveDataRoot('hongtang', 'D:/Source/2026-03', tc.TempRoot);
            notReplaced = bms.profile.PathProfileResolver.resolveDataRoot('hongtang', 'D:/SourceExtra/2026-03', tc.TempRoot);

            tc.verifyEqual(replaced, fullfile('F:', 'Source', '2026-03'));
            tc.verifyEqual(notReplaced, fullfile('D:', 'SourceExtra', '2026-03'));
        end

        function bridgeProfileAppliesActivePathProfile(tc)
            tc.writeProfiles(struct( ...
                'profile_id', 'unit_remote', ...
                'hostnames', {{'UNIT-HOST'}}, ...
                'data_roots', struct('zhishan', 'X:/Zhishan/202604'), ...
                'path_replacements', []));
            setenv('GUANBING_PATH_PROFILE', 'unit_remote');
            raw = struct('bridge_id', 'zhishan', ...
                'bridge_name', 'Zhishan', ...
                'default_config', '', ...
                'default_data_root', 'D:/Zhishan/202604');

            profile = bms.profile.BridgeProfile.fromStruct(raw, tc.TempRoot);

            tc.verifyEqual(profile.DefaultDataRoot, fullfile('X:', 'Zhishan', '202604'));
        end
    end

    methods (Access = private)
        function writeProfiles(tc, profile)
            payload = struct('profiles', profile);
            path = fullfile(tc.TempRoot, 'config', 'path_profiles.json');
            fid = fopen(path, 'w');
            tc.assertGreaterThan(fid, 0);
            cleaner = onCleanup(@() fclose(fid));
            fprintf(fid, '%s', jsonencode(payload));
            delete(cleaner);
        end
    end
end
