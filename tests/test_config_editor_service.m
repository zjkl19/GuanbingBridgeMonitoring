classdef test_config_editor_service < matlab.unittest.TestCase
    methods (Test)
        function editorKeysUseConfiguredKnownModules(tc)
            cfg = struct();
            cfg.defaults = struct('header_marker', 1, 'deflection', struct(), 'unknown_block', struct());
            cfg.per_point = struct('strain', struct(), 'wind_raw', struct());
            cfg.points = struct('temperature', {{'T-1'}});

            keys = bms.gui.ConfigEditorService.editableModuleKeys(cfg, 'threshold');

            tc.verifyTrue(any(strcmp(keys, 'temperature')));
            tc.verifyTrue(any(strcmp(keys, 'deflection')));
            tc.verifyTrue(any(strcmp(keys, 'strain')));
            tc.verifyFalse(any(strcmp(keys, 'header_marker')));
            tc.verifyFalse(any(strcmp(keys, 'unknown_block')));
        end

        function postFilterKeysAreLimitedToSupportedModules(tc)
            cfg = struct();
            cfg.defaults = struct('deflection', struct(), 'strain', struct(), ...
                'bearing_displacement', struct(), 'dynamic_strain_lowpass', struct());

            keys = bms.gui.ConfigEditorService.editableModuleKeys(cfg, 'post_filter');

            tc.verifyEqual(keys(:)', {'dynamic_strain_lowpass', 'deflection', 'bearing_displacement'});
            tc.verifyFalse(any(strcmp(keys, 'strain')));
        end
    end
end
