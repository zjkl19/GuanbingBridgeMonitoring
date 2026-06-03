classdef SpectrumPointService
    %SPECTRUMPOINTSERVICE Per-point spectrum processing and table output.

    methods (Static)
        function [ampDay, freqDay] = processPoint(datesAll, pid, rootDir, subfolder, targetFreqs, tolerance, psdRoot, style, cfg, spec, useParallel)
            nDay = numel(datesAll);
            nFreq = numel(targetFreqs);
            ampDay = NaN(nDay, nFreq);
            freqDay = NaN(nDay, nFreq);

            if useParallel
                parfor di = 1:nDay
                    [ampDay(di, :), freqDay(di, :)] = bms.analyzer.SpectrumPeakService.processOneDay( ...
                        datesAll(di), pid, rootDir, subfolder, spec.sensorType, targetFreqs, tolerance, psdRoot, style, cfg);
                end
            else
                for di = 1:nDay
                    [ampDay(di, :), freqDay(di, :)] = bms.analyzer.SpectrumPeakService.processOneDay( ...
                        datesAll(di), pid, rootDir, subfolder, spec.sensorType, targetFreqs, tolerance, psdRoot, style, cfg);
                end
            end
        end

        function writePointSheet(datesAll, freqDay, ampDay, forceSeries, targetFreqs, excelFile, moduleKey, pid)
            dateCol = datesAll(:);
            freqTbl = array2table(freqDay, 'VariableNames', compose('Freq_%0.3fHz', targetFreqs));
            ampTbl = array2table(ampDay, 'VariableNames', compose('Amp_%0.3fHz', targetFreqs));
            T = [table(dateCol, 'VariableNames', {'Date'}), freqTbl, ampTbl];
            if ~isempty(forceSeries)
                T = [T, table(forceSeries(:), 'VariableNames', {'CableForce_kN'})];
            end
            bms.io.StatsWriter.writeModuleTableChecked(T, excelFile, moduleKey, 'Sheet', pid);
        end

        function [forceSeries, warnLines, forceYLim, hasParams] = cableForceSeries(cfg, pid, freqDay, style)
            [rho, L, forceDecimals, hasParams] = bms.analyzer.CableForceService.params(cfg, pid);
            forceYLim = bms.analyzer.CableForceService.resolveYLim(cfg, pid, style);
            freqsForForce = bms.analyzer.CableForceService.forceFrequencies(cfg, pid, freqDay);
            forceSeries = bms.analyzer.CableForceService.compute(freqsForForce, rho, L, forceDecimals);
            warnLines = bms.analyzer.CableForceService.warnLines(cfg, pid, style, '');
        end
    end
end
