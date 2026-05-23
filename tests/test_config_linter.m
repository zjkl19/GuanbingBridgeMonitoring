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
