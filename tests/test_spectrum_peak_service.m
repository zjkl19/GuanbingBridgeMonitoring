classdef test_spectrum_peak_service < matlab.unittest.TestCase
    methods (Test)
        function peakRowsExtractsBandMaximum(tc)
            f = (0:0.1:5)';
            Pdb = -100 * ones(size(f));
            Pdb(abs(f - 1.2) < 1e-12) = 10;
            Pdb(abs(f - 3.0) < 1e-12) = 20;

            [ampRow, freqRow] = bms.analyzer.SpectrumPeakService.peakRows(f, Pdb, [1.2 3.0 4.8], 0.11);

            tc.verifyEqual(ampRow(1), 10);
            tc.verifyEqual(freqRow(1), 1.2, 'AbsTol', 1e-12);
            tc.verifyEqual(ampRow(2), 20);
            tc.verifyEqual(freqRow(2), 3.0, 'AbsTol', 1e-12);
            tc.verifyEqual(ampRow(3), -100);
            tc.verifyEqual(freqRow(3), 4.7, 'AbsTol', 1e-12);
        end

        function peakRowsSupportsPerOrderTolerance(tc)
            f = (0:0.05:3)';
            Pdb = -100 * ones(size(f));
            Pdb(abs(f - 1.2) < 1e-12) = 10;
            Pdb(abs(f - 2.15) < 1e-12) = 20;

            [ampRow, freqRow] = bms.analyzer.SpectrumPeakService.peakRows(f, Pdb, [1.0 2.0], [0.1 0.2]);

            tc.verifyLessThan(freqRow(1), 1.11);
            tc.verifyEqual(ampRow(2), 20);
            tc.verifyEqual(freqRow(2), 2.15, 'AbsTol', 1e-12);
        end

        function computeWindowPsdUsesMorningAnalysisWindow(tc)
            day = datetime(2026, 1, 1);
            fs = 10;
            n = 10 * 60 * fs;
            times = day + duration(5, 30, 0) + seconds((0:n-1)' / fs);
            values = sin(2 * pi * 1.0 * seconds(times - times(1)));

            [f, Pdb, ok] = bms.analyzer.SpectrumPeakService.computeWindowPsd(times, values, day);

            tc.verifyTrue(ok);
            tc.verifyFalse(isempty(f));
            tc.verifyEqual(numel(f), numel(Pdb));
            tc.verifyTrue(any(f > 0));
            tc.verifyTrue(all(isfinite(Pdb)));
        end

        function spectrumPipelineResolvesPointOverrides(tc)
            spec = bms.analyzer.SpectrumAnalysisPipeline.spec('accel_spectrum');
            cfg = struct();
            cfg.per_point.accel_spectrum.P_1 = struct( ...
                'target_freqs', [1.1 2.2], ...
                'tolerance', 0.25, ...
                'theor_freqs', [1.0 2.0], ...
                'theor_labels', ["一阶", "二阶"]);

            [freqs, tol, theorFreqs, theorLabels] = ...
                bms.analyzer.SpectrumAnalysisPipeline.pointParams(cfg, 'P-1', spec, [9.9], 0.01, [], {});
            [serviceFreqs, serviceTol, serviceTheorFreqs, serviceTheorLabels] = ...
                bms.analyzer.SpectrumConfigService.pointParams(cfg, 'P-1', spec, [9.9], 0.01, [], {});

            tc.verifyEqual(freqs, [1.1 2.2]);
            tc.verifyEqual(tol, 0.25);
            tc.verifyEqual(theorFreqs, [1.0 2.0]);
            tc.verifyEqual(theorLabels(:), {'一阶'; '二阶'});
            tc.verifyEqual(serviceFreqs, freqs);
            tc.verifyEqual(serviceTol, tol);
            tc.verifyEqual(serviceTheorFreqs, theorFreqs);
            tc.verifyEqual(serviceTheorLabels(:), theorLabels(:));
        end

        function spectrumPipelineResolvesConfiguredPeakOrders(tc)
            spec = bms.analyzer.SpectrumAnalysisPipeline.spec('accel_spectrum');
            cfg = struct();
            cfg.accel_spectrum_params.peak_orders = struct( ...
                'order', 1, ...
                'label', '一阶', ...
                'theoretical_hz', 1.05, ...
                'search_center_hz', 1.20, ...
                'search_half_width_hz', 0.10);

            [freqs, tol, theorFreqs, theorLabels, peakLabels] = ...
                bms.analyzer.SpectrumConfigService.pointParams(cfg, 'P-1', spec, [1 2 3], 0.15, [], {});

            tc.verifyEqual(freqs, 1.20);
            tc.verifyEqual(tol, 0.10);
            tc.verifyEqual(theorFreqs, 1.05);
            tc.verifyEqual(theorLabels(:), {'理论一阶频率 1.050Hz'});
            tc.verifyEqual(peakLabels(:), {'一阶'});
        end

        function spectrumPeakOrdersAcceptSearchMinMax(tc)
            spec = bms.analyzer.SpectrumAnalysisPipeline.spec('accel_spectrum');
            cfg = struct();
            cfg.accel_spectrum_params.peak_orders = struct( ...
                'order', 1, ...
                'label', 'first', ...
                'theoretical_hz', 0.593, ...
                'search_min_hz', 0.44, ...
                'search_max_hz', 0.84);

            [freqs, tol, theorFreqs, ~, peakLabels] = ...
                bms.analyzer.SpectrumConfigService.pointParams(cfg, 'AZ-1', spec, [], 0.15, [], {});

            tc.verifyEqual(freqs, 0.64, 'AbsTol', 1e-12);
            tc.verifyEqual(tol, 0.20, 'AbsTol', 1e-12);
            tc.verifyEqual(theorFreqs, 0.593);
            tc.verifyEqual(peakLabels(:), {'first'});
        end

        function cableSpectrumSpecKeepsCableForceBehavior(tc)
            spec = bms.analyzer.SpectrumAnalysisPipeline.spec('cable_accel_spectrum');

            tc.verifyEqual(spec.sensorType, 'cable_accel');
            tc.verifyEqual(spec.perPointKey, 'cable_accel');
            tc.verifyTrue(spec.includeForce);
            tc.verifyTrue(ismember('cable_force', spec.pointKeys));
        end

        function spectrumServicesKeepPipelineHelperBehavior(tc)
            spec = bms.analyzer.SpectrumAnalysisPipeline.spec('cable_accel_spectrum');
            cfg.points.cable_force = {'S1', 'S2'};

            tc.verifyEqual( ...
                bms.analyzer.SpectrumConfigService.resolvePoints(cfg, spec), ...
                bms.analyzer.SpectrumAnalysisPipeline.resolvePoints(cfg, spec));
            tc.verifyEqual( ...
                bms.analyzer.SpectrumPlotService.groupDisplayName('GroupA', {'S1', 'S2'}), ...
                bms.analyzer.SpectrumAnalysisPipeline.groupDisplayName('GroupA', {'S1', 'S2'}));
        end

        function cableSpectrumPointsFallBackToForceGroups(tc)
            spec = bms.analyzer.SpectrumAnalysisPipeline.spec('cable_accel_spectrum');
            cfg.groups.cable_force = struct('G1', {{'S1', 'S2'}}, 'G2', {{'S2', 'S3'}});

            points = bms.analyzer.SpectrumConfigService.resolvePoints(cfg, spec);

            tc.verifyEqual(points, {'S1'; 'S2'; 'S3'});
        end

        function accelSpectrumSpecDefinesFrequencyGroupOutput(tc)
            spec = bms.analyzer.SpectrumAnalysisPipeline.spec('accel_spectrum');

            tc.verifyEqual(spec.freqGroupKey, 'acceleration');
            tc.verifyTrue(isfield(spec, 'freqGroupOutputDir'));
            tc.verifyFalse(isempty(spec.freqGroupOutputDir));
        end

        function plotFrequencyGroupsWritesGroupBundle(tc)
            rootDir = tempname;
            mkdir(rootDir);
            tc.addTeardown(@() rmdir(rootDir, 's'));

            cfg.groups.acceleration = struct('ZG', {{'A1', 'A2'}});
            cfg.plot_common = struct( ...
                'save_fig', false, ...
                'append_timestamp', false, ...
                'gap_mode', 'connect');
            datesAll = (datetime(2026, 3, 23):days(1):datetime(2026, 3, 24)).';
            freqSeriesAll = {[1.19; 1.21]; [1.18; 1.22]};
            targetFreqsAll = {[1.20]; [1.20]};
            peakLabelsAll = {{'P1'}; {'P1'}};
            theorFreqsAll = {[1.05]; [1.05]};
            theorLabelsAll = {{'Theoretical 1.050Hz'}; {'Theoretical 1.050Hz'}};
            style = struct( ...
                'freq_ylabel', 'Peak frequency (Hz)', ...
                'freq_title_prefix', 'Peak frequency', ...
                'group_labels', struct('ZG', 'ZG main'), ...
                'group_legend_location', 'northeast', ...
                'group_legend_box', 'off');
            outDir = fullfile(rootDir, 'freq_groups');

            bms.analyzer.SpectrumPlotService.plotFrequencyGroups( ...
                cfg, {'A1'; 'A2'}, datesAll, freqSeriesAll, [true; true], outDir, style, ...
                'acceleration', targetFreqsAll, peakLabelsAll, theorFreqsAll, theorLabelsAll);

            files = dir(fullfile(outDir, 'SpecFreq_ZG_main_Group_*.jpg'));
            tc.verifyEqual(numel(files), 1);
        end

        function frequencyGroupsAllowStyleSpecificPointLists(tc)
            cfg.groups.acceleration = struct('ZG', {{'A1', 'A1-Y', 'A2'}});
            style.groups = struct('ZG', {{'A1', 'A2'}});

            groups = bms.analyzer.SpectrumPlotService.resolveFrequencyGroups(cfg, style, 'acceleration');

            tc.verifyEqual(groups.ZG(:), {'A1'; 'A2'});
        end
    end
end
