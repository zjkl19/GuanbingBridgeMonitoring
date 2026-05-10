classdef test_crack_analysis_pipeline < matlab.unittest.TestCase
    properties
        Root
        ProjectRoot
        OldFigureVisible
    end

    methods (TestMethodSetup)
        function setupCase(tc)
            tc.ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(tc.ProjectRoot, ...
                fullfile(tc.ProjectRoot, 'config'), ...
                fullfile(tc.ProjectRoot, 'pipeline'), ...
                fullfile(tc.ProjectRoot, 'analysis'));
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
        function crackPipelineWritesStatsAndPlotsWithTemperature(tc)
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'features', 'C1.csv'), [0.10; 0.15; 0.20]);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'features', 'C1-t.csv'), [20; 21; 22]);
            cfg = crack_cfg();
            cfg.points.crack = {'C1'};
            cfg.groups.crack = struct('G1', {{'C1'}});

            analyze_crack_points(tc.Root, '2026-01-01', '2026-01-01', ...
                'crack_stats.xlsx', 'features', cfg);

            T = readtable(fullfile(tc.Root, 'stats', 'crack_stats.xlsx'), 'VariableNamingRule', 'preserve');
            tc.verifyEqual(T.PointID{1}, 'C1');
            tc.verifyEqual(T.CrkMin(1), 0.10, 'AbsTol', 1e-12);
            tc.verifyEqual(T.CrkMax(1), 0.20, 'AbsTol', 1e-12);
            tc.verifyEqual(T.TmpMean(1), 21, 'AbsTol', 1e-12);
            tc.verifyGreaterThanOrEqual(numel(dir(fullfile(tc.Root, 'crack_plots', '*.fig'))), 2);
            tc.verifyGreaterThanOrEqual(numel(dir(fullfile(tc.Root, 'temp_plots', '*.fig'))), 2);
        end

        function bridgeConfigsResolveCrackPipelineInputs(tc)
            configFiles = { ...
                'default_config.json', ...
                'hongtang_config.json', ...
                'jiulongjiang_config.json', ...
                'shuixianhua_config.json'};

            for i = 1:numel(configFiles)
                cfg = load_config(fullfile(tc.ProjectRoot, 'config', configFiles{i}));
                style = bms.analyzer.CrackAnalysisPipeline.style(cfg);
                opt = bms.analyzer.CrackAnalysisPipeline.options(style);
                groups = bms.analyzer.CrackAnalysisPipeline.resolveGroups(cfg, opt);
                points = bms.analyzer.CrackAnalysisPipeline.resolvePoints(cfg, groups);

                tc.verifyEqual( ...
                    bms.analyzer.CrackAnalysisPipeline.resolveSubfolder(cfg), ...
                    bms.config.ConfigReader.getSubfolder(cfg, 'crack', '???'), configFiles{i});
                tc.verifyTrue(islogical(opt.per_point_plot), configFiles{i});
                tc.verifyTrue(islogical(opt.group_plot), configFiles{i});
                tc.verifyTrue(isstruct(groups), configFiles{i});
                tc.verifyTrue(iscell(points), configFiles{i});
            end
        end

        function crackAnalyzerUsesSharedPipelineAdapter(tc)
            analyzer = bms.analyzer.CrackAnalyzer('root', '2026-01-01', '2026-01-01', '', 'features', struct());

            tc.verifyEqual(analyzer.Key, 'crack');
            tc.verifyEqual(analyzer.Subfolder, 'features');
        end
    end
end

function cfg = crack_cfg()
    cfg = struct();
    cfg.defaults = struct('header_marker', 'Time');
    cfg.subfolders = struct('crack', 'features');
    cfg.file_patterns = struct();
    cfg.file_patterns.crack = struct('default', '{point}.csv', 'per_point', struct());
    cfg.file_patterns.crack_temp = struct('default', '{point}.csv', 'per_point', struct());
    cfg.points = struct();
    cfg.groups = struct();
    cfg.plot_styles = struct('crack', struct( ...
        'per_point_plot', true, ...
        'group_plot', true, ...
        'temp_enabled', true, ...
        'skip_group_if_missing', true, ...
        'output_dir_crack', 'crack_plots', ...
        'output_dir_temp', 'temp_plots', ...
        'ylim_auto', true));
end

function write_series_csv(path, values)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid > 0, 'Failed to create test csv.');
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'Time,Value\n');
    base = datetime(2026, 1, 1, 0, 0, 0);
    for i = 1:numel(values)
        fprintf(fid, '%s,%.6f\n', datestr(base + minutes(i - 1), 'yyyy-mm-dd HH:MM:SS.FFF'), values(i));
    end
end
