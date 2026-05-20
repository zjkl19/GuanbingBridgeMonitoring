classdef SpectrumPeakService
    %SPECTRUMPEAKSERVICE Shared Welch PSD peak extraction helpers.

    methods (Static)
        function [ampRow, freqRow] = processOneDay(day, pid, rootDir, subfolder, sensorType, targetFreqs, tolerance, psdRoot, style, cfg)
            ampRow = NaN(1, numel(targetFreqs));
            freqRow = NaN(1, numel(targetFreqs));

            dayStr = datestr(day, 'yyyy-mm-dd');
            [times, values] = load_timeseries_range(rootDir, subfolder, pid, dayStr, dayStr, cfg, sensorType);
            if isempty(times)
                return;
            end

            [f, Pdb, ok] = bms.analyzer.SpectrumPeakService.computeWindowPsd(times, values, day);
            if ~ok
                return;
            end

            bms.analyzer.SpectrumPeakService.savePsdPlot(f, Pdb, targetFreqs, pid, dayStr, psdRoot, style, cfg);
            [ampRow, freqRow] = bms.analyzer.SpectrumPeakService.peakRows(f, Pdb, targetFreqs, tolerance);
        end

        function [f, Pdb, ok] = computeWindowPsd(times, values, day)
            f = [];
            Pdb = [];
            ok = false;

            t0 = day + duration(5, 30, 0);
            t1 = day + duration(5, 40, 0);
            winIdx = times >= t0 & times <= t1;
            if ~any(winIdx)
                return;
            end

            tsWin = times(winIdx);
            fs = 1 / median(seconds(diff(tsWin)));
            if ~isfinite(fs) || fs <= 0
                return;
            end

            winSec = 20;
            wlen = round(winSec * fs);
            if mod(wlen, 2) == 1
                wlen = wlen + 1;
            end
            overlap = round(0.5 * wlen);
            nfft = 2^nextpow2(max(wlen, 8192));

            xRaw = values(winIdx);
            good = isfinite(xRaw);
            if nnz(good) < 3
                return;
            end
            x = detrend(xRaw(good));
            if numel(x) < wlen
                wlen = numel(x);
                overlap = round(0.5 * wlen);
                nfft = 2^nextpow2(max(wlen, 512));
            end

            [Pxx, f] = pwelch(x, hamming(wlen), overlap, nfft, fs, 'onesided');
            Pdb = 10 * log10(Pxx);
            ok = true;
        end

        function [ampRow, freqRow] = peakRows(f, Pdb, targetFreqs, tolerance)
            ampRow = NaN(1, numel(targetFreqs));
            freqRow = NaN(1, numel(targetFreqs));
            tolerance = bms.analyzer.SpectrumConfigService.normalizeTolerance(tolerance, targetFreqs);
            for i = 1:numel(targetFreqs)
                f0 = targetFreqs(i);
                tol = tolerance(min(i, numel(tolerance)));
                idxBand = f >= f0 - tol & f <= f0 + tol;
                if ~any(idxBand)
                    continue;
                end

                [pk, idxRel] = max(Pdb(idxBand));
                bandF = f(idxBand);
                ampRow(i) = pk;
                freqRow(i) = bandF(idxRel);
            end
        end

        function savePsdPlot(f, Pdb, targetFreqs, pid, dayStr, psdRoot, style, cfg)
            psdDir = fullfile(psdRoot, pid);
            bms.core.PathResolver.ensureDir(psdDir);

            fig = figure('Visible', 'off', 'Position', [100 100 900 420]);
            plot(f, Pdb, 'Color', style.psd_color, 'LineWidth', 1);
            grid on;
            hold on;
            xline(targetFreqs, '--r');
            xlabel('频率 (Hz)');
            ylabel(style.psd_ylabel);
            title(sprintf('%s %s  %s', style.psd_title_prefix, pid, dayStr));
            bms.plot.PlotService.saveModuleBundle(fig, psdDir, sprintf('PSD_%s_%s', pid, dayStr), cfg, struct('save_emf', false));
        end
    end
end
