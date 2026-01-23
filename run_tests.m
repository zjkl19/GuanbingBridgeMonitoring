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
    here = fileparts(mfilename('fullpath'));
    proj = fileparts(here);
    addpath(fullfile(proj,'config'), fullfile(proj,'pipeline'), ...
            fullfile(proj,'analysis'), fullfile(proj,'tests'), proj);

    switch mode
        case "all"
            res = runtests;
        case "smoke"
            files = { ...
                'tests/test_simulated_data.m', ...
                'tests/test_load_timeseries_range.m', ...
                'test.m' ...
            };
            res = runtests(files);
        case "default"
            files = { ...
                'tests/test_simulated_data.m', ...
                'tests/test_load_timeseries_range.m', ...
                'tests/test_config_utils.m', ...
                'test.m' ...
            };
            res = runtests(files);
        case "custom"
            res = runtests(files);
        otherwise
            error('Unknown mode: %s', mode);
    end

    disp(res);
    if any(~[res.Passed])
        error('One or more tests failed.');
    end
end
