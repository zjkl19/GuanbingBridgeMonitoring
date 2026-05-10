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

            tc.verifyTrue(startsWith(string(temp.GuiLabel), "🌡"));
            tc.verifyTrue(startsWith(string(rain.GuiLabel), "🌧"));
            tc.verifyTrue(startsWith(string(wim.GuiLabel), "🚗"));
            tc.verifyEqual(wim.Label, 'WIM');
        end
    end
end
