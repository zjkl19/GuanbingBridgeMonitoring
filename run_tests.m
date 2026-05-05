function run_tests(target)
% run_tests  Convenience wrapper to run project tests from CLI or MATLAB.
% Usage:
%   run_tests()                     % default subset (simulated + core)
%   run_tests('all')                % run all discovered tests (runtests)
%   run_tests('smoke')              % minimal fast set on fixtures
%   run_tests({'tests/test_simulated_data.m','test.m'})  % custom list
%
% Exits with error if any test fails (useful for CI / -batch).

    if nargin < 1 || isempty(target)
        mode = "default";
    elseif ischar(target) || isstring(target)
        mode = string(target);
    elseif iscell(target)
        mode = "custom";
        files = cellstr(target);
    else
        error('Unsupported target type.');
    end

    % Paths
    proj = fileparts(mfilename('fullpath'));
    addpath(fullfile(proj,'config'), fullfile(proj,'pipeline'), ...
            fullfile(proj,'analysis'), fullfile(proj,'tests'), proj);

    switch mode
        case "all"
            res = runtests(fullfile(proj, 'tests'));
        case "smoke"
            files = { ...
                'tests/test_simulated_data.m', ...
                'tests/test_load_timeseries_range.m' ...
            };
            res = runtests(existingTestFiles(files));
        case "default"
            files = { ...
                'tests/test_simulated_data.m', ...
                'tests/test_load_timeseries_range.m', ...
                'tests/test_config_utils.m', ...
                'tests/test_core_context.m', ...
                'tests/test_config_store.m', ...
                'tests/test_config_patch.m', ...
                'tests/test_config_migrator.m', ...
                'tests/test_bridge_profile.m', ...
                'tests/test_data_layout_resolver.m', ...
                'tests/test_cache_and_artifacts.m', ...
                'tests/test_run_request.m', ...
                'tests/test_run_preflight.m', ...
                'tests/test_manifest_reader.m', ...
                'tests/test_app_step_layer.m', ...
                'tests/test_bms_services.m', ...
                'tests/test_run_all_summary.m', ...
                'tests/test_bms_run_context.m' ...
            };
            res = runtests(existingTestFiles(files));
        case "custom"
            res = runtests(existingTestFiles(files));
        otherwise
            error('Unknown mode: %s', mode);
    end

    disp(res);
    if any(~[res.Passed])
        error('One or more tests failed.');
    end
end

function files = existingTestFiles(files)
    keep = true(size(files));
    for i = 1:numel(files)
        keep(i) = exist(files{i}, 'file') == 2;
    end
    files = files(keep);
end
