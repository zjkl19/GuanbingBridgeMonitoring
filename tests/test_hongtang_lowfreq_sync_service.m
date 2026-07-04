classdef test_hongtang_lowfreq_sync_service < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'config'), fullfile(proj, 'pipeline'), fullfile(proj, 'analysis'), fullfile(proj, 'scripts'));
        end
    end

    methods (Test)
        function mapsWorkbookHeadersToJikangParameters(tc)
            opts = bms.data.HongtangLowFreqSyncService.optionsFromConfig(tempdir, struct());
            headers = {'SamplingTime', 'Z11-1', 'Q1-Z', 'Q1-H', 'SB-1'};
            sensors = [ ...
                localSensor('dev-a', 'Z11-1', 'pz', 1), ...
                localSensor('dev-a', 'Q1', 'pqz', 1), ...
                localSensor('dev-a', 'Q1', 'pqh', 2), ...
                localSensor('dev-b', 'SB-1', 'psb', 1)];

            map = bms.data.HongtangLowFreqSyncService.buildColumnMap(headers, sensors, opts);

            tc.verifyEqual(map(2).para_id, 'pz');
            tc.verifyEqual(map(2).round_digits, 4);
            tc.verifyEqual(map(3).para_id, 'pqz');
            tc.verifyEqual(map(4).para_id, 'pqh');
            tc.verifyEqual(map(5).para_id, 'psb');
        end

        function duplicateSamplesKeepLatestSystemTime(tc)
            rows = [ ...
                localSample('p1', '2026-04-01 00:00:00', '2026-04-01 00:00:02', '1.1'), ...
                localSample('p1', '2026-04-01 00:00:00', '2026-04-01 00:00:03', '2.2'), ...
                localSample('p2', '2026-04-01 01:00:00', '2026-04-01 01:00:00', '3.3')];

            [records, dropped] = bms.data.HongtangLowFreqSyncService.dedupeSamples(rows);
            keys = arrayfun(@(r) r.para_id, records, 'UniformOutput', false);
            idx = find(strcmp(keys, 'p1'), 1);

            tc.verifyEqual(dropped, 1);
            tc.verifyEqual(numel(records), 2);
            tc.verifyEqual(records(idx).value, 2.2);
        end
    end
end

function s = localSensor(deviceId, baseName, paraId, paramNum)
s = struct('device_id', deviceId, 'base_name', baseName, 'para_id', paraId, ...
    'param_num', paramNum, 'para_type', 1, 'unit', '', 'unit_name', '');
end

function s = localSample(paraId, collectTime, systemTime, value)
s = struct('paraId', paraId, 'collectTime', collectTime, 'systemTime', systemTime, 'paraValue', value);
end
