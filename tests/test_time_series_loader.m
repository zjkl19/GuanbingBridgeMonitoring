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
            addpath(fullfile(proj, 'pipeline'));
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

        function cachedCsvSeriesCountsUtf16LeCrLfHeadersOnce(tc)
            path = fullfile(tc.TempDir, 'series_utf16le_crlf.csv');
            marker = '[Absolute Time]';
            write_utf16le_bom(path, sprintf([ ...
                'metadata one\r\n' ...
                'metadata two\r\n' ...
                '%s,Value\r\n' ...
                '2026-04-01 00:00:00.000,1.00\r\n' ...
                '2026-04-01 00:00:00.050,2.00\r\n' ...
                '2026-04-01 00:00:00.100,3.00\r\n' ...
                '2026-04-01 00:00:00.150,4.00\r\n'], marker));

            [t, v, meta] = bms.data.TimeSeriesLoader.readCachedCsvSeries(path, marker);

            tc.verifyEqual(meta.header_lines, 3);
            tc.verifyEqual(numel(t), 4);
            tc.verifyEqual(v(:), [1; 2; 3; 4]);
            tc.verifyEqual(t(1), datetime(2026, 4, 1, 0, 0, 0));
        end

        function textscanFastPathReadsEveryUtf16LeCrLfDataRow(tc)
            path = fullfile(tc.TempDir, 'series_utf16le_crlf_fast.csv');
            write_utf16le_bom(path, sprintf([ ...
                'metadata one\r\n' ...
                'metadata two\r\n' ...
                '[Absolute Time],Value\r\n' ...
                '2026-04-01 00:00:00.000,5.00\r\n' ...
                '2026-04-01 00:00:00.050,6.00\r\n' ...
                '2026-04-01 00:00:00.100,7.00\r\n' ...
                '2026-04-01 00:00:00.150,8.00\r\n']));

            [t, v, ok] = bms.data.TimeSeriesLoader.readCsvSeriesWithTextscan( ...
                path, 3, 'UTF-16LE');

            tc.verifyTrue(ok);
            tc.verifyEqual(numel(t), 4);
            tc.verifyEqual(v(:), [5; 6; 7; 8]);
            tc.verifyEqual(t(1), datetime(2026, 4, 1, 0, 0, 0));
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

        function findCsvForPointUsesHongtangWindTimestampFallback(tc)
            write_text(fullfile(tc.TempDir, '塔顶风速_20260705224400015.csv'), 'x');

            cfg = struct();
            cfg.per_point.wind.W2 = struct('speed_point_id', '塔顶风速_178');
            cfg.file_patterns.wind_speed.default = {'{file_id}.csv'};
            cfg.file_patterns.wind_speed.per_point.W2 = {'{file_id}.csv', '塔顶风速_*.csv'};

            fp = bms.data.TimeSeriesLoader.findCsvForPoint(tc.TempDir, 'W2', cfg, 'wind_speed');

            tc.verifyEqual(fp, fullfile(tc.TempDir, '塔顶风速_20260705224400015.csv'));
        end

        function findCsvForPointUsesHongtangEqTimestampFallback(tc)
            write_text(fullfile(tc.TempDir, 'X_20260705224156737.csv'), 'x');

            cfg = struct();
            cfg.per_point.eq.EQ_X = struct('file_id', 'X_144');
            cfg.file_patterns.eq_x.default = {'{file_id}.csv'};
            cfg.file_patterns.eq_x.per_point.EQ_X = {'{file_id}.csv', 'X_*.csv'};

            fp = bms.data.TimeSeriesLoader.findCsvForPoint(tc.TempDir, 'EQ-X', cfg, 'eq_x');

            tc.verifyEqual(fp, fullfile(tc.TempDir, 'X_20260705224156737.csv'));
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

        function autoSourceReadsMatCacheWhenCsvIsArchived(tc)
            mkdir(fullfile(tc.TempDir, 'lowfreq'));
            waveDir = fullfile(tc.TempDir, '2026-01-01', 'wave');
            mkdir(waveDir);
            csvPath = fullfile(waveDir, 'SPEED.csv');
            write_text(csvPath, sprintf(['ignored header\n' ...
                '2026-01-01 00:00:00.000,11.00\n' ...
                '2026-01-01 00:00:01.000,12.00\n']));

            cfg = local_hongtang_wind_cfg('auto');

            [~, v1] = load_timeseries_range( ...
                tc.TempDir, 'wave', 'W1', '2026-01-01', '2026-01-01', cfg, 'wind_speed');
            tc.verifyEqual(v1(:), [11; 12]);
            tc.verifyTrue(isfile(fullfile(waveDir, 'cache', 'SPEED.mat')));

            delete(csvPath);
            [t2, v2, meta2] = load_timeseries_range( ...
                tc.TempDir, 'wave', 'W1', '2026-01-01', '2026-01-01', cfg, 'wind_speed');

            tc.verifyEqual(numel(t2), 2);
            tc.verifyEqual(v2(:), [11; 12]);
            tc.verifyTrue(endsWith(meta2.files{1}, fullfile('cache', 'SPEED.mat')));
        end

        function rangeLoaderMatOnlyDoesNotFallbackToCsv(tc)
            mkdir(fullfile(tc.TempDir, 'lowfreq'));
            waveDir = fullfile(tc.TempDir, '2026-01-01', 'wave');
            mkdir(waveDir);
            write_text(fullfile(waveDir, 'SPEED.csv'), sprintf(['ignored header\n' ...
                '2026-01-01 00:00:00.000,21.00\n']));

            cfg = local_hongtang_wind_cfg('mat_only');

            [t, v, meta] = load_timeseries_range( ...
                tc.TempDir, 'wave', 'W1', '2026-01-01', '2026-01-01', cfg, 'wind_speed');

            tc.verifyEmpty(t);
            tc.verifyEmpty(v);
            tc.verifyEmpty(meta.files);
        end

        function matOnlyRequiresCacheMetadata(tc)
            mkdir(fullfile(tc.TempDir, 'lowfreq'));
            cacheDir = fullfile(tc.TempDir, '2026-01-01', 'wave', 'cache');
            mkdir(cacheDir);
            times = datetime(2026, 1, 1, 0, 0, 0);
            vals = 31;
            save(fullfile(cacheDir, 'SPEED.mat'), 'times', 'vals');

            cfg = local_hongtang_wind_cfg('mat_only');

            [t, v] = load_timeseries_range( ...
                tc.TempDir, 'wave', 'W1', '2026-01-01', '2026-01-01', cfg, 'wind_speed');

            tc.verifyEmpty(t);
            tc.verifyEmpty(v);
        end

        function pointNameMatchingUsesBoundaries(tc)
            tc.verifyTrue(bms.data.TimeSeriesLoader.nameMatchesId('A1_174.mat', 'A1'));
            tc.verifyTrue(bms.data.TimeSeriesLoader.nameMatchesId('CS1_148.mat', 'CS1'));
            tc.verifyFalse(bms.data.TimeSeriesLoader.nameMatchesId('A10-X_156.mat', 'A1'));
            tc.verifyFalse(bms.data.TimeSeriesLoader.nameMatchesId('CS10_166.mat', 'CS1'));
        end

        function dataIndexFindsMatCacheWhenCsvIsArchived(tc)
            mkdir(fullfile(tc.TempDir, 'lowfreq'));
            waveDir = fullfile(tc.TempDir, '2026-01-01', 'wave');
            mkdir(waveDir);
            csvPath = fullfile(waveDir, 'SPEED.csv');
            write_text(csvPath, sprintf(['ignored header\n' ...
                '2026-01-01 00:00:00.000,41.00\n']));
            cfg = local_hongtang_wind_cfg('auto');
            bms.data.TimeSeriesLoader.readCachedCsvSeries(csvPath, '[missing marker]');
            delete(csvPath);

            src = bms.data.DataSourceFactory.create(tc.TempDir, cfg);
            files = bms.data.DataIndex.findPointFiles(src, 'W1', 'wave', ...
                '2026-01-01', '2026-01-01', {'{file_id}.csv'}, cfg, 'wind');

            tc.verifyEqual(numel(files), 1);
            tc.verifyTrue(endsWith(files{1}, fullfile('cache', 'SPEED.mat')));
        end

        function dataIndexMatOnlyDoesNotFallbackToCsv(tc)
            mkdir(fullfile(tc.TempDir, 'lowfreq'));
            waveDir = fullfile(tc.TempDir, '2026-01-01', 'wave');
            mkdir(waveDir);
            write_text(fullfile(waveDir, 'SPEED.csv'), sprintf(['ignored header\n' ...
                '2026-01-01 00:00:00.000,51.00\n']));
            cfg = local_hongtang_wind_cfg('mat_only');

            src = bms.data.DataSourceFactory.create(tc.TempDir, cfg);
            files = bms.data.DataIndex.findPointFiles(src, 'W1', 'wave', ...
                '2026-01-01', '2026-01-01', {'SPEED.csv'}, cfg, 'wind');

            tc.verifyEmpty(files);
        end

        function dataIndexPreferMatStillFallsBackToCsv(tc)
            mkdir(fullfile(tc.TempDir, 'lowfreq'));
            waveDir = fullfile(tc.TempDir, '2026-01-01', 'wave');
            mkdir(waveDir);
            csvPath = fullfile(waveDir, 'SPEED.csv');
            write_text(csvPath, sprintf(['ignored header\n' ...
                '2026-01-01 00:00:00.000,61.00\n']));
            cfg = local_hongtang_wind_cfg('prefer_mat');

            src = bms.data.DataSourceFactory.create(tc.TempDir, cfg);
            files = bms.data.DataIndex.findPointFiles(src, 'W1', 'wave', ...
                '2026-01-01', '2026-01-01', {'SPEED.csv'}, cfg, 'wind');

            tc.verifyEqual(numel(files), 1);
            tc.verifyEqual(files{1}, char(java.io.File(csvPath).getCanonicalPath()));
        end

        function preferMatRejectsExistingInvalidCachesAndFallsBackToCsv(tc)
            invalidKinds = {'metadata', 'missing_variables', 'corrupt', 'wrong_types', ...
                'unparseable_text', 'all_nat', 'invalid_numeric_time'};
            for i = 1:numel(invalidKinds)
                caseDir = fullfile(tc.TempDir, sprintf('case_%d', i));
                waveDir = fullfile(caseDir, 'wave');
                cacheDir = fullfile(waveDir, 'cache');
                mkdir(cacheDir);
                csvPath = fullfile(waveDir, 'SPEED.csv');
                write_text(csvPath, sprintf(['ignored header\n' ...
                    '2026-01-01 00:00:00.000,71.00\n']));
                cachePath = fullfile(cacheDir, 'SPEED.mat');
                switch invalidKinds{i}
                    case 'metadata'
                        times = datetime(2026, 1, 1); %#ok<NASGU>
                        vals = 1; %#ok<NASGU>
                        save(cachePath, 'times', 'vals');
                    case 'missing_variables'
                        unrelated = 1; %#ok<NASGU>
                        save(cachePath, 'unrelated');
                        bms.data.CacheManager.writeMetadata( ...
                            cachePath, {}, struct(), 'csv_timeseries_v2');
                    case 'corrupt'
                        write_text(cachePath, 'not a mat file');
                        bms.data.CacheManager.writeMetadata( ...
                            cachePath, {}, struct(), 'csv_timeseries_v2');
                    case 'wrong_types'
                        times = struct('bad', true); %#ok<NASGU>
                        vals = 'not numeric'; %#ok<NASGU>
                        save(cachePath, 'times', 'vals');
                        bms.data.CacheManager.writeMetadata( ...
                            cachePath, {}, struct(), 'csv_timeseries_v2');
                    case 'unparseable_text'
                        times = ["bad-date"; "still-bad"]; %#ok<NASGU>
                        vals = [1; 2]; %#ok<NASGU>
                        save(cachePath, 'times', 'vals');
                        bms.data.CacheManager.writeMetadata( ...
                            cachePath, {}, struct(), 'csv_timeseries_v2');
                    case 'all_nat'
                        times = [NaT; NaT]; %#ok<NASGU>
                        vals = [1; 2]; %#ok<NASGU>
                        save(cachePath, 'times', 'vals');
                        bms.data.CacheManager.writeMetadata( ...
                            cachePath, {}, struct(), 'csv_timeseries_v2');
                    case 'invalid_numeric_time'
                        times = [NaN; NaN]; %#ok<NASGU>
                        vals = [1; 2]; %#ok<NASGU>
                        save(cachePath, 'times', 'vals');
                        bms.data.CacheManager.writeMetadata( ...
                            cachePath, {}, struct(), 'csv_timeseries_v2');
                end
                cfg = local_hongtang_wind_cfg('prefer_mat');

                selected = bms.data.TimeSeriesLoader.findSeriesFileForPoint( ...
                    waveDir, 'W1', cfg, 'wind_speed');
                tc.verifyEqual(selected, csvPath, sprintf('case=%s', invalidKinds{i}));
            end
        end

        function preferMatFallsBackAfterSelectedCacheFailsActualRead(tc)
            waveDir = fullfile(tc.TempDir, '2026-01-01', 'wave');
            cacheDir = fullfile(waveDir, 'cache');
            mkdir(cacheDir);
            csvPath = fullfile(waveDir, 'SPEED.csv');
            write_text(csvPath, sprintf(['ignored header\n' ...
                '2026-01-01 00:00:00.000,91.00\n' ...
                '2026-01-01 00:00:01.000,92.00\n']));
            cachePath = fullfile(cacheDir, 'SPEED.mat');
            write_text(cachePath, 'not a readable MAT cache');
            cfg = local_hongtang_wind_cfg('prefer_mat');

            loader = bms.data.TimeSeriesRangeLoader.donghuaLoader(cfg);
            loader.find_file = @(varargin) cachePath;
            loader.find_fallback_file = @(varargin) csvPath;
            range = struct( ...
                'start', datetime(2026, 1, 1), ...
                'end', datetime(2026, 1, 1, 23, 59, 59));
            meta0 = struct('files', {{}});
            [t, v, meta] = bms.data.TimeSeriesRangeLoader.readByDay( ...
                loader, tc.TempDir, 'wave', 'W1', 'wind_speed', range, ...
                {'2026-01-01'}, meta0);

            tc.verifyEqual(numel(t), 2);
            tc.verifyEqual(v(:), [91; 92], 'AbsTol', 1e-12);
            tc.verifyTrue(any(strcmp(meta.rejected_cache_files, cachePath)));
            tc.verifyTrue(any(strcmp(meta.files, csvPath)));
        end

        function matOnlyKeepsInvalidCacheFailClosed(tc)
            waveDir = fullfile(tc.TempDir, 'wave');
            cacheDir = fullfile(waveDir, 'cache');
            mkdir(cacheDir);
            csvPath = fullfile(waveDir, 'SPEED.csv');
            write_text(csvPath, sprintf(['ignored header\n' ...
                '2026-01-01 00:00:00.000,81.00\n']));
            cachePath = fullfile(cacheDir, 'SPEED.mat');
            write_text(cachePath, 'not a mat file');
            cfg = local_hongtang_wind_cfg('mat_only');

            selected = bms.data.TimeSeriesLoader.findSeriesFileForPoint( ...
                waveDir, 'W1', cfg, 'wind_speed');

            tc.verifyEqual(selected, cachePath);
            tc.verifyNotEqual(selected, csvPath);
        end

        function cachedCsvSeriesAllowsMojibakeSourcePathWhenFingerprintMatches(tc)
            path = fullfile(tc.TempDir, 'series_mojibake.csv');
            write_text(path, sprintf(['ignored header\n' ...
                '2026-03-01 00:00:00.000,13.00\n' ...
                '2026-03-01 00:00:01.000,14.00\n']));

            [~, ~, meta1] = bms.data.TimeSeriesLoader.readCachedCsvSeries(path, '[missing marker]');
            metaPath = bms.data.CacheManager.metadataPath(meta1.cache_path);
            rawMeta = jsondecode(fileread(metaPath));
            rawMeta.source_records.path = fullfile('F:\mojibake-root', 'series_mojibake.csv');
            bms.core.Logger.writeJson(metaPath, rawMeta);

            [~, v2, meta2] = bms.data.TimeSeriesLoader.readCachedCsvSeries(path, '[missing marker]');

            tc.verifyTrue(meta2.cache_hit);
            tc.verifyEqual(v2(:), [13; 14]);
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

function cfg = local_hongtang_wind_cfg(sourceMode)
cfg = struct();
cfg.vendor = 'hongtang';
cfg.defaults = struct('header_marker', '[missing marker]');
cfg.data_adapter.time_series = struct( ...
    'source_mode', sourceMode, ...
    'cache_version', 'csv_timeseries_v2');
cfg.file_patterns.wind_speed.default = '{file_id}.csv';
cfg.per_point.wind.W1 = struct('speed_point_id', 'SPEED');
end
