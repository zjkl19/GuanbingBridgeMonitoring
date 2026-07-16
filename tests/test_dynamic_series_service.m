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

        function binnedCoverageRateHandlesBurstyRollingExports(tc)
            base = datetime(2026, 1, 1, 0, 0, 0);
            times = datetime.empty(0, 1);
            for minuteIndex = 0:59
                burst = base + minutes(minuteIndex) + seconds((0:1199)' / 250);
                times = [times; burst]; %#ok<AGROW>
            end
            vals = 3 * ones(size(times));

            tc.verifyEqual( ...
                bms.analyzer.DynamicSeriesService.sampleRate(times, true, 1), ...
                250, 'RelTol', 1e-9);
            coverageFs = bms.analyzer.DynamicSeriesService.binnedCoverageSampleRate( ...
                times, 10, 1);
            tc.verifyEqual(coverageFs, 20, 'RelTol', 1e-12);

            [~, means, meanMax] = bms.analyzer.DynamicSeriesService.movingMeanByTimeBins( ...
                times, vals, 10, 0.7, coverageFs, true);
            tc.verifyEqual(nnz(isfinite(means)), 6);
            tc.verifyEqual(meanMax, 3, 'AbsTol', 1e-12);
        end

        function isolatedHighRateBurstDoesNotQualifyAsTenMinuteMean(tc)
            base = datetime(2026, 1, 1, 0, 0, 0);
            times = base + seconds((0:1199)' / 250);
            vals = 9 * ones(size(times));

            coverageFs = bms.analyzer.DynamicSeriesService.binnedCoverageSampleRate( ...
                times, 10, 1);
            tc.verifyEqual(coverageFs, 2, 'RelTol', 1e-12);

            [~, means, meanMax, meanTime] = ...
                bms.analyzer.DynamicSeriesService.movingMeanByTimeBins( ...
                    times, vals, 10, 0.7, coverageFs, true);
            tc.verifyEqual(nnz(isfinite(means)), 0);
            tc.verifyTrue(isnan(meanMax));
            tc.verifyTrue(isnat(meanTime));
        end

        function windTemporalCoverageRequiresSevenOfTenSlices(tc)
            base = datetime(2026, 1, 1, 0, 0, 0);
            sixSlices = base + minutes((0:5)') + seconds(1);
            sevenSlices = base + minutes((0:6)') + seconds(1);
            [~, sixMeans] = bms.analyzer.DynamicSeriesService.movingMeanByTimeBins( ...
                sixSlices, ones(size(sixSlices)), 10, 0.7, 1/60, true);
            [~, sevenMeans] = bms.analyzer.DynamicSeriesService.movingMeanByTimeBins( ...
                sevenSlices, ones(size(sevenSlices)), 10, 0.7, 1/60, true);

            tc.verifyEqual(nnz(isfinite(sixMeans)), 0);
            tc.verifyEqual(nnz(isfinite(sevenMeans)), 1);
        end

        function temporalCoverageIgnoresNaNOnlySlicesAndHandlesWindowBoundary(tc)
            base = datetime(2026, 1, 1, 0, 0, 0);
            times = base + minutes((0:7)') + seconds(1);
            vals = ones(size(times));
            vals(4) = NaN;
            times(end) = base + minutes(10); % belongs to the next window
            [~, means] = bms.analyzer.DynamicSeriesService.movingMeanByTimeBins( ...
                times, vals, 10, 0.7, 1/60, true);

            tc.verifyEqual(nnz(isfinite(means)), 0);
        end

        function rmsKeepsEstablishedCountCoverageWithoutTemporalSlicing(tc)
            base = datetime(2026, 1, 1, 0, 0, 0);
            times = base + seconds((0:1199)' / 250);
            vals = 3 * ones(size(times));
            coverageFs = bms.analyzer.DynamicSeriesService.binnedCoverageSampleRate( ...
                times, 10, 1);

            [~, rmsValues, rmsMax] = bms.analyzer.DynamicSeriesService.rmsByTimeBins( ...
                times, vals, 10, 0.7, coverageFs);

            tc.verifyEqual(nnz(isfinite(rmsValues)), 1);
            tc.verifyEqual(rmsMax, 3, 'AbsTol', 1e-12);
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

        function timeBinAggregatesRespectCoverageThreshold(tc)
            base = datetime(2026, 1, 1, 0, 0, 0);
            times = base + seconds(0:1199)';
            vals = [2 * ones(600, 1); 4 * ones(600, 1)];
            vals(100:500) = NaN;

            [binTimes, rmsVals, rmsMax, tMax] = bms.analyzer.DynamicSeriesService.rmsByTimeBins( ...
                times, vals, 10, 0.7, 1);
            [meanTimes, meanVals, meanMax, meanTMax] = bms.analyzer.DynamicSeriesService.movingMeanByTimeBins( ...
                times, vals, 10, 0.7, 1);

            tc.verifyGreaterThanOrEqual(numel(rmsVals), 2);
            tc.verifyTrue(isnan(rmsVals(1)));
            tc.verifyEqual(rmsVals(2), 4);
            tc.verifyEqual(rmsMax, 4);
            tc.verifyEqual(tMax, base + minutes(15));
            tc.verifyEqual(meanTimes, binTimes);
            tc.verifyTrue(isnan(meanVals(1)));
            tc.verifyEqual(meanVals(2), 4);
            tc.verifyEqual(meanMax, 4);
            tc.verifyEqual(meanTMax, base + minutes(15));
        end

        function limitSeriesPointsKeepsCriticalExtrema(tc)
            times = datetime(2026, 1, 1, 0, 0, 0) + seconds(0:99)';
            vals = zeros(100, 1);
            vals(37) = -20;
            vals(73) = 8;

            [keptTimes, keptVals] = bms.analyzer.DynamicSeriesService.limitSeriesPoints(times, vals, 10);

            tc.verifyTrue(any(keptTimes == times(37)));
            tc.verifyTrue(any(keptTimes == times(73)));
            tc.verifyTrue(any(abs(keptVals + 20) < 1e-12));
            tc.verifyTrue(any(abs(keptVals - 8) < 1e-12));

            spikeIdx = (5:10:95).';
            vals = zeros(100, 1);
            vals(spikeIdx) = (1:numel(spikeIdx)).';
            [~, keptVals] = bms.analyzer.DynamicSeriesService.limitSeriesPoints(times, vals, 40);

            tc.verifyLessThanOrEqual(numel(keptVals), 40);
            tc.verifyTrue(all(ismember((1:numel(spikeIdx)).', keptVals)));
        end

        function rawPlotPerDayMaxCanExceedCommonLimit(tc)
            cfg.plot_common = struct( ...
                'fig_max_points', 50000, ...
                'dynamic_raw_fig_max_points', 1200000, ...
                'dynamic_raw_min_points_per_day', 12000, ...
                'dynamic_raw_line_width', 1.2, ...
                'dynamic_raw_render_mode', 'dense_band', ...
                'dynamic_raw_band_bins', 48000, ...
                'dynamic_raw_band_line_width', 0.45, ...
                'dynamic_raw_trace_points', 0);

            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawPlotMaxPoints(cfg, 50000), 1200000);
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawPlotPerDayMax(cfg, 90, 50000), 13334);
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawPlotLineWidth(cfg, 1.0), 1.2);
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawPlotRenderMode(cfg, 'line'), 'dense_band');
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawPlotBandBins(cfg, 1000), 48000);
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawPlotBandLineWidth(cfg, 0.4), 0.45);
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawPlotTracePoints(cfg, 120000), 0);

            opts = bms.analyzer.DynamicSeriesService.rawPlotOptions(cfg, 50000);
            tc.verifyEqual(opts.fig_max_points, 1200000);
            tc.verifyEqual(opts.raw_render_mode, 'dense_band');
            tc.verifyEqual(opts.raw_band_bins, 48000);
            tc.verifyEqual(opts.raw_band_line_width, 0.45);
            tc.verifyEqual(opts.raw_trace_points, 0);

            cfg.plot_common = struct('fig_max_points', 50000);
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawPlotPerDayMax(cfg, 90, 50000), 556);
        end

        function fullRawSamplingUsesPeakPreservingRenderBudget(tc)
            cfg.plot_common = struct( ...
                'dynamic_raw_sampling_mode', 'full', ...
                'dynamic_raw_full_render_policy', 'peak_preserving', ...
                'dynamic_raw_fig_max_points', 1200000, ...
                'dynamic_raw_render_mode', 'dense_band');

            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawSamplingMode(cfg), 'full');
            tc.verifyTrue(bms.analyzer.DynamicSeriesService.isFullRawSampling(cfg));
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawFullRenderPolicy(cfg), 'peak_preserving');
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawPlotMaxPoints(cfg, 50000), 1200000);
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawPlotPerDayMax(cfg, 90, 50000), 13334);
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawPlotRenderMode(cfg, 'dense_band'), 'line');

            opts = bms.analyzer.DynamicSeriesService.rawPlotOptions(cfg, 50000);
            tc.verifyEqual(opts.fig_max_points, 1200000);
            tc.verifyEqual(opts.raw_render_mode, 'line');
            tc.verifyEqual(opts.raw_sampling_mode, 'full');
            tc.verifyEqual(opts.reduction_scope, 'render_only');
            tc.verifyEqual(opts.reduction_algorithm, 'peak_preserving_bucket_minmax_v1');
        end

        function unspecifiedFullRenderPolicyPreservesLegacyAllVertices(tc)
            cfg.plot_common = struct('dynamic_raw_sampling_mode', 'full');

            tc.verifyEqual( ...
                bms.analyzer.DynamicSeriesService.rawFullRenderPolicy(cfg), ...
                'all_vertices');
            tc.verifyEqual( ...
                bms.analyzer.DynamicSeriesService.rawPlotMaxPoints(cfg, 50000), ...
                Inf);
            tc.verifyEqual( ...
                bms.analyzer.DynamicSeriesService.rawPlotPerDayMax(cfg, 90, 50000), ...
                Inf);
        end

        function legacyAllVertexPolicyRemainsExplicitlyAvailable(tc)
            cfg.plot_common = struct( ...
                'dynamic_raw_sampling_mode', 'full', ...
                'dynamic_raw_full_render_policy', 'all_vertices');

            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawPlotMaxPoints(cfg, 50000), Inf);
            tc.verifyEqual(bms.analyzer.DynamicSeriesService.rawPlotPerDayMax(cfg, 90, 50000), Inf);
        end

        function moduleOverrideChangesPlotRetentionButNotDynamicStatistics(tc)
            values = sin((1:4000)' / 17);
            values(123) = -3.5;
            values(3210) = 4.25;
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'MODULE.csv'), values);

            cappedCfg = dynamic_cfg();
            cappedCfg.plot_common = struct('fig_max_points', 1000);
            moduleCfg = cappedCfg;
            moduleCfg.plot_common.dynamic_raw_modules.acceleration = struct( ...
                'sampling_mode', 'full', ...
                'line_width', 1.0, ...
                'render_mode', 'line', ...
                'full_render_policy', 'peak_preserving', ...
                'render_max_points', 1200000, ...
                'min_points_per_day', 12000, ...
                'gap_mode', 'connect');
            spec = bms.analyzer.DynamicAccelerationPipeline.spec('acceleration');

            capped = bms.analyzer.DynamicSeriesService.collectRecord( ...
                tc.Root, 'wave', 'MODULE', '2026-01-01', '2026-01-01', ...
                cappedCfg, 'acceleration', true, true);
            full = bms.analyzer.DynamicAccelerationSeriesService.collectRecord( ...
                tc.Root, 'wave', 'MODULE', '2026-01-01', '2026-01-01', ...
                moduleCfg, true, spec, true);
            effective = bms.analyzer.DynamicAccelerationSeriesService.modulePlotConfig(moduleCfg, spec);

            tc.verifyLessThan(numel(capped.vals), numel(values));
            tc.verifyEqual(numel(full.vals), numel(values));
            tc.verifyEqual([full.mn full.mx full.av full.rms_max], ...
                [capped.mn capped.mx capped.av capped.rms_max], 'AbsTol', 1e-12);
            tc.verifyEqual(full.rms_times, capped.rms_times);
            tc.verifyEqual(full.rms_vals, capped.rms_vals, 'AbsTol', 1e-12);
            tc.verifyEqual(effective.plot_common.dynamic_raw_sampling_mode, 'full');
            tc.verifyEqual(effective.plot_common.dynamic_raw_line_width, 1.0);
            tc.verifyEqual(effective.plot_common.dynamic_raw_render_mode, 'line');
            tc.verifyEqual(effective.plot_common.dynamic_raw_full_render_policy, ...
                'peak_preserving');
            tc.verifyEqual(effective.plot_common.dynamic_raw_fig_max_points, 1200000);
            tc.verifyEqual(effective.plot_common.dynamic_raw_min_points_per_day, 12000);
            tc.verifyEqual(effective.plot_common.gap_mode, 'connect');
            tc.verifyEqual( ...
                bms.analyzer.DynamicSeriesService.rawSamplingMode(moduleCfg), ...
                'capped');
        end

        function fullRawLinePlotsEveryFiniteSample(tc)
            fig = figure('Visible', 'off');
            cleaner = onCleanup(@() close(fig)); %#ok<NASGU>
            ax = axes(fig);
            times = datetime(2026, 1, 1, 0, 0, 0) + milliseconds(0:1999)';
            vals = sin((1:2000)' / 20);
            vals([9 501]) = NaN;
            cfg.plot_common = struct( ...
                'dynamic_raw_sampling_mode', 'full', ...
                'dynamic_raw_render_mode', 'dense_band', ...
                'gap_mode', 'connect');

            opts = bms.analyzer.DynamicSeriesService.rawPlotOptions(cfg, 10);
            opts.plot_scope = 'point_time_history';
            opts.source_provenance = struct( ...
                'source_sample_count', 2000, ...
                'incomplete_day_count', 0, ...
                'completeness_scope', 'required_export_contribution');
            h = bms.analyzer.DynamicSeriesService.plotRawSeries( ...
                ax, times, vals, [0 0.4470 0.7410], opts, 1.0);

            tc.verifyEqual(nnz(isfinite(h.YData)), nnz(isfinite(vals)));
            tc.verifyEqual(h.UserData.plot_provenance.sampling_mode, 'full');
            tc.verifyEqual(h.UserData.plot_provenance.finite_count, nnz(isfinite(vals)));
            tc.verifyEqual(h.UserData.plot_provenance.plotted_finite_count, nnz(isfinite(vals)));
            tc.verifyFalse(h.UserData.plot_provenance.reduction_applied);
            tc.verifyEqual(h.UserData.plot_provenance.plot_scope, 'point_time_history');
            tc.verifyEqual(h.UserData.plot_provenance.source.source_sample_count, 2000);
            tc.verifyEqual(h.UserData.plot_provenance.source.completeness_scope, ...
                'required_export_contribution');
            tc.verifyEmpty(findall(ax, 'Type', 'patch'));
        end

        function fullCollectRecordRetainsEveryDailySample(tc)
            values = sin((1:4000)' / 17);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'FULL.csv'), values);
            cfg = dynamic_cfg();
            cfg.plot_common = struct('dynamic_raw_sampling_mode', 'full');

            rec = bms.analyzer.DynamicSeriesService.collectRecord( ...
                tc.Root, 'wave', 'FULL', '2026-01-01', '2026-01-01', ...
                cfg, 'acceleration', true, true);

            tc.verifyTrue(rec.has_data);
            tc.verifyEqual(numel(rec.vals), numel(values));
            tc.verifyEqual(nnz(isfinite(rec.vals)), numel(values));
        end

        function fullAnalysisCanBoundRenderSeriesWithoutChangingStatistics(tc)
            values = sin((1:20000)' / 17);
            values(1234) = -9.5;
            values(17654) = 12.25;
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'BOUNDED.csv'), values);
            cfg = dynamic_cfg();
            cfg.plot_common = struct( ...
                'fig_max_points', 1000, ...
                'dynamic_raw_sampling_mode', 'full', ...
                'dynamic_raw_fig_max_points', 1000, ...
                'dynamic_raw_min_points_per_day', 1000, ...
                'dynamic_raw_full_render_policy', 'peak_preserving');

            rec = bms.analyzer.DynamicSeriesService.collectRecord( ...
                tc.Root, 'wave', 'BOUNDED', '2026-01-01', '2026-01-01', ...
                cfg, 'acceleration', true, true);

            tc.verifyTrue(rec.has_data);
            tc.verifyLessThanOrEqual(numel(rec.vals), 1000);
            tc.verifyEqual(rec.source_provenance.source_sample_count, numel(values));
            tc.verifyEqual(rec.mn, round(min(values), 3));
            tc.verifyEqual(rec.mx, round(max(values), 3));
            tc.verifyEqual(rec.av, round(mean(values), 3));
            tc.verifyTrue(any(abs(rec.vals + 9.5) < 1e-12));
            tc.verifyTrue(any(abs(rec.vals - 12.25) < 1e-12));
        end

        function reducedFullPlotProvenanceSeparatesAnalysisAndRenderCounts(tc)
            fig = figure('Visible', 'off');
            cleaner = onCleanup(@() close(fig)); %#ok<NASGU>
            ax = axes(fig);
            times = datetime(2026, 1, 1) + milliseconds(0:1999)';
            vals = sin((1:2000)' / 10);
            opts = struct( ...
                'fig_max_points', 100, ...
                'gap_mode', 'connect', ...
                'raw_sampling_mode', 'full', ...
                'raw_render_mode', 'line', ...
                'reduction_scope', 'render_only', ...
                'reduction_algorithm', 'peak_preserving_bucket_minmax_v1', ...
                'extrema_preserved', true, ...
                'first_last_preserved', true, ...
                'source_provenance', struct( ...
                    'source_sample_count', 2000, ...
                    'finite_source_sample_count', 2000));

            h = bms.analyzer.DynamicSeriesService.plotRawSeries( ...
                ax, times, vals, [0 0.4470 0.7410], opts, 1.0);
            provenance = h.UserData.plot_provenance;

            tc.verifyEqual(provenance.schema_version, 2);
            tc.verifyEqual(provenance.input_count, 2000);
            tc.verifyEqual(provenance.finite_count, 2000);
            tc.verifyLessThanOrEqual(provenance.plotted_finite_count, 100);
            tc.verifyEqual(provenance.render_vertex_count, provenance.plotted_finite_count);
            tc.verifyTrue(provenance.reduction_applied);
            tc.verifyEqual(provenance.reduction_scope, 'render_only');
            tc.verifyTrue(provenance.extrema_preserved);
            tc.verifyTrue(provenance.first_last_preserved);
        end

        function dailyEnvelopeMatchesFullValuesBeforeRenderReduction(tc)
            times = datetime(2026, 1, 1) + seconds(0:3599)';
            vals = reshape(1:3600, [], 1);

            envelope = bms.analyzer.DynamicSeriesService.envelopeByTimeBins(times, vals, 30);

            tc.verifyEqual(numel(envelope.times), 48);
            tc.verifyEqual(envelope.min(1), 1);
            tc.verifyEqual(envelope.max(1), 1800);
            tc.verifyEqual(envelope.p01(1), prctile(vals(1:1800), 1), 'AbsTol', 1e-12);
            tc.verifyEqual(envelope.p99(2), prctile(vals(1801:3600), 99), 'AbsTol', 1e-12);
            tc.verifyEqual(envelope.rms(1), sqrt(mean(vals(1:1800).^2)), 'AbsTol', 1e-12);
            tc.verifyTrue(all(isnan(envelope.min(3:end))));
        end

        function rollingExportDayIncludesFollowingFolderSamples(tc)
            mkdir(fullfile(tc.Root, '2026-01-02', 'wave'));
            firstTimes = [ ...
                datetime(2025, 12, 31, 9, 0, 0); ...
                datetime(2026, 1, 1, 0, 0, 0); ...
                datetime(2026, 1, 1, 8, 59, 59)];
            nextTimes = [ ...
                datetime(2026, 1, 1, 9, 0, 0); ...
                datetime(2026, 1, 1, 12, 0, 0); ...
                datetime(2026, 1, 1, 23, 59, 59); ...
                datetime(2026, 1, 2, 9, 0, 0)];
            write_series_csv_times( ...
                fullfile(tc.Root, '2026-01-01', 'wave', 'ROLL.csv'), ...
                firstTimes, [1; 2; 3]);
            write_series_csv_times( ...
                fullfile(tc.Root, '2026-01-02', 'wave', 'ROLL.csv'), ...
                nextTimes, [4; 5; 6; 7]);
            cfg = dynamic_cfg();
            cfg.plot_common = struct('dynamic_raw_sampling_mode', 'full');

            rec = bms.analyzer.DynamicSeriesService.collectRecord( ...
                tc.Root, 'wave', 'ROLL', '2026-01-01', '2026-01-01', ...
                cfg, 'acceleration', false, true);

            tc.verifyTrue(rec.has_data);
            tc.verifyEqual(rec.times, [firstTimes(2:3); nextTimes(1:3)]);
            tc.verifyEqual(rec.vals, [2; 3; 4; 5; 6]);
            tc.verifyEqual(rec.mn, 2);
            tc.verifyEqual(rec.mx, 6);
            tc.verifyEqual(rec.av, 4);
            tc.verifyTrue(all(rec.times >= datetime(2026, 1, 1)));
            tc.verifyTrue(all(rec.times < datetime(2026, 1, 2)));
            tc.verifyTrue(rec.source_provenance.complete_day_count == 1);
            tc.verifyEqual(rec.source_provenance.source_file_count, 2);
        end

        function rollingExportResolvesNextFolderAcrossMonthlyPartition(tc)
            partitions = fullfile(tc.Root, 'partitions');
            aprilRoot = fullfile(partitions, '2026年4月');
            mayRoot = fullfile(partitions, '2026年5月');
            excludedRoot = fullfile(partitions, '2026年5月纯地震分析');
            mkdir(fullfile(aprilRoot, '2026-04-30', 'wave'));
            mkdir(fullfile(mayRoot, '2026-05-01', 'wave'));
            mkdir(fullfile(excludedRoot, '2026-05-01', 'wave'));
            write_series_csv_times(fullfile(aprilRoot, '2026-04-30', 'wave', 'CROSS.csv'), ...
                [datetime(2026, 4, 30, 0, 0, 0); datetime(2026, 4, 30, 8, 59, 59)], [1; 2]);
            write_series_csv_times(fullfile(mayRoot, '2026-05-01', 'wave', 'CROSS.csv'), ...
                [datetime(2026, 4, 30, 9, 0, 0); datetime(2026, 4, 30, 23, 59, 59)], [3; 4]);
            write_series_csv_times(fullfile(excludedRoot, '2026-05-01', 'wave', 'CROSS.csv'), ...
                datetime(2026, 4, 30, 12, 0, 0), 999);

            [times, vals, meta] = bms.data.TimeSeriesRangeLoader.loadCalendarDay( ...
                [aprilRoot filesep], 'wave', 'CROSS', '2026-04-30', dynamic_cfg(), 'acceleration');

            tc.verifyEqual(times, [ ...
                datetime(2026, 4, 30, 0, 0, 0); datetime(2026, 4, 30, 8, 59, 59); ...
                datetime(2026, 4, 30, 9, 0, 0); datetime(2026, 4, 30, 23, 59, 59)]);
            tc.verifyEqual(vals, [1; 2; 3; 4]);
            tc.verifyTrue(meta.calendar_day_source_complete);
            tc.verifyEqual(numel(meta.files), 2);
            tc.verifyTrue(any(strcmp(meta.resolved_source_roots, mayRoot)));
            tc.verifyFalse(any(contains(meta.files, '纯地震分析')));
        end

        function rollingExportResolvesNextFolderAcrossQuarterPartition(tc)
            partitions = fullfile(tc.Root, 'quarter_partitions');
            q1Root = fullfile(partitions, '2026年1-3月');
            q2Root = fullfile(partitions, '2026年4-6月');
            mkdir(fullfile(q1Root, '2026-03-31', 'wave'));
            mkdir(fullfile(q2Root, '2026-04-01', 'wave'));
            write_series_csv_times(fullfile(q1Root, '2026-03-31', 'wave', 'Q.csv'), ...
                datetime(2026, 3, 31, 8, 0, 0), 1);
            write_series_csv_times(fullfile(q2Root, '2026-04-01', 'wave', 'Q.csv'), ...
                datetime(2026, 3, 31, 12, 0, 0), 2);

            [~, vals, meta] = bms.data.TimeSeriesRangeLoader.loadCalendarDay( ...
                q1Root, 'wave', 'Q', '2026-03-31', dynamic_cfg(), 'acceleration');

            tc.verifyEqual(vals, [1; 2]);
            tc.verifyTrue(meta.calendar_day_source_complete);
            tc.verifyTrue(any(strcmp(meta.resolved_source_roots, q2Root)));
        end

        function rollingExportMissingLookaheadIsExplicitlyIncomplete(tc)
            write_series_csv_times(fullfile(tc.Root, '2026-01-01', 'wave', 'PARTIAL.csv'), ...
                [datetime(2026, 1, 1, 0, 0, 0); datetime(2026, 1, 1, 8, 59, 59)], [1; 2]);

            [times, vals, meta] = bms.data.TimeSeriesRangeLoader.loadCalendarDay( ...
                tc.Root, 'wave', 'PARTIAL', '2026-01-01', dynamic_cfg(), 'acceleration');

            tc.verifyEqual(numel(times), 2);
            tc.verifyEqual(vals, [1; 2]);
            tc.verifyFalse(meta.calendar_day_source_complete);
            tc.verifyEqual(meta.calendar_day_missing_required_sources, {'2026-01-02'});
            tc.verifyEqual(meta.calendar_day_coverage_end, '2026-01-01 08:59:59.000');
        end

        function noncontributingRollingFilesCannotClaimCompleteSource(tc)
            mkdir(fullfile(tc.Root, '2026-01-02', 'wave'));
            write_series_csv_times(fullfile(tc.Root, '2026-01-01', 'wave', 'OUTSIDE.csv'), ...
                datetime(2025, 12, 31, 12, 0, 0), 1);
            write_series_csv_times(fullfile(tc.Root, '2026-01-02', 'wave', 'OUTSIDE.csv'), ...
                datetime(2026, 1, 2, 0, 0, 0), 2);

            [times, vals, meta] = bms.data.TimeSeriesRangeLoader.loadCalendarDay( ...
                tc.Root, 'wave', 'OUTSIDE', '2026-01-01', dynamic_cfg(), 'acceleration');

            tc.verifyEmpty(times);
            tc.verifyEmpty(vals);
            tc.verifyFalse(meta.calendar_day_source_complete);
            tc.verifyEqual(meta.calendar_day_missing_required_sources, ...
                {'2026-01-01'; '2026-01-02'});
            tc.verifyEqual(meta.noncontributing_export_dates, ...
                {'2026-01-01'; '2026-01-02'});
            tc.verifyEqual(meta.duplicate_timestamp_count, 0);
        end

        function rollingExportDeduplicatesConflictingBoundaryTimestamp(tc)
            mkdir(fullfile(tc.Root, '2026-01-02', 'wave'));
            boundary = datetime(2026, 1, 1, 9, 0, 0);
            write_series_csv_times(fullfile(tc.Root, '2026-01-01', 'wave', 'DUP.csv'), ...
                [datetime(2026, 1, 1, 8, 0, 0); boundary], [1; 2]);
            write_series_csv_times(fullfile(tc.Root, '2026-01-02', 'wave', 'DUP.csv'), ...
                [boundary; datetime(2026, 1, 1, 10, 0, 0)], [3; 4]);

            [times, vals, meta] = bms.data.TimeSeriesRangeLoader.loadCalendarDay( ...
                tc.Root, 'wave', 'DUP', '2026-01-01', dynamic_cfg(), 'acceleration');

            tc.verifyEqual(times, [datetime(2026, 1, 1, 8, 0, 0); boundary; datetime(2026, 1, 1, 10, 0, 0)]);
            tc.verifyEqual(vals, [1; 3; 4]);
            tc.verifyEqual(meta.duplicate_timestamp_count, 1);
            tc.verifyEqual(meta.conflicting_timestamp_count, 1);
        end

        function rollingExportAppliesDailyMedianAfterBothHalvesMerge(tc)
            mkdir(fullfile(tc.Root, '2026-01-02', 'wave'));
            write_series_csv_times(fullfile(tc.Root, '2026-01-01', 'wave', 'MEDIAN.csv'), ...
                [datetime(2026, 1, 1, 0, 0, 0); datetime(2026, 1, 1, 8, 0, 0)], [1; 3]);
            write_series_csv_times(fullfile(tc.Root, '2026-01-02', 'wave', 'MEDIAN.csv'), ...
                [datetime(2026, 1, 1, 9, 0, 0); datetime(2026, 1, 1, 23, 0, 0)], [7; 9]);
            cfg = dynamic_cfg();
            cfg.defaults.acceleration = struct( ...
                'offset_correction', struct('mode', 'daily_median'));

            [~, vals] = bms.data.TimeSeriesRangeLoader.loadCalendarDay( ...
                tc.Root, 'wave', 'MEDIAN', '2026-01-01', cfg, 'acceleration');

            tc.verifyEqual(vals, [-4; -2; 2; 4]);
        end

        function periodRootDoesNotRequestRollingLookahead(tc)
            periodRoot = fullfile(tc.Root, 'period_root');
            mkdir(fullfile(periodRoot, 'lowfreq'));
            mkdir(fullfile(periodRoot, 'wave'));
            write_series_csv_times(fullfile(periodRoot, 'wave', 'PERIOD.csv'), ...
                [datetime(2026, 1, 1, 0, 0, 0); datetime(2026, 1, 1, 12, 0, 0)], [5; 6]);
            cfg = dynamic_cfg();
            cfg.vendor = 'hongtang';

            [~, vals, meta] = bms.data.TimeSeriesRangeLoader.loadCalendarDay( ...
                periodRoot, 'wave', 'PERIOD', '2026-01-01', cfg, 'acceleration');

            tc.verifyEqual(vals, [5; 6]);
            tc.verifyFalse(meta.calendar_day_lookahead_requested);
            tc.verifyEqual(numel(meta.files), 1);
        end

        function absoluteAggregateFileIsReadOnlyOnceAcrossDates(tc)
            aggregateDir = fullfile(tc.Root, 'aggregate_wave');
            mkdir(aggregateDir);
            write_series_csv_times(fullfile(aggregateDir, 'AGG.csv'), ...
                [datetime(2026, 1, 1, 0, 0, 0); datetime(2026, 1, 2, 0, 0, 0)], [1; 2]);

            [times, vals, meta] = load_timeseries_range( ...
                tc.Root, aggregateDir, 'AGG', '2026-01-01', '2026-01-02', ...
                dynamic_cfg(), 'acceleration');

            tc.verifyEqual(numel(times), 2);
            tc.verifyEqual(vals, [1; 2]);
            tc.verifyEqual(numel(meta.files), 1);
            tc.verifyEqual(meta.duplicate_file_count, 1);
        end

        function fullSamplingUsesExplicitGroupPolicy(tc)
            cfg.plot_common = struct('dynamic_raw_sampling_mode', 'full');
            tc.verifyEqual( ...
                bms.analyzer.DynamicAccelerationSeriesService.groupSamplingMode(cfg), 'full');
            cfg.plot_common.dynamic_group_sampling_mode = 'capped';
            tc.verifyEqual( ...
                bms.analyzer.DynamicAccelerationSeriesService.groupSamplingMode(cfg), 'capped');
            cfg2 = bms.analyzer.DynamicAccelerationSeriesService.configForSamplingMode(cfg, 'capped');
            tc.verifyEqual(cfg2.plot_common.dynamic_raw_sampling_mode, 'capped');
        end

        function boundedFullRenderRetainsReusableGroupSeries(tc)
            cfg.plot_common = struct( ...
                'dynamic_raw_sampling_mode', 'full', ...
                'dynamic_raw_full_render_policy', 'peak_preserving');
            tc.verifyFalse( ...
                bms.analyzer.DynamicAccelerationSeriesService.shouldReleasePointSeries(cfg));

            cfg.plot_common.dynamic_raw_full_render_policy = 'all_vertices';
            tc.verifyTrue( ...
                bms.analyzer.DynamicAccelerationSeriesService.shouldReleasePointSeries(cfg));
        end

        function cappedGroupReloadDoesNotReapplyFullPointOverride(tc)
            values = sin((1:4000)' / 17);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'GROUP.csv'), values);
            cfg = dynamic_cfg();
            cfg.plot_common = struct( ...
                'fig_max_points', 1000, ...
                'dynamic_group_sampling_mode', 'capped');
            cfg.plot_common.dynamic_raw_modules.acceleration = struct( ...
                'sampling_mode', 'full', ...
                'line_width', 1.0, ...
                'render_mode', 'line', ...
                'gap_mode', 'connect');
            spec = bms.analyzer.DynamicAccelerationPipeline.spec('acceleration');
            pointCfg = bms.analyzer.DynamicAccelerationSeriesService.modulePlotConfig(cfg, spec);
            groupCfg = bms.analyzer.DynamicAccelerationSeriesService.configForSamplingMode( ...
                pointCfg, bms.analyzer.DynamicAccelerationSeriesService.groupSamplingMode(pointCfg));

            pointRecord = bms.analyzer.DynamicAccelerationSeriesService.collectRecord( ...
                tc.Root, 'wave', 'GROUP', '2026-01-01', '2026-01-01', ...
                cfg, true, spec, true);
            groupRecords = bms.analyzer.DynamicAccelerationSeriesService.collectGroupRecords( ...
                tc.Root, 'wave', {'GROUP'}, '2026-01-01', '2026-01-01', ...
                groupCfg, true, spec);

            tc.verifyEqual(numel(pointRecord.vals), numel(values));
            tc.verifyEqual(numel(groupRecords), 1);
            tc.verifyLessThan(numel(groupRecords(1).vals), numel(values));
            tc.verifyLessThanOrEqual(numel(groupRecords(1).vals), 1000);
            tc.verifyEqual(groupRecords(1).mn, pointRecord.mn, 'AbsTol', 1e-12);
            tc.verifyEqual(groupRecords(1).mx, pointRecord.mx, 'AbsTol', 1e-12);
        end

        function structuralDateRangeIncludesFinalDay(tc)
            [dt0, dt1] = bms.analyzer.StructuralTimeSeriesPlotService.dateRange( ...
                '2026-04-01', '2026-04-30');
            tc.verifyEqual(dt0, datetime(2026, 4, 1));
            tc.verifyGreaterThan(dt1, datetime(2026, 4, 30, 23, 59, 59));
            tc.verifyLessThan(dt1, datetime(2026, 5, 1));
        end

        function denseBandSeriesKeepsEnvelopeExtrema(tc)
            times = datetime(2026, 1, 1, 0, 0, 0) + seconds(0:999)';
            vals = sin((1:1000)' / 5);
            vals(123) = -20;
            vals(876) = 18;

            [xBand, yBand] = bms.analyzer.DynamicSeriesService.denseBandSeries(times, vals, 25);

            tc.verifyEqual(numel(xBand), numel(yBand));
            tc.verifyLessThanOrEqual(numel(yBand), 50);
            tc.verifyTrue(any(abs(yBand + 20) < 1e-12));
            tc.verifyTrue(any(abs(yBand - 18) < 1e-12));
            tc.verifyFalse(any(isnat(xBand)));
            tc.verifyFalse(any(isnan(yBand)));
        end

        function rawDenseBandPlotAcceptsDatetimeAxes(tc)
            fig = figure('Visible', 'off');
            cleaner = onCleanup(@() close(fig)); %#ok<NASGU>
            ax = axes(fig);
            times = datetime(2026, 1, 1, 0, 0, 0) + seconds(0:999)';
            vals = sin((1:1000)' / 5);
            opts = struct('raw_render_mode', 'dense_band', ...
                'raw_band_bins', 25, ...
                'raw_band_line_width', 0.45, ...
                'raw_trace_points', 0);

            h = bms.analyzer.DynamicSeriesService.plotRawSeries(ax, times, vals, [0; 0.4470; 0.7410], opts, 1.0);

            tc.verifyTrue(isgraphics(h));
            tc.verifyGreaterThanOrEqual(numel(findall(ax, 'Type', 'patch')), 1);
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

        function mergedEnvelopeInsertsNaNsAcrossMissingWholeDay(tc)
            first = bms.analyzer.DynamicSeriesService.emptyEnvelope(30);
            first.times = datetime(2026, 1, 1, 0, 15, 0) + minutes((0:47)' * 30);
            second = bms.analyzer.DynamicSeriesService.emptyEnvelope(30);
            second.times = datetime(2026, 1, 3, 0, 15, 0) + minutes((0:47)' * 30);
            fields = {'p01', 'p05', 'p50', 'p95', 'p99', 'min', 'max', 'rms'};
            for i = 1:numel(fields)
                first.(fields{i}) = ones(48, 1) * i;
                second.(fields{i}) = ones(48, 1) * (i + 10);
            end

            merged = bms.analyzer.DynamicSeriesService.mergeEnvelopes( ...
                {first; second}, 30);

            tc.verifyNumElements(merged.times, 144);
            missingDay = dateshift(merged.times, 'start', 'day') == datetime(2026, 1, 2);
            tc.verifyEqual(nnz(missingDay), 48);
            for i = 1:numel(fields)
                tc.verifyTrue(all(isnan(merged.(fields{i})(missingDay))));
                tc.verifyEqual(merged.(fields{i})(1:48), first.(fields{i}));
                tc.verifyEqual(merged.(fields{i})(97:144), second.(fields{i}));
            end
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
            provenanceFiles = dir(fullfile(tc.Root, 'accel_group', '*.plot.json'));
            tc.verifyGreaterThanOrEqual(numel(provenanceFiles), 1);
            payload = jsondecode(fileread(fullfile(provenanceFiles(1).folder, provenanceFiles(1).name)));
            tc.verifyEqual(sort(string({payload.series.point_id})), ["A1" "A2"]);
            tc.verifyTrue(all(arrayfun(@(entry) isstruct(entry.source), payload.series)));
        end

        function accelerationRmsPointDrawsConfiguredWarnLines(tc)
            values = 10 * ones(1201, 1);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'A1.csv'), values);
            cfg = dynamic_cfg();
            cfg.points = struct('acceleration', {{'A1'}});
            cfg.plot_common = struct('save_fig', true, 'append_timestamp', false, 'lightweight_fig', false);
            cfg.plot_styles = struct('acceleration', struct( ...
                'ylim_auto', true, ...
                'rms_warn_lines', [ ...
                    struct('y', 31.5, 'label', 'Level 1'), ...
                    struct('y', 50, 'label', 'Level 2')]));
            spec = bms.analyzer.DynamicAccelerationPipeline.spec('acceleration');
            style = bms.analyzer.DynamicAccelerationPipeline.plotStyle(cfg, spec);
            stats = cell(1, 6);

            bms.analyzer.DynamicAccelerationPipeline.runSequential( ...
                tc.Root, 'wave', '2026-01-01', '2026-01-01', cfg, true, {'A1'}, style, stats, spec);

            figs = dir(fullfile(tc.Root, '**', 'AccelRMS10_A1*.fig'));
            tc.verifyGreaterThanOrEqual(numel(figs), 1);
            values = constant_line_values(fullfile(figs(1).folder, figs(1).name));
            tc.verifyTrue(any(abs(values - 31.5) < 1e-9));
            tc.verifyTrue(any(abs(values - 50) < 1e-9));
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

        function cableAccelerationSpecAllowsRawGroupWarnLines(tc)
            spec = bms.analyzer.DynamicAccelerationPipeline.spec('cable_accel');
            style.group_warn_lines = [ ...
                struct('y', 100, 'label', 'Level 1'), ...
                struct('y', 300, 'label', 'Level 2')];

            warnField = bms.analyzer.DynamicAccelerationPlotService.specField(spec, 'groupWarnField', 'group_warn_lines');
            warnLines = bms.analyzer.DynamicAccelerationPlotService.resolveGroupWarnLines( ...
                style, warnField, 'X6_X16');

            tc.verifyEqual(warnField, 'group_warn_lines');
            tc.verifyEqual(numel(warnLines), 2);
            tc.verifyEqual(reshape(cellfun(@(x) x.y, warnLines), [], 1), [100; 300]);
        end

        function cableAccelerationGroupWarnLinesUseCommonPointThresholds(tc)
            spec = bms.analyzer.DynamicAccelerationPipeline.spec('cable_accel');
            style = struct('ylabel', 'Cable acceleration (mm/s^2)');
            cfg.per_point.cable_accel.C1.thresholds = struct('min', -500, 'max', 500);
            cfg.per_point.cable_accel.C2.thresholds = struct('min', -500, 'max', 500);
            records = repmat(bms.analyzer.DynamicSeriesService.initRecord(), 2, 1);
            records(1).pid = 'C1';
            records(2).pid = 'C2';

            warnLines = bms.analyzer.DynamicAccelerationPlotService.resolveGroupWarnLines( ...
                style, 'group_warn_lines', 'G1', cfg, spec, records);

            tc.verifyEqual(numel(warnLines), 2);
            tc.verifyEqual(sort(cellfun(@(x) x.y, warnLines)), [-500; 500]);
            tc.verifyTrue(contains(warnLines{1}.unit, 'mm/s'));
        end

        function cableAccelerationGroupWarnLinesSkipMixedPointThresholds(tc)
            spec = bms.analyzer.DynamicAccelerationPipeline.spec('cable_accel');
            style = struct('ylabel', 'Cable acceleration (mm/s^2)');
            cfg.per_point.cable_accel.C1.thresholds = struct('min', -500, 'max', 500);
            cfg.per_point.cable_accel.C2.thresholds = struct('min', -100, 'max', 100);
            records = repmat(bms.analyzer.DynamicSeriesService.initRecord(), 2, 1);
            records(1).pid = 'C1';
            records(2).pid = 'C2';

            warnLines = bms.analyzer.DynamicAccelerationPlotService.resolveGroupWarnLines( ...
                style, 'group_warn_lines', 'G1', cfg, spec, records);

            tc.verifyEmpty(warnLines);
        end

        function rmsAutoYLimOverridesConfiguredFixedRanges(tc)
            style = struct( ...
                'rms_ylim_auto', true, ...
                'rms_ylim', [0 1], ...
                'rms_ylims', struct('name', 'C1', 'ylim', [0 0.5]));

            tc.verifyEmpty( ...
                bms.analyzer.DynamicAccelerationPlotService.resolveRmsYLim( ...
                    style, 'C1'));

            fig = figure('Visible', 'off');
            cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
            plot(0:10, 0:10);
            bms.analyzer.DynamicAccelerationPlotService.applyRmsYLim(style, 'C1');
            tc.verifyNotEqual(ylim, [0 1]);
        end

        function cableAccelerationGroupsFallbackToCableForceGroups(tc)
            values = sin((0:1200)' / 10);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'C1.csv'), values);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'C2.csv'), values * 0.5);
            cfg = dynamic_cfg();
            cfg.points = struct('cable_accel', {{'C1', 'C2'}});
            cfg.groups = struct('cable_force', struct('G1', {{'C1', 'C2'}}));
            cfg.per_point.cable_accel.C1.thresholds = struct('min', -500, 'max', 500);
            cfg.per_point.cable_accel.C2.thresholds = struct('min', -500, 'max', 500);
            cfg.plot_common = struct('save_fig', true, 'append_timestamp', false, 'lightweight_fig', false);
            cfg.plot_styles = struct('cable_accel', struct( ...
                'ylim_auto', false, ...
                'ylim', [-600 600], ...
                'group_output_dir', 'cable_accel_group', ...
                'rms_group_output_dir', 'cable_accel_rms_group', ...
                'envelope_enabled', false, ...
                'ylabel', 'Cable acceleration (mm/s^2)', ...
                'rms_ylabel', '10 min RMS (mm/s^2)'));
            spec = bms.analyzer.DynamicAccelerationPipeline.spec('cable_accel');
            style = bms.analyzer.DynamicAccelerationPipeline.plotStyle(cfg, spec);

            bms.analyzer.DynamicAccelerationSeriesService.plotConfiguredGroups( ...
                tc.Root, 'wave', '2026-01-01', '2026-01-01', cfg, true, style, spec);

            groupFigs = dir(fullfile(tc.Root, 'cable_accel_group', '*.fig'));
            tc.verifyGreaterThanOrEqual(numel(groupFigs), 1);
            values = constant_line_values(fullfile(groupFigs(1).folder, groupFigs(1).name));
            tc.verifyEqual(values(:), [-500; 500]);
        end

        function explicitEmptyCableAccelerationGroupsDisableFallback(tc)
            values = sin((0:1200)' / 10);
            write_series_csv(fullfile(tc.Root, '2026-01-01', 'wave', 'C1.csv'), values);
            cfg = dynamic_cfg();
            cfg.points = struct('cable_accel', {{'C1'}});
            cfg.groups = struct( ...
                'cable_accel', struct(), ...
                'cable_force', struct('G1', {{'C1'}}));
            cfg.plot_common = struct('save_fig', true, 'append_timestamp', false);
            cfg.plot_styles = struct('cable_accel', struct( ...
                'group_output_dir', 'cable_accel_group', ...
                'rms_group_output_dir', 'cable_accel_rms_group'));
            spec = bms.analyzer.DynamicAccelerationPipeline.spec('cable_accel');
            style = bms.analyzer.DynamicAccelerationPipeline.plotStyle(cfg, spec);

            bms.analyzer.DynamicAccelerationSeriesService.plotConfiguredGroups( ...
                tc.Root, 'wave', '2026-01-01', '2026-01-01', cfg, true, style, spec);

            tc.verifyFalse(isfolder(fullfile(tc.Root, 'cable_accel_group')));
            tc.verifyFalse(isfolder(fullfile(tc.Root, 'cable_accel_rms_group')));
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

function write_series_csv_times(path, times, values)
    assert(numel(times) == numel(values), 'Times and values must have equal length.');
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid > 0, 'Failed to create test csv.');
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'Time,Value\n');
    for i = 1:numel(values)
        fprintf(fid, '%s,%.6f\n', datestr(times(i), 'yyyy-mm-dd HH:MM:SS.FFF'), values(i));
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
