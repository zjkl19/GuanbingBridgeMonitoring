classdef test_dynamic_series_service < matlab.unittest.TestCase
    properties
        Root
    end

    methods (TestMethodSetup)
        function setupCase(tc)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'pipeline'), fullfile(proj, 'analysis'));
            tc.Root = tempname;
            mkdir(fullfile(tc.Root, '2026-01-01', 'wave'));
        end
    end

    methods (TestMethodTeardown)
        function cleanupCase(tc)
            if exist(tc.Root, 'dir')
                rmdir(tc.Root, 's');
            end
        end
    end

    methods (Test)
        function sampleRateFallsBackUnlessAutoDetectIsEnabled(tc)
            times = datetime(2026, 1, 1, 0, 0, 0) + seconds(0:4)';

            tc.verifyEqual(bms.analyzer.DynamicSeriesService.sampleRate(times, false, 100), 100);
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.sampleRate(times, true, 100), 1);
        end

        function rmsSeriesUsesCoverageThreshold(tc)
            times = datetime(2026, 1, 1, 0, 0, 0) + seconds(0:5)';
            vals = [1; NaN; NaN; 1; 1; 1];

            [rmsVals, rmsMax, tMax] = bms.analyzer.DynamicSeriesService.rmsSeries(times, vals, 1, 3 / 60, 0.7);

            tc.verifySize(rmsVals, size(vals));
            tc.verifyTrue(isnan(rmsVals(2)));
            tc.verifyEqual(rmsMax, 1);
            tc.verifyEqual(tMax, times(4));
        end

        function movingMeanSeriesMatchesWindWindowBehavior(tc)
            times = datetime(2026, 1, 1, 0, 0, 0) + seconds(0:5)';
            vals = [2; NaN; NaN; 4; 6; 8];

            [meanVals, meanMax, tMax] = bms.analyzer.DynamicSeriesService.movingMeanSeries(times, vals, 1, 3 / 60, 0.7);

            tc.verifySize(meanVals, size(vals));
            tc.verifyTrue(isnan(meanVals(2)));
            tc.verifyEqual(meanMax, 7);
            tc.verifyEqual(tMax, times(6));
        end

        function collectRecordLoadsStatsAndRmsPeak(tc)
            values = 2 * ones(601, 1);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'A1.csv'), values);
            cfg = dynamic_cfg();

            rec = bms.analyzer.DynamicSeriesService.collectRecord( ...
                tc.Root, 'wave', 'A1', '2026-01-01', '2026-01-01', cfg, 'acceleration', true, true);

            tc.verifyTrue(rec.has_data);
            tc.verifyEqual(rec.fs, 1);
            tc.verifyEqual(rec.mn, 2);
            tc.verifyEqual(rec.mx, 2);
            tc.verifyEqual(rec.av, 2);
            tc.verifyEqual(rec.rms_max, 2);
            tc.verifyFalse(isnat(rec.rms_time));
            tc.verifyEqual(numel(rec.vals), 601);
        end

        function dynamicStatsTableKeepsAnalyzerColumnNames(tc)
            rows = {'A1', 1, 2, 1.5, 0.5, datetime(2026, 1, 1, 0, 0, 0)};

            T = bms.analyzer.DynamicSeriesService.dynamicStatsTable(rows);

            tc.verifyEqual(T.Properties.VariableNames, ...
                {'PointID', 'Min', 'Max', 'Mean', 'RMS10minMax', 'RMSStartTime'});
        end

        function windStatsTableKeepsAnalyzerColumnNames(tc)
            rows = {'W1', 1, 3, 2, 2.5, datetime(2026, 1, 1, 0, 0, 0)};

            T = bms.analyzer.DynamicSeriesService.windStatsTable(rows);

            tc.verifyEqual(T.Properties.VariableNames, ...
                {'PointID', 'MinSpeed', 'MaxSpeed', 'MeanSpeed', 'Mean10minMax', 'Mean10minTime'});
        end
    end
end

function cfg = dynamic_cfg()
    cfg = struct();
    cfg.defaults = struct('header_marker', 'Time');
    cfg.subfolders = struct('acceleration', 'wave');
end

function write_series_csv(path, values)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid > 0, 'Failed to create test csv.');
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'Time,Value\n');
    base = datetime(2026, 1, 1, 0, 0, 0);
    for i = 1:numel(values)
        fprintf(fid, '%s,%.6f\n', datestr(base + seconds(i - 1), 'yyyy-mm-dd HH:MM:SS.FFF'), values(i));
    end
end
