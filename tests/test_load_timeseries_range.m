classdef test_load_timeseries_range < matlab.unittest.TestCase
    % Unit tests for load_timeseries_range with minimal data under tests/data/_unit

    properties
        DataRoot
        ProjRoot
        Cfg
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.ProjRoot = fileparts(fileparts(mfilename('fullpath')));
            tc.DataRoot = fullfile(tc.ProjRoot, 'tests', 'data', '_unit');

            addpath(tc.ProjRoot, ...
                    fullfile(tc.ProjRoot,'pipeline'), ...
                    fullfile(tc.ProjRoot,'config'));

            tc.Cfg = load_config(fullfile(tc.ProjRoot,'tests','config','test_config.json'));
            tc.Cfg.defaults.header_marker = '[绝对时间]';

            % ensure required subfolders
            if ~isfield(tc.Cfg,'subfolders'), tc.Cfg.subfolders = struct(); end
            tc.Cfg.subfolders.strain = '特征值';
            tc.Cfg.subfolders.crack = '特征值';
            tc.Cfg.subfolders.wind_raw = '波形';
            tc.Cfg.subfolders.eq_raw = '波形';

            % file patterns
            if ~isfield(tc.Cfg,'file_patterns'), tc.Cfg.file_patterns = struct(); end
            tc.Cfg.file_patterns.crack = struct('default',{'{point}_*.csv'},'per_point',struct());
            tc.Cfg.file_patterns.wind_speed = struct('default',{'{file_id}.csv'},'per_point',struct());
            tc.Cfg.file_patterns.wind_direction = struct('default',{'{file_id}.csv'},'per_point',struct());
            tc.Cfg.file_patterns.eq_x = struct('default',{'{file_id}.csv'},'per_point',struct());
            tc.Cfg.file_patterns.eq_y = struct('default',{'{file_id}.csv'},'per_point',struct());
            tc.Cfg.file_patterns.eq_z = struct('default',{'{file_id}.csv'},'per_point',struct());
            tc.Cfg.file_patterns.cable_accel = struct('default',{'{point}_*.csv'},'per_point',struct());

            if ~isfield(tc.Cfg,'per_point') || ~isstruct(tc.Cfg.per_point)
                tc.Cfg.per_point = struct();
            end
            if ~isfield(tc.Cfg.per_point,'wind')
                tc.Cfg.per_point.wind = struct();
            end
            tc.Cfg.per_point.wind.W1 = struct('speed_point_id','风速_162','dir_point_id','风向_163');

            if ~isfield(tc.Cfg.per_point,'eq')
                tc.Cfg.per_point.eq = struct();
            end
            tc.Cfg.per_point.eq.EQ_X = struct('file_id','X_144');
        end
    end

    methods (Test)
        function testUtf8BasicLoad(tc)
            [t,v,~] = load_timeseries_range(tc.DataRoot, '特征值', 'TEST-STRAIN-001', ...
                '2025-01-01', '2025-01-01', tc.Cfg, 'strain');
            tc.verifyEqual(numel(t), 2);
            tc.verifyEqual(v(1), 1.0);
            tc.verifyEqual(v(2), 2.0);
        end

        function testUtf16BomLoad(tc)
            [t,v,~] = load_timeseries_range(tc.DataRoot, '特征值', 'UTF16-PID', ...
                '2025-01-02', '2025-01-02', tc.Cfg, 'strain');
            tc.verifyEqual(numel(t), 2);
            tc.verifyEqual(v(1), 4.0);
        end

        function testThresholdsAndTimeRange(tc)
            cfg = tc.Cfg;
            cfg.defaults.strain.thresholds = struct('min',0,'max',10, ...
                't_range_start','','t_range_end','');
            cfg.per_point.strain.THRESH_001 = struct('thresholds', struct( ...
                'min',0,'max',4, ...
                't_range_start','2025-01-01 00:00:01', ...
                't_range_end','2025-01-01 00:00:02'));

            [~,v,~] = load_timeseries_range(tc.DataRoot, '特征值', 'THRESH-001', ...
                '2025-01-01', '2025-01-01', cfg, 'strain');
            tc.verifyEqual(numel(v), 5);
            tc.verifyEqual(v(1), 1.0);
            tc.verifyTrue(all(isnan(v(2:end))));
        end

        function testEmptyTimeRangeAppliesGlobal(tc)
            cfg = tc.Cfg;
            cfg.defaults.strain.thresholds = [];
            cfg.per_point.strain.THRESH_EMPTY = struct('thresholds', struct( ...
                'min',0,'max',8, ...
                't_range_start','', ...
                't_range_end',''));

            [~,v,~] = load_timeseries_range(tc.DataRoot, '特征值', 'THRESH-EMPTY', ...
                '2025-01-01', '2025-01-01', cfg, 'strain');
            tc.verifyEqual(numel(v), 2);
            tc.verifyEqual(v(1), 1.0);
            tc.verifyTrue(isnan(v(2)));
        end

        function testFilePatternFallback(tc)
            cfg = tc.Cfg;
            if isfield(cfg.defaults,'crack') && isfield(cfg.defaults.crack,'thresholds')
                cfg.defaults.crack.thresholds = [];
            end
            [t,v,~] = load_timeseries_range(tc.DataRoot, '特征值', 'PATTERN-PID', ...
                '2025-01-01', '2025-01-01', cfg, 'crack');
            tc.verifyEqual(numel(v), 1);
            tc.verifyEqual(v(1), 3.0);
            tc.verifyEqual(t(1), datetime(2025,1,1,0,0,0));
        end

        function testWindFileIdMapping(tc)
            [t,v,~] = load_timeseries_range(tc.DataRoot, '波形', 'W1', ...
                '2025-01-01', '2025-01-01', tc.Cfg, 'wind_speed');
            tc.verifyEqual(numel(v), 1);
            tc.verifyEqual(v(1), 1.5);
            tc.verifyEqual(t(1), datetime(2025,1,1,0,0,0));
        end

        function testEqFileIdMapping(tc)
            [t,v,~] = load_timeseries_range(tc.DataRoot, '波形', 'EQ-X', ...
                '2025-01-01', '2025-01-01', tc.Cfg, 'eq_x');
            tc.verifyEqual(numel(v), 1);
            tc.verifyEqual(v(1), 0.01);
            tc.verifyEqual(t(1), datetime(2025,1,1,0,0,0));
        end

        function testCableFilePattern(tc)
            [t,v,~] = load_timeseries_range(tc.DataRoot, '波形', 'CS1', ...
                '2025-01-01', '2025-01-01', tc.Cfg, 'cable_accel');
            tc.verifyEqual(numel(v), 1);
            tc.verifyEqual(v(1), 2.5);
            tc.verifyEqual(t(1), datetime(2025,1,1,0,0,0));
        end

        function testMissingFile(tc)
            [t,v,~] = load_timeseries_range(tc.DataRoot, '特征值', 'MISSING', ...
                '2025-01-01', '2025-01-01', tc.Cfg, 'strain');
            tc.verifyEmpty(t);
            tc.verifyEmpty(v);
        end

        function testNonNumericValue(tc)
            [~,v,~] = load_timeseries_range(tc.DataRoot, '特征值', 'BAD-001', ...
                '2025-01-01', '2025-01-01', tc.Cfg, 'strain');
            tc.verifyEqual(numel(v), 2);
            tc.verifyTrue(isnan(v(2)));
        end
    end
end
