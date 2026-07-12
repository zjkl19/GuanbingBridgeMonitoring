function tests = test_workbench_provenance_contract
tests = functiontests(localfunctions);
end

function testSharedFixtureClosesSourceInputAndPlottedCounts(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
path = fullfile(root, 'tests', 'fixtures', 'workbench_provenance_contract.json');
payload = jsondecode(fileread(path));
verifyEqual(testCase, payload.schema_version, 1);
verifyEqual(testCase, payload.file_stub, 'A1');
verifyEqual(testCase, numel(payload.series), 1);
series = payload.series(1);
verifyEqual(testCase, series.sampling_mode, 'full');
verifyFalse(testCase, series.reduction_applied);
verifyEqual(testCase, series.source.source_sample_count, series.input_count);
verifyEqual(testCase, series.source.finite_source_sample_count, series.finite_count);
verifyEqual(testCase, series.finite_count, series.plotted_finite_count);
verifyEqual(testCase, series.source.completeness_scope, 'required_export_contribution');
verifyTrue(testCase, islogical(series.source.internal_gap_coverage_assessed));
verifyEqual(testCase, series.source.calendar_day_count_requested, ...
    series.source.complete_day_count + series.source.incomplete_day_count);
verifyEqual(testCase, numel(series.source.incomplete_days), ...
    series.source.incomplete_day_count);
end
