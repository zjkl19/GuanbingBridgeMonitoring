classdef test_frequency_spectrum_service < matlab.unittest.TestCase
    properties
        Root
        OldFigureVisible
    end

    methods (TestMethodSetup)
        function setupCase(tc)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(projectRoot, fullfile(projectRoot, 'analysis'), fullfile(projectRoot, 'pipeline'));
            tc.Root = tempname;
            mkdir(tc.Root);
            tc.OldFigureVisible = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
        end
    end

    methods (TestMethodTeardown)
        function cleanupCase(tc)
            close all force;
            set(0, 'DefaultFigureVisible', tc.OldFigureVisible);
            if exist(tc.Root, 'dir')
                rmdir(tc.Root, 's');
            end
        end
    end

    methods (Test)
        function computeSpectrumFindsSineFrequencyBand(tc)
            fs = 20;
            data = spectrum_table(fs, 2.0);

            [freq, amplitude] = bms.analyzer.FrequencySpectrumService.computeSpectrum( ...
                data, '2026-01-01 00:00:00.000', '2026-01-01 00:00:09.950', fs, struct('smoothWindow', 1));

            [~, idx] = max(amplitude(freq > 0));
            positiveFreq = freq(freq > 0);
            tc.verifyEqual(positiveFreq(idx), 2.0, 'AbsTol', 0.11);
        end

        function detectTargetPeaksChoosesStrongestPeakInTolerance(tc)
            freq = (0:0.1:5)';
            amplitude = zeros(size(freq));
            amplitude(abs(freq - 1.9) < 1e-12) = 2;
            amplitude(abs(freq - 2.0) < 1e-12) = 5;
            amplitude(abs(freq - 2.1) < 1e-12) = 3;

            results = bms.analyzer.FrequencySpectrumService.detectTargetPeaks(freq, amplitude, 2.0, 0.15);

            tc.verifyEqual(height(results), 1);
            tc.verifyEqual(results.Frequency_Hz(1), 2.0, 'AbsTol', 1e-12);
            tc.verifyEqual(results.Amplitude(1), 5);
        end

        function legacyWrapperWritesSpectrumBundle(tc)
            fs = 20;
            data = spectrum_table(fs, 2.0);
            here = pwd;
            cleanup = onCleanup(@() cd(here));
            cd(tc.Root);

            analyze_frequency_spectrum(data, datetime(2026, 1, 1), ...
                datetime(2026, 1, 1, 0, 0, 9.950), fs, 2.0, 0.2, true);

            figs = dir(fullfile(tc.Root, '频谱分析结果', '*.fig'));
            tc.verifyGreaterThanOrEqual(numel(figs), 1);
        end
    end
end

function data = spectrum_table(fs, freqHz)
    times = datetime(2026, 1, 1) + seconds((0:199)' / fs);
    values = sin(2 * pi * freqHz * seconds(times - times(1)));
    data = table(times, values, 'VariableNames', {'Time', 'Value'});
end
