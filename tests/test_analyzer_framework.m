classdef test_analyzer_framework < matlab.unittest.TestCase
    methods (TestMethodSetup)
        function setupPaths(~)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'analysis'), fullfile(proj, 'pipeline'));
        end
    end

    methods (Test)
        function analyzerResultRoundTripsToStruct(tc)
            started = datetime(2026, 1, 1, 0, 0, 0);
            ended = started + seconds(2);
            r = bms.analyzer.AnalyzerResult.ok('temperature', 'D:/x/temp_stats.xlsx', {'D:/x/a.jpg'}, {'warn'}, started, ended);
            s = r.toStruct();
            tc.verifyEqual(s.key, 'temperature');
            tc.verifyEqual(s.status, 'ok');
            tc.verifyEqual(s.stats_path, 'D:/x/temp_stats.xlsx');
            tc.verifyEqual(s.artifacts, {'D:/x/a.jpg'});
            tc.verifyEqual(s.artifact_count, 1);
            tc.verifyEqual(s.figure_count, 0);
            tc.verifyEqual(s.elapsed_sec, 2);
        end

        function factoryCreatesModuleAdapters(tc)
            sub = struct('temperature', 'features', 'humidity', 'features', ...
                'rainfall', 'features', 'gnss', 'features', 'deflection', 'features_rs', ...
                'bearing_displacement', 'features_rs', 'tilt', 'wave_rs', ...
                'crack', 'features', 'strain', 'features', 'wind_raw', 'features', ...
                'eq_raw', 'wave', 'acceleration', 'wave', 'cable_accel', 'wave', ...
                'acceleration_raw', 'wave', 'cable_accel_raw', 'wave', 'wim', 'WIM');
            keys = {'temperature','humidity','rainfall','gnss','deflection', ...
                'bearing_displacement','tilt','crack','strain','wind','earthquake', ...
                'acceleration','cable_accel','accel_spectrum','cable_accel_spectrum', ...
                'dynamic_strain_highpass','dynamic_strain_lowpass','wim'};
            for i = 1:numel(keys)
                a = bms.analyzer.AnalyzerFactory.create(keys{i}, 'D:/data', ...
                    '2026-01-01', '2026-01-02', 'D:/data/stats', sub, struct(), {'P1'});
                tc.verifyTrue(isa(a, 'bms.analyzer.BaseAnalyzer'));
                if strcmp(keys{i}, 'earthquake')
                    tc.verifyEqual(a.Key, 'earthquake');
                else
                    tc.verifyEqual(a.Key, keys{i});
                end
                expectedStats = bms.module.ModuleRegistry.fromKey(keys{i}).StatsFile;
                if ~isempty(expectedStats)
                    tc.verifyTrue(endsWith(a.StatsFile, expectedStats));
                else
                    tc.verifyEqual(a.StatsFile, '');
                end
            end
        end

        function stepExecutorCapturesAnalyzerResult(tc)
            step = bms.app.StepDefinition.fromKey('temperature');
            statsPath = fullfile(tempdir, 'temp_stats.xlsx');
            fcn = @() bms.analyzer.AnalyzerResult.ok('temperature', statsPath, {'a.jpg'}, {}, datetime('now'), datetime('now'));
            result = bms.app.StepExecutor.execute(step, fcn);
            tc.verifyEqual(result.Status, 'ok');
            tc.verifyEqual(result.StatsPath, statsPath);
            tc.verifyEqual(result.Artifacts, {'a.jpg'});
        end
    end
end
