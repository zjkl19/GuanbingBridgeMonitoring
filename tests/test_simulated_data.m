classdef test_simulated_data < matlab.unittest.TestCase
    % Smoke tests on deterministic, self-contained synthetic fixtures.
    %
    % Keep these fixtures local to the test.  The historical tests/data
    % calendar-day folders are intentionally gitignored and therefore are
    % not available in a clean checkout or release worktree.
    properties
        Root
        Cfg
    end

    properties (Constant)
        Date0 = '2025-01-01';
        Date1 = '2025-01-02';
    end

    methods (TestMethodSetup)
        function createFixtures(tc)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(projectRoot, ...
                fullfile(projectRoot, 'pipeline'), ...
                fullfile(projectRoot, 'config'));

            tc.Root = tempname;
            mkdir(tc.Root);
            tc.Cfg = load_config(fullfile(projectRoot, 'tests', 'config', 'test_config.json'));
            tc.Cfg.vendor = 'donghua';
            tc.Cfg.defaults.header_marker = '[ABSOLUTE_TIME]';
            tc.Cfg.defaults.deflection.outlier = [];
            tc.Cfg.subfolders.deflection = 'features_resampled';
            tc.Cfg.subfolders.strain = 'features';
            tc.Cfg.subfolders.acceleration = 'wave_resampled';
            tc.Cfg.file_patterns.deflection = tc.exactPattern();
            tc.Cfg.file_patterns.strain = tc.exactPattern();
            tc.Cfg.file_patterns.acceleration = tc.exactPattern();

            for dayIndex = 0:1
                day = datetime(2025, 1, 1) + days(dayIndex);
                dayDir = fullfile(tc.Root, datestr(day, 'yyyy-mm-dd'));

                deflection = linspace(5, 10.5, 12)';
                deflection([4, 8]) = [35; -12];
                tc.writeSeries(fullfile(dayDir, tc.Cfg.subfolders.deflection, ...
                    'GB-DIS-G05-001-01Y.csv'), ...
                    day + minutes(0:10:110)', deflection);

                strain = (-50:2:-12)';
                strain([6, 11]) = [450; -500];
                tc.writeSeries(fullfile(dayDir, tc.Cfg.subfolders.strain, ...
                    'GB-RSG-G05-001-01.csv'), ...
                    day + minutes(0:5:95)', strain);

                acceleration = repmat([-1; 1], 50, 1);
                tc.writeSeries(fullfile(dayDir, tc.Cfg.subfolders.acceleration, ...
                    'GB-VIB-G05-001-01.csv'), ...
                    day + seconds((0:99)' * 0.05), acceleration);
            end
        end
    end

    methods (TestMethodTeardown)
        function removeFixtures(tc)
            if ~isempty(tc.Root) && isfolder(tc.Root)
                rmdir(tc.Root, 's');
            end
        end
    end

    methods (Test)
        function deflectionThresholds(tc)
            [~, v] = load_timeseries_range(tc.Root, tc.Cfg.subfolders.deflection, ...
                'GB-DIS-G05-001-01Y', tc.Date0, tc.Date1, tc.Cfg, 'deflection');
            tc.verifyNumElements(v, 24, 'Should merge two days (12 each).');
            tc.verifyEqual(nnz(isnan(v)), 4, 'Out-of-range values should be NaN.');
            tc.verifyLessThanOrEqual(max(v,[],'omitnan'), 31);
            tc.verifyGreaterThanOrEqual(min(v,[],'omitnan'), -10);
        end

        function strainOutlier(tc)
            [~, v] = load_timeseries_range(tc.Root, tc.Cfg.subfolders.strain, ...
                'GB-RSG-G05-001-01', tc.Date0, tc.Date1, tc.Cfg, 'strain');
            tc.verifyNumElements(v, 40, 'Two days, 20 rows each.');
            tc.verifyEqual(nnz(isnan(v)), 4, 'Out-of-range strain should be NaN.');
            tc.verifyTrue(all(v(isfinite(v)) >= -400 & v(isfinite(v)) <= 200));
        end

        function accelBasic(tc)
            [times, vals] = load_timeseries_range(tc.Root, tc.Cfg.subfolders.acceleration, ...
                'GB-VIB-G05-001-01', tc.Date0, tc.Date1, tc.Cfg, 'acceleration');
            tc.verifyNumElements(vals, 200, 'Two days, 100 rows each.');
            % Sampling interval ~0.05 s within each daily segment.  Exclude
            % the expected overnight boundary before taking the median.
            dt = seconds(diff(times));
            dt = dt(dt < 1);
            tc.verifyLessThan(abs(median(dt) - 0.05), 1e-3);
            tc.verifyLessThan(abs(mean(vals, 'omitnan')), 0.2, 'Mean should be near zero.');
        end

        function headerMarker(tc)
            cfg = load_config(fullfile(fileparts(mfilename('fullpath')), 'config', 'test_config.json'));
            tc.verifyEqual(string(cfg.defaults.header_marker), "[绝对时间]");
        end
    end

    methods (Access = private)
        function pattern = exactPattern(~)
            pattern = struct('default', {{'{point}.csv'}}, 'per_point', struct());
        end

        function writeSeries(tc, path, times, values)
            folder = fileparts(path);
            if ~isfolder(folder)
                mkdir(folder);
            end
            fid = fopen(path, 'wt', 'n', 'UTF-8');
            tc.assertGreaterThan(fid, 0, sprintf('Could not create fixture: %s', path));
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, 'Dummy,Header\n%s,Value\n', tc.Cfg.defaults.header_marker);
            for i = 1:numel(values)
                fprintf(fid, '%s,%.12g\n', ...
                    datestr(times(i), 'yyyy-mm-dd HH:MM:SS.FFF'), values(i));
            end
        end
    end
end
