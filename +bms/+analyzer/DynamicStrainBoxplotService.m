classdef DynamicStrainBoxplotService
    %DYNAMICSTRAINBOXPLOTSERVICE Shared boxplot/stat helpers for dynamic strain.

    methods (Static)
        function plotMat = sampleBoxplotMatrix(dataMat, maxPointsPerSeries)
            if nargin < 2 || isempty(maxPointsPerSeries) || ~isscalar(maxPointsPerSeries) || ...
                    ~isfinite(maxPointsPerSeries) || maxPointsPerSeries < 1000
                maxPointsPerSeries = 50000;
            end
            maxPointsPerSeries = round(maxPointsPerSeries);

            nCols = size(dataMat, 2);
            keepCols = cell(nCols, 1);
            maxLen = 0;
            for c = 1:nCols
                v = dataMat(:, c);
                v = v(isfinite(v));
                if numel(v) > maxPointsPerSeries
                    [~, minIdx] = min(v);
                    [~, maxIdx] = max(v);
                    idx = unique(round(linspace(1, numel(v), maxPointsPerSeries)), 'stable');
                    idx = unique([idx(:); minIdx; maxIdx]);
                    if numel(idx) > maxPointsPerSeries
                        protectedIdx = unique([minIdx; maxIdx]);
                        candidateIdx = setdiff(idx(:), protectedIdx(:), 'stable');
                        remaining = maxPointsPerSeries - numel(protectedIdx);
                        if remaining > 0 && ~isempty(candidateIdx)
                            pick = unique(round(linspace(1, numel(candidateIdx), remaining)), 'stable');
                            candidateIdx = candidateIdx(pick);
                        else
                            candidateIdx = [];
                        end
                        idx = unique([protectedIdx(:); candidateIdx(:)]);
                    end
                    idx = sort(idx(:));
                    v = v(idx);
                end
                keepCols{c} = v;
                maxLen = max(maxLen, numel(v));
            end

            plotMat = NaN(maxLen, nCols);
            for c = 1:nCols
                v = keepCols{c};
                plotMat(1:numel(v), c) = v;
            end
        end

        function T = statsTable(dataMat, labels)
            n = numel(labels);
            mins = NaN(n, 1);
            q1s = NaN(n, 1);
            meds = NaN(n, 1);
            q3s = NaN(n, 1);
            maxs = NaN(n, 1);
            means = NaN(n, 1);
            stds = NaN(n, 1);
            cnts = NaN(n, 1);

            for k = 1:n
                v = dataMat(:, k);
                v = v(isfinite(v));
                if isempty(v)
                    continue;
                end
                mins(k) = min(v);
                q1s(k) = quantile(v, 0.25);
                meds(k) = quantile(v, 0.50);
                q3s(k) = quantile(v, 0.75);
                maxs(k) = max(v);
                means(k) = mean(v);
                stds(k) = std(v);
                cnts(k) = numel(v);
            end

            T = table(labels(:), mins, q1s, meds, q3s, maxs, means, stds, cnts, ...
                'VariableNames', {'PointID', 'Min', 'Q1', 'Median', 'Q3', 'Max', 'Mean', 'Std', 'Count'});
        end

        function [values, times] = processPoint(rootDir, subfolder, startDate, endDate, pointId, dsCfg, cfg, mode)
            sourceCfg = bms.analyzer.DynamicStrainBoxplotService.sourceCleaningConfig(cfg);
            [times, values] = load_timeseries_range( ...
                rootDir, subfolder, pointId, startDate, endDate, sourceCfg, 'strain');
            if isempty(values)
                return;
            end

            fs = bms.analyzer.DynamicStrainBoxplotService.estimateSampleRate(times, ...
                bms.analyzer.DynamicStrainBoxplotService.getFieldDefault(dsCfg, 'Fs', []), ...
                ['dynamic_strain_' char(mode) ':fs']);

            mode = lower(char(string(mode)));
            switch mode
                case {'highpass', 'high'}
                    fc = bms.analyzer.DynamicStrainBoxplotService.getFieldDefault(dsCfg, 'Fc', []);
                    values = bms.analyzer.DynamicStrainBoxplotService.highpassBySegments(times, values, fs, fc, dsCfg);
                    thresholdKey = 'dynamic_strain';
                case {'lowpass', 'low'}
                    [fc, cutoffMinutes] = bms.analyzer.DynamicStrainBoxplotService.resolveLowpassCutoff(dsCfg, fs);
                    order = max(1, min(6, round(bms.analyzer.DynamicStrainBoxplotService.getNumericFieldDefault(dsCfg, 'FilterOrder', 2))));
                    if ~isempty(fc) && fc > 0
                        nyq = fs / 2;
                        if nyq > 0 && fc < nyq
                            values = bms.analyzer.DynamicStrainBoxplotService.lowpassBySegments(times, values, fs, fc, order, dsCfg);
                            if ~isempty(cutoffMinutes)
                                fprintf('    Lowpass cutoff period %.3g min (fs=%.6g Hz)\n', cutoffMinutes, fs);
                            end
                        else
                            bms.analyzer.DynamicStrainBoxplotService.warningOnce('dynamic_strain_lowpass:fc', ...
                                sprintf('Lowpass cutoff %.6g Hz is not below Nyquist %.6g Hz; skipping filter.', fc, nyq));
                        end
                    end
                    thresholdKey = 'dynamic_strain_lowpass';
                otherwise
                    error('DynamicStrainBoxplotService:UnsupportedMode', 'Unsupported dynamic strain filter mode: %s', mode);
            end

            edgeTrimSec = bms.analyzer.DynamicStrainBoxplotService.getNumericFieldDefault(dsCfg, 'EdgeTrimSec', 0);
            [values, times] = bms.analyzer.DynamicStrainBoxplotService.trimEdges(values, times, fs, edgeTrimSec);
            values = bms.analyzer.DynamicStrainBoxplotService.applyBoundsAndThresholds(values, times, dsCfg, cfg, thresholdKey, pointId);
        end

        function sourceCfg = sourceCleaningConfig(cfg)
            % Dynamic strain filters must see the complete finite source
            % series. Absolute static-strain thresholds are referenced to a
            % fixed baseline and can erase an entire later month after a
            % legitimate seasonal baseline shift. Preserve file aliases,
            % offsets, scaling, zero and outlier rules, but defer thresholding
            % until after the dynamic high/low-pass filter.
            sourceCfg = cfg;
            if ~isstruct(sourceCfg)
                return;
            end
            if isfield(sourceCfg, 'defaults') && isstruct(sourceCfg.defaults) ...
                    && isfield(sourceCfg.defaults, 'strain') ...
                    && isstruct(sourceCfg.defaults.strain) ...
                    && isfield(sourceCfg.defaults.strain, 'thresholds')
                sourceCfg.defaults.strain = rmfield(sourceCfg.defaults.strain, 'thresholds');
            end
            if ~isfield(sourceCfg, 'per_point') || ~isstruct(sourceCfg.per_point) ...
                    || ~isfield(sourceCfg.per_point, 'strain') ...
                    || ~isstruct(sourceCfg.per_point.strain)
                return;
            end
            pointFields = fieldnames(sourceCfg.per_point.strain);
            for i = 1:numel(pointFields)
                key = pointFields{i};
                block = sourceCfg.per_point.strain.(key);
                if isstruct(block) && isfield(block, 'thresholds')
                    sourceCfg.per_point.strain.(key) = rmfield(block, 'thresholds');
                end
            end
        end

        function values = highpass(values, fs, fc)
            if isempty(fc) || ~isfinite(fc) || fc <= 0
                return;
            end
            nyq = fs / 2;
            if ~(isfinite(nyq) && nyq > 0 && fc < nyq)
                bms.analyzer.DynamicStrainBoxplotService.warningOnce('dynamic_strain_highpass:fc', ...
                    sprintf('Highpass cutoff %.6g Hz is not below Nyquist %.6g Hz; skipping filter.', fc, nyq));
                return;
            end

            [b, a] = butter(1, fc / nyq, 'high');
            maskInvalid = isnan(values) | ~isfinite(values);
            values(maskInvalid) = 0;
            values = filtfilt(b, a, values);
            values(maskInvalid) = NaN;
        end

        function valuesOut = highpassBySegments(times, values, fs, fc, dsCfg)
            if isempty(fc) || ~isfinite(fc) || fc <= 0
                valuesOut = values;
                return;
            end
            nyq = fs / 2;
            if ~(isfinite(nyq) && nyq > 0 && fc < nyq)
                bms.analyzer.DynamicStrainBoxplotService.warningOnce('dynamic_strain_highpass:fc', ...
                    sprintf('Highpass cutoff %.6g Hz is not below Nyquist %.6g Hz; skipping filter.', fc, nyq));
                valuesOut = values;
                return;
            end

            [b, a] = butter(1, fc / nyq, 'high');
            valuesOut = bms.analyzer.DynamicStrainBoxplotService.filterBySegmentsAndChunks( ...
                times, values, fs, b, a, dsCfg, 'highpass');
        end

        function [values, times] = trimEdges(values, times, fs, edgeTrimSec)
            trimN = round(edgeTrimSec * fs);
            if trimN > 0 && numel(values) > 2 * trimN
                values = values(trimN+1:end-trimN);
                times = times(trimN+1:end-trimN);
            end
        end

        function values = applyBoundsAndThresholds(values, times, dsCfg, cfg, thresholdKey, pointId)
            lowerBound = bms.analyzer.DynamicStrainBoxplotService.getFieldDefault(dsCfg, 'LowerBound', []);
            upperBound = bms.analyzer.DynamicStrainBoxplotService.getFieldDefault(dsCfg, 'UpperBound', []);
            if ~isempty(lowerBound)
                values(values < lowerBound) = NaN;
            end
            if ~isempty(upperBound)
                values(values > upperBound) = NaN;
            end
            values = apply_threshold_rules(values, times, resolve_post_filter_thresholds(cfg, thresholdKey, pointId));
        end

        function fs = estimateSampleRate(times, fsCfg, warningId)
            if nargin < 3 || isempty(warningId)
                warningId = 'dynamic_strain:fs';
            end
            if ~isempty(fsCfg) && isfinite(fsCfg) && fsCfg > 0
                fs = double(fsCfg);
                return;
            end
            fs = 20;
            if numel(times) < 2
                bms.analyzer.DynamicStrainBoxplotService.warningOnce(warningId, ...
                    'Cannot estimate sample rate from dynamic strain data; using default 20 Hz.');
                return;
            end
            dt = bms.analyzer.DynamicStrainBoxplotService.diffSeconds(times(:));
            dt = dt(isfinite(dt) & dt > 0);
            if isempty(dt)
                bms.analyzer.DynamicStrainBoxplotService.warningOnce(warningId, ...
                    'Cannot estimate sample rate from dynamic strain data; using default 20 Hz.');
                return;
            end
            fs = 1 / median(dt);
        end

        function [fc, cutoffMinutes] = resolveLowpassCutoff(dsCfg, fs)
            cutoffMinutes = [];
            fc = bms.analyzer.DynamicStrainBoxplotService.getFieldDefault(dsCfg, 'Fc', []);
            if ~isempty(fc) && isfinite(fc) && fc > 0
                fc = double(fc);
                return;
            end

            cutoffMinutes = bms.analyzer.DynamicStrainBoxplotService.getFieldDefault(dsCfg, 'CutoffPeriodMinutes', []);
            if ~isempty(cutoffMinutes) && isfinite(cutoffMinutes) && cutoffMinutes > 0
                cutoffMinutes = double(cutoffMinutes);
                fc = 1 / (cutoffMinutes * 60);
                return;
            end

            mode = lower(char(string(bms.analyzer.DynamicStrainBoxplotService.getFieldDefault(dsCfg, 'FilterMode', 'auto'))));
            if strcmp(mode, 'auto')
                cutoffMinutes = bms.analyzer.DynamicStrainBoxplotService.autoCutoffPeriodMinutes(dsCfg, fs);
                fc = 1 / (cutoffMinutes * 60);
            else
                fc = [];
            end
        end

        function minutesValue = autoCutoffPeriodMinutes(dsCfg, fs)
            preset = lower(char(string(bms.analyzer.DynamicStrainBoxplotService.getFieldDefault(dsCfg, 'AutoPreset', 'temperature'))));
            switch preset
                case {'temperature', 'temp', 'thermal', 'temperature_strain'}
                    minutesValue = bms.analyzer.DynamicStrainBoxplotService.getNumericFieldDefault(dsCfg, 'AutoCutoffPeriodMinutes', 720);
                otherwise
                    minutesValue = bms.analyzer.DynamicStrainBoxplotService.getNumericFieldDefault(dsCfg, 'AutoCutoffPeriodMinutes', 720);
            end

            if ~isfinite(minutesValue) || minutesValue <= 0
                minutesValue = 720;
            end
            minSamples = bms.analyzer.DynamicStrainBoxplotService.getNumericFieldDefault(dsCfg, 'MinSamplesPerCutoff', 20);
            if isfinite(fs) && fs > 0 && isfinite(minSamples) && minSamples > 0
                sampleMinutes = 1 / fs / 60;
                minutesValue = max(minutesValue, minSamples * sampleMinutes);
            end
        end

        function valuesOut = lowpassBySegments(times, values, fs, fc, order, dsCfg)
            valuesOut = NaN(size(values));
            values = values(:);
            times = times(:);
            n = min(numel(values), numel(times));
            if n == 0
                return;
            end
            values = values(1:n);
            times = times(1:n);

            valid = isfinite(values) & bms.analyzer.DynamicStrainBoxplotService.isValidTime(times);
            idx = find(valid);
            if isempty(idx)
                return;
            end

            dtAll = bms.analyzer.DynamicStrainBoxplotService.diffSeconds(times(idx));
            dtAll = dtAll(isfinite(dtAll) & dtAll > 0);
            if isempty(dtAll)
                maxGap = 5 / fs;
            else
                maxGap = 5 * median(dtAll);
            end
            maxGapCfg = bms.analyzer.DynamicStrainBoxplotService.getFieldDefault(dsCfg, 'MaxGapSec', []);
            if ~isempty(maxGapCfg) && isfinite(maxGapCfg) && maxGapCfg > 0
                maxGap = min(maxGap, double(maxGapCfg));
            end

            [b, a] = butter(order, fc / (fs / 2), 'low');
            minLen = 3 * max(numel(a), numel(b));
            useDownsample = bms.analyzer.DynamicStrainBoxplotService.getLogicalFieldDefault( ...
                dsCfg, 'DownsampleBeforeFilter', false);
            gapBreaks = diff(idx) > 1 | bms.analyzer.DynamicStrainBoxplotService.diffSeconds(times(idx)) > maxGap;
            starts = [1; find(gapBreaks) + 1];
            stops = [find(gapBreaks); numel(idx)];
            for si = 1:numel(starts)
                seg = idx(starts(si):stops(si));
                if numel(seg) <= minLen
                    valuesOut(seg) = values(seg);
                elseif useDownsample
                    valuesOut(seg) = bms.analyzer.DynamicStrainBoxplotService.lowpassDownsampledSegment( ...
                        times(seg), values(seg), fs, fc, order, dsCfg);
                else
                    valuesOut(seg) = filtfilt(b, a, double(values(seg)));
                end
            end
        end

        function valuesOut = filterBySegmentsAndChunks(times, values, fs, b, a, dsCfg, mode)
            valuesOut = NaN(size(values));
            values = values(:);
            times = times(:);
            n = min(numel(values), numel(times));
            if n == 0
                return;
            end
            values = values(1:n);
            times = times(1:n);

            valid = isfinite(values) & bms.analyzer.DynamicStrainBoxplotService.isValidTime(times);
            idx = find(valid);
            if isempty(idx)
                return;
            end

            maxGap = bms.analyzer.DynamicStrainBoxplotService.segmentMaxGapSec(times(idx), fs, dsCfg);
            minLen = 3 * max(numel(a), numel(b));
            gapBreaks = diff(idx) > 1 | bms.analyzer.DynamicStrainBoxplotService.diffSeconds(times(idx)) > maxGap;
            starts = [1; find(gapBreaks) + 1];
            stops = [find(gapBreaks); numel(idx)];

            chunkDays = bms.analyzer.DynamicStrainBoxplotService.getNumericFieldDefault(dsCfg, 'ChunkDays', 0);
            chunkSec = chunkDays * 86400;
            overlapSec = bms.analyzer.DynamicStrainBoxplotService.getNumericFieldDefault(dsCfg, 'ChunkOverlapSec', NaN);
            if ~isfinite(overlapSec) || overlapSec < 0
                overlapSec = max(300, 20 / max(eps, bms.analyzer.DynamicStrainBoxplotService.inferCutoffFromFilter(b, a, fs, mode)));
            end

            for si = 1:numel(starts)
                seg = idx(starts(si):stops(si));
                if numel(seg) <= minLen
                    valuesOut(seg) = values(seg);
                elseif isfinite(chunkSec) && chunkSec > 0
                    valuesOut(seg) = bms.analyzer.DynamicStrainBoxplotService.filterSegmentInChunks( ...
                        times(seg), values(seg), b, a, minLen, chunkSec, overlapSec);
                else
                    valuesOut(seg) = filtfilt(b, a, double(values(seg)));
                end
            end
        end

        function valuesOut = filterSegmentInChunks(times, values, b, a, minLen, chunkSec, overlapSec)
            values = values(:);
            tsec = bms.analyzer.DynamicStrainBoxplotService.relativeSeconds(times);
            valuesOut = NaN(size(values));
            if numel(values) <= minLen || isempty(tsec) || ~all(isfinite(tsec)) || tsec(end) <= tsec(1)
                if numel(values) > minLen
                    valuesOut = filtfilt(b, a, double(values));
                else
                    valuesOut = values;
                end
                return;
            end

            t0 = tsec(1);
            tEnd = tsec(end);
            coreStart = t0;
            while coreStart <= tEnd
                coreEnd = min(coreStart + chunkSec, tEnd + eps);
                if coreEnd <= coreStart
                    break;
                end
                if coreEnd >= tEnd
                    coreMask = tsec >= coreStart & tsec <= tEnd;
                else
                    coreMask = tsec >= coreStart & tsec < coreEnd;
                end
                coreLocal = find(coreMask);
                if isempty(coreLocal)
                    coreStart = coreEnd;
                    continue;
                end

                extMask = tsec >= (coreStart - overlapSec) & tsec <= (coreEnd + overlapSec);
                extLocal = find(extMask);
                if numel(extLocal) <= minLen
                    valuesOut(coreLocal) = values(coreLocal);
                else
                    filteredExt = filtfilt(b, a, double(values(extLocal)));
                    [~, loc] = ismember(coreLocal, extLocal);
                    validLoc = loc > 0;
                    valuesOut(coreLocal(validLoc)) = filteredExt(loc(validLoc));
                end
                coreStart = coreEnd;
            end
        end

        function valuesOut = lowpassDownsampledSegment(times, values, fs, fc, order, dsCfg)
            values = values(:);
            valuesOut = NaN(size(values));
            n = numel(values);
            minSamples = bms.analyzer.DynamicStrainBoxplotService.getNumericFieldDefault( ...
                dsCfg, 'DownsampleMinSamples', 200000);
            downsampleSec = bms.analyzer.DynamicStrainBoxplotService.getNumericFieldDefault(dsCfg, 'DownsampleSec', 0);
            if n < minSamples || ~(isfinite(downsampleSec) && downsampleSec > 0)
                [b, a] = butter(order, fc / (fs / 2), 'low');
                valuesOut = filtfilt(b, a, double(values));
                return;
            end

            maxStep = 0.25 / fc;
            if isfinite(maxStep) && maxStep > 0
                downsampleSec = min(downsampleSec, maxStep);
            end

            tsec = bms.analyzer.DynamicStrainBoxplotService.relativeSeconds(times);
            if isempty(tsec) || numel(tsec) ~= n || ~all(isfinite(tsec)) || tsec(end) <= tsec(1)
                [b, a] = butter(order, fc / (fs / 2), 'low');
                valuesOut = filtfilt(b, a, double(values));
                return;
            end

            bins = floor((tsec - tsec(1)) / downsampleSec) + 1;
            nBins = max(bins);
            if nBins < 1
                valuesOut = values;
                return;
            end
            vBin = accumarray(bins(:), double(values), [nBins 1], @median, NaN);
            tBin = accumarray(bins(:), double(tsec), [nBins 1], @mean, NaN);
            keep = isfinite(vBin) & isfinite(tBin);
            vBin = vBin(keep);
            tBin = tBin(keep);
            if numel(vBin) <= 3 * (order + 1)
                valuesOut = values;
                return;
            end

            dtBin = diff(tBin);
            dtBin = dtBin(isfinite(dtBin) & dtBin > 0);
            if isempty(dtBin)
                valuesOut = values;
                return;
            end
            fsBin = 1 / median(dtBin);
            nyqBin = fsBin / 2;
            if ~(isfinite(nyqBin) && nyqBin > 0 && fc < nyqBin)
                [b, a] = butter(order, fc / (fs / 2), 'low');
                valuesOut = filtfilt(b, a, double(values));
                return;
            end

            [bBin, aBin] = butter(order, fc / nyqBin, 'low');
            vFilt = filtfilt(bBin, aBin, vBin);
            valuesOut = interp1(tBin, vFilt, tsec, 'linear', 'extrap');
        end

        function maxGap = segmentMaxGapSec(times, fs, dsCfg)
            dtAll = bms.analyzer.DynamicStrainBoxplotService.diffSeconds(times);
            dtAll = dtAll(isfinite(dtAll) & dtAll > 0);
            if isempty(dtAll)
                maxGap = 5 / fs;
            else
                maxGap = 5 * median(dtAll);
            end
            maxGapCfg = bms.analyzer.DynamicStrainBoxplotService.getFieldDefault(dsCfg, 'MaxGapSec', []);
            if ~isempty(maxGapCfg) && isfinite(maxGapCfg) && maxGapCfg > 0
                maxGap = min(maxGap, double(maxGapCfg));
            end
        end

        function tsec = relativeSeconds(times)
            times = times(:);
            if isempty(times)
                tsec = [];
            elseif isdatetime(times) || isduration(times)
                tsec = seconds(times - times(1));
            else
                tsec = double(times) - double(times(1));
            end
            tsec = tsec(:);
        end

        function fc = inferCutoffFromFilter(~, ~, fs, mode)
            if strcmpi(char(string(mode)), 'highpass')
                fc = max(eps, fs / 100);
            else
                fc = max(eps, fs / 100);
            end
        end

        function tf = isValidTime(times)
            if isdatetime(times)
                tf = ~isnat(times);
            else
                tf = isfinite(times);
            end
        end

        function dt = diffSeconds(times)
            if isdatetime(times) || isduration(times)
                dt = seconds(diff(times));
            else
                dt = diff(double(times));
            end
        end

        function value = getFieldDefault(s, name, defaultValue)
            if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
                value = s.(name);
            else
                value = defaultValue;
            end
        end

        function value = getNumericFieldDefault(s, name, defaultValue)
            value = defaultValue;
            if isstruct(s) && isfield(s, name) && ~isempty(s.(name)) && ...
                    isnumeric(s.(name)) && isscalar(s.(name)) && isfinite(s.(name))
                value = double(s.(name));
            end
        end

        function value = getLogicalFieldDefault(s, name, defaultValue)
            value = defaultValue;
            if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
                raw = s.(name);
                if islogical(raw)
                    value = logical(raw);
                elseif isnumeric(raw) && isscalar(raw)
                    value = raw ~= 0;
                end
            end
        end

        function warningOnce(id, message)
            persistent fired;
            if isempty(fired)
                fired = containers.Map();
            end
            if ~isKey(fired, id)
                warning(message);
                fired(id) = true;
            end
        end
    end
end
