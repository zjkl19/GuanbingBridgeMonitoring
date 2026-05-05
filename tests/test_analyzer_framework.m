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
            tc.verifyEqual(s.elapsed_sec, 2);
        end

        function factoryCreatesLowRiskAdapters(tc)
            sub = struct('temperature', 'features', 'humidity', 'features', ...
                'rainfall', 'features', 'deflection', 'features_rs', 'crack', 'features');
            keys = {'temperature','humidity','rainfall','deflection','crack'};
            for i = 1:numel(keys)
                a = bms.analyzer.AnalyzerFactory.create(keys{i}, 'D:/data', ...
                    '2026-01-01', '2026-01-02', 'D:/data/stats', sub, struct(), {'P1'});
                tc.verifyTrue(isa(a, 'bms.analyzer.BaseAnalyzer'));
                tc.verifyEqual(a.Key, keys{i});
                tc.verifyTrue(endsWith(a.StatsFile, bms.module.ModuleRegistry.fromKey(keys{i}).StatsFile));
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
