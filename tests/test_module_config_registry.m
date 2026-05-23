classdef test_module_config_registry < matlab.unittest.TestCase
    methods (Test)
        function registryExposesPlotMetadata(tc)
            defs = bms.config.ModuleConfigRegistry.plotModuleDefs();
            values = {defs.value};

            tc.verifyTrue(any(strcmp(values, 'deflection')));
            wind = bms.config.ModuleConfigRegistry.fromKey('wind_speed');
            tc.verifyEqual(wind.style_key, 'wind');
            tc.verifyEqual(wind.section, 'speed');
            tc.verifyEqual(wind.point_key, 'wind');
            tc.verifyEqual(wind.per_point_key, 'wind_speed');
        end

        function aliasesCoverLegacyDynamicStrainName(tc)
            aliases = bms.config.ModuleConfigRegistry.aliasesForKey('dynamic_strain_highpass');

            tc.verifyTrue(any(strcmp(aliases, 'dynamic_strain_highpass')));
            tc.verifyTrue(any(strcmp(aliases, 'dynamic_strain')));
            tc.verifyTrue(any(strcmp(aliases, 'strain')));
        end

        function resolverReadsNestedPlotStyle(tc)
            cfg.plot_styles.wind.speed.ylabel = '风速 (m/s)';
            cfg.plot_styles.wind.speed.title_prefix = '风速时程';

            style = bms.config.ModuleConfigResolver.resolvePlotStyle( ...
                cfg, 'wind_speed', struct('ylabel', '默认', 'ylim_auto', true));

            tc.verifyEqual(style.ylabel, '风速 (m/s)');
            tc.verifyEqual(style.title_prefix, '风速时程');
            tc.verifyTrue(style.ylim_auto);
        end

        function resolverPrefersStrainTimeseriesGroups(tc)
            cfg.groups.strain_timeseries.G1 = {'S-1', 'S-2'};
            cfg.groups.strain.Legacy = {'OLD'};

            groups = bms.config.ModuleConfigResolver.resolveGroups(cfg, 'strain');

            tc.verifyTrue(isfield(groups, 'G1'));
            tc.verifyFalse(isfield(groups, 'Legacy'));
            tc.verifyEqual(groups.G1(:), {'S-1'; 'S-2'});
        end
    end
end
