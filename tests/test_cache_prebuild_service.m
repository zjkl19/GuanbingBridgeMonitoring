classdef test_cache_prebuild_service < matlab.unittest.TestCase
    properties
        TempRoot
    end

    methods (TestMethodSetup)
        function setup(tc)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(projectRoot, fullfile(projectRoot, 'config'), ...
                fullfile(projectRoot, 'pipeline'), fullfile(projectRoot, 'analysis'));
            tc.TempRoot = tempname;
            mkdir(tc.TempRoot);
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if isfolder(tc.TempRoot), rmdir(tc.TempRoot, 's'); end
        end
    end

    methods (Test)
        function datedFolderBackendCreatesAndReusesConfiguredCacheOnly(tc)
            dayDir = fullfile(tc.TempRoot, '2026-05-01', 'feature');
            mkdir(dayDir);
            sourcePath = fullfile(dayDir, 'TEMP01.csv');
            sourceText = localWriteTwoColumnCsv(sourcePath, [11; 12]);
            localWriteTwoColumnCsv(fullfile(dayDir, 'UNCONFIGURED.csv'), [91; 92]);
            wimDir = fullfile(tc.TempRoot, 'WIM');
            mkdir(wimDir);
            localWriteTwoColumnCsv(fullfile(wimDir, 'DTCZ-01.csv'), [1; 2]);
            cfg = localStandardConfig('guanbing');
            cfg.subfolders.temperature = 'feature';
            cfg.points.temperature = {'T1'};
            cfg.file_patterns.temperature.default = '{file_id}.csv';
            cfg.per_point.temperature.T1 = struct('file_id', 'TEMP01');

            first = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, '2026-05-01', '2026-05-01', cfg);

            tc.verifyEqual(first.Status, 'ok');
            summary = jsondecode(fileread(first.StatsPath));
            tc.verifyEqual(summary.layout, 'dated_folders');
            tc.verifyEqual(summary.service, ...
                'bms.data.TimeSeriesCachePrebuildService');
            tc.verifyEqual(summary.source_file_count, 1);
            tc.verifyEqual(summary.created_count, 1);
            tc.verifyEqual(summary.failed_count, 0);
            tc.verifyEqual(summary.discovery_scope, ...
                'configured_analysis_timeseries_csv_only');
            tc.verifyTrue(any(strcmp(summary.explicit_exclusions, 'wim')));
            cachePath = localStandardCachePath(sourcePath);
            tc.verifyTrue(isfile(cachePath));
            tc.verifyTrue(isfile(bms.data.CacheManager.metadataPath(cachePath)));
            tc.verifyFalse(isfile(localStandardCachePath( ...
                fullfile(dayDir, 'UNCONFIGURED.csv'))));
            tc.verifyFalse(isfile(localStandardCachePath( ...
                fullfile(wimDir, 'DTCZ-01.csv'))));
            tc.verifyEqual(fileread(sourcePath), sourceText);
            [times, vals, meta] = bms.data.TimeSeriesLoader.readMatSeries( ...
                cachePath, struct('cache_version', 'csv_timeseries_v2', ...
                'require_metadata', true));
            tc.verifyTrue(meta.read_ok);
            tc.verifyEqual(numel(times), 2);
            tc.verifyEqual(vals(:), [11; 12]);
            before = dir(cachePath);

            second = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, '2026-05-01', '2026-05-01', cfg);

            tc.verifyEqual(second.Status, 'ok');
            summary2 = jsondecode(fileread(second.StatsPath));
            tc.verifyEqual(summary2.reused_count, 1);
            tc.verifyEqual(summary2.created_count, 0);
            after = dir(cachePath);
            tc.verifyEqual(after.bytes, before.bytes);
            tc.verifyEqual(after.datenum, before.datenum);

            fid = fopen(sourcePath, 'at');
            tc.assertGreaterThan(fid, 0);
            appendCleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, '2026-05-01 00:00:02.000,13.000000\n');
            clear appendCleanup;
            third = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, '2026-05-01', '2026-05-01', cfg);
            tc.verifyEqual(third.Status, 'ok');
            summary3 = jsondecode(fileread(third.StatsPath));
            tc.verifyEqual(summary3.rebuilt_count, 1);
            [~, rebuiltValues, rebuiltMeta] = ...
                bms.data.TimeSeriesLoader.readMatSeries(cachePath, ...
                struct('cache_version', 'csv_timeseries_v2', ...
                'require_metadata', true));
            tc.verifyTrue(rebuiltMeta.read_ok);
            tc.verifyEqual(rebuiltValues(:), [11; 12; 13]);
        end

        function datedFolderBackendIncludesEnabledCrackTemperatureCompanion(tc)
            dayDir = fullfile(tc.TempRoot, '2026-05-01', 'feature');
            mkdir(dayDir);
            crackPath = fullfile(dayDir, 'CR1.csv');
            tempPath = fullfile(dayDir, 'CR1-t.csv');
            localWriteTwoColumnCsv(crackPath, [0.1; 0.2]);
            localWriteTwoColumnCsv(tempPath, [21; 22]);
            cfg = localStandardConfig('guanbing');
            cfg.subfolders.crack = 'feature';
            cfg.points.crack = {'CR1'};
            cfg.file_patterns.crack.default = '{point}.csv';
            cfg.file_patterns.crack_temp.default = '{point}.csv';
            cfg.plot_styles.crack = struct('temp_enabled', true);

            result = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, '2026-05-01', '2026-05-01', cfg);

            tc.verifyEqual(result.Status, 'ok');
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyEqual(summary.source_file_count, 2);
            tc.verifyEqual(summary.created_count, 2);
            tc.verifyTrue(isfile(localStandardCachePath(crackPath)));
            tc.verifyTrue(isfile(localStandardCachePath(tempPath)));
            sensorTypes = [summary.files.sensor_types];
            tc.verifyTrue(any(strcmp(sensorTypes, 'crack')));
            tc.verifyTrue(any(strcmp(sensorTypes, 'crack_temp')));
        end

        function hongtangBackendCachesSpeedAndDirectionButNotWorkbookOrWim(tc)
            mkdir(fullfile(tc.TempRoot, 'lowfreq'));
            localWriteText(fullfile(tc.TempRoot, 'lowfreq', 'data.xlsx'), ...
                'workbook placeholder');
            waveDir = fullfile(tc.TempRoot, '2026-05-01', 'wave');
            mkdir(waveDir);
            speedPath = fullfile(waveDir, 'SPEED.csv');
            directionPath = fullfile(waveDir, 'DIRECTION.csv');
            localWriteTwoColumnCsv(speedPath, [3; 4]);
            localWriteTwoColumnCsv(directionPath, [90; 100]);
            localWriteTwoColumnCsv(fullfile(waveDir, 'NOISE.csv'), [7; 8]);
            wimDir = fullfile(tc.TempRoot, 'WIM');
            mkdir(wimDir);
            localWriteTwoColumnCsv(fullfile(wimDir, 'DTCZ.csv'), [1; 2]);
            cfg = localStandardConfig('hongtang');
            cfg.subfolders.wind_raw = 'wave';
            cfg.points.wind = {'W1'};
            cfg.file_patterns.wind_speed.default = '{file_id}.csv';
            cfg.file_patterns.wind_direction.default = '{file_id}.csv';
            cfg.per_point.wind.W1 = struct( ...
                'speed_point_id', 'SPEED', 'dir_point_id', 'DIRECTION');

            result = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, '2026-05-01', '2026-05-01', cfg);

            tc.verifyEqual(result.Status, 'ok');
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyEqual(summary.layout, 'hongtang_period');
            tc.verifyEqual(summary.source_file_count, 2);
            tc.verifyEqual(summary.created_count, 2);
            tc.verifyEqual(summary.failed_count, 0);
            tc.verifyTrue(isfile(localStandardCachePath(speedPath)));
            tc.verifyTrue(isfile(localStandardCachePath(directionPath)));
            tc.verifyFalse(isfile(localStandardCachePath( ...
                fullfile(waveDir, 'NOISE.csv'))));
            tc.verifyFalse(isfile(localStandardCachePath( ...
                fullfile(wimDir, 'DTCZ.csv'))));
            tc.verifyTrue(any(strcmp(summary.files(1).sensor_types, 'wind_speed')) ...
                || any(strcmp(summary.files(2).sensor_types, 'wind_speed')));
            tc.verifyTrue(any(strcmp(summary.files(1).sensor_types, 'wind_direction')) ...
                || any(strcmp(summary.files(2).sensor_types, 'wind_direction')));
        end

        function dailyExportBackendDelegatesToMultichannelBuilder(tc)
            csvDir = fullfile(tc.TempRoot, 'data_jlj_2026-05-01', ...
                'data', 'jlj', 'csv');
            mkdir(csvDir);
            sourcePath = fullfile(csvDir, 'POINT01.csv');
            localWriteText(sourcePath, sprintf([ ...
                'ts,value_x,value_y,value_z\n' ...
                '2026-05-01 00:00:00.000,1,11,21\n' ...
                '2026-05-01 00:00:01.000,2,12,22\n']));
            cfg = struct();
            cfg.vendor = 'jiulongjiang';
            cfg.data_adapter = struct('vendor', 'jiulongjiang', ...
                'cache', struct('enabled', true, 'dir', 'cache', ...
                'validate', 'mtime_size'));
            cfg.cache_prebuild = localCacheOptions();

            result = bms.data.CachePrebuildService.run( ...
                tc.TempRoot, '2026-05-01', '2026-05-01', cfg);

            tc.verifyEqual(result.Status, 'ok');
            summary = jsondecode(fileread(result.StatsPath));
            tc.verifyEqual(summary.layout, 'jlj_daily_export');
            tc.verifyEqual(summary.service, 'bms.data.JljCachePrebuildService');
            tc.verifyEqual(summary.created_count, 1);
            cachePath = localStandardCachePath(sourcePath);
            tc.verifyTrue(isfile(cachePath));
            S = load(cachePath, 'ts', 'valx', 'valy', 'valz');
            tc.verifyEqual(S.valx(:), [1; 2]);
            tc.verifyEqual(S.valy(:), [11; 12]);
            tc.verifyEqual(S.valz(:), [21; 22]);
        end

        function supportedLayoutsAreExplicit(tc)
            tc.verifyTrue(bms.data.CachePrebuildService.supportsLayout('dated_folders'));
            tc.verifyTrue(bms.data.CachePrebuildService.supportsLayout('hongtang_period'));
            tc.verifyTrue(bms.data.CachePrebuildService.supportsLayout('jlj_daily_export'));
            tc.verifyFalse(bms.data.CachePrebuildService.supportsLayout('unknown'));
        end
    end
end

function cfg = localStandardConfig(vendor)
cfg = struct();
cfg.vendor = vendor;
cfg.defaults = struct('header_marker', '[missing marker]');
cfg.subfolders = struct();
cfg.points = struct();
cfg.file_patterns = struct();
cfg.per_point = struct();
cfg.time_series = struct('source_mode', 'auto', ...
    'cache_version', 'csv_timeseries_v2', 'require_metadata', true);
cfg.cache_prebuild = localCacheOptions();
end

function options = localCacheOptions()
options = struct('manifest_dir', 'run_logs', ...
    'force_rebuild', false, 'min_free_gib', 0, ...
    'min_free_fraction', 0, 'estimated_cache_ratio', 1.25, ...
    'max_workers', 1);
end

function content = localWriteTwoColumnCsv(path, values)
content = sprintf([ ...
    'ignored header\n' ...
    '2026-05-01 00:00:00.000,%.6f\n' ...
    '2026-05-01 00:00:01.000,%.6f\n'], values(1), values(2));
localWriteText(path, content);
content = fileread(path);
end

function localWriteText(path, content)
parent = fileparts(path);
if ~isfolder(parent), mkdir(parent); end
fid = fopen(path, 'wt', 'n', 'UTF-8');
if fid < 0, error('test:writeFailed', 'Unable to write %s', path); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, content, 'char');
end

function path = localStandardCachePath(sourcePath)
[folder, base, ~] = fileparts(sourcePath);
path = fullfile(folder, 'cache', [base '.mat']);
end
