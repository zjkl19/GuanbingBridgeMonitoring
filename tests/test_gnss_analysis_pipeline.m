classdef test_gnss_analysis_pipeline < matlab.unittest.TestCase
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
            mkdir(fullfile(tc.Root, '2026-01-01', 'wave'));
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
        function gnssPipelineWritesComponentStatsAndPlot(tc)
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'G1_X.csv'), [1; 2; 3]);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'G1_Y.csv'), [4; 5; 6]);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'G1_Z.csv'), [7; 8; 9]);
            cfg = gnss_cfg();

            analyze_gnss_points(tc.Root, {'G1'}, '2026-01-01', '2026-01-01', ...
                'gnss_stats.xlsx', 'wave', cfg);

            T = readtable(fullfile(tc.Root, 'stats', 'gnss_stats.xlsx'), 'VariableNamingRule', 'preserve');
            tc.verifyEqual(height(T), 3);
            tc.verifyEqual(string(T.Component), ["X"; "Y"; "Z"]);
            tc.verifyEqual(T.Min_mm(1), 1);
            tc.verifyEqual(T.Max_mm(3), 9);
            tc.verifyEqual(T.Mean_mm(2), 5);
            figs = dir(fullfile(tc.Root, 'gnss_plots', '*.fig'));
            tc.verifyGreaterThanOrEqual(numel(figs), 1);
        end

        function bridgeConfigsResolveGnssPipelineInputs(tc)
            configFiles = { ...
                'default_config.json', ...
                'hongtang_config.json', ...
                'jiulongjiang_config.json', ...
                'shuixianhua_config.json'};

            for i = 1:numel(configFiles)
                cfg = load_config(fullfile(tc.ProjectRoot, 'config', configFiles{i}));
                style = bms.analyzer.GnssAnalysisPipeline.style(cfg);
                components = bms.analyzer.GnssAnalysisPipeline.components();

                tc.verifyEqual( ...
                    bms.analyzer.GnssAnalysisPipeline.resolveSubfolder(cfg), ...
                    bms.config.ConfigReader.getSubfolder(cfg, 'gnss', '波形'), configFiles{i});
                tc.verifyEqual(numel(components), 3, configFiles{i});
                tc.verifySize(bms.analyzer.GnssAnalysisPipeline.colors(style), [3 3], configFiles{i});
            end
        end

        function gnssAnalyzerUsesSharedPipelineAdapter(tc)
            analyzer = bms.analyzer.GnssAnalyzer('root', '2026-01-01', '2026-01-01', '', 'wave', struct(), {'G1'});

            tc.verifyEqual(analyzer.Key, 'gnss');
            tc.verifyEqual(analyzer.Points, {'G1'});
        end
    end
end

function cfg = gnss_cfg()
    cfg = struct();
    cfg.defaults = struct('header_marker', 'Time');
    cfg.subfolders = struct('gnss', 'wave');
    cfg.file_patterns = struct();
    cfg.file_patterns.gnss_x = struct('default', '{point}_X.csv', 'per_point', struct());
    cfg.file_patterns.gnss_y = struct('default', '{point}_Y.csv', 'per_point', struct());
    cfg.file_patterns.gnss_z = struct('default', '{point}_Z.csv', 'per_point', struct());
    cfg.plot_styles = struct('gnss', struct( ...
        'output_dir', 'gnss_plots', ...
        'ylim_auto', true, ...
        'colors', [0 0.447 0.741; 0.85 0.325 0.098; 0.466 0.674 0.188]));
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
