classdef test_wind_analysis_pipeline < matlab.unittest.TestCase
    properties
        ProjectRoot
        Root
    end

    methods (TestMethodSetup)
        function makeTempRoot(tc)
            tc.Root = tempname;
            mkdir(tc.Root);
            tc.addTeardown(@() rmdir(tc.Root, 's'));
        end
    end

    methods (TestClassSetup)
        function addPaths(tc)
            tc.ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(tc.ProjectRoot, ...
                fullfile(tc.ProjectRoot, 'config'), ...
                fullfile(tc.ProjectRoot, 'pipeline'), ...
                fullfile(tc.ProjectRoot, 'analysis'));
        end
    end

    methods (Test)
        function bridgeConfigsResolveWindInputs(tc)
            configFiles = { ...
                'default_config.json', ...
                'hongtang_config.json', ...
                'jiulongjiang_config.json', ...
                'shuixianhua_config.json'};

            for i = 1:numel(configFiles)
                cfg = load_config(fullfile(tc.ProjectRoot, 'config', configFiles{i}));

                subfolder = bms.analyzer.WindAnalysisPipeline.resolveSubfolder(cfg);
                expectedSubfolder = bms.config.ConfigReader.getSubfolder(cfg, 'wind_raw', '波形');
                tc.verifyEqual(subfolder, expectedSubfolder, configFiles{i});
                tc.verifyEqual(bms.analyzer.WindSeriesService.resolveSubfolder(cfg), subfolder, configFiles{i});

                points = bms.analyzer.WindAnalysisPipeline.resolvePoints(cfg);
                tc.verifyTrue(iscell(points), configFiles{i});
                tc.verifyEqual(bms.analyzer.WindSeriesService.resolvePoints(cfg), points, configFiles{i});

                style = bms.analyzer.WindAnalysisPipeline.style(cfg);
                serviceStyle = bms.analyzer.WindPlotService.style(cfg);
                tc.verifyEqual(serviceStyle.output.root_dir, style.output.root_dir, configFiles{i});
                tc.verifyNotEmpty(style.output.root_dir, configFiles{i});
                tc.verifyNotEmpty(style.output.speed_dir, configFiles{i});
                tc.verifyNotEmpty(style.output.direction_dir, configFiles{i});
                tc.verifyNotEmpty(style.output.speed10_dir, configFiles{i});
                tc.verifyNotEmpty(style.output.rose_dir, configFiles{i});
                tc.verifyNotEmpty(bms.analyzer.WindAnalysisPipeline.statsFileName(cfg), configFiles{i});

                params = bms.analyzer.WindAnalysisPipeline.params(cfg, 'W1');
                tc.verifyEqual(bms.analyzer.WindSeriesService.params(cfg, 'W1'), params, configFiles{i});
                tc.verifyGreaterThan(params.window_minutes, 0, configFiles{i});
                tc.verifyGreaterThan(params.sector_deg, 0, configFiles{i});
                tc.verifyGreaterThan(numel(params.speed_bins), 1, configFiles{i});
            end
        end

        function perPointWindParamsOverrideDefaults(tc)
            cfg.wind_params = struct( ...
                'alarm_levels', [20 25 30], ...
                'window_minutes', 10, ...
                'decimals', 2, ...
                'speed_bins', [0 5 10], ...
                'sector_deg', 22.5);
            cfg.per_point.wind.W_1 = struct( ...
                'alarm_levels', [10 11], ...
                'window_minutes', 3, ...
                'decimals', 1, ...
                'speed_bins', [0 1 2 3], ...
                'sector_deg', 45);

            params = bms.analyzer.WindAnalysisPipeline.params(cfg, 'W-1');

            tc.verifyEqual(params.alarm_levels, [10 11]);
            tc.verifyEqual(params.window_minutes, 3);
            tc.verifyEqual(params.decimals, 1);
            tc.verifyEqual(params.speed_bins, [0 1 2 3]);
            tc.verifyEqual(params.sector_deg, 45);
        end

        function windAnalyzerUsesPipelineEntryPoint(tc)
            analyzer = bms.analyzer.WindAnalyzer('root', '2026-01-01', '2026-01-01', '', 'wave', struct());

            tc.verifyClass(analyzer, 'bms.analyzer.WindAnalyzer');
            tc.verifyEqual(analyzer.Key, 'wind');
        end

        function windPointUsesRollingLookaheadAndRecordsProvenance(tc)
            mkdir(fullfile(tc.Root, '2026-01-01', 'wave'));
            mkdir(fullfile(tc.Root, '2026-01-02', 'wave'));
            firstTimes = [datetime(2026, 1, 1, 0, 0, 0); datetime(2026, 1, 1, 8, 59, 59)];
            nextTimes = [datetime(2026, 1, 1, 9, 0, 0); datetime(2026, 1, 1, 12, 0, 0); datetime(2026, 1, 1, 23, 59, 59)];
            write_wind_csv_times(fullfile(tc.Root, '2026-01-01', 'wave', 'SPEED.csv'), firstTimes, [1; 2]);
            write_wind_csv_times(fullfile(tc.Root, '2026-01-02', 'wave', 'SPEED.csv'), nextTimes, [3; -44; 5]);
            write_wind_csv_times(fullfile(tc.Root, '2026-01-01', 'wave', 'DIR.csv'), firstTimes, [90; 100]);
            write_wind_csv_times(fullfile(tc.Root, '2026-01-02', 'wave', 'DIR.csv'), nextTimes, [110; 120; 130]);
            cfg = rolling_wind_cfg();

            [row, series] = bms.analyzer.WindSeriesService.analyzePoint( ...
                tc.Root, 'wave', 'W1', '2026-01-01', '2026-01-01', cfg);

            tc.verifyEqual(series.tSpeed, [firstTimes; nextTimes]);
            tc.verifyEqual(series.vSpeed([1 2 3 5]), [1; 2; 3; 5]);
            tc.verifyTrue(isnan(series.vSpeed(4)));
            tc.verifyEqual(series.tDir, [firstTimes; nextTimes]);
            tc.verifyEqual(series.vDir, [90; 100; 110; 120; 130]);
            tc.verifyEqual(row{2}, 1);
            tc.verifyEqual(row{3}, 5);
            tc.verifyEqual(row{4}, 2.75);
            tc.verifyEqual(series.speed_source_provenance.complete_day_count, 1);
            tc.verifyEqual(series.speed_source_provenance.source_file_count, 2);
            tc.verifyEqual(series.speed_source_provenance.source_sample_count, 5);
            tc.verifyEqual(series.speed_source_provenance.finite_source_sample_count, 4);
            tc.verifyEqual(series.direction_source_provenance.source_file_count, 2);
            tc.verifyEqual(series.direction_source_provenance.finite_source_sample_count, 5);
        end

        function hongtangWindRulesRejectNegativeSpeedAndInvalidDirection(tc)
            cfg = load_config(fullfile(tc.ProjectRoot, 'config', 'hongtang_config.json'));
            speedRules = bms.data.CleaningPipeline.resolveRules(cfg, 'wind_speed', 'W1');
            directionRules = bms.data.CleaningPipeline.resolveRules(cfg, 'wind_direction', 'W1');

            speed = bms.data.CleaningPipeline.applyThresholds([-1; 0; 12], ...
                datetime(2026, 1, 1) + seconds(0:2)', speedRules.thresholds);
            direction = bms.data.CleaningPipeline.applyThresholds([-1; 0; 360; 361], ...
                datetime(2026, 1, 1) + seconds(0:3)', directionRules.thresholds);

            tc.verifyTrue(isnan(speed(1)));
            tc.verifyEqual(speed(2:3), [0; 12]);
            tc.verifyTrue(isnan(direction(1)));
            tc.verifyEqual(direction(2:3), [0; 360]);
            tc.verifyTrue(isnan(direction(4)));
        end

        function windPlotsCarrySpeedAndDirectionSourceProvenance(tc)
            cfg = rolling_wind_cfg();
            cfg.plot_common = struct( ...
                'save_jpg', false, 'save_emf', false, 'save_fig', false, ...
                'append_timestamp', false, 'dynamic_raw_sampling_mode', 'full');
            style = bms.analyzer.WindPlotService.style(cfg);
            style.output.root_dir = 'wind_output';
            times = datetime(2026, 1, 1, 0, 0, 0) + minutes((0:4)');
            source = bms.analyzer.DynamicSeriesService.initSourceProvenance(1);
            source.complete_day_count = 1;
            source.source_files = {'source.mat'};
            source.source_file_count = 1;
            source.source_sample_count = 5;
            source.finite_source_sample_count = 5;
            series = bms.analyzer.WindSeriesService.seriesStruct( ...
                'W1', times, [1; 2; 3; 4; 5], times, [0; 45; 90; 135; 180], ...
                bms.analyzer.WindSeriesService.params(cfg, 'W1'));
            series.t10 = times;
            series.v10 = [1; 2; 3; 4; 5];
            series.speed_source_provenance = source;
            series.direction_source_provenance = source;

            outRoot = fullfile(tc.Root, style.output.root_dir);
            mkdir(outRoot);
            bms.analyzer.WindPlotService.plotPoint( ...
                series, style, outRoot, '2026-01-01', '2026-01-01', cfg);

            speedJson = dir(fullfile(outRoot, style.output.speed_dir, '*.plot.json'));
            speed10Json = dir(fullfile(outRoot, style.output.speed10_dir, '*.plot.json'));
            roseJson = dir(fullfile(outRoot, style.output.rose_dir, '*.plot.json'));
            tc.verifyEqual(numel(speedJson), 1);
            tc.verifyEqual(numel(speed10Json), 1);
            tc.verifyEqual(numel(roseJson), 1);
            speedPayload = jsondecode(fileread(fullfile(speedJson(1).folder, speedJson(1).name)));
            rosePayload = jsondecode(fileread(fullfile(roseJson(1).folder, roseJson(1).name)));
            tc.verifyEqual(speedPayload.series(1).source.source_file_count, 1);
            tc.verifyEqual(numel(rosePayload.series), 2);
            tc.verifyTrue(all(arrayfun(@(x) x.source.source_sample_count == 5, rosePayload.series)));
        end

        function windRoseLabelsUseMeteorologicalCompassOrientation(tc)
            fig = figure('Visible', 'off');
            cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
            ax = axes(fig);
            bms.analyzer.WindPlotService.drawDirectionLabels(ax, 1);

            north = findobj(ax, 'Type', 'text', 'String', 'N');
            east = findobj(ax, 'Type', 'text', 'String', 'E');
            tc.verifyEqual(numel(north), 1);
            tc.verifyEqual(numel(east), 1);
            tc.verifyEqual(north.Position(1), 0, 'AbsTol', 1e-12);
            tc.verifyGreaterThan(north.Position(2), 0);
            tc.verifyGreaterThan(east.Position(1), 0);
            tc.verifyEqual(east.Position(2), 0, 'AbsTol', 1e-12);
        end

        function windRoseRadialLabelsDoNotOverlapEastCompassLabel(tc)
            fig = figure('Visible', 'off');
            cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
            ax = axes(fig);
            hold(ax, 'on');
            bms.analyzer.WindPlotService.drawPolarGrid(ax, 0.2);

            labels = findobj(ax, 'Type', 'text');
            tc.verifyEqual(numel(labels), 4);
            positions = vertcat(labels.Position);
            tc.verifyTrue(all(positions(:, 1) > 0));
            tc.verifyTrue(all(positions(:, 2) > 0));
        end
    end
end

function cfg = rolling_wind_cfg()
cfg = struct();
cfg.defaults = struct( ...
    'header_marker', 'Time', ...
    'wind_speed', struct('thresholds', struct('min', 0)), ...
    'wind_direction', struct('thresholds', struct('min', 0, 'max', 360)));
cfg.subfolders = struct('wind_raw', 'wave');
cfg.points = struct('wind', {{'W1'}});
cfg.file_patterns = struct( ...
    'wind_speed', struct('default', '{file_id}.csv'), ...
    'wind_direction', struct('default', '{file_id}.csv'));
cfg.per_point = struct('wind', struct('W1', struct( ...
    'speed_point_id', 'SPEED', 'dir_point_id', 'DIR', ...
    'window_minutes', 10, 'decimals', 2)));
end

function write_wind_csv_times(path, times, values)
assert(numel(times) == numel(values), 'Times and values must have equal length.');
fid = fopen(path, 'w', 'n', 'UTF-8');
assert(fid > 0, 'Failed to create wind test csv.');
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, 'Time,Value\n');
for i = 1:numel(values)
    fprintf(fid, '%s,%.6f\n', datestr(times(i), 'yyyy-mm-dd HH:MM:SS.FFF'), values(i));
end
end
