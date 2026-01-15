classdef test_load_timeseries_range < matlab.unittest.TestCase
    % 基础冒烟测试：验证 load_timeseries_range 能读取 CSV 并应用 header 检测与缓存。
    % 在临时目录下创建 YYYY-MM-DD/<subfolder>/xxx.csv 并清理。

    properties
        TempRoot
        Cfg
        ProjRoot
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            % 定位项目根目录（tests 上一级）
            tc.ProjRoot = fileparts(fileparts(mfilename('fullpath')));
            tc.TempRoot = tempname;
            mkdir(tc.TempRoot);
            addpath(tc.ProjRoot);
            addpath(fullfile(tc.ProjRoot,'pipeline'));
            addpath(fullfile(tc.ProjRoot,'config'));

            tc.Cfg = load_config();
            % 强制关键配置，避免编码/阈值影响测试
            tc.Cfg.defaults.header_marker = '[绝对时间]';
            if isfield(tc.Cfg,'defaults')
                fns = fieldnames(tc.Cfg.defaults);
                for i = 1:numel(fns)
                    if isfield(tc.Cfg.defaults.(fns{i}),'thresholds')
                        tc.Cfg.defaults.(fns{i}).thresholds = [];
                    end
                    if isfield(tc.Cfg.defaults.(fns{i}),'zero_to_nan')
                        tc.Cfg.defaults.(fns{i}).zero_to_nan = false;
                    end
                end
            end
            if ~isfield(tc.Cfg,'subfolders'), tc.Cfg.subfolders = struct(); end
            if ~isfield(tc.Cfg.subfolders,'strain'), tc.Cfg.subfolders.strain = '特征值'; end
            if ~isfield(tc.Cfg.subfolders,'crack'),  tc.Cfg.subfolders.crack  = '特征值'; end
            if ~isfield(tc.Cfg,'file_patterns')
                tc.Cfg.file_patterns = struct();
            end
            if ~isfield(tc.Cfg.file_patterns,'crack')
                tc.Cfg.file_patterns.crack = struct('default',{{'{point}_*.csv'}},'per_point',struct());
            end
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if exist(tc.TempRoot,'dir')
                rmdir(tc.TempRoot,'s');
            end
            % 不移除路径，避免干扰其他测试
        end
    end

    methods (Test)
        function testBasicLoad(tc)
            dateStr = '2025-01-01';
            subfolder = get_sub(tc.Cfg, 'strain', '特征值');
            pid = 'TEST-PID-001';
            header_marker = get_header_marker(tc.Cfg);

            dayDir = fullfile(tc.TempRoot, dateStr, subfolder);
            mkdir(dayDir);
            fp = fullfile(dayDir, [pid '.csv']);
            % 写入含 header 标记的简单 CSV
            fid = fopen(fp,'wt');
            fprintf(fid, 'Header1,Header2\n');
            fprintf(fid, '%s,Value\n', header_marker);
            fprintf(fid, '2025-01-01 00:00:00.000,1.0\n');
            fprintf(fid, '2025-01-01 00:00:01.000,2.0\n');
            fclose(fid);

            [t,v,meta] = load_timeseries_range(tc.TempRoot, subfolder, pid, dateStr, dateStr, tc.Cfg, 'strain');
            tc.verifyEqual(numel(t), 2);
            tc.verifyEqual(numel(v), 2);
            tc.verifyEqual(v(1), 1.0);
            tc.verifyEqual(meta.files{1}, fp);

            % 第二次调用应命中缓存
            [t2,v2,~] = load_timeseries_range(tc.TempRoot, subfolder, pid, dateStr, dateStr, tc.Cfg, 'strain');
            tc.verifyEqual(numel(t2), 2);
            tc.verifyEqual(v2(2), 2.0);
        end

        function testFilePatternFallback(tc)
            % 确认 file_patterns default 生效
            dateStr = '2025-02-02';
            subfolder = get_sub(tc.Cfg, 'crack', '特征值');
            pid = 'PATTERN-PID';
            header_marker = get_header_marker(tc.Cfg);

            dayDir = fullfile(tc.TempRoot, dateStr, subfolder);
            mkdir(dayDir);
            fp = fullfile(dayDir, [pid '_abc.csv']);
            fid = fopen(fp,'wt');
            fprintf(fid, '%s,Value\n', header_marker);
            fprintf(fid, '2025-02-02 00:00:00.000,3.0\n');
            fclose(fid);

            [t,v,~] = load_timeseries_range(tc.TempRoot, subfolder, pid, dateStr, dateStr, tc.Cfg, 'crack');
            tc.verifyEqual(numel(v),1);
            tc.verifyEqual(v(1),3.0);
            tc.verifyEqual(t(1), datetime(2025,2,2,0,0,0));
        end
    end
end

function sub = get_sub(cfg, key, fallback)
    sub = fallback;
    if isfield(cfg,'subfolders') && isfield(cfg.subfolders,key)
        sub = cfg.subfolders.(key);
    end
end

function hm = get_header_marker(cfg)
    hm = '[绝对时间]';
    if isfield(cfg,'defaults') && isfield(cfg.defaults,'header_marker')
        hm = cfg.defaults.header_marker;
    end
end
