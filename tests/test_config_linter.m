classdef test_config_linter < matlab.unittest.TestCase
    methods (Test)
        function linterAcceptsMatchingPerPointReferences(tc)
            cfg = minimal_config();
            cfg.points.deflection = {'P-1'};
            cfg.per_point.deflection.P_1.alarm_bounds = struct('level2', [-2 2]);

            result = bms.config.ConfigLinter.lint(cfg);

            tc.verifyFalse(any(contains(result.warnings, 'per_point.deflection.P_1 has no matching')));
        end

        function linterWarnsUnmatchedPerPointReferences(tc)
            cfg = minimal_config();
            cfg.points.deflection = {'P-1'};
            cfg.per_point.deflection.P_2.alarm_bounds = struct('level2', [-2 2]);

            result = bms.config.ConfigLinter.lint(cfg);

            tc.verifyTrue(any(contains(result.warnings, 'per_point.deflection.P_2 has no matching')));
            tc.verifyEqual(result.status, 'warning');
            tc.verifyTrue(isfield(result, 'issues'));
            tc.verifyTrue(any(strcmp({result.issues.category}, 'orphan_per_point_rule')));
        end

        function lintPathLoadsConfig(tc)
            tmp = [tempname '.json'];
            cleanup = onCleanup(@() cleanup_file(tmp)); %#ok<NASGU>
            write_text(tmp, ['{"vendor":"unit","defaults":{"header_marker":"time"},' ...
                '"subfolders":{},"file_patterns":{},"groups":{},"points":{},"plot_styles":{}}']);

            result = bms.config.ConfigLinter.lintPath(tmp);

            tc.verifyTrue(isfield(result, 'path'));
            tc.verifyTrue(any(strcmp(result.status, {'ok', 'warning'})));
        end

        function optionalEmptyPointsAreInfo(tc)
            cfg = minimal_config();
            cfg.points.rainfall = {};

            result = bms.config.ConfigLinter.lint(cfg);

            tc.verifyFalse(any(contains(result.warnings, 'points.rainfall is configured but empty')));
            tc.verifyTrue(any(contains(result.infos, 'points.rainfall is configured but empty')));
            tc.verifyGreaterThanOrEqual(result.summary.info, 1);
        end

        function linterWarnsGroupReferencesUnknownPoint(tc)
            cfg = minimal_config();
            cfg.points.deflection = {'P-1', 'P-2'};
            cfg.groups.deflection.G1 = {'P-1', 'P-3'};

            result = bms.config.ConfigLinter.lint(cfg);

            tc.verifyTrue(any(contains(result.warnings, ...
                'groups.deflection group G1 references unknown point P-3')));
            tc.verifyTrue(any(strcmp({result.issues.category}, 'group_point_reference')));
        end

        function linterAcceptsMatchingGroupLabels(tc)
            cfg = minimal_config();
            cfg.points.deflection = {'P-1', 'P-2'};
            cfg.groups.deflection.G1 = {'P-1', 'P-2'};
            cfg.plot_styles.deflection.group_labels.G1 = '测试分组';

            result = bms.config.ConfigLinter.lint(cfg);

            tc.verifyFalse(any(contains(result.warnings, ...
                'plot_styles.deflection.group_labels.G1 references unknown group')));
        end

        function linterWarnsUnknownGroupLabels(tc)
            cfg = minimal_config();
            cfg.points.deflection = {'P-1', 'P-2'};
            cfg.groups.deflection.G1 = {'P-1', 'P-2'};
            cfg.plot_styles.deflection.group_labels.G2 = '孤儿分组';

            result = bms.config.ConfigLinter.lint(cfg);

            tc.verifyTrue(any(contains(result.warnings, ...
                'plot_styles.deflection.group_labels.G2 references unknown group')));
            tc.verifyTrue(any(strcmp({result.issues.category}, 'group_label_reference')));
        end

        function linterWarnsSingleOutputDirSuffix(tc)
            cfg = minimal_config();
            cfg.plot_styles.deflection.single_output_dir = '时程曲线_主梁挠度_单点';

            result = bms.config.ConfigLinter.lint(cfg);

            tc.verifyTrue(any(contains(result.warnings, ...
                'plot_styles.deflection.single_output_dir single plot output dir should not end with _单点')));
            tc.verifyTrue(any(strcmp({result.issues.category}, 'single_output_dir_suffix')));
        end

        function linterWarnsInvalidDynamicRawSamplingMode(tc)
            cfg = minimal_config();
            cfg.plot_common.dynamic_raw_sampling_mode = 'unlimited';

            result = bms.config.ConfigLinter.lint(cfg);

            tc.verifyTrue(any(contains(result.warnings, ...
                'dynamic_raw_sampling_mode must be capped or full')));
            tc.verifyTrue(any(strcmp({result.issues.category}, 'dynamic_raw_sampling_mode')));
        end

        function linterAcceptsNormalizedDynamicRawSamplingMode(tc)
            cfg = minimal_config();
            cfg.plot_common.dynamic_raw_sampling_mode = ' FULL ';

            result = bms.config.ConfigLinter.lint(cfg);

            tc.verifyFalse(any(contains(result.warnings, ...
                'dynamic_raw_sampling_mode must be capped or full')));
        end

        function lintProfilesCoversBridgeCatalog(tc)
            root = fileparts(fileparts(mfilename('fullpath')));

            result = bms.config.ConfigLinter.lintProfiles(root);

            tc.verifyTrue(isfield(result, 'profile_ids'));
            tc.verifyTrue(ismember('zhishan', result.profile_ids));
            tc.verifyTrue(ismember('chongyangxi', result.profile_ids));
            tc.verifyNotEqual(result.status, 'failed');
        end
    end
end

function cfg = minimal_config()
    cfg = struct();
    cfg.vendor = 'unit';
    cfg.defaults = struct('header_marker', 'time');
    cfg.subfolders = struct();
    cfg.file_patterns = struct();
    cfg.groups = struct();
    cfg.points = struct();
    cfg.plot_styles = struct();
end

function write_text(path, text)
    fid = fopen(path, 'wt', 'n', 'UTF-8');
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', text);
end

function cleanup_file(path)
    if isfile(path)
        delete(path);
    end
end
