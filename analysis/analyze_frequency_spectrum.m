function result = analyze_frequency_spectrum(data, start_time, end_time, sampling_rate, target_freqs, tolerance, mark_peaks)
% analyze_frequency_spectrum  Compatibility wrapper for manual FFT spectrum plots.

    if nargin < 5, target_freqs = []; end
    if nargin < 6 || isempty(tolerance), tolerance = 0.05; end
    if nargin < 7 || isempty(mark_peaks), mark_peaks = false; end

    result = bms.analyzer.FrequencySpectrumService.run( ...
        data, start_time, end_time, sampling_rate, target_freqs, tolerance, mark_peaks);
end
