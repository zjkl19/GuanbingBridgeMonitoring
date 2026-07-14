classdef test_workbench_task_history_contract < matlab.unittest.TestCase
    methods (Test)
        function sharedStatusFixtureKeepsStableJsonNames(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            fixturePath = fullfile(root, 'tests', 'fixtures', 'workbench_task_history_contract.json');
            payload = jsondecode(fileread(fixturePath));

            testCase.verifyEqual(payload.schema_version, 1);
            testCase.verifyEqual(payload.analysis_status.status, 'running');
            testCase.verifyEqual(payload.analysis_status.current_module_key, 'cable_acceleration');
            testCase.verifyEqual(payload.analysis_status.current_module_label, '索力加速度');
            testCase.verifyEqual(payload.analysis_status.completed_modules, 7);
            testCase.verifyEqual(payload.analysis_status.module_total, 11);
            testCase.verifyEqual(payload.analysis_status.progress_fraction, 0.64, 'AbsTol', 1e-12);
            testCase.verifyEqual(payload.report_status.state, 'completed');
            testCase.verifyEqual(payload.report_status.stage, 'qc');
            testCase.verifyNotEmpty(payload.report_status.result_path);
            testCase.verifyEqual(payload.report_result.state, 'completed');
            testCase.verifyNotEmpty(payload.report_result.report_path);
            testCase.verifyNotEmpty(payload.report_result.pdf_path);
            testCase.verifyEqual(payload.report_result.qc.status, 'passed');
        end
    end
end
