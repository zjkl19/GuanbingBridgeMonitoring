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
    end
end
