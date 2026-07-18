classdef SpectrumPointService
    %SPECTRUMPOINTSERVICE Per-point spectrum processing and table output.

    methods (Static)
        function [ampDay, freqDay] = processPoint(datesAll, pid, rootDir, subfolder, targetFreqs, tolerance, psdRoot, style, cfg, spec, useParallel)
            nDay = numel(datesAll);
            nFreq = numel(targetFreqs);
            ampDay = NaN(nDay, nFreq);
            freqDay = NaN(nDay, nFreq);

            if useParallel
                bms.app.RunProgressReporter.checkpoint( ...
                    'stage', 'parallel_spectrum_dates', ...
                    'current_point_id', pid, ...
                    'current_date', '', ...
                    'processed_dates', 0, ...
                    'total_dates', nDay);
                parfor di = 1:nDay
                    [ampDay(di, :), freqDay(di, :)] = bms.analyzer.SpectrumPeakService.processOneDay( ...
                        datesAll(di), pid, rootDir, subfolder, spec.sensorType, targetFreqs, tolerance, psdRoot, style, cfg);
                end
            else
                for di = 1:nDay
                    bms.app.StopController.throwIfRequested('Stop requested before next spectrum date');
                    bms.app.RunProgressReporter.checkpoint( ...
                        'stage', 'analyze_spectrum_date', ...
                        'current_point_id', pid, ...
                        'current_date', datestr(datesAll(di), 'yyyy-mm-dd'), ...
                        'processed_dates', di - 1, ...
                        'total_dates', nDay);
                    [ampDay(di, :), freqDay(di, :)] = bms.analyzer.SpectrumPeakService.processOneDay( ...
                        datesAll(di), pid, rootDir, subfolder, spec.sensorType, targetFreqs, tolerance, psdRoot, style, cfg);
                end
            end
            if nDay > 0
                bms.app.RunProgressReporter.checkpoint( ...
                    'stage', 'spectrum_dates_complete', ...
                    'current_point_id', pid, ...
                    'current_date', datestr(datesAll(end), 'yyyy-mm-dd'), ...
                    'processed_dates', nDay, ...
                    'total_dates', nDay);
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
