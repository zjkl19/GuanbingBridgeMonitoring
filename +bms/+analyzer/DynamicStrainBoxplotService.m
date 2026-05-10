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
                    idx = unique(round(linspace(1, numel(v), maxPointsPerSeries)), 'stable');
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
            [times, values] = load_timeseries_range( ...
                rootDir, subfolder, pointId, startDate, endDate, cfg, 'strain');
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
                    values = bms.analyzer.DynamicStrainBoxplotService.highpass(values, fs, fc);
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
            gapBreaks = diff(idx) > 1 | bms.analyzer.DynamicStrainBoxplotService.diffSeconds(times(idx)) > maxGap;
            starts = [1; find(gapBreaks) + 1];
            stops = [find(gapBreaks); numel(idx)];
            for si = 1:numel(starts)
                seg = idx(starts(si):stops(si));
                if numel(seg) <= minLen
                    valuesOut(seg) = values(seg);
                else
                    valuesOut(seg) = filtfilt(b, a, double(values(seg)));
                end
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
