classdef test_time_series_loader < matlab.unittest.TestCase
    properties
        TempDir
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj);
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if exist(tc.TempDir, 'dir')
                rmdir(tc.TempDir, 's');
            end
        end
    end

    methods (Test)
        function cachedCsvSeriesDetectsMarkerAndWritesMetadata(tc)
            path = fullfile(tc.TempDir, 'series.csv');
            write_text(path, sprintf(['Meta,Info\n' ...
                '[绝对时间],Value\n' ...
                '2026-03-01 00:00:00.000,1.25\n' ...
                '2026-03-01 00:00:01.000,2.50\n']));

            [t, v, meta] = bms.data.TimeSeriesLoader.readCachedCsvSeries(path, '[绝对时间]');

            tc.verifyEqual(numel(t), 2);
            tc.verifyEqual(v(:), [1.25; 2.50]);
            tc.verifyEqual(meta.header_lines, 2);
            tc.verifyTrue(isfile(meta.cache_path));
            tc.verifyTrue(isfile(bms.data.CacheManager.metadataPath(meta.cache_path)));

            [~, v2, meta2] = bms.data.TimeSeriesLoader.readCachedCsvSeries(path, '[绝对时间]');

            tc.verifyEqual(v2(:), [1.25; 2.50]);
            tc.verifyTrue(meta2.cache_hit);
        end

        function cachedCsvSeriesFallsBackToFirstDataLine(tc)
            path = fullfile(tc.TempDir, 'series_no_marker.csv');
            write_text(path, sprintf(['ignored header\n' ...
                '2026-03-01 00:00:00.000,3.00\n' ...
                '2026-03-01 00:00:01.000,4.00\n']));

            [~, v, meta] = bms.data.TimeSeriesLoader.readCachedCsvSeries(path, '[missing marker]');

            tc.verifyEqual(v(:), [3.00; 4.00]);
            tc.verifyEqual(meta.header_lines, 1);
        end

        function findCsvForPointUsesPointPatternBeforeDefault(tc)
            write_text(fullfile(tc.TempDir, 'default_PT-01.csv'), 'x');
            write_text(fullfile(tc.TempDir, 'special_PT-01.csv'), 'x');

            cfg = struct();
            cfg.file_patterns.strain.default = 'default_{point}.csv';
            cfg.file_patterns.strain.per_point.PT_01 = 'special_{point}.csv';

            fp = bms.data.TimeSeriesLoader.findCsvForPoint(tc.TempDir, 'PT-01', cfg, 'strain');

            tc.verifyEqual(fp, fullfile(tc.TempDir, 'special_PT-01.csv'));
        end

        function findCsvForPointUsesWindAliasFallback(tc)
            write_text(fullfile(tc.TempDir, 'DIR-ALIAS.csv'), 'x');

            cfg = struct();
            cfg.per_point.wind.CS_01 = struct( ...
                'speed_point_id', 'SPD-ALIAS', ...
                'dir_point_id', 'DIR-ALIAS');

            fp = bms.data.TimeSeriesLoader.findCsvForPoint(tc.TempDir, 'CS-01', cfg, 'wind_direction');

            tc.verifyEqual(fp, fullfile(tc.TempDir, 'DIR-ALIAS.csv'));
        end
    end
end

function write_text(path, text)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid > 0, 'Failed to create test file.');
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', text);
end
