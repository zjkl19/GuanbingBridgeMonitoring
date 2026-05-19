classdef test_earthquake_series_service < matlab.unittest.TestCase
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
        function componentFromPointDetectsAxis(tc)
            [sensorType, component] = bms.analyzer.EarthquakeSeriesService.componentFromPoint('EQ-Y');

            tc.verifyEqual(sensorType, 'eq_y');
            tc.verifyEqual(component, 'Y');
        end

        function collectRecordLoadsAxisSeries(tc)
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'EQ-Y.csv'), [0.1; 0.2]);
            cfg = eq_cfg();
            params = struct('alarm_levels', [1 2]);

            rec = bms.analyzer.EarthquakeSeriesService.collectRecord( ...
                tc.Root, 'wave', 'EQ-Y', '2026-01-01', '2026-01-01', cfg, params);

            tc.verifyTrue(rec.has_data);
            tc.verifyEqual(rec.sensor_type, 'eq_y');
            tc.verifyEqual(rec.comp, 'Y');
            tc.verifyEqual(rec.params.alarm_levels, [1 2]);
            tc.verifyEqual(rec.vals, [0.1; 0.2], 'AbsTol', 1e-12);
        end

        function valueRulesFilterBeforeUnitScale(tc)
            params = struct('raw_min_filter', -50, 'value_scale', 0.01);

            vals = bms.analyzer.EarthquakeSeriesService.applyValueRules([-60; -50; 100], params);

            tc.verifyTrue(isnan(vals(1)));
            tc.verifyEqual(vals(2), -0.5, 'AbsTol', 1e-12);
            tc.verifyEqual(vals(3), 1.0, 'AbsTol', 1e-12);
        end
    end
end

function cfg = eq_cfg()
    cfg = struct();
    cfg.defaults = struct('header_marker', 'Time');
    cfg.subfolders = struct('eq_raw', 'wave');
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
