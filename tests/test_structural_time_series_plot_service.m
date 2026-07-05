classdef test_structural_time_series_plot_service < matlab.unittest.TestCase
    properties
        Root
    end

    methods (TestMethodSetup)
        function setupCase(tc)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'analysis'), fullfile(proj, 'pipeline'));
            tc.Root = tempname;
            mkdir(tc.Root);
        end
    end

    methods (TestMethodTeardown)
        function cleanupCase(tc)
            if exist(tc.Root, 'dir')
                rmdir(tc.Root, 's');
            end
        end
    end

    methods (Test)
        function fromCellsBuildsPlotRecords(tc)
            times = {datetime(2026, 1, 1) + minutes((0:2)')};
            values = {[1; 2; 3]};

            data = bms.analyzer.StructuralTimeSeriesPlotService.fromCells(times, values, {'P1'});

            tc.verifyEqual(numel(data), 1);
            tc.verifyEqual(data(1).pid, 'P1');
            tc.verifyEqual(data(1).vals, [1; 2; 3]);
        end

        function plotDataListWritesBundle(tc)
            data = struct( ...
                'pid', 'P1', ...
                'times', datetime(2026, 1, 1) + minutes((0:2)'), ...
                'vals', [1; 2; 3]);
            opts = struct( ...
                'style', struct(), ...
                'outputDir', 'plots', ...
                'baseName', 'StructuralPlotTest', ...
                'titleText', 'Structural Plot Test', ...
                'ylabel', 'Value', ...
                'ylimRange', [0 5], ...
                'warnLines', struct('y', 4, 'label', 'Warn', 'color', [1 0 0]), ...
                'defaultColors', [0 0 1]);

            bms.analyzer.StructuralTimeSeriesPlotService.plotDataList( ...
                tc.Root, data, '2026-01-01', '2026-01-01', opts, struct());

            tc.verifyTrue(exist(fullfile(tc.Root, 'plots', 'StructuralPlotTest.fig'), 'file') == 2);
        end

        function deflectionPipelineUsesSharedPlotService(tc)
            mkdir(fullfile(tc.Root, '2026-01-01', 'features'));
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'features', 'D1.csv'), [1; 2; 4; 3]);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'features', 'D2.csv'), [2; 3; 5; 4]);
            cfg = struct();
            cfg.defaults = struct('header_marker', 'Time');
            cfg.subfolders = struct('deflection', 'features');
            cfg.points = struct('deflection', {{'D1', 'D2'}});
            cfg.groups = struct('deflection', {{{'D1', 'D2'}}});
            cfg.plot_styles = struct('deflection', struct('ylim_auto', true));
            bounds = struct('level2', [-2 2], 'level3', [-3 3]);
            cfg.per_point = struct('deflection', struct( ...
                'D1', struct('alarm_bounds', bounds), ...
                'D2', struct('alarm_bounds', bounds)));
            excelPath = fullfile(tc.Root, 'deflection_stats.xlsx');

            analyze_deflection_points(tc.Root, '2026-01-01', '2026-01-01', excelPath, 'features', cfg);

            tc.verifyTrue(exist(excelPath, 'file') == 2);
            rawSingleFigs = dir(fullfile(tc.Root, '时程曲线_挠度_原始', '*.fig'));
            filtSingleFigs = dir(fullfile(tc.Root, '时程曲线_挠度_滤波', '*.fig'));
            rawGroupFigs = dir(fullfile(tc.Root, '时程曲线_挠度_组图_原始', '*.fig'));
            filtGroupFigs = dir(fullfile(tc.Root, '时程曲线_挠度_组图_滤波', '*.fig'));
            tc.verifyGreaterThanOrEqual(numel(rawSingleFigs), 2);
            tc.verifyGreaterThanOrEqual(numel(filtSingleFigs), 2);
            tc.verifyGreaterThanOrEqual(numel(rawGroupFigs), 1);
            tc.verifyGreaterThanOrEqual(numel(filtGroupFigs), 1);

            spec = bms.analyzer.StructuralFilteredSeriesPipeline.spec('deflection');
            warnLines = bms.analyzer.StructuralFilteredPlotService.defaultWarnLines( ...
                cfg.plot_styles.deflection, cfg, spec, 'D1');
            tc.verifyEqual(sort(cellfun(@(x) x.y, warnLines)), [-3; -2; 2; 3]);
            records = struct('pid', {'D1', 'D2'});
            groupWarnLines = bms.analyzer.StructuralFilteredSeriesPipeline.deflectionGroupWarnLines( ...
                records, cfg.plot_styles.deflection, cfg, spec);
            tc.verifyEqual(sort(cellfun(@(x) x.y, groupWarnLines)), [-3; -2; 2; 3]);

            cfgMismatch = cfg;
            cfgMismatch.per_point.deflection.D2.alarm_bounds = struct( ...
                'level2', [-4 4], 'level3', [-5 5]);
            mismatchWarnLines = bms.analyzer.StructuralFilteredSeriesPipeline.deflectionGroupWarnLines( ...
                records, cfg.plot_styles.deflection, cfgMismatch, spec);
            tc.verifyEmpty(mismatchWarnLines);

            labelStyle = struct('group_labels', struct('G1', '中文分组'));
            [titleText, fileNameTag] = bms.analyzer.StructuralFilteredPlotService.titleParts( ...
                labelStyle, spec, 'G1', 'Filt');
            tc.verifyEqual(fileNameTag, 'G1');
            tc.verifyEqual(titleText, '挠度时程 中文分组 Filt');
        end

        function tiltPipelineUsesSharedPlotService(tc)
            mkdir(fullfile(tc.Root, '2026-01-01', 'wave'));
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'T1.csv'), [0.1; 0.2; 0.3; 0.2]);
            cfg = struct();
            cfg.defaults = struct('header_marker', 'Time');
            cfg.subfolders = struct('tilt', 'wave');
            cfg.points = struct('tilt', {{'T1'}});
            cfg.groups = struct('tilt', struct('G1', {{'T1'}}));
            cfg.plot_styles = struct('tilt', struct( ...
                'output_dir', 'tilt_plots', ...
                'single_output_dir', 'tilt_point_plots', ...
                'group_output_dir', 'tilt_group_plots', ...
                'warn_lines', struct('y', 0.08, 'label', 'Level 2'), ...
                'ylim_auto', true));
            excelPath = fullfile(tc.Root, 'tilt_stats.xlsx');

            analyze_tilt_points(tc.Root, '2026-01-01', '2026-01-01', excelPath, 'wave', cfg);

            tc.verifyTrue(exist(excelPath, 'file') == 2);
            pointFigs = dir(fullfile(tc.Root, 'tilt_point_plots', '*.fig'));
            groupFigs = dir(fullfile(tc.Root, 'tilt_group_plots', '*.fig'));
            tc.verifyGreaterThanOrEqual(numel(pointFigs), 1);
            tc.verifyGreaterThanOrEqual(numel(groupFigs), 1);
            tc.verifyEqual(constant_line_values(fullfile(pointFigs(1).folder, pointFigs(1).name)), 0.08);
            tc.verifyEqual(constant_line_values(fullfile(groupFigs(1).folder, groupFigs(1).name)), 0.08);
        end

        function bearingPipelineProcessesGroupFallback(tc)
            mkdir(fullfile(tc.Root, '2026-01-01', 'features'));
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'features', 'B1.csv'), [1; 2; 4; 3]);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'features', 'B2.csv'), [2; 3; 5; 4]);
            cfg = struct();
            cfg.defaults = struct('header_marker', 'Time');
            cfg.subfolders = struct('bearing_displacement', 'features');
            cfg.groups = struct('bearing_displacement', {{{'B1', 'B2'}}});
            cfg.plot_styles = struct('bearing_displacement', struct('output_dir', 'bearing_plots', 'ylim_auto', true));
            bounds = struct('level2', [-80 80], 'level3', [-100 100]);
            cfg.per_point = struct('bearing_displacement', struct( ...
                'B1', struct('alarm_bounds', bounds), ...
                'B2', struct('alarm_bounds', bounds)));
            excelPath = fullfile(tc.Root, 'bearing_stats.xlsx');

            analyze_bearing_displacement_points(tc.Root, '2026-01-01', '2026-01-01', excelPath, '', cfg);

            T = readtable(excelPath, 'VariableNamingRule', 'preserve');
            tc.verifyEqual(height(T), 2);
            figs = dir(fullfile(tc.Root, 'bearing_plots', '*.fig'));
            tc.verifyGreaterThanOrEqual(numel(figs), 4);
            groupFigs = dir(fullfile(tc.Root, 'bearing_plots_组图', '*.fig'));
            tc.verifyGreaterThanOrEqual(numel(groupFigs), 2);
            origGroupFigs = groupFigs(contains({groupFigs.name}, 'Orig'));
            filtGroupFigs = groupFigs(contains({groupFigs.name}, 'Filt'));
            tc.verifyGreaterThanOrEqual(numel(origGroupFigs), 1);
            tc.verifyGreaterThanOrEqual(numel(filtGroupFigs), 1);
            tc.verifyEqual(constant_line_values(fullfile(origGroupFigs(1).folder, origGroupFigs(1).name)).', [-100 -80 80 100]);
            tc.verifyEmpty(constant_line_values(fullfile(filtGroupFigs(1).folder, filtGroupFigs(1).name)));

            spec = bms.analyzer.StructuralFilteredSeriesPipeline.spec('bearing_displacement');
            records = struct('pid', {'B1', 'B2'});
            cfgMismatch = cfg;
            cfgMismatch.per_point.bearing_displacement.B2.alarm_bounds = struct( ...
                'level2', [-70 70], 'level3', [-90 90]);
            mismatchWarnLines = bms.analyzer.StructuralFilteredSeriesPipeline.bearingGroupWarnLines( ...
                records, cfg.plot_styles.bearing_displacement, cfgMismatch, spec);
            tc.verifyEmpty(mismatchWarnLines);
        end

        function bridgeConfigsResolveFilteredPipelineInputs(tc)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            configFiles = { ...
                'default_config.json', ...
                'hongtang_config.json', ...
                'jiulongjiang_config.json', ...
                'shuixianhua_config.json'};
            for i = 1:numel(configFiles)
                cfg = load_config(fullfile(projectRoot, 'config', configFiles{i}));

                defSpec = bms.analyzer.StructuralFilteredSeriesPipeline.spec('deflection');
                bearSpec = bms.analyzer.StructuralFilteredSeriesPipeline.spec('bearing_displacement');
                tiltSpec = bms.analyzer.StructuralFilteredSeriesPipeline.spec('tilt');

                tc.verifyEqual( ...
                    bms.analyzer.StructuralFilteredSeriesPipeline.resolveSubfolder(cfg, defSpec), ...
                    bms.config.ConfigReader.getSubfolder(cfg, 'deflection', defSpec.defaultSubfolder));
                tc.verifyEqual( ...
                    bms.analyzer.StructuralFilteredSeriesPipeline.resolveSubfolder(cfg, bearSpec), ...
                    bms.config.ConfigReader.getSubfolder(cfg, 'bearing_displacement', ...
                        bms.config.ConfigReader.getSubfolder(cfg, 'deflection', bearSpec.defaultSubfolder)));
                tc.verifyClass( ...
                    bms.analyzer.StructuralFilteredSeriesPipeline.groupsAsCell( ...
                        bms.analyzer.StructuralPlotConfigService.getGroups(cfg, 'bearing_displacement', {})), ...
                    'cell');
                tc.verifyEqual( ...
                    bms.analyzer.StructuralFilteredSeriesService.groupsAsCell( ...
                        bms.analyzer.StructuralPlotConfigService.getGroups(cfg, 'bearing_displacement', {})), ...
                    bms.analyzer.StructuralFilteredSeriesPipeline.groupsAsCell( ...
                        bms.analyzer.StructuralPlotConfigService.getGroups(cfg, 'bearing_displacement', {})));
                tc.verifyEqual( ...
                    bms.analyzer.StructuralFilteredSeriesPipeline.resolveSubfolder(cfg, tiltSpec), ...
                    bms.config.ConfigReader.getSubfolder(cfg, 'tilt', tiltSpec.defaultSubfolder));
                tc.verifyEqual( ...
                    bms.analyzer.StructuralFilteredPlotService.fileSuffixTag('Filtered'), ...
                    bms.analyzer.StructuralFilteredSeriesPipeline.fileSuffixTag('Filtered'));
            end
        end

        function structuralAnalyzersUseSharedPipelineAdapters(tc)
            defl = bms.analyzer.DeflectionAnalyzer('root', '2026-01-01', '2026-01-01', '', 'features', struct());
            tilt = bms.analyzer.TiltAnalyzer('root', '2026-01-01', '2026-01-01', '', 'wave', struct());
            bearing = bms.analyzer.BearingDisplacementAnalyzer('root', '2026-01-01', '2026-01-01', '', 'features', struct());

            tc.verifyEqual(defl.Key, 'deflection');
            tc.verifyEqual(tilt.Key, 'tilt');
            tc.verifyEqual(bearing.Key, 'bearing_displacement');
        end
    end
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

function values = constant_line_values(figPath)
    fig = openfig(figPath, 'invisible');
    cleaner = onCleanup(@() close(fig)); %#ok<NASGU>
    lines = findall(fig, '-isa', 'matlab.graphics.chart.decoration.ConstantLine');
    if isempty(lines)
        values = [];
        return;
    end
    values = sort(arrayfun(@(h) h.Value, lines));
end
