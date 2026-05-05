classdef test_timeseries_loader_service < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj);
        end
    end

    methods (Test)
        function detectsColumnsAndClipsRange(tc)
            tmp = tempname;
            mkdir(tmp);
            path = fullfile(tmp, 'sample.csv');
            Time = datetime(2026, 1, 1, 0, 0, 0) + days(0:2)';
            Value = [1; 2; 3];
            writetable(table(Time, Value), path);

            T = bms.data.TimeSeriesLoader.readCsv(path);
            [t, v] = bms.data.TimeSeriesLoader.columns(T, 'Value');
            [tcrop, vcrop] = bms.data.TimeSeriesLoader.clip(t, v, '2026-01-02', '2026-01-02');

            tc.verifyEqual(numel(tcrop), 1);
            tc.verifyEqual(vcrop, 2);
        end
    end
end
