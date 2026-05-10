classdef test_scalar_series_service < matlab.unittest.TestCase
    properties
        Root
        OldFigureVisible
    end

    methods (TestMethodSetup)
        function setupCase(tc)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'pipeline'), fullfile(proj, 'analysis'));
            tc.Root = tempname;
            mkdir(fullfile(tc.Root, '2026-01-01', 'features'));
            tc.OldFigureVisible = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
        end
    end

    methods (TestMethodTeardown)
        function cleanupCase(tc)
            close all force;
            set(0, 'DefaultFigureVisible', tc.OldFigureVisible);
            if exist(tc.Root, 'dir')
                rmdir(tc.Root, 's');
            end
        end
    end

    methods (Test)
        function temperatureAnalyzerUsesScalarSeriesService(tc)
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'features', 'TEMP-01.csv'), [10; 12; NaN]);
            cfg = scalar_cfg('temperature');

            analyze_temperature_points(tc.Root, {'TEMP-01'}, '2026-01-01', '2026-01-01', ...
                'temperature_stats.xlsx', 'features', cfg);

            T = readtable(fullfile(tc.Root, 'stats', 'temperature_stats.xlsx'), 'VariableNamingRule', 'preserve');
            tc.verifyEqual(T.PointID{1}, 'TEMP-01');
            tc.verifyEqual(T.Min(1), 10);
            tc.verifyEqual(T.Max(1), 12);
            tc.verifyEqual(T.Mean(1), 11);
        end

        function humidityAnalyzerUsesScalarSeriesService(tc)
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'features', 'HUM-01.csv'), [60; 70; 80]);
            cfg = scalar_cfg('humidity');

            analyze_humidity_points(tc.Root, {'HUM-01'}, '2026-01-01', '2026-01-01', ...
                'humidity_stats.xlsx', 'features', cfg);

            T = readtable(fullfile(tc.Root, 'stats', 'humidity_stats.xlsx'), 'VariableNamingRule', 'preserve');
            tc.verifyEqual(T.PointID{1}, 'HUM-01');
            tc.verifyEqual(T.Min(1), 60);
            tc.verifyEqual(T.Max(1), 80);
            tc.verifyEqual(T.Mean(1), 70);
            tc.verifyTrue(isfolder(fullfile(tc.Root, '频次分布_湿度')));
        end

        function rainfallAnalyzerUsesScalarSeriesService(tc)
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'features', 'RAIN-01.csv'), [2; 4; 6]);
            cfg = scalar_cfg('rainfall');

            analyze_rainfall_points(tc.Root, {'RAIN-01'}, '2026-01-01', '2026-01-01', ...
                'rainfall_stats.xlsx', 'features', cfg);

            T = readtable(fullfile(tc.Root, 'stats', 'rainfall_stats.xlsx'), 'VariableNamingRule', 'preserve');
            tc.verifyEqual(T.PointID{1}, 'RAIN-01');
            tc.verifyEqual(T.ValidCount(1), 3);
            tc.verifyEqual(T.Max_mm_h(1), 6);
            tc.verifyEqual(T.Mean_mm_h(1), 4);
            tc.verifyEqual(T.Total_mm(1), 8 / 60, 'AbsTol', 1e-12);
        end
    end
end

function cfg = scalar_cfg(key)
    cfg = struct();
    cfg.defaults = struct('header_marker', '[绝对时间]');
    cfg.subfolders = struct();
    cfg.subfolders.(key) = 'features';
    cfg.plot_styles = struct();
    cfg.plot_styles.(key) = struct('ylim_auto', true);
end

function write_series_csv(path, values)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid > 0, 'Failed to create test csv.');
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'Meta,Info\n');
    fprintf(fid, '[绝对时间],Value\n');
    base = datetime(2026, 1, 1, 0, 0, 0);
    for i = 1:numel(values)
        fprintf(fid, '%s,%.6f\n', datestr(base + minutes(i - 1), 'yyyy-mm-dd HH:MM:SS.FFF'), values(i));
    end
end
