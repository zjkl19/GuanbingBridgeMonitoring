classdef test_reporting_contract < matlab.unittest.TestCase
    methods (Test)
        function contractCapturesModuleOutputs(tc)
            cfg = load_config(fullfile(project_root(), 'tests', 'config', 'layered_bridge_project.json'));
            opts = struct('doDeflect', true);

            contract = bms.reporting.AnalysisReportingContract.build(cfg, opts);

            tc.verifyEqual(contract.summary.module_count, 1);
            rec = contract.modules{1};
            tc.verifyEqual(rec.key, 'deflection');
            tc.verifyEqual(rec.point_count, 1);
            tc.verifyEqual(rec.points, {'D-1'});
            tc.verifyEqual(rec.subfolder, 'features');
            tc.verifyEqual(rec.config.per_point_key, 'deflection');
            tc.verifyEqual(rec.stats_file, 'deflection_stats.xlsx');
        end

        function contractCapturesOutputDirRecords(tc)
            cfg = load_config(fullfile(project_root(), 'tests', 'config', 'layered_bridge_project.json'));
            cfg.plot_styles.deflection.output_dir = 'deflection';
            cfg.plot_styles.deflection.group_output_dir = 'deflection_group';
            opts = struct('doDeflect', true);

            contract = bms.reporting.AnalysisReportingContract.build(cfg, opts);

            rec = contract.modules{1};
            tc.verifyEqual(rec.output_dirs, {'deflection_原始', 'deflection_滤波', 'deflection_group_原始', 'deflection_group_滤波'});
            tc.verifyEqual({rec.output_dir_records.role}, {'raw_plot', 'filtered_plot', 'raw_group_plot', 'filtered_group_plot'});
            tc.verifyEqual({rec.output_dir_records.field}, {'raw_output_dir', 'filtered_output_dir', 'raw_group_output_dir', 'filtered_group_output_dir'});
        end

        function climateRuntimeDefaultsPopulateContractPointCounts(tc)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_dir(root)); %#ok<NASGU>
            cfg = struct();
            opts = struct('doTemp', true, 'doHumidity', true);

            result = bms.app.RunPreflight.check( ...
                root, '2026-03-01', '2026-03-02', opts, cfg);
            contract = result.reporting_contract;

            keys = cellfun(@(rec) rec.key, contract.modules, 'UniformOutput', false);
            temp = contract.modules{strcmp(keys, 'temperature')};
            humidity = contract.modules{strcmp(keys, 'humidity')};
            tc.verifyEqual(temp.points, ...
                {'GB-RTS-G05-001-01','GB-RTS-G05-001-02','GB-RTS-G05-001-03'});
            tc.verifyEqual(humidity.points, ...
                {'GB-RHS-G05-001-01','GB-RHS-G05-001-02','GB-RHS-G05-001-03'});
            tc.verifyEqual(temp.point_count, 3);
            tc.verifyEqual(humidity.point_count, 3);
            tc.verifyEqual(temp.points_source, 'runtime_default');
            tc.verifyEqual(humidity.points_source, 'runtime_default');
            tc.verifyEqual(contract.summary.point_count, 6);
            tc.verifyEmpty(result.errors);
        end

        function climateContractPreservesConfiguredAndExplicitEmptySemantics(tc)
            cfg = struct();
            cfg.points = struct();
            cfg.points.temperature = {'T-1'};
            cfg.points.temp_humidity = {'TH-1'};
            cfg.points.humidity = {};
            opts = struct('doTemp', true, 'doHumidity', true);

            contract = bms.reporting.AnalysisReportingContract.build(cfg, opts);

            keys = cellfun(@(rec) rec.key, contract.modules, 'UniformOutput', false);
            temp = contract.modules{strcmp(keys, 'temperature')};
            humidity = contract.modules{strcmp(keys, 'humidity')};
            tc.verifyEqual(temp.points, {'T-1', 'TH-1'});
            tc.verifyEqual(temp.points_source, 'configured');
            tc.verifyEqual(humidity.points, {'TH-1'});
            tc.verifyEqual(humidity.points_source, 'configured');

            cfg.points.temp_humidity = {};
            contract = bms.reporting.AnalysisReportingContract.build(cfg, opts);
            keys = cellfun(@(rec) rec.key, contract.modules, 'UniformOutput', false);
            humidity = contract.modules{strcmp(keys, 'humidity')};
            tc.verifyEmpty(humidity.points);
            tc.verifyEqual(humidity.point_count, 0);
            tc.verifyEqual(humidity.points_source, 'explicit_empty');
        end

        function preflightAttachesReportingContract(tc)
            root = tempname;
            mkdir(root);
            cleanup = onCleanup(@() cleanup_dir(root)); %#ok<NASGU>
            cfg = load_config(fullfile(project_root(), 'tests', 'config', 'layered_bridge_project.json'));
            opts = struct('doDeflect', true);

            result = bms.app.RunPreflight.check(root, '2026-03-01', '2026-03-02', opts, cfg);

            tc.verifyTrue(isfield(result, 'reporting_contract'));
            tc.verifyEqual(result.reporting_contract.summary.module_count, 1);
            tc.verifyEmpty(result.errors);
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
