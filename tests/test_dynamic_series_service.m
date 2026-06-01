classdef test_dynamic_series_service < matlab.unittest.TestCase
    properties
        Root
    end

    methods (TestMethodSetup)
        function setupCase(tc)
            proj = fileparts(fileparts(mfilename('fullpath')));
            addpath(proj, fullfile(proj, 'pipeline'), fullfile(proj, 'analysis'));
            tc.Root = tempname;
            mkdir(fullfile(tc.Root, '2026-01-01', 'wave'));
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
        function sampleRateFallsBackUnlessAutoDetectIsEnabled(tc)
            times = datetime(2026, 1, 1, 0, 0, 0) + seconds(0:4)';

            tc.verifyEqual(bms.analyzer.DynamicSeriesService.sampleRate(times, false, 100), 100);
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.sampleRate(times, true, 100), 1);
        end

        function rmsSeriesUsesCoverageThreshold(tc)
            times = datetime(2026, 1, 1, 0, 0, 0) + seconds(0:5)';
            vals = [1; NaN; NaN; 1; 1; 1];

            [rmsVals, rmsMax, tMax] = bms.analyzer.DynamicSeriesService.rmsSeries(times, vals, 1, 3 / 60, 0.7);

            tc.verifySize(rmsVals, size(vals));
            tc.verifyTrue(isnan(rmsVals(2)));
            tc.verifyEqual(rmsMax, 1);
            tc.verifyEqual(tMax, times(4));
        end

        function rmsPeakForStatsIgnoresCleanedSparseNaNs(tc)
            times = datetime(2026, 1, 1, 0, 0, 0) + seconds(0:5)';
            vals = [2; 2; NaN; 2; 2; 2];

            [rmsMax, tMax] = bms.analyzer.DynamicSeriesService.rmsPeakForStats( ...
                times, vals, 1, 3 / 60, 3);

            tc.verifyEqual(rmsMax, 2);
            tc.verifyFalse(isnat(tMax));
        end

        function movingMeanSeriesMatchesWindWindowBehavior(tc)
            times = datetime(2026, 1, 1, 0, 0, 0) + seconds(0:5)';
            vals = [2; NaN; NaN; 4; 6; 8];

            [meanVals, meanMax, tMax] = bms.analyzer.DynamicSeriesService.movingMeanSeries(times, vals, 1, 3 / 60, 0.7);

            tc.verifySize(meanVals, size(vals));
            tc.verifyTrue(isnan(meanVals(2)));
            tc.verifyEqual(meanMax, 7);
            tc.verifyEqual(tMax, times(6));
        end

        function collectRecordLoadsStatsAndRmsPeak(tc)
            values = 2 * ones(601, 1);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'A1.csv'), values);
            cfg = dynamic_cfg();

            rec = bms.analyzer.DynamicSeriesService.collectRecord( ...
                tc.Root, 'wave', 'A1', '2026-01-01', '2026-01-01', cfg, 'acceleration', true, true);

            tc.verifyTrue(rec.has_data);
            tc.verifyEqual(rec.fs, 1);
            tc.verifyEqual(rec.mn, 2);
            tc.verifyEqual(rec.mx, 2);
            tc.verifyEqual(rec.av, 2);
            tc.verifyEqual(rec.rms_max, 2);
            tc.verifyFalse(isnat(rec.rms_time));
            tc.verifyEqual(numel(rec.vals), 601);
        end

        function dynamicStatsTableKeepsAnalyzerColumnNames(tc)
            rows = {'A1', 1, 2, 1.5, 0.5, datetime(2026, 1, 1, 0, 0, 0)};

            T = bms.analyzer.DynamicSeriesService.dynamicStatsTable(rows);

            tc.verifyEqual(T.Properties.VariableNames, ...
                {'PointID', 'Min', 'Max', 'Mean', 'RMS10minMax', 'RMSStartTime'});
        end

        function windStatsTableKeepsAnalyzerColumnNames(tc)
            rows = {'W1', 1, 3, 2, 2.5, datetime(2026, 1, 1, 0, 0, 0)};

            T = bms.analyzer.DynamicSeriesService.windStatsTable(rows);

            tc.verifyEqual(T.Properties.VariableNames, ...
                {'PointID', 'MinSpeed', 'MaxSpeed', 'MeanSpeed', 'Mean10minMax', 'Mean10minTime'});
        end

        function accelerationPipelineSpecKeepsOutputDirs(tc)
            spec = bms.analyzer.DynamicAccelerationPipeline.spec('acceleration');

            tc.verifyEqual(spec.moduleKey, 'acceleration');
            tc.verifyEqual(spec.sensorType, 'acceleration');
            tc.verifyEqual(spec.outputDir, '时程曲线_加速度');
            tc.verifyTrue(spec.keepSeries);
        end

        function cableAccelerationFallsBackToCableForcePoints(tc)
            cfg.points.cable_force = {'S1', 'S2'};
            spec = bms.analyzer.DynamicAccelerationPipeline.spec('cable_accel');

            points = bms.analyzer.DynamicAccelerationPipeline.resolvePoints(cfg, spec);

            tc.verifyEqual(points, {'S1'; 'S2'});
            tc.verifyEqual(bms.analyzer.DynamicAccelerationSeriesService.resolvePoints(cfg, spec), points);
            tc.verifyEqual(spec.sensorType, 'cable_accel');
            tc.verifyFalse(spec.keepSeries);
            tc.verifyTrue(spec.envelopeEnabled);
            tc.verifyEqual(spec.envelopeFilePrefix, 'CableAccelEnvelope30');
        end

        function cableAccelerationWritesEnvelopePlot(tc)
            values = sin((0:600)' / 30);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'C1.csv'), values);
            cfg = dynamic_cfg();
            cfg.points = struct('cable_accel', {{'C1'}});
            cfg.plot_common = struct('save_fig', false, 'append_timestamp', false);
            cfg.plot_styles = struct('cable_accel', struct( ...
                'ylim_auto', true, ...
                'envelope_bin_minutes', 10));
            spec = bms.analyzer.DynamicAccelerationPipeline.spec('cable_accel');
            style = bms.analyzer.DynamicAccelerationPipeline.plotStyle(cfg, spec);
            stats = cell(1, 6);

            bms.analyzer.DynamicAccelerationPipeline.runWithOptionalParallel( ...
                tc.Root, 'wave', '2026-01-01', '2026-01-01', cfg, true, {'C1'}, style, stats, spec);

            tc.verifyGreaterThanOrEqual(numel(dir(fullfile(tc.Root, spec.envelopeOutputDir, '*.jpg'))), 1);
        end

        function envelopeBandBreaksAcrossMissingBins(tc)
            fig = figure('Visible', 'off');
            cleaner = onCleanup(@() close(fig)); %#ok<NASGU>
            ax = axes(fig);
            t = datetime(2026, 1, 1, 0, 0, 0) + minutes(0:5)';
            lo = [1; 1; NaN; NaN; 2; 2];
            hi = [2; 2; NaN; NaN; 3; 3];

            bms.analyzer.DynamicAccelerationPlotService.fillEnvelopeBand(ax, t, lo, hi, [0.5 0.5 0.8], 'band');

            patches = findall(ax, 'Type', 'patch');
            tc.verifyNumElements(patches, 2);
        end

        function accelerationPipelineDelegatesStyleResolution(tc)
            cfg.plot_styles.acceleration = struct('ylabel', 'Custom Accel', 'ylim_auto', true);
            spec = bms.analyzer.DynamicAccelerationPipeline.spec('acceleration');

            pipelineStyle = bms.analyzer.DynamicAccelerationPipeline.plotStyle(cfg, spec);
            serviceStyle = bms.analyzer.DynamicAccelerationSeriesService.plotStyle(cfg, spec);

            tc.verifyEqual(serviceStyle.ylabel, pipelineStyle.ylabel);
            tc.verifyTrue(serviceStyle.ylim_auto);
        end

        function accelerationPipelineWritesConfiguredGroupPlots(tc)
            values = sin((0:600)' / 30);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'A1.csv'), values);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'A2.csv'), values * 0.5);
            cfg = dynamic_cfg();
            cfg.points = struct('acceleration', {{'A1', 'A2'}});
            cfg.groups = struct('acceleration', struct('G1', {{'A1', 'A2'}}));
            cfg.plot_common = struct('save_fig', false, 'append_timestamp', false);
            cfg.plot_styles = struct('acceleration', struct( ...
                'ylim_auto', true, ...
                'group_output_dir', 'accel_group', ...
                'rms_group_output_dir', 'accel_rms_group', ...
                'group_labels', struct('G1', 'Main span')));
            spec = bms.analyzer.DynamicAccelerationPipeline.spec('acceleration');
            style = bms.analyzer.DynamicAccelerationPipeline.plotStyle(cfg, spec);
            stats = cell(2, 6);

            bms.analyzer.DynamicAccelerationPipeline.runSequential( ...
                tc.Root, 'wave', '2026-01-01', '2026-01-01', cfg, true, {'A1', 'A2'}, style, stats, spec);

            tc.verifyGreaterThanOrEqual(numel(dir(fullfile(tc.Root, 'accel_group', '*.jpg'))), 1);
            tc.verifyGreaterThanOrEqual(numel(dir(fullfile(tc.Root, 'accel_rms_group', '*.jpg'))), 1);
        end

        function accelerationGroupWarnLinesResolveByGroupName(tc)
            style = struct();
            style.rms_warn_lines = struct( ...
                'ZG', {{struct('y', 100, 'label', 'Level 1'), struct('y', 300, 'label', 'Level 2')}}, ...
                'ZL', {{struct('y', 31.5, 'label', 'Level 1'), struct('y', 50, 'label', 'Level 2')}});

            warnLines = bms.analyzer.DynamicAccelerationPlotService.resolveGroupWarnLines( ...
                style, 'rms_warn_lines', 'ZL');

            tc.verifyEqual(numel(warnLines), 2);
            tc.verifyEqual(cellfun(@(x) x.y, warnLines), [31.5; 50]);
        end

        function accelerationGroupWarnLinesResolveGlobalList(tc)
            style = struct();
            style.rms_warn_lines = [ ...
                struct('y', 100, 'label', 'Level 1'), ...
                struct('y', 300, 'label', 'Level 2')];

            warnLines = bms.analyzer.DynamicAccelerationPlotService.resolveGroupWarnLines( ...
                style, 'rms_warn_lines', 'AnyGroup');

            tc.verifyEqual(numel(warnLines), 2);
            tc.verifyEqual(reshape(cellfun(@(x) x.y, warnLines), [], 1), [100; 300]);
        end

        function cableAccelerationSpecDisablesRawGroupWarnLines(tc)
            spec = bms.analyzer.DynamicAccelerationPipeline.spec('cable_accel');
            style.group_warn_lines = [ ...
                struct('y', 100, 'label', 'Level 1'), ...
                struct('y', 300, 'label', 'Level 2')];

            warnField = bms.analyzer.DynamicAccelerationPlotService.specField(spec, 'groupWarnField', 'group_warn_lines');
            warnLines = bms.analyzer.DynamicAccelerationPlotService.resolveGroupWarnLines( ...
                style, warnField, 'X6_X16');

            tc.verifyEqual(warnField, '');
            tc.verifyEmpty(warnLines);
        end

        function accelerationPointsFallBackToGroups(tc)
            cfg = dynamic_cfg();
            cfg.points = struct();
            cfg.groups = struct('acceleration', struct('G1', {{'A1', 'A2'}}, 'G2', {{'A2', 'A3'}}));
            spec = bms.analyzer.DynamicAccelerationPipeline.spec('acceleration');

            points = bms.analyzer.DynamicAccelerationPipeline.resolvePoints(cfg, spec);

            tc.verifyEqual(points, {'A1'; 'A2'; 'A3'});
        end
    end
end

function cfg = dynamic_cfg()
    cfg = struct();
    cfg.defaults = struct('header_marker', 'Time');
    cfg.subfolders = struct('acceleration', 'wave');
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
