classdef VibrationModeService
    %VIBRATIONMODESERVICE Legacy vibration mode extraction helpers.

    methods (Static)
        function normalizedDisplacement = analyzeLargeFiles(filePaths, startTime, endTime, frequency, samplingRate, opts)
            if nargin < 6 || isempty(opts)
                opts = struct();
            end
            filePaths = cellstr(string(filePaths));
            bms.analyzer.VibrationModeService.validateInputs(filePaths, frequency, samplingRate);

            [b, a] = bms.analyzer.VibrationModeService.bandpassCoefficients(frequency, samplingRate, opts);
            amplitudes = zeros(numel(filePaths), 1);
            for i = 1:numel(filePaths)
                values = bms.data.LargeCsvService.extractTimeRange(filePaths{i}, startTime, endTime);
                if isempty(values)
                    error('VibrationModeService:NoData', ...
                        'Point %d has no valid data in the selected time range.', i);
                end
                filtered = bms.analyzer.VibrationModeService.bandpassSignal(values, b, a);
                amplitudes(i) = rms(filtered);
            end

            normalizedDisplacement = bms.analyzer.VibrationModeService.normalizeAmplitudes(amplitudes);
        end

        function validateInputs(filePaths, frequency, samplingRate)
            if numel(filePaths) < 2
                error('VibrationModeService:TooFewPoints', 'At least two points are required.');
            end
            if isempty(frequency) || ~isscalar(frequency) || ~isfinite(frequency) || frequency <= 0
                error('VibrationModeService:InvalidFrequency', 'frequency must be a positive scalar.');
            end
            if isempty(samplingRate) || ~isscalar(samplingRate) || ~isfinite(samplingRate) || samplingRate <= 0
                error('VibrationModeService:InvalidSamplingRate', 'sampling_rate must be a positive scalar.');
            end
        end

        function [b, a] = bandpassCoefficients(frequency, samplingRate, opts)
            bandwidth = bms.analyzer.VibrationModeService.option(opts, 'filter_bandwidth', 0.1);
            order = bms.analyzer.VibrationModeService.option(opts, 'filter_order', 4);
            nyquist = samplingRate / 2;
            band = [(frequency - bandwidth), (frequency + bandwidth)] / nyquist;
            if any(~isfinite(band)) || band(1) <= 0 || band(2) >= 1 || band(1) >= band(2)
                error('VibrationModeService:InvalidFilterBand', ...
                    'Invalid bandpass filter band for frequency %.4g Hz and sampling rate %.4g Hz.', ...
                    frequency, samplingRate);
            end
            [b, a] = butter(order, band, 'bandpass');
        end

        function filtered = bandpassSignal(values, b, a)
            values = double(values(:));
            filtered = filtfilt(b, a, values);
        end

        function normalized = normalizeAmplitudes(amplitudes)
            amplitudes = double(amplitudes(:));
            maxAmplitude = max(amplitudes);
            if isempty(maxAmplitude) || ~isfinite(maxAmplitude) || maxAmplitude <= 0
                normalized = zeros(size(amplitudes));
            else
                normalized = amplitudes / maxAmplitude;
            end
        end

        function value = option(opts, fieldName, defaultValue)
            value = defaultValue;
            if isstruct(opts) && isfield(opts, fieldName) && ~isempty(opts.(fieldName))
                value = opts.(fieldName);
            end
        end
    end
end
