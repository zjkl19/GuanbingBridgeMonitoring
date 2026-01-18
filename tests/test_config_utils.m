classdef test_config_utils < matlab.unittest.TestCase
    % 单元测试：validate_config 与 save_config 基本行为

    properties
        TempDir
    end

    methods (TestMethodSetup)
        function setupPaths(tc)
            tc.TempDir = tempname;
            mkdir(tc.TempDir);
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(fullfile(proj,'config'));
            addpath(fullfile(proj,'scripts'));
        end
    end

    methods (TestMethodTeardown)
        function cleanup(tc)
            if exist(tc.TempDir,'dir'), rmdir(tc.TempDir,'s'); end
        end
    end

    methods (Test)
        function validateGoodConfig(tc)
            cfg = baseCfg();
            warns = validate_config(cfg, false);
            tc.verifyEmpty(warns, '合法配置不应产生警告');
        end

        function validateWarnMissingMinMax(tc)
            cfg = baseCfg();
            % 刻意去掉 per_point 阈值的 min/max
            cfg.per_point.acceleration.TEST_PT.thresholds = struct( ...
                'min', {[]}, 'max', {[]}, 't_range_start', {''}, 't_range_end', {''});
            warns = validate_config(cfg, false);
            tc.verifyTrue(any(contains(warns, 'must have numeric min/max')), ...
                '缺少 min/max 应产生警告');
        end

        function saveConfigCreatesBackup(tc)
            cfg = baseCfg();
            target = fullfile(tc.TempDir,'cfg.json');
            % 先写一个旧文件
            fid = fopen(target,'wt'); fwrite(fid, '{"old":true}','char'); fclose(fid);
            save_config(cfg, target, true);
            % 新文件能被解析且字段存在
            txt = fileread(target);
            cfg2 = jsondecode(txt);
            tc.verifyTrue(isfield(cfg2,'defaults'));
            % 备份存在
            backups = dir(fullfile(tc.TempDir,'cfg_backup_*.json'));
            tc.verifyGreaterThanOrEqual(numel(backups),1);
        end
    end
end

function cfg = baseCfg()
    cfg = struct();
    cfg.defaults = struct();
    cfg.defaults.header_marker = '[绝对时间]';
    cfg.defaults.deflection = struct( ...
        'thresholds', struct('min', -1, 'max', 1), ...
        'zero_to_nan', true, ...
        'outlier', struct('window_sec', 10, 'threshold_factor', 3));
    cfg.defaults.acceleration = struct( ...
        'thresholds', [], 'zero_to_nan', false, 'outlier', []);
    cfg.per_point = struct();
    cfg.per_point.acceleration = struct();
    cfg.per_point.acceleration.TEST_PT = struct( ...
        'thresholds', struct('min', -2, 'max', 2), ...
        'zero_to_nan', false, ...
        'outlier', struct('window_sec', 5, 'threshold_factor', 2));
end
