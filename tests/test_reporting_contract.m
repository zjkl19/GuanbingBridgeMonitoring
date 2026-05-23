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
