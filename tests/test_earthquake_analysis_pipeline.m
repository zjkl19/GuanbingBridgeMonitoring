classdef test_earthquake_analysis_pipeline < matlab.unittest.TestCase
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
        function earthquakePipelineWritesComponentPlots(tc)
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'EQ-UT-X.csv'), [0.1; 0.4; 0.2]);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'EQ-UT-Y.csv'), [0.2; 0.5; 0.3]);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'EQ-UT-Z.csv'), [0.3; 0.6; 0.4]);
            cfg = eq_cfg();

            analyze_eq_points(tc.Root, '2026-01-01', '2026-01-01', 'wave', cfg);

            figs = dir(fullfile(tc.Root, 'eq_out', 'series', '*.fig'));
            tc.verifyGreaterThanOrEqual(numel(figs), 3);
            names = string({figs.name});
            tc.verifyTrue(any(contains(names, 'EQ_X_2026-01-01_2026-01-01')));
            tc.verifyTrue(any(contains(names, 'EQ_Y_2026-01-01_2026-01-01')));
            tc.verifyTrue(any(contains(names, 'EQ_Z_2026-01-01_2026-01-01')));

            statsPath = fullfile(tc.Root, 'stats', 'eq_stats.xlsx');
            tc.verifyTrue(isfile(statsPath));
            T = readtable(statsPath, 'TextType', 'string');
            tc.verifyEqual(height(T), 3);
            tc.verifyTrue(all(ismember({'PointID', 'Component', 'Peak', 'PeakSigned', 'PeakTime'}, T.Properties.VariableNames)));
            tc.verifyEqual(sort(T.Component), ["X"; "Y"; "Z"]);
            tc.verifyEqual(max(T.Peak), 0.6, 'AbsTol', 1e-12);

            provenanceFiles = dir(fullfile(tc.Root, 'eq_out', 'series', '*.plot.json'));
            tc.verifyEqual(numel(provenanceFiles), 3);
            payload = jsondecode(fileread(fullfile( ...
                provenanceFiles(1).folder, provenanceFiles(1).name)));
            tc.verifyTrue(isfield(payload.series(1), 'source'));
            tc.verifyEqual(payload.series(1).source.calendar_day_count_requested, 1);
            tc.verifyEqual(payload.series(1).source.source_sample_count, 3);
            tc.verifyEqual(payload.series(1).source.finite_source_sample_count, 3);
            tc.verifyEqual(payload.series(1).source.completeness_scope, ...
                'required_export_contribution');
        end

        function earthquakeStatsExposeSignedPeakValue(tc)
            rec = bms.analyzer.EarthquakeSeriesService.initRecord();
            rec.pid = 'EQ-UT-Y';
            rec.comp = 'Y';
            rec.has_data = true;
            rec.times = datetime(2026, 1, 1, 0, 0, 0) + seconds(0:2)';
            rec.vals = [0.2; -0.9; 0.8];
            rec.peak = 0.9;
            rec.peak_signed = -0.9;
            rec.peak_time = rec.times(2);

            T = bms.analyzer.EarthquakeAnalysisPipeline.statsTable(rec);

            tc.verifyEqual(T.Peak, 0.9, 'AbsTol', 1e-12);
            tc.verifyEqual(T.PeakSigned, -0.9, 'AbsTol', 1e-12);
            tc.verifyEqual(T.PeakTime, "2026-01-01 00:00:01");
        end

        function bridgeConfigsResolveEarthquakePipelineInputs(tc)
            configFiles = { ...
                'default_config.json', ...
                'hongtang_config.json', ...
                'jiulongjiang_config.json', ...
                'shuixianhua_config.json'};

            for i = 1:numel(configFiles)
                cfg = load_config(fullfile(tc.ProjectRoot, 'config', configFiles{i}));
                style = bms.analyzer.EarthquakeAnalysisPipeline.style(cfg);
                points = bms.analyzer.EarthquakeAnalysisPipeline.resolvePoints(cfg);
                params = bms.analyzer.EarthquakeAnalysisPipeline.params(cfg, '');

                tc.verifyEqual( ...
                    bms.analyzer.EarthquakeAnalysisPipeline.resolveSubfolder(cfg), ...
                    bms.config.ConfigReader.getSubfolder(cfg, 'eq_raw', '波形'), configFiles{i});
                tc.verifyTrue(iscell(points), configFiles{i});
                tc.verifyNotEmpty(style.output.root_dir, configFiles{i});
                tc.verifyNotEmpty(style.output.series_dir, configFiles{i});
                tc.verifyTrue(isnumeric(params.alarm_levels), configFiles{i});
            end
        end

        function earthquakeParamsCarryScalingAndRawFilter(tc)
            cfg = eq_cfg();
            cfg.eq_params.raw_min_filter = -50;
            cfg.eq_params.value_scale = 0.01;

            params = bms.analyzer.EarthquakeAnalysisPipeline.params(cfg, 'EQ-UT-X');

            tc.verifyEqual(params.alarm_levels, [0.5, 1.0]);
            tc.verifyEqual(params.raw_min_filter, -50);
            tc.verifyEqual(params.value_scale, 0.01);
        end

        function earthquakeAnalyzerUsesSharedPipelineAdapter(tc)
            analyzer = bms.analyzer.EarthquakeAnalyzer('root', '2026-01-01', '2026-01-01', '', 'wave', struct());

            tc.verifyEqual(analyzer.Key, 'earthquake');
            tc.verifyEqual(analyzer.Points, {});
        end
    end
end

function cfg = eq_cfg()
    cfg = struct();
    cfg.defaults = struct('header_marker', 'Time');
    cfg.subfolders = struct('eq_raw', 'wave');
    cfg.points = struct('eq', {{'EQ-UT-X', 'EQ-UT-Y', 'EQ-UT-Z'}});
    cfg.file_patterns = struct();
    cfg.file_patterns.eq_x = struct('default', '{point}.csv', 'per_point', struct());
    cfg.file_patterns.eq_y = struct('default', '{point}.csv', 'per_point', struct());
    cfg.file_patterns.eq_z = struct('default', '{point}.csv', 'per_point', struct());
    cfg.eq_params = struct('alarm_levels', [0.5, 1.0]);
    cfg.plot_styles = struct('eq', struct( ...
        'output', struct('root_dir', 'eq_out', 'series_dir', 'series', 'prefix', 'EQ'), ...
        'ylabel', 'EQ acceleration', ...
        'title_prefix', 'EQ', ...
        'ylim_auto', true, ...
        'color', [0 0.447 0.741]));
end

function write_series_csv(path, values)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid > 0, 'Failed to create test csv.');
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'Time,Value\n');
    base = datetime(2026, 1, 1, 0, 0, 0);
    for i = 1:numel(values)
        fprintf(fid, '%s,%.6f\n', datestr(base + seconds(i - 1), 'yyyy-mm-dd HH:MM:SS.FFF'), values(i));
    end
end
