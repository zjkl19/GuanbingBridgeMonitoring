classdef test_module_registry < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'config'), fullfile(proj, 'pipeline'), fullfile(proj, 'analysis'), fullfile(proj, 'scripts'));
        end
    end

    methods (Test)
        function registryDrivesStepDefinitions(tc)
            spec = bms.module.ModuleRegistry.fromKey('acceleration');
            tc.verifyEqual(spec.OptField, 'doAccel');
            tc.verifyEqual(spec.StatsFile, 'accel_stats.xlsx');
            tc.verifyTrue(spec.HighMemoryRisk);

            def = bms.app.StepDefinition.fromKey('acceleration');
            tc.verifyEqual(def.Label, spec.Label);
            tc.verifyEqual(def.StatsFile, spec.StatsFile);
        end

        function optionsAndExpectedStatsComeFromRegistry(tc)
            opts = struct('doAccel', true, 'doGNSS', true, 'doCrack', false);
            specs = bms.module.ModuleRegistry.enabledFromOptions(opts);
            tc.verifyEqual(arrayfun(@(s) s.Key, specs, 'UniformOutput', false), {'gnss', 'acceleration'});

            statsDir = fullfile(tempdir, 'stats_unit');
            expected = bms.module.ModuleRegistry.expectedStatsFiles(statsDir, opts);
            tc.verifyTrue(any(endsWith(expected, fullfile('stats_unit', 'gnss_stats.xlsx'))));
            tc.verifyTrue(any(endsWith(expected, fullfile('stats_unit', 'accel_stats.xlsx'))));
        end

        function cachePrebuildContractIsExplicitAndSafe(tc)
            spec = bms.module.ModuleRegistry.fromKey('cache_prebuild');
            tc.verifyEqual(spec.OptField, 'doCachePrebuild');
            tc.verifyEqual(spec.Label, '预生成分析缓存');
            tc.verifyEqual(spec.Category, 'preprocess');
            tc.verifyFalse(spec.BridgeScoped);
            tc.verifyTrue(contains(string(spec.Description), "已解压 CSV"));
            tc.verifyTrue(contains(string(spec.Description), "不删除源数据"));

            enabled = bms.module.ModuleRegistry.enabledKeys(struct('doCachePrebuild', true));
            tc.verifyEqual(enabled, {'cache_prebuild'});
            row = spec.toStruct('');
            tc.verifyEqual(row.description, spec.Description);
        end

        function manifestPreflightReportsMissingStats(tc)
            tmp = tempname;
            mkdir(tmp);
            cleanup = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>
            opts = struct('doTemp', true, 'doWIM', true);
            report = bms.module.ModuleRegistry.preflight(tmp, opts);
            tc.verifyEqual(numel(report), 1);
            tc.verifyEqual(report{1}.key, 'temperature');
            tc.verifyEqual(report{1}.status, 'missing');
        end

        function schemaValidatorWarnsUnknownModuleKeys(tc)
            cfg = struct('defaults', struct(), 'subfolders', struct(), 'file_patterns', struct(), 'points', struct(), 'plot_styles', struct());
            cfg.points.not_a_module = {'P1'};
            warns = bms.config.SchemaValidator.validate(cfg);
            tc.verifyTrue(any(contains(warns, 'points.not_a_module is not registered')));
        end

        function analysisModulesExposeIconGuiLabels(tc)
            temp = bms.module.ModuleRegistry.fromKey('temperature');
            rain = bms.module.ModuleRegistry.fromKey('rainfall');
            wim = bms.module.ModuleRegistry.fromKey('wim');
            gnss = bms.module.ModuleRegistry.fromKey('gnss');
            accel = bms.module.ModuleRegistry.fromKey('acceleration');
            cableAccel = bms.module.ModuleRegistry.fromKey('cable_accel');
            accelSpec = bms.module.ModuleRegistry.fromKey('accel_spectrum');
            cableSpec = bms.module.ModuleRegistry.fromKey('cable_accel_spectrum');
            wind = bms.module.ModuleRegistry.fromKey('wind');
            crack = bms.module.ModuleRegistry.fromKey('crack');
            strain = bms.module.ModuleRegistry.fromKey('strain');
            dynHigh = bms.module.ModuleRegistry.fromKey('dynamic_strain_highpass');
            dynLow = bms.module.ModuleRegistry.fromKey('dynamic_strain_lowpass');

            tc.verifyTrue(startsWith(string(temp.GuiLabel), "🌡"));
            tc.verifyTrue(startsWith(string(rain.GuiLabel), "🌧"));
            tc.verifyTrue(startsWith(string(wim.GuiLabel), "🚚"));
            tc.verifyTrue(startsWith(string(gnss.GuiLabel), "🛰"));
            tc.verifyTrue(startsWith(string(wind.GuiLabel), "🌀"));
            tc.verifyTrue(startsWith(string(accel.GuiLabel), "📈"));
            tc.verifyTrue(startsWith(string(cableAccel.GuiLabel), "〰"));
            tc.verifyTrue(startsWith(string(accelSpec.GuiLabel), "📶"));
            tc.verifyTrue(startsWith(string(cableSpec.GuiLabel), "📶"));
            tc.verifyTrue(startsWith(string(crack.GuiLabel), "⚡"));
            tc.verifyTrue(startsWith(string(strain.GuiLabel), "ε"));
            tc.verifyTrue(startsWith(string(dynHigh.GuiLabel), "ε~"));
            tc.verifyTrue(startsWith(string(dynLow.GuiLabel), "ε~"));
            tc.verifyFalse(startsWith(string(dynHigh.GuiLabel), "📈"));
            tc.verifyEqual(wim.Label, 'WIM');
        end

        function directChineseLabelsArePreserved(tc)
            cases = {
                'zip_precheck', '预检查压缩包数量'
                'unzip', '批量解压'
                'rename_csv', '批量重命名CSV'
                'remove_header', '批量去除表头'
                'cache_prebuild', '预生成分析缓存'
                'dynamic_strain_lowpass', '动应变分析（低通+箱线图）'
                'rename_crk', '裂缝重命名'
            };

            for k = 1:size(cases, 1)
                spec = bms.module.ModuleRegistry.fromKey(cases{k, 1});
                tc.verifyEqual(spec.Label, cases{k, 2});
            end
        end
    end
end
