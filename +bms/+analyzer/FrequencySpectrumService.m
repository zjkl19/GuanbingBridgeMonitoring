classdef FrequencySpectrumService
    %FREQUENCYSPECTRUMSERVICE Manual FFT spectrum and target peak helpers.

    methods (Static)
        function result = run(data, startTime, endTime, samplingRate, targetFreqs, tolerance, markPeaks, opts)
            if nargin < 5, targetFreqs = []; end
            if nargin < 6 || isempty(tolerance), tolerance = 0.05; end
            if nargin < 7 || isempty(markPeaks), markPeaks = false; end
            if nargin < 8 || isempty(opts), opts = struct(); end

            [freq, amplitude] = bms.analyzer.FrequencySpectrumService.computeSpectrum( ...
                data, startTime, endTime, samplingRate, opts);
            fig = bms.analyzer.FrequencySpectrumService.plotSpectrum(freq, amplitude, opts);

            peaks = table([], [], 'VariableNames', {'Frequency_Hz', 'Amplitude'});
            if bms.config.ConfigReader.boolValue(markPeaks, false)
                peaks = bms.analyzer.FrequencySpectrumService.detectTargetPeaks( ...
                    freq, amplitude, targetFreqs, tolerance);
                bms.analyzer.FrequencySpectrumService.annotatePeaks(peaks);
                bms.analyzer.FrequencySpectrumService.displayPeakResults(peaks);
            end

            outDir = bms.analyzer.FrequencySpectrumService.option(opts, 'outputDir', '频谱分析结果');
            baseName = bms.analyzer.FrequencySpectrumService.option(opts, 'baseName', ...
                ['spectrum_plot_' datestr(now, 'yyyymmdd_HHMMSS')]);
            cfg = bms.analyzer.FrequencySpectrumService.option(opts, 'cfg', struct());
            paths = bms.analyzer.FrequencySpectrumService.savePlot(fig, outDir, baseName, cfg);

            result = struct('freq', freq, 'amplitude', amplitude, 'peaks', peaks, 'paths', {paths});
            disp('频谱分析完成。');
        end

        function [freq, amplitude] = computeSpectrum(data, startTime, endTime, samplingRate, opts)
            if nargin < 5 || isempty(opts)
                opts = struct();
            end
            if ~istable(data)
                error('FrequencySpectrumService:InvalidInput', 'Input data must be a table.');
            end
            if nargin < 4 || isempty(samplingRate) || ~isscalar(samplingRate) || ~isfinite(samplingRate) || samplingRate <= 0
                error('FrequencySpectrumService:InvalidSamplingRate', 'sampling_rate must be a positive scalar.');
            end

            [times, values] = bms.analyzer.FrequencySpectrumService.tableSeries(data);
            t0 = bms.analyzer.FrequencySpectrumService.parseTime(startTime);
            t1 = bms.analyzer.FrequencySpectrumService.parseTime(endTime);
            mask = times >= t0 & times <= t1;
            selected = values(mask);
            selected = selected(isfinite(selected));
            if isempty(selected)
                error('FrequencySpectrumService:NoData', 'No data found in the selected time range.');
            end

            n = numel(selected);
            fftResult = fft(selected);
            freqAll = (0:n-1)' * (samplingRate / n);
            amplitudeAll = abs(fftResult(:)) / n;
            windowSize = bms.analyzer.FrequencySpectrumService.option(opts, 'smoothWindow', 5);
            amplitudeAll = bms.analyzer.FrequencySpectrumService.smoothAmplitude(amplitudeAll, windowSize);

            halfN = floor(n / 2) + 1;
            freq = freqAll(1:halfN);
            amplitude = amplitudeAll(1:halfN);
        end

        function [times, values] = tableSeries(data)
            times = data{:, 1};
            if ~isdatetime(times)
                times = datetime(times, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
            end
            values = data{:, 2};
            if ~isnumeric(values)
                values = str2double(string(values));
            end
            values = values(:);
        end

        function t = parseTime(value)
            if isdatetime(value)
                t = value;
            else
                t = datetime(value, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
            end
        end

        function y = smoothAmplitude(values, windowSize)
            if nargin < 2 || isempty(windowSize) || ~isscalar(windowSize) || windowSize < 1
                windowSize = 5;
            end
            windowSize = round(windowSize);
            if exist('smooth', 'file') == 2 || exist('smooth', 'builtin') == 5
                y = smooth(values, windowSize);
            else
                y = movmean(values, windowSize, 'omitnan');
            end
            y = y(:);
        end

        function fig = plotSpectrum(freq, amplitude, opts)
            if nargin < 3 || isempty(opts)
                opts = struct();
            end
            fig = figure('Position', [100 100 900 420]);
            plot(freq, amplitude);
            xlim(bms.analyzer.FrequencySpectrumService.option(opts, 'xlim', [0 10]));
            xlabel(bms.analyzer.FrequencySpectrumService.option(opts, 'xlabel', '频率 (Hz)'));
            ylabel(bms.analyzer.FrequencySpectrumService.option(opts, 'ylabel', '幅值'));
            title(bms.analyzer.FrequencySpectrumService.option(opts, 'title', '平滑后的频谱图'));
            grid on;
        end

        function results = detectTargetPeaks(freq, amplitude, targetFreqs, tolerance)
            if nargin < 4 || isempty(tolerance)
                tolerance = 0.05;
            end
            freq = freq(:);
            amplitude = amplitude(:);
            targetFreqs = targetFreqs(:)';

            detectedFreqs = [];
            detectedPks = [];
            for i = 1:numel(targetFreqs)
                targetRange = [targetFreqs(i) - tolerance, targetFreqs(i) + tolerance];
                rangeMask = freq >= targetRange(1) & freq <= targetRange(2);
                freqRange = freq(rangeMask);
                ampRange = amplitude(rangeMask);
                if isempty(ampRange)
                    continue;
                end

                [pks, locs] = findpeaks(ampRange, freqRange, 'SortStr', 'descend');
                if isempty(pks)
                    continue;
                end
                detectedFreqs = [detectedFreqs; locs(1)]; %#ok<AGROW>
                detectedPks = [detectedPks; pks(1)]; %#ok<AGROW>
            end

            results = table(detectedFreqs, detectedPks, ...
                'VariableNames', {'Frequency_Hz', 'Amplitude'});
        end

        function annotatePeaks(results, opts)
            if nargin < 2 || isempty(opts)
                opts = struct();
            end
            if isempty(results)
                return;
            end

            offset = bms.analyzer.FrequencySpectrumService.option(opts, 'labelOffset', 0.02);
            hold on;
            for i = 1:height(results)
                text(results.Frequency_Hz(i), results.Amplitude(i) + offset, ...
                    sprintf('X=%.3f', results.Frequency_Hz(i)), ...
                    'FontSize', 8, ...
                    'VerticalAlignment', 'bottom', ...
                    'HorizontalAlignment', 'center', ...
                    'BackgroundColor', 'white', ...
                    'EdgeColor', 'black');
            end
            hold off;
        end

        function displayPeakResults(results)
            disp('检测到的目标频率附近的峰值:');
            disp(results);
        end

        function paths = savePlot(fig, outDir, baseName, cfg)
            if nargin < 4
                cfg = struct();
            end
            bms.core.PathResolver.ensureDir(outDir);
            paths = bms.plot.PlotService.saveModuleBundle(fig, outDir, baseName, cfg);
            disp(['频谱图已保存至 ' char(string(outDir))]);
        end

        function value = option(opts, fieldName, defaultValue)
            value = defaultValue;
            if isstruct(opts) && isfield(opts, fieldName) && ~isempty(opts.(fieldName))
                value = opts.(fieldName);
            end
        end
    end
end
