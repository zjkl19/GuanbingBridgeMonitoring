classdef test_config_integration_regression < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            rootDir = project_root();
            addpath(rootDir);
            addpath(fullfile(rootDir, 'config'));
        end
    end

    methods (Test)
        function fourBridgeConfigsLoadLintAndBuildContracts(tc)
            rootDir = project_root();
            configPaths = { ...
                fullfile(rootDir, 'config', 'default_config.json'), ...
                fullfile(rootDir, 'config', 'hongtang_config.json'), ...
                fullfile(rootDir, 'config', 'jiulongjiang_config.json'), ...
                fullfile(rootDir, 'config', 'shuixianhua_config.json'), ...
                fullfile(rootDir, 'config', 'chongyangxi_config.json'), ...
                fullfile(rootDir, 'config', 'zhishan_config.json')};

            for i = 1:numel(configPaths)
                cfg = load_config(configPaths{i});
                lint = bms.config.ConfigLinter.lint(cfg);
                tc.verifyEmpty(lint.errors, ['lint errors in ' configPaths{i}]);

                contract = bms.reporting.AnalysisReportingContract.build(cfg, struct());
                tc.verifyGreaterThan(contract.summary.module_count, 0, ...
                    ['empty reporting contract for ' configPaths{i}]);

                root = tempname;
                mkdir(root);
                cleanup = onCleanup(@() cleanup_dir(root)); %#ok<NASGU>
                preflight = bms.app.RunPreflight.check(root, '2026-03-01', '2026-03-02', struct(), cfg);
                tc.verifyEmpty(preflight.errors, ['preflight errors in ' configPaths{i}]);
                tc.verifyTrue(isfield(preflight, 'reporting_contract'));
                clear cleanup;
            end
        end

        function hongtangQ2Sl8CleansNegativeValues(tc)
            rootDir = project_root();
            cfg = load_config(fullfile(rootDir, 'config', 'hongtang_config.json'));

            tc.verifyEqual(cfg.per_point.strain.SL_8.thresholds.min, 0);
            tc.verifyEqual(cfg.per_point.strain.SL_8.thresholds.max, 150);
            tc.verifyEqual(cfg.plot_common.dynamic_raw_sampling_mode, 'full');
            tc.verifyEqual(cfg.plot_common.dynamic_raw_line_width, 1.0);
            tc.verifyEqual(cfg.plot_common.gap_mode, 'connect');
            tc.verifyTrue(isfield(cfg.groups, 'cable_accel'));
            tc.verifyFalse(bms.analyzer.StructuralPlotConfigService.hasGroups(cfg.groups.cable_accel));

            accelRules = bms.data.CleaningPipeline.resolveRules( ...
                cfg, 'acceleration', 'A1');
            tc.verifyEqual(accelRules.thresholds.min, -0.5);
            tc.verifyEqual(accelRules.thresholds.max, 0.5);

            requested = struct('CS1', 1, 'CS6', 6, 'CS8', 2.6, ...
                'CS9', 1, 'CS11', 1, 'CS12', 2);
            names = fieldnames(requested);
            for i = 1:numel(names)
                rules = bms.data.CleaningPipeline.resolveRules( ...
                    cfg, 'cable_accel', names{i});
                tc.verifyEqual(rules.thresholds.min, -requested.(names{i}));
                tc.verifyEqual(rules.thresholds.max, requested.(names{i}));
            end

            cx6Rules = bms.data.CleaningPipeline.resolveRules( ...
                cfg, 'cable_accel', 'CX6');
            tc.verifyEqual(cx6Rules.thresholds.min, -3);
            tc.verifyEqual(cx6Rules.thresholds.max, 3);
            tc.verifyNumElements(cx6Rules.exclude_ranges, 1);
            tc.verifyEqual(cx6Rules.exclude_ranges.start_time, '2025-12-15 00:00:00');
            tc.verifyEqual(cx6Rules.exclude_ranges.end_time, '2025-12-31 23:59:59');

            style = bms.analyzer.DynamicAccelerationPipeline.plotStyle( ...
                cfg, bms.analyzer.DynamicAccelerationPipeline.spec('cable_accel'));
            tc.verifyTrue(style.ylim_auto);
            tc.verifyTrue(style.rms_ylim_auto);
            tc.verifyEmpty(style.ylim);
            tc.verifyEmpty(style.ylims);
            tc.verifyEmpty(style.rms_ylim);
            tc.verifyEmpty(style.rms_ylims);
        end

        function hongtangAccelerationSpectrumStartsAboveTheory(tc)
            rootDir = project_root();
            cfg = load_config(fullfile(rootDir, 'config', 'hongtang_config.json'));
            spec = bms.analyzer.SpectrumAnalysisPipeline.spec('accel_spectrum');
            pointIds = bms.analyzer.SpectrumConfigService.resolvePoints(cfg, spec);
            for i = 1:numel(pointIds)
                [~, ~, theorFreqs, ~, ~] = ...
                    bms.analyzer.SpectrumConfigService.pointParams( ...
                        cfg, pointIds{i}, spec, [], [], [], {});
                pt = bms.analyzer.SpectrumConfigService.pointConfig( ...
                    cfg, spec.perPointKey, pointIds{i});
                orders = pt.peak_orders;
                for j = 1:numel(orders)
                    tc.verifyGreaterThanOrEqual(orders(j).search_min_hz, ...
                        theorFreqs(j) + 0.05 - 1e-12);
                    tc.verifyLessThan(orders(j).search_min_hz, orders(j).search_max_hz);
                end
            end
        end
    end
end

function cleanup_dir(path)
    if isfolder(path)
        rmdir(path, 's');
    end
end

function root = project_root()
    root = fileparts(fileparts(mfilename('fullpath')));
end
