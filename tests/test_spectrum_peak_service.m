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
    end
end
