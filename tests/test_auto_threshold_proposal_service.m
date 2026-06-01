classdef test_auto_threshold_proposal_service < matlab.unittest.TestCase
    properties
        Root
        ProjRoot
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.ProjRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(tc.ProjRoot, fullfile(tc.ProjRoot, 'pipeline'), fullfile(tc.ProjRoot, 'config'));
            tc.Root = tempname;
            mkdir(fullfile(tc.Root, '2026-01-01', 'features'));
            tc.writeSeries(fullfile(tc.Root, '2026-01-01', 'features', 'T-1.csv'));
        end
    end

    methods (TestMethodTeardown)
        function teardown(tc)
            if ~isempty(tc.Root) && exist(tc.Root, 'dir')
                rmdir(tc.Root, 's');
            end
        end
    end

    methods (Test)
        function testGenerateQuantileProposalAndApply(tc)
            cfg = tc.minimalConfig();
            opts = bms.config.AutoThresholdProposalService.defaultOptions();
            opts.module_keys = {'temperature'};
            opts.use_quantile = true;
            opts.quantile_low = 0;
            opts.quantile_high = 95;
            opts.padding_factor = 0;
            opts.use_mad = false;
            opts.use_iqr = false;
            opts.use_spike_window = false;
            opts.use_zero_or_flat = false;
            opts.min_valid_count = 20;
            opts.max_removed_ratio = 0.20;

            result = bms.config.AutoThresholdProposalService.generate( ...
                cfg, tc.Root, '2026-01-01', '2026-01-01', opts);

            tc.verifyGreaterThanOrEqual(numel(result.proposals), 1);
            tc.verifyEqual(result.proposals(1).module_key, 'temperature');
            tc.verifyEqual(result.proposals(1).point_id, 'T-1');
            tc.verifyTrue(result.proposals(1).max < 100);

            cfg2 = bms.config.AutoThresholdProposalService.applyAccepted(cfg, result.proposals(1));
            tc.verifyTrue(isfield(cfg2.per_point.temperature, 'T_1'));
            tc.verifyTrue(isfield(cfg2.per_point.temperature.T_1, 'thresholds'));
        end

        function testTableRoundTrip(tc)
            p = bms.config.AutoThresholdProposalService.generateForSeries( ...
                datetime(2026,1,1,0,0,0) + seconds(0:50), [zeros(1,50), 999], ...
                'deflection', 'D-1', 'deflection', bms.config.AutoThresholdProposalService.defaultOptions());
            tc.assumeGreaterThan(numel(p), 0);

            rows = bms.config.AutoThresholdProposalService.proposalsToCell(p);
            p2 = bms.config.AutoThresholdProposalService.cellToProposals(rows);

            tc.verifyEqual(numel(p2), numel(p));
            tc.verifyEqual(p2(1).module_key, p(1).module_key);
            tc.verifyEqual(p2(1).point_id, p(1).point_id);
        end

        function testGenerateCapturesPreviewSeriesWhenRequested(tc)
            cfg = tc.minimalConfig();
            opts = bms.config.AutoThresholdProposalService.defaultOptions();
            opts.module_keys = {'temperature'};
            opts.capture_preview_series = true;
            opts.preview_sample_count = 10;
            opts.use_auto_cut = false;
            opts.use_quantile = true;
            opts.use_mad = false;
            opts.use_iqr = false;
            opts.use_spike_window = false;
            opts.use_zero_or_flat = false;
            opts.min_valid_count = 20;

            result = bms.config.AutoThresholdProposalService.generate( ...
                cfg, tc.Root, '2026-01-01', '2026-01-01', opts);

            tc.verifyTrue(isfield(result, 'preview_series'));
            tc.verifyNumElements(result.preview_series, 1);
            tc.verifyEqual(result.preview_series(1).module_key, 'temperature');
            tc.verifyEqual(result.preview_series(1).point_id, 'T-1');
            tc.verifyLessThanOrEqual(result.preview_series(1).sample_count, 10);
            tc.verifyEqual(numel(result.preview_series(1).values), result.preview_series(1).sample_count);
        end

        function testWriteArtifactsOmitsPreviewSeries(tc)
            cfg = tc.minimalConfig();
            opts = bms.config.AutoThresholdProposalService.defaultOptions();
            opts.module_keys = {'temperature'};
            opts.capture_preview_series = true;
            opts.preview_sample_count = 10;
            opts.use_auto_cut = false;
            opts.use_quantile = true;
            opts.use_mad = false;
            opts.use_iqr = false;
            opts.use_spike_window = false;
            opts.use_zero_or_flat = false;
            opts.min_valid_count = 20;

            result = bms.config.AutoThresholdProposalService.generate( ...
                cfg, tc.Root, '2026-01-01', '2026-01-01', opts);
            paths = bms.config.AutoThresholdProposalService.writeArtifacts(tc.Root, result);
            decoded = jsondecode(fileread(paths.json));

            tc.verifyTrue(isfield(result, 'preview_series'));
            tc.verifyFalse(isfield(decoded, 'preview_series'));
        end

        function testHelpLinesDescribeAlgorithms(tc)
            lines = bms.config.AutoThresholdProposalService.helpLines();
            text = join(string(lines), newline);

            tc.verifyTrue(contains(text, '分位数'));
            tc.verifyTrue(contains(text, 'MAD'));
            tc.verifyTrue(contains(text, '局部尖峰'));
            tc.verifyTrue(contains(text, '参数含义'));
        end

        function testSpikeWindowKeepsStrongestWindowsBeforeLimit(tc)
            base = datetime(2026,1,1,0,0,0);
            times = base + seconds(0:999);
            values = sin((1:1000) / 13)';
            values(80:82) = 25;
            values(500:504) = 160;
            values(700:704) = 120;
            opts = tc.spikeOnlyOptions();
            opts.max_window_proposals_per_point = 2;
            opts.spike_window_merge_gap_seconds = 0;
            opts.spike_window_padding_seconds = 0;

            proposals = bms.config.AutoThresholdProposalService.generateForSeries( ...
                times, values, 'strain', 'SX-T', 'strain', opts);
            starts = string({proposals.t_range_start});

            tc.verifyNumElements(proposals, 2);
            tc.verifyTrue(any(contains(starts, '00:08:19')));
            tc.verifyTrue(any(contains(starts, '00:11:39')));
            tc.verifyFalse(any(contains(starts, '00:01:19')));
            tc.verifyGreaterThan(min([proposals.score]), 0);
        end

        function testSpikeWindowMergesNearbyCandidates(tc)
            base = datetime(2026,1,1,0,0,0);
            times = base + seconds(0:999);
            values = sin((1:1000) / 13)';
            values(500:504) = 120;
            values(510:514) = 130;
            values(800:804) = 80;
            opts = tc.spikeOnlyOptions();
            opts.max_window_proposals_per_point = 1;
            opts.spike_window_merge_gap_seconds = 10;
            opts.spike_window_padding_seconds = 0;

            proposals = bms.config.AutoThresholdProposalService.generateForSeries( ...
                times, values, 'strain', 'SX-T', 'strain', opts);

            tc.verifyNumElements(proposals, 1);
            tc.verifyEqual(proposals(1).removed_count, 10);
            tc.verifyTrue(contains(string(proposals(1).t_range_start), '00:08:19'));
            tc.verifyTrue(contains(string(proposals(1).t_range_end), '00:08:33'));
        end

        function testSampleSeriesPreservesNarrowSpike(tc)
            times = datetime(2026,1,1,0,0,0) + seconds(0:999);
            values = sin((1:1000) / 25)';
            values(777) = 1000;

            [~, sampled] = bms.config.AutoThresholdProposalService.sampleSeries(times, values, 50);

            tc.verifyLessThanOrEqual(numel(sampled), 50);
            tc.verifyTrue(any(sampled == 1000));
        end

        function testAutoCutProducesOneSidedGlobalLowerCut(tc)
            times = datetime(2026,1,1,0,0,0) + seconds(0:999);
            values = sin((1:1000) / 25)' * 3;
            values([120 300 700]) = -1000;
            opts = tc.autoCutOnlyOptions();

            proposals = bms.config.AutoThresholdProposalService.generateForSeries( ...
                times, values, 'strain', 'SX-T', 'strain', opts);

            tc.verifyNumElements(proposals, 1);
            tc.verifyEqual(proposals(1).algorithm, 'auto_cut');
            tc.verifyEqual(proposals(1).kind, 'range');
            tc.verifyTrue(isfinite(proposals(1).min));
            tc.verifyTrue(isnan(proposals(1).max));
            tc.verifyLessThan(proposals(1).min, -100);
            tc.verifyGreaterThan(proposals(1).min, -1000);

            cfg = struct();
            cfg.per_point = struct();
            cfg.per_point.strain = struct();
            cfg.per_point.strain.SX_T = struct('thresholds', struct('min', -10, 'max', 10));
            cfg.name_map_global = struct();
            cfg2 = bms.config.AutoThresholdProposalService.applyAccepted(cfg, proposals(1));
            tc.verifyNumElements(cfg2.per_point.strain.SX_T.thresholds, 2);
            tc.verifyTrue(isnan(cfg2.per_point.strain.SX_T.thresholds(2).max));
        end

        function testAutoCutFallsBackToWindowWhenGlobalCutIsUnsafe(tc)
            times = datetime(2026,1,1,0,0,0) + seconds(0:999);
            values = zeros(1000, 1);
            values(100:500) = -1000;
            values(800:804) = -1300;
            opts = tc.autoCutOnlyOptions();
            opts.max_removed_ratio = 0.60;
            opts.auto_cut_min_gap_sigma = 1;
            opts.auto_cut_global_max_span_seconds = 60;
            opts.auto_cut_window_merge_gap_seconds = 0;

            proposals = bms.config.AutoThresholdProposalService.generateForSeries( ...
                times, values, 'strain', 'SX-T', 'strain', opts);

            tc.verifyNumElements(proposals, 1);
            tc.verifyEqual(proposals(1).algorithm, 'auto_cut');
            tc.verifyEqual(proposals(1).kind, 'window_range');
            tc.verifyTrue(contains(string(proposals(1).t_range_start), '00:13:'));
            tc.verifyTrue(contains(string(proposals(1).t_range_end), '00:13:'));
        end
    end

    methods
        function opts = autoCutOnlyOptions(~)
            opts = bms.config.AutoThresholdProposalService.defaultOptions();
            opts.use_auto_cut = true;
            opts.use_quantile = false;
            opts.use_mad = false;
            opts.use_iqr = false;
            opts.use_spike_window = false;
            opts.use_zero_or_flat = false;
            opts.auto_cut_mode = 'standard';
            opts.min_valid_count = 30;
            opts.min_removed_count = 1;
            opts.auto_cut_min_removed_count = 3;
            opts.auto_cut_max_proposals_per_point = 3;
            opts.auto_cut_padding_seconds = 0;
        end

        function opts = spikeOnlyOptions(~)
            opts = bms.config.AutoThresholdProposalService.defaultOptions();
            opts.use_auto_cut = false;
            opts.use_quantile = false;
            opts.use_mad = false;
            opts.use_iqr = false;
            opts.use_spike_window = true;
            opts.use_zero_or_flat = false;
            opts.spike_mad_factor = 6;
            opts.min_window_points = 3;
            opts.min_valid_count = 30;
        end

        function cfg = minimalConfig(~)
            cfg = struct();
            cfg.vendor = 'donghua';
            cfg.defaults = struct();
            cfg.defaults.header_marker = '__no_header__';
            cfg.defaults.temperature = struct('thresholds', struct('min', -1, 'max', 1));
            cfg.points = struct('temperature', {{'T-1'}});
            cfg.subfolders = struct('temperature', 'features');
            cfg.file_patterns = struct();
            cfg.file_patterns.temperature = struct('default', {{'{point}.csv'}}, 'per_point', struct());
            cfg.per_point = struct();
        end

        function writeSeries(~, path)
            fid = fopen(path, 'wt');
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
            base = datetime(2026,1,1,0,0,0);
            for i = 1:100
                t = base + minutes(i - 1);
                v = sin(i / 8) * 5;
                fprintf(fid, '%s,%.6f\n', datestr(t, 'yyyy-mm-dd HH:MM:SS'), v);
            end
            fprintf(fid, '%s,%.6f\n', datestr(base + minutes(100), 'yyyy-mm-dd HH:MM:SS'), 100.0);
        end
    end
end
