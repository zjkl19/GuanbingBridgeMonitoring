classdef test_strain_analysis_pipeline < matlab.unittest.TestCase
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
        function strainPipelineWritesStatsPointGroupAndBoxplot(tc)
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'features', 'S1.csv'), [1; 2; 3; 2]);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'features', 'S2.csv'), [2; 3; 4; 3]);
            cfg = strain_cfg();

            analyze_strain_points(tc.Root, '2026-01-01', '2026-01-01', ...
                'strain_stats.xlsx', 'features', cfg);

            T = readtable(fullfile(tc.Root, 'stats', 'strain_stats.xlsx'), 'VariableNamingRule', 'preserve');
            tc.verifyEqual(height(T), 1);
            tc.verifyEqual(string(T.PointID(1)), "S1");
            tc.verifyGreaterThanOrEqual(numel(dir(fullfile(tc.Root, 'strain_points', '*.fig'))), 1);
            tc.verifyGreaterThanOrEqual(numel(dir(fullfile(tc.Root, 'strain_groups', '*.fig'))), 1);
            tc.verifyGreaterThanOrEqual(numel(dir(fullfile(tc.Root, 'strain_boxplots', '*.fig'))), 1);
        end

        function bridgeConfigsResolveStrainPipelineInputs(tc)
            configFiles = { ...
                'default_config.json', ...
                'hongtang_config.json', ...
                'jiulongjiang_config.json', ...
                'shuixianhua_config.json'};

            for i = 1:numel(configFiles)
                cfg = load_config(fullfile(tc.ProjectRoot, 'config', configFiles{i}));
                ctx = bms.analyzer.StrainAnalysisPipeline.context(cfg);
                serviceCtx = bms.analyzer.StrainConfigService.context(cfg);

                tc.verifyEqual( ...
                    bms.analyzer.StrainAnalysisPipeline.resolveSubfolder(cfg), ...
                    bms.config.ConfigReader.getSubfolder(cfg, 'strain', '特征值'), configFiles{i});
                tc.verifyEqual( ...
                    bms.analyzer.StrainConfigService.resolveSubfolder(cfg), ...
                    bms.analyzer.StrainAnalysisPipeline.resolveSubfolder(cfg), configFiles{i});
                tc.verifyTrue(isstruct(ctx.style), configFiles{i});
                tc.verifyEqual(serviceCtx.explicit_points, ctx.explicit_points, configFiles{i});
                tc.verifyEqual(serviceCtx.explicit_groups, ctx.explicit_groups, configFiles{i});
                tc.verifyEqual(serviceCtx.explicit_ts_groups, ctx.explicit_ts_groups, configFiles{i});
                tc.verifyTrue(iscell(ctx.points), configFiles{i});
                tc.verifyTrue(islogical(ctx.explicit_points), configFiles{i});
                tc.verifyTrue(islogical(ctx.explicit_groups), configFiles{i});
                tc.verifyTrue(islogical(ctx.explicit_ts_groups), configFiles{i});
            end
        end

        function strainPipelineDelegatesBoxplotMatrix(tc)
            dataList = struct( ...
                'pid', {'S1', 'S2'}, ...
                'times', {datetime(2026, 1, 1), datetime(2026, 1, 1)}, ...
                'vals', {[1; 2; 3], [10; 11]});

            pipelineMat = bms.analyzer.StrainAnalysisPipeline.buildBoxplotMatrix(dataList, 50000);
            serviceMat = bms.analyzer.StrainPlotService.buildBoxplotMatrix(dataList, 50000);

            tc.verifyEqual(serviceMat, pipelineMat);
        end

        function strainAnalyzerUsesSharedPipelineAdapter(tc)
            analyzer = bms.analyzer.StrainAnalyzer('root', '2026-01-01', '2026-01-01', '', 'features', struct());

            tc.verifyEqual(analyzer.Key, 'strain');
            tc.verifyEqual(analyzer.StatsFile, '');
        end
    end
end

function cfg = strain_cfg()
    cfg = struct();
    cfg.defaults = struct('header_marker', 'Time');
    cfg.subfolders = struct('strain', 'features');
    cfg.points = struct('strain', {{'S1'}});
    cfg.groups = struct( ...
        'strain', struct('G1', {{'S1', 'S2'}}), ...
        'strain_timeseries', struct('G1', {{'S1', 'S2'}}));
    cfg.plot_styles = struct('strain', struct( ...
        'output_dir', 'strain_points', ...
        'group_output_dir', 'strain_groups', ...
        'boxplot_output_dir', 'strain_boxplots', ...
        'ylabel', 'Strain', ...
        'title_prefix', 'Strain', ...
        'boxplot_title_prefix', 'Strain Box', ...
        'ylim_auto', true, ...
        'show_warn_lines_point', false, ...
        'show_warn_lines_boxplot', false));
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
