classdef test_cleaning_pipeline < matlab.unittest.TestCase
    properties
        TempDir
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj);
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if exist(tc.TempDir, 'dir'), rmdir(tc.TempDir, 's'); end
        end
    end

    methods (Test)
        function resolvesDefaultAndPointRules(tc)
            cfg = struct();
            cfg.defaults.strain = struct('thresholds', struct('min', -10, 'max', 10), ...
                'zero_to_nan', true, 'offset_correction', 2);
            cfg.per_point.strain.PT_1 = struct('thresholds', struct('min', -5, 'max', 5), ...
                'offset_correction', 3);

            rules = bms.data.CleaningPipeline.resolveRules(cfg, 'strain', 'PT-1');
            tc.verifyEqual(numel(rules.thresholds), 2);
            tc.verifyTrue(rules.zero_to_nan);
            tc.verifyEqual(rules.offset_correction, 3);
        end

        function appliesOffsetThresholdsAndZero(tc)
            t = datetime(2026,1,1,0,0,0) + seconds(0:4)';
            v = [-2; 0; 2; 9; 100];
            rules = struct();
            rules.offset_correction = 1;
            rules.zero_to_nan = true;
            rules.outlier_window_sec = [];
            rules.outlier_threshold_factor = [];
            rules.thresholds = struct('min', 0, 'max', 10, ...
                't_range_start', '2026-01-01 00:00:00', ...
                't_range_end', '2026-01-01 00:00:04');

            [out, log] = bms.data.CleaningPipeline.apply(v, t, rules);
            tc.verifyTrue(isnan(out(1)));
            tc.verifyEqual(out(2), 1);
            tc.verifyEqual(out(3), 3);
            tc.verifyEqual(out(4), 10);
            tc.verifyTrue(isnan(out(5)));
            tc.verifyEqual(log.threshold_removed_count, 2);
            tc.verifyEqual(log.offset_correction, 1);
            tc.verifyEqual(log.final_nan_count, 2);
            tc.verifyEqual(log.final_count, 3);
        end

        function finalCountsExcludeInitialThresholdAndZeroNaNs(tc)
            t = datetime(2026,1,1,0,0,0) + seconds(0:4)';
            v = [NaN; 0; 2; 11; 5];
            rules = bms.data.CleaningPipeline.emptyRules();
            rules.zero_to_nan = true;
            rules.thresholds = struct('min', 0, 'max', 10);

            [out, log] = bms.data.CleaningPipeline.apply(v, t, rules);

            tc.verifyTrue(isnan(out(1)));
            tc.verifyTrue(isnan(out(2)));
            tc.verifyEqual(out(3), 2);
            tc.verifyTrue(isnan(out(4)));
            tc.verifyEqual(out(5), 5);
            tc.verifyEqual(log.initial_count, 5);
            tc.verifyEqual(log.initial_nan_count, 1);
            tc.verifyEqual(log.threshold_removed_count, 1);
            tc.verifyEqual(log.zero_removed_count, 1);
            tc.verifyEqual(log.final_nan_count, 3);
            tc.verifyEqual(log.final_count, 2);
        end

        function recordOffsetFailureEmitsWarning(tc)
            rules = bms.data.CleaningPipeline.emptyRules();
            rules.offset_correction = 1;
            opts = struct('record_offset', true);

            tc.verifyWarning(@() bms.data.CleaningPipeline.recordOffset({datetime(2026,1,1)}, [], rules, opts, 1), ...
                'CleaningPipeline:recordOffset');
        end

        function appliesFirstDayMeanOffsetWithinConfiguredRange(tc)
            t = [ ...
                datetime(2026,3,3,0,0,0) + hours(0:2), ...
                datetime(2026,3,4,0,0,0) + hours(0:1)]';
            v = [10; 12; 14; 16; 18];
            rules = bms.data.CleaningPipeline.emptyRules();
            rules.offset_correction = struct( ...
                'mode', 'first_day_mean', ...
                'start_date', '2026-03-01', ...
                'end_date', '2026-03-31');

            [out, log] = bms.data.CleaningPipeline.apply(v, t, rules);

            tc.verifyEqual(out(1:3), [-2; 0; 2], 'AbsTol', 1e-12);
            tc.verifyEqual(out(4:5), [4; 6], 'AbsTol', 1e-12);
            tc.verifyTrue(log.offset_applied);
            tc.verifyEqual(log.offset_correction, -12, 'AbsTol', 1e-12);
        end

        function appliesDailyMedianOffsetScaleBeforeThresholds(tc)
            t = [ ...
                datetime(2026,3,3,0,0,0) + minutes(0:2), ...
                datetime(2026,3,4,0,0,0) + minutes(0:2)]';
            v = [100; 102; 200; 200; 202; 400];
            rules = bms.data.CleaningPipeline.emptyRules();
            rules.offset_correction = struct('mode', 'daily_median');
            rules.value_scale = 0.01;
            rules.thresholds = struct('min', -1, 'max', 1);

            [out, log] = bms.data.CleaningPipeline.apply(v, t, rules);

            tc.verifyEqual(out(1:3), [-0.02; 0; 0.98], 'AbsTol', 1e-12);
            tc.verifyEqual(out(4:5), [-0.02; 0], 'AbsTol', 1e-12);
            tc.verifyTrue(isnan(out(6)));
            tc.verifyTrue(log.offset_applied);
            tc.verifyTrue(log.value_scale_applied);
            tc.verifyEqual(log.value_scale, 0.01, 'AbsTol', 1e-12);
            tc.verifyEqual(log.threshold_removed_count, 1);
        end

        function appliesFixedOffsetWithinConfiguredRange(tc)
            t = datetime(2026,3,31,0,0,0) + days(0:2)';
            v = [10; 10; 10];
            rules = bms.data.CleaningPipeline.emptyRules();
            rules.offset_correction = struct( ...
                'mode', 'fixed', ...
                'value', 5, ...
                'start_date', '2026-04-01', ...
                'end_date', '2026-04-30');

            [out, log] = bms.data.CleaningPipeline.apply(v, t, rules);

            tc.verifyEqual(out, [10; 15; 15], 'AbsTol', 1e-12);
            tc.verifyTrue(log.offset_applied);
            tc.verifyEqual(log.offset_correction, 5, 'AbsTol', 1e-12);
        end

        function dailyMedianOffsetKeepsInputShape(tc)
            t = datetime(2026,3,3,0,0,0) + minutes(0:2);
            v = [100 102 104];
            rules = bms.data.CleaningPipeline.emptyRules();
            rules.offset_correction = struct('mode', 'daily_median');

            out = bms.data.CleaningPipeline.apply(v, t, rules);

            tc.verifySize(out, size(v));
            tc.verifyEqual(out, [-2 0 2], 'AbsTol', 1e-12);
        end

        function minGreaterThanMaxCanFilterAllFiniteValues(tc)
            t = datetime(2026,1,1) + seconds(0:2)';
            v = [1; 2; 3];
            rules = bms.data.CleaningPipeline.emptyRules();
            rules.thresholds = struct('min', 1000, 'max', -1000);

            out = bms.data.CleaningPipeline.apply(v, t, rules);
            tc.verifyTrue(all(isnan(out)));
        end

        function timeSeriesLoaderReadsAndClips(tc)
            path = fullfile(tc.TempDir, 'series.csv');
            T = table( ...
                datetime(2026,1,1,0,0,0)' + minutes(0:2)', ...
                [1; 2; 3], ...
                'VariableNames', {'Time','Value'});
            writetable(T, path);

            series = bms.data.TimeSeriesLoader.readSeries(path, {'Value'}, '2026-01-01', '2026-01-01');
            tc.verifyEqual(series.sample_count, 3);
            tc.verifyEqual(series.valid_count, 3);
            tc.verifyEqual(series.value_column, 'Value');
            summary = bms.data.TimeSeriesLoader.summarize(series.time, series.value);
            tc.verifyEqual(summary.max_value, 3);
        end
    end
end
