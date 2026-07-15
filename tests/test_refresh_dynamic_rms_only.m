classdef test_refresh_dynamic_rms_only < matlab.unittest.TestCase
    properties
        TempDir
        OriginalFigureVisible
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(projectRoot, fullfile(projectRoot, 'config'), ...
                fullfile(projectRoot, 'pipeline'), fullfile(projectRoot, 'analysis'), ...
                fullfile(projectRoot, 'scripts'));
            tc.OriginalFigureVisible = get(groot, 'defaultFigureVisible');
            set(groot, 'defaultFigureVisible', 'off');
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            set(groot, 'defaultFigureVisible', tc.OriginalFigureVisible);
            close all force;
            if exist(tc.TempDir, 'dir')
                rmdir(tc.TempDir, 's');
            end
        end
    end

    methods (Test)
        function matOnlyRefreshUsesConfiguredFileAlias(tc)
            cfg = localConfig('mat_only');
            cacheDir = fullfile(tc.TempDir, '2026-04-01', 'wave', 'cache');
            mkdir(cacheDir);
            cachePath = fullfile(cacheDir, 'ACC_ALIAS_stream.mat');
            times = datetime(2026, 4, 1, 0, 0, 0) + seconds((0:1199)');
            vals = 0.2 * sin((0:1199)' / 20);
            save(cachePath, 'times', 'vals');
            bms.data.CacheManager.writeMetadata( ...
                cachePath, {}, struct(), 'csv_timeseries_v2');

            result = refresh_dynamic_rms_only(tc.TempDir, ...
                '2026-04-01', '2026-04-01', cfg, {'acceleration'});

            module = result.modules.acceleration;
            tc.verifyEqual(module.point_count, 1);
            tc.verifyEqual(module.refreshed_count, 1);
            tc.verifyEmpty(module.skipped_points{1});
            tc.verifyTrue(isfile(module.stats_file));
            stats = readtable(module.stats_file, 'VariableNamingRule', 'preserve');
            tc.verifyEqual(height(stats), 1);
            tc.verifyEqual(string(stats.PointID(1)), "A1");
            tc.verifyGreaterThan(stats.RMS10minMax(1), 0);
        end

        function matOnlyCableRefreshUsesConfiguredFileAlias(tc)
            cfg = localConfig('mat_only');
            cacheDir = fullfile(tc.TempDir, '2026-04-01', 'cable-wave', 'cache');
            mkdir(cacheDir);
            cachePath = fullfile(cacheDir, 'CABLE_ALIAS_stream.mat');
            times = datetime(2026, 4, 1, 0, 0, 0) + seconds((0:1199)');
            vals = 0.4 * cos((0:1199)' / 25);
            save(cachePath, 'times', 'vals');
            bms.data.CacheManager.writeMetadata( ...
                cachePath, {}, struct(), 'csv_timeseries_v2');

            result = refresh_dynamic_rms_only(tc.TempDir, ...
                '2026-04-01', '2026-04-01', cfg, {'cable_accel'});

            module = result.modules.cable_accel;
            tc.verifyEqual(module.point_count, 1);
            tc.verifyEqual(module.refreshed_count, 1);
            tc.verifyEmpty(module.skipped_points{1});
            stats = readtable(module.stats_file, 'VariableNamingRule', 'preserve');
            tc.verifyEqual(height(stats), 1);
            tc.verifyEqual(string(stats.PointID(1)), "C1");
            tc.verifyGreaterThan(stats.RMS10minMax(1), 0);
        end

        function groupedRefreshCreatesOnlyRmsGroupArtifacts(tc)
            cfg = localConfig('mat_only');
            cfg.groups.acceleration = struct('G1', {{'A1'}});
            cfg.plot_styles = struct('acceleration', struct( ...
                'group_output_dir', 'raw_group_should_not_change', ...
                'rms_group_output_dir', 'rms_group_refresh'));
            cfg.plot_common = struct('save_fig', true, 'append_timestamp', false);
            cacheDir = fullfile(tc.TempDir, '2026-04-01', 'wave', 'cache');
            mkdir(cacheDir);
            cachePath = fullfile(cacheDir, 'ACC_ALIAS_stream.mat');
            times = datetime(2026, 4, 1, 0, 0, 0) + seconds((0:1199)');
            vals = 0.2 * sin((0:1199)' / 20);
            save(cachePath, 'times', 'vals');
            bms.data.CacheManager.writeMetadata( ...
                cachePath, {}, struct(), 'csv_timeseries_v2');

            refresh_dynamic_rms_only(tc.TempDir, ...
                '2026-04-01', '2026-04-01', cfg, {'acceleration'});

            tc.verifyFalse(isfolder(fullfile(tc.TempDir, 'raw_group_should_not_change')));
            rmsFiles = dir(fullfile(tc.TempDir, 'rms_group_refresh', '*'));
            rmsFiles = rmsFiles(~[rmsFiles.isdir]);
            tc.verifyGreaterThanOrEqual(numel(rmsFiles), 1);
        end

        function zeroPointRefreshLeavesExistingStatsUntouched(tc)
            cfg = localConfig('mat_only');
            mkdir(fullfile(tc.TempDir, '2026-04-01', 'wave'));
            statsDir = fullfile(tc.TempDir, 'stats');
            mkdir(statsDir);
            statsPath = fullfile(statsDir, 'accel_stats.xlsx');
            sentinel = table("keep-existing", 'VariableNames', {'Marker'});
            writetable(sentinel, statsPath);
            bytesBefore = localReadBytes(statsPath);

            tc.verifyError(@() refresh_dynamic_rms_only(tc.TempDir, ...
                '2026-04-01', '2026-04-01', cfg, {'acceleration'}), ...
                'refresh_dynamic_rms_only:NoPointsRefreshed');

            tc.verifyEqual(localReadBytes(statsPath), bytesBefore);
            preserved = readtable(statsPath, 'VariableNamingRule', 'preserve');
            tc.verifyEqual(string(preserved.Marker(1)), "keep-existing");
        end

        function explicitEmptyOverridePreservesLegacyBehavior(tc)
            cfg = localConfig('mat_only');
            mkdir(fullfile(tc.TempDir, '2026-04-01', 'wave'));

            result = refresh_dynamic_rms_only(tc.TempDir, ...
                '2026-04-01', '2026-04-01', cfg, {'acceleration'}, ...
                struct('allow_empty_output', true));

            module = result.modules.acceleration;
            tc.verifyEqual(module.refreshed_count, 0);
            tc.verifyEqual(module.skipped_points{1}, {'A1'});
            tc.verifyTrue(isfile(module.stats_file));
        end
    end
end

function cfg = localConfig(sourceMode)
    cfg = struct();
    cfg.vendor = 'hongtang';
    cfg.subfolders = struct( ...
        'acceleration', 'wave', ...
        'cable_accel', 'cable-wave');
    cfg.points = struct( ...
        'acceleration', {{'A1'}}, ...
        'cable_accel', {{'C1'}});
    cfg.groups = struct( ...
        'acceleration', struct(), ...
        'cable_accel', struct());
    cfg.per_point = struct();
    cfg.per_point.acceleration.A1 = struct('file_id', 'ACC_ALIAS');
    cfg.per_point.cable_accel.C1 = struct('file_id', 'CABLE_ALIAS');
    cfg.file_patterns = struct();
    cfg.file_patterns.acceleration = struct('default', '{file_id}_*.csv');
    cfg.file_patterns.cable_accel = struct('default', '{file_id}_*.csv');
    cfg.data_adapter.time_series = struct( ...
        'source_mode', sourceMode, ...
        'cache_version', 'csv_timeseries_v2', ...
        'require_metadata', true);
end

function bytes = localReadBytes(path)
    fid = fopen(path, 'r');
    assert(fid > 0, 'Unable to open test file: %s', path);
    cleaner = onCleanup(@() fclose(fid));
    bytes = fread(fid, Inf, '*uint8');
end
