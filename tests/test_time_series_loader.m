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

        function cachedCsvSeriesReadsUtf16LeBomWithoutWarnings(tc)
            path = fullfile(tc.TempDir, 'series_utf16le.csv');
            write_utf16le_bom(path, sprintf(['ignored header\n' ...
                '2026-03-01 00:00:00.000,5.00\n' ...
                '2026-03-01 00:00:01.000,6.00\n']));

            lastwarn('');
            [~, v, meta] = bms.data.TimeSeriesLoader.readCachedCsvSeries(path, '[missing marker]');
            [warnMsg, ~] = lastwarn();

            tc.verifyEmpty(warnMsg);
            tc.verifyEqual(v(:), [5.00; 6.00]);
            tc.verifyEqual(meta.header_lines, 1);
        end

        function readCsvSeriesParsesUtf16LeBomWithoutHeader(tc)
            path = fullfile(tc.TempDir, 'series_utf16le_no_header.csv');
            write_utf16le_bom(path, sprintf(['2026-03-01 00:00:00.000,7.00\n' ...
                '2026-03-01 00:00:01.000,8.00\n']));

            lastwarn('');
            [t, v, ok] = bms.data.TimeSeriesLoader.readCsvSeriesWithFallback(path, 0);
            [warnMsg, ~] = lastwarn();

            tc.verifyTrue(ok);
            tc.verifyEmpty(warnMsg);
            tc.verifyEqual(numel(t), 2);
            tc.verifyEqual(v(:), [7.00; 8.00]);
        end

        function preferredEncodingsDetectUtf16LeBom(tc)
            path = fullfile(tc.TempDir, 'series_utf16le_order.csv');
            write_utf16le_bom(path, '2026-03-01 00:00:00.000,1.00\n');

            encs = bms.data.TimeSeriesLoader.preferredEncodings(path);

            tc.verifyEqual(encs{1}, 'UTF-16LE');
            tc.verifyEqual(encs, {'UTF-16LE'});
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

        function findCsvForPointUsesConfiguredRegex(tc)
            nested = fullfile(tc.TempDir, 'uuid-001');
            mkdir(nested);
            write_text(fullfile(nested, 'CH24_485缓变量_原始数据_1-41-24_202505210810.csv'), 'x');
            write_text(fullfile(nested, 'CH2_485缓变量_原始数据_1-41-2_202505210810.csv'), 'x');

            cfg = struct();
            cfg.file_patterns.deflection.default = 'NO_MATCH_{file_id}.csv';
            cfg.file_patterns.deflection.regex = '^CH24_485缓变量_原始数据_.*\.csv$';
            cfg.per_point.deflection.CYX_DIS_G02_010_01_Y = struct('file_id', 'TARGET-24');

            fp = bms.data.TimeSeriesLoader.findCsvForPoint( ...
                tc.TempDir, 'CYX-DIS-G02-010-01-Y', cfg, 'deflection');

            tc.verifyEqual(fp, fullfile(nested, 'CH24_485缓变量_原始数据_1-41-24_202505210810.csv'));
        end

        function hongtangMixedLayoutReadsDatedWaveCsv(tc)
            mkdir(fullfile(tc.TempDir, 'lowfreq'));
            waveDir = fullfile(tc.TempDir, '2026-01-01', 'wave');
            mkdir(waveDir);
            write_text(fullfile(waveDir, 'SPEED.csv'), sprintf(['ignored header\n' ...
                '2026-01-01 00:00:00.000,1.00\n' ...
                '2026-01-01 00:00:01.000,2.00\n']));

            cfg = struct();
            cfg.vendor = 'hongtang';
            cfg.defaults = struct('header_marker', '[missing marker]');
            cfg.file_patterns.wind_speed.default = '{file_id}.csv';
            cfg.per_point.wind.W1 = struct('speed_point_id', 'SPEED');

            [t, v, meta] = load_timeseries_range( ...
                tc.TempDir, 'wave', 'W1', '2026-01-01', '2026-01-01', cfg, 'wind_speed');

            tc.verifyEqual(numel(t), 2);
            tc.verifyEqual(v(:), [1; 2]);
            tc.verifyEqual(meta.data_source, 'bms.data.DatedFolderAdapter');
            tc.verifyTrue(contains(meta.files{1}, fullfile('2026-01-01', 'wave', 'SPEED.csv')));
        end

        function cachedCsvSeriesIgnoresCacheWithoutMetadata(tc)
            path = fullfile(tc.TempDir, 'series_stale.csv');
            write_text(path, sprintf(['ignored header\n' ...
                '2026-03-01 00:00:00.000,9.00\n' ...
                '2026-03-01 00:00:01.000,10.00\n']));
            cacheDir = fullfile(tc.TempDir, 'cache');
            mkdir(cacheDir);
            times = datetime(2026, 1, 1, 0, 0, 0);
            vals = -999;
            save(fullfile(cacheDir, 'series_stale.mat'), 'times', 'vals');

            [~, v, meta] = bms.data.TimeSeriesLoader.readCachedCsvSeries(path, '[missing marker]');

            tc.verifyFalse(meta.cache_hit);
            tc.verifyEqual(v(:), [9; 10]);
        end
    end
end

function write_text(path, text)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid > 0, 'Failed to create test file.');
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', text);
end

function write_utf16le_bom(path, text)
    fid = fopen(path, 'w');
    assert(fid > 0, 'Failed to create test file.');
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes = [uint8([255 254]), unicode2native(text, 'UTF-16LE')];
    fwrite(fid, bytes, 'uint8');
end
