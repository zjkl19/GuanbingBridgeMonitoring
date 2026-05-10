classdef test_wind_analysis_pipeline < matlab.unittest.TestCase
    properties
        ProjectRoot
    end

    methods (TestClassSetup)
        function addPaths(tc)
            tc.ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(tc.ProjectRoot, ...
                fullfile(tc.ProjectRoot, 'config'), ...
                fullfile(tc.ProjectRoot, 'pipeline'), ...
                fullfile(tc.ProjectRoot, 'analysis'));
        end
    end

    methods (Test)
        function bridgeConfigsResolveWindInputs(tc)
            configFiles = { ...
                'default_config.json', ...
                'hongtang_config.json', ...
                'jiulongjiang_config.json', ...
                'shuixianhua_config.json'};

            for i = 1:numel(configFiles)
                cfg = load_config(fullfile(tc.ProjectRoot, 'config', configFiles{i}));

                subfolder = bms.analyzer.WindAnalysisPipeline.resolveSubfolder(cfg);
                expectedSubfolder = bms.config.ConfigReader.getSubfolder(cfg, 'wind_raw', '波形');
                tc.verifyEqual(subfolder, expectedSubfolder, configFiles{i});

                points = bms.analyzer.WindAnalysisPipeline.resolvePoints(cfg);
                tc.verifyTrue(iscell(points), configFiles{i});

                style = bms.analyzer.WindAnalysisPipeline.style(cfg);
                tc.verifyNotEmpty(style.output.root_dir, configFiles{i});
                tc.verifyNotEmpty(style.output.speed_dir, configFiles{i});
                tc.verifyNotEmpty(style.output.direction_dir, configFiles{i});
                tc.verifyNotEmpty(style.output.speed10_dir, configFiles{i});
                tc.verifyNotEmpty(style.output.rose_dir, configFiles{i});
                tc.verifyNotEmpty(bms.analyzer.WindAnalysisPipeline.statsFileName(cfg), configFiles{i});

                params = bms.analyzer.WindAnalysisPipeline.params(cfg, 'W1');
                tc.verifyGreaterThan(params.window_minutes, 0, configFiles{i});
                tc.verifyGreaterThan(params.sector_deg, 0, configFiles{i});
                tc.verifyGreaterThan(numel(params.speed_bins), 1, configFiles{i});
            end
        end

        function perPointWindParamsOverrideDefaults(tc)
            cfg.wind_params = struct( ...
                'alarm_levels', [20 25 30], ...
                'window_minutes', 10, ...
                'decimals', 2, ...
                'speed_bins', [0 5 10], ...
                'sector_deg', 22.5);
            cfg.per_point.wind.W_1 = struct( ...
                'alarm_levels', [10 11], ...
                'window_minutes', 3, ...
                'decimals', 1, ...
                'speed_bins', [0 1 2 3], ...
                'sector_deg', 45);

            params = bms.analyzer.WindAnalysisPipeline.params(cfg, 'W-1');

            tc.verifyEqual(params.alarm_levels, [10 11]);
            tc.verifyEqual(params.window_minutes, 3);
            tc.verifyEqual(params.decimals, 1);
            tc.verifyEqual(params.speed_bins, [0 1 2 3]);
            tc.verifyEqual(params.sector_deg, 45);
        end

        function windAnalyzerUsesPipelineEntryPoint(tc)
            analyzer = bms.analyzer.WindAnalyzer('root', '2026-01-01', '2026-01-01', '', 'wave', struct());

            tc.verifyClass(analyzer, 'bms.analyzer.WindAnalyzer');
            tc.verifyEqual(analyzer.Key, 'wind');
        end
    end
end
