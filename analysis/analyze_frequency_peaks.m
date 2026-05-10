function results = analyze_frequency_peaks(freq, amplitude, target_freqs, tolerance)
% analyze_frequency_peaks  Compatibility wrapper for target frequency labels.

    if nargin < 4 || isempty(tolerance)
        tolerance = 0.05;
    end

    results = bms.analyzer.FrequencySpectrumService.detectTargetPeaks( ...
        freq, amplitude, target_freqs, tolerance);
    bms.analyzer.FrequencySpectrumService.annotatePeaks(results);
    bms.analyzer.FrequencySpectrumService.displayPeakResults(results);
end
