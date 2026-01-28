classdef test_load_timeseries_range < matlab.unittest.TestCase
    % Basic unit tests for load_timeseries_range:
    % - reads CSV with header marker
    % - caches second call
    % - respects file_patterns fallback
    %
    % The tests create temporary YYYY-MM-DD/<subfolder>/xxx.csv files.

    properties
        TempRoot
        Cfg
        ProjRoot
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.ProjRoot = fileparts(fileparts(mfilename('fullpath')));
            tc.TempRoot = tempname;
            mkdir(tc.TempRoot);
            addpath(tc.ProjRoot, ...
                    fullfile(tc.ProjRoot,'pipeline'), ...
                    fullfile(tc.ProjRoot,'config'));

            tc.Cfg = load_config(fullfile(tc.ProjRoot,'tests','config','test_config.json'));
            % force key config to avoid encoding surprises
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
            if ~isfield(tc.Cfg.subfolders,'wind_raw'), tc.Cfg.subfolders.wind_raw = '波形'; end
            if ~isfield(tc.Cfg,'file_patterns')
                tc.Cfg.file_patterns = struct();
            end
            if ~isfield(tc.Cfg.file_patterns,'crack')
                tc.Cfg.file_patterns.crack = struct('default',{{'{point}_*.csv'}},'per_point',struct());
            end
            if ~isfield(tc.Cfg.file_patterns,'wind_speed')
                tc.Cfg.file_patterns.wind_speed = struct('default',{{'{file_id}.csv'}},'per_point',struct());
            end
            if ~isfield(tc.Cfg.file_patterns,'wind_direction')
                tc.Cfg.file_patterns.wind_direction = struct('default',{{'{file_id}.csv'}},'per_point',struct());
            end
            if ~isfield(tc.Cfg,'per_point') || ~isstruct(tc.Cfg.per_point)
                tc.Cfg.per_point = struct();
            end
            if ~isfield(tc.Cfg.per_point,'wind')
                tc.Cfg.per_point.wind = struct();
            end
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if exist(tc.TempRoot,'dir')
                rmdir(tc.TempRoot,'s');
            end
            % keep paths; harmless for other tests
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
            % simple CSV with header marker line
            % write with explicit UTF-8 to avoid mojibake in header marker
            fid = fopen(fp,'w','n','UTF-8');
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

            % second call should hit cache and keep values
            [t2,v2,~] = load_timeseries_range(tc.TempRoot, subfolder, pid, dateStr, dateStr, tc.Cfg, 'strain');
            tc.verifyEqual(numel(t2), 2);
            tc.verifyEqual(v2(2), 2.0);
        end

        function testFilePatternFallback(tc)
            % ensure file_patterns default works
            dateStr = '2025-02-02';
            subfolder = get_sub(tc.Cfg, 'crack', '特征值');
            pid = 'PATTERN-PID';
            header_marker = get_header_marker(tc.Cfg);

            dayDir = fullfile(tc.TempRoot, dateStr, subfolder);
            mkdir(dayDir);
            fp = fullfile(dayDir, [pid '_abc.csv']);
            fid = fopen(fp,'w','n','UTF-8');
            fprintf(fid, '%s,Value\n', header_marker);
            fprintf(fid, '2025-02-02 00:00:00.000,3.0\n');
            fclose(fid);

            [t,v,~] = load_timeseries_range(tc.TempRoot, subfolder, pid, dateStr, dateStr, tc.Cfg, 'crack');
            tc.verifyEqual(numel(v),1);
            tc.verifyEqual(v(1),3.0);
            tc.verifyEqual(t(1), datetime(2025,2,2,0,0,0));
        end

        function testWindAliasFileId(tc)
            dateStr = '2025-03-03';
            subfolder = get_sub(tc.Cfg, 'wind_raw', '波形');
            pid = 'W1';
            header_marker = get_header_marker(tc.Cfg);

            tc.Cfg.per_point.wind.W1 = struct( ...
                'speed_point_id', '风速_162', ...
                'dir_point_id', '风向_163');

            dayDir = fullfile(tc.TempRoot, dateStr, subfolder);
            mkdir(dayDir);

            fpSpeed = fullfile(dayDir, '风速_162.csv');
            fid = fopen(fpSpeed, 'w', 'n', 'UTF-8');
            fprintf(fid, '%s,Value\n', header_marker);
            fprintf(fid, '2025-03-03 00:00:00.000,1.5\n');
            fclose(fid);

            [t, v, meta] = load_timeseries_range(tc.TempRoot, subfolder, pid, dateStr, dateStr, tc.Cfg, 'wind_speed');
            tc.verifyEqual(numel(v), 1);
            tc.verifyEqual(v(1), 1.5);
            tc.verifyEqual(meta.files{1}, fpSpeed);
            tc.verifyEqual(t(1), datetime(2025,3,3,0,0,0));
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
