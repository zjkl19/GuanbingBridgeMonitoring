classdef test_chongyangxi_config < matlab.unittest.TestCase
    properties
        Root
        ConfigPath
        TempDir
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.Root = fileparts(fileparts(mfilename('fullpath')));
            tc.ConfigPath = fullfile(tc.Root, 'config', 'chongyangxi_config.json');
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            addpath(tc.Root);
            addpath(fullfile(tc.Root, 'config'));
            addpath(fullfile(tc.Root, 'pipeline'));
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
        function configMapsChongyangxiPoints(tc)
            cfg = load_config(tc.ConfigPath);

            tc.verifyEqual(cfg.vendor, 'chongyangxi');
            tc.verifyEqual(cfg.bridge_id, 'chongyangxi');
            tc.verifyEqual(numel(cfg.points.strain), 8);
            tc.verifyEqual(numel(cfg.points.deflection), 36);
            tc.verifyEqual(numel(cfg.points.tilt), 6);
            tc.verifyEqual(numel(cfg.points.acceleration), 2);
            tc.verifyEqual(numel(cfg.points.crack), 3);

            tc.verifyEqual(bms.data.TimeSeriesLoader.resolveFileId( ...
                cfg, 'deflection', 'CYX-DIS-G02-010-01-Y'), '新增测点24');
            tc.verifyEqual(bms.data.TimeSeriesLoader.resolveFileId( ...
                cfg, 'strain', 'CYX-RSG-G05-005-01'), 'CYX-RSG-G05-005-01');
            tc.verifyEqual(cfg.defaults.tilt.alarm_bounds.level2(:).', [-0.08, 0.08]);

            profile = bms.profile.BridgeProfileRegistry.fromId('chongyangxi', tc.Root);
            tc.verifyEqual(profile.BridgeName, '崇阳溪大桥');
            inferred = bms.profile.BridgeProfileRegistry.infer(cfg, 'D:/崇阳溪数据');
            tc.verifyEqual(inferred.BridgeId, 'chongyangxi');
        end

        function rangeLoaderReadsNestedExportEndDayFolder(tc)
            cfg = struct();
            cfg.vendor = 'chongyangxi';
            cfg.defaults = struct('header_marker', '[绝对时间]');
            cfg.subfolders = struct('strain', '特征值');
            cfg.file_patterns = struct('strain', struct('default', '{file_id}_*.csv'));
            cfg.per_point = struct('strain', struct('PT_1', struct('file_id', 'PT-1')));
            cfg.points = struct('strain', {{'PT-1'}});
            cfg.groups = struct();
            cfg.plot_styles = struct();

            exportDir = fullfile(tc.TempDir, '2025-05-21', '特征值', 'uuid-001');
            mkdir(exportDir);
            local_write_donghua_csv(fullfile(exportDir, 'PT-1_峰值_原始数据_1-1.csv'), ...
                {'2025-05-19 23:59:59.000', '2025-05-20 08:00:00.000', '2025-05-20 12:00:00.000', '2025-05-21 00:00:00.000'}, ...
                [0, 1, 2, 3]);

            [t, v, meta] = load_timeseries_range(tc.TempDir, '特征值', 'PT-1', ...
                '2025-05-20', '2025-05-20', cfg, 'strain');

            tc.verifyEqual(numel(v), 2);
            tc.verifyEqual(v(:).', [1, 2]);
            tc.verifyEqual(t(1), datetime(2025, 5, 20, 8, 0, 0));
            tc.verifyEqual(numel(meta.files), 1);
            tc.verifyTrue(contains(meta.files{1}, 'uuid-001'));
        end
    end
end

function local_write_donghua_csv(path, times, values)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '开始时间,%s\n', times{1});
    fprintf(fid, '序列号,unit\n');
    fprintf(fid, '通道号,1\n');
    fprintf(fid, '测点路径,unit\n');
    fprintf(fid, '采样频率,20\n');
    fprintf(fid, '通道名称,1-1\n');
    fprintf(fid, '[绝对时间],PT-1[unit]\n');
    for i = 1:numel(values)
        fprintf(fid, '%s,%.3f\n', times{i}, values(i));
    end
end
