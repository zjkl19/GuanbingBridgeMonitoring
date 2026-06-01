classdef CleaningPipeline
    %CLEANINGPIPELINE Applies common point-series cleaning rules.

    methods (Static)
        function rules = resolveRules(cfg, sensorType, pointId)
            if nargin < 1 || isempty(cfg), cfg = struct(); end
            if nargin < 2 || isempty(sensorType), sensorType = 'generic'; end
            if nargin < 3 || isempty(pointId), pointId = ''; end
            sensorType = char(string(sensorType));
            pointId = char(string(pointId));

            rules = bms.data.CleaningPipeline.emptyRules();
            sharedSensor = bms.data.CleaningPipeline.sharedSensorType(sensorType);

            rules = bms.data.CleaningPipeline.mergeDefaultRules(rules, cfg, sensorType);
            if ~isempty(sharedSensor)
                rules = bms.data.CleaningPipeline.mergeDefaultRules(rules, cfg, sharedSensor);
            end

            rules = bms.data.CleaningPipeline.mergePointRules(rules, cfg, sensorType, pointId);
            if ~isempty(sharedSensor)
                rules = bms.data.CleaningPipeline.mergePointRules(rules, cfg, sharedSensor, pointId);
            end
            if startsWith(sensorType, 'wind_')
                rules = bms.data.CleaningPipeline.mergePointRules(rules, cfg, 'wind', pointId);
            end
        end

        function rules = emptyRules()
            rules = struct('thresholds', [], 'zero_to_nan', false, ...
                'outlier_window_sec', [], 'outlier_threshold_factor', [], ...
                'offset_correction', [], 'value_scale', []);
        end

        function [vals, log] = apply(vals, times, rules, opts)
            if nargin < 3 || isempty(rules), rules = bms.data.CleaningPipeline.emptyRules(); end
            if nargin < 4 || isempty(opts), opts = struct(); end
            original = vals;

            log = struct();
            log.initial_count = numel(vals);
            log.initial_nan_count = sum(isnan(vals));
            log.offset_correction = [];
            log.offset_applied = false;
            log.threshold_removed_count = 0;
            log.zero_removed_count = 0;
            log.outlier_removed_count = 0;
            log.final_count = numel(vals);
            log.final_nan_count = sum(isnan(vals));

            [vals, offsetApplied, offsetValue] = bms.data.CleaningPipeline.applyOffset(vals, times, rules);
            log.offset_applied = offsetApplied;
            if offsetApplied
                log.offset_correction = offsetValue;
                bms.data.CleaningPipeline.recordOffset(times, vals, rules, opts, offsetValue);
            end
            [vals, scaleApplied, scaleValue] = bms.data.CleaningPipeline.applyValueScale(vals, rules);
            log.value_scale_applied = scaleApplied;
            log.value_scale = scaleValue;

            thresholds = [];
            if isstruct(rules) && isfield(rules, 'thresholds')
                thresholds = rules.thresholds;
            end
            before = isnan(vals);
            vals = bms.data.CleaningPipeline.applyThresholds(vals, times, thresholds);
            after = isnan(vals);
            log.threshold_removed_count = sum(after & ~before);

            before = isnan(vals);
            vals = bms.data.CleaningPipeline.applyZeroToNan(vals, rules);
            after = isnan(vals);
            log.zero_removed_count = sum(after & ~before);

            before = isnan(vals);
            vals = bms.data.CleaningPipeline.applyOutliers(vals, times, rules);
            after = isnan(vals);
            log.outlier_removed_count = sum(after & ~before);

            log.final_nan_count = sum(isnan(vals));
            log.changed_count = bms.data.CleaningPipeline.changedCount(original, vals);
        end

        function [vals, applied, offset] = applyOffset(vals, times, rules)
            applied = false;
            offset = [];
            if ~isstruct(rules) || ~isfield(rules, 'offset_correction') || isempty(rules.offset_correction)
                return;
            end

            offset = bms.data.CleaningPipeline.resolveOffsetValue(rules.offset_correction, times, vals);
            if isnumeric(offset) && ~isscalar(offset) && numel(offset) == numel(vals)
                offset = reshape(offset, size(vals));
            end
            if bms.data.CleaningPipeline.isOffsetApplicable(offset, vals)
                vals = vals + offset;
                offset = bms.data.CleaningPipeline.compactOffsetLogValue(offset, rules.offset_correction);
                applied = true;
            end
        end

        function [vals, applied, scale] = applyValueScale(vals, rules)
            applied = false;
            scale = [];
            if ~isstruct(rules) || ~isfield(rules, 'value_scale') || isempty(rules.value_scale)
                return;
            end
            raw = rules.value_scale;
            if ischar(raw) || isstring(raw)
                raw = str2double(raw);
            end
            if isnumeric(raw) && isscalar(raw) && isfinite(raw) && raw ~= 1
                scale = double(raw);
                vals = vals .* scale;
                applied = true;
            end
        end

        function vals = applyThresholds(vals, times, thresholds)
            if isempty(vals) || isempty(thresholds), return; end
            if ~isstruct(thresholds), return; end
            thresholds = thresholds(:);
            for k = 1:numel(thresholds)
                th = thresholds(k);
                tmask = true(size(vals));
                if isfield(th, 't_range_start') && isfield(th, 't_range_end') ...
                        && ~isempty(th.t_range_start) && ~isempty(th.t_range_end)
                    t0 = bms.data.CleaningPipeline.parseRuleTime(th.t_range_start);
                    t1 = bms.data.CleaningPipeline.parseRuleTime(th.t_range_end);
                    tmask = (times >= t0) & (times <= t1);
                end
                if isfield(th, 'min') && ~isempty(th.min) && isfinite(th.min)
                    vals(tmask & vals < th.min) = NaN;
                end
                if isfield(th, 'max') && ~isempty(th.max) && isfinite(th.max)
                    vals(tmask & vals > th.max) = NaN;
                end
            end
        end

        function vals = applyZeroToNan(vals, rules)
            if isstruct(rules) && isfield(rules, 'zero_to_nan') && logical(rules.zero_to_nan)
                vals(vals == 0) = NaN;
            end
        end

        function vals = applyOutliers(vals, times, rules)
            if ~isstruct(rules) || ~isfield(rules, 'outlier_window_sec') || ~isfield(rules, 'outlier_threshold_factor')
                return;
            end
            if isempty(rules.outlier_window_sec) || isempty(rules.outlier_threshold_factor) || numel(times) < 2
                return;
            end
            dt = seconds(diff(times));
            dt = dt(isfinite(dt) & dt > 0);
            if isempty(dt), return; end
            fs = 1 / median(dt);
            w = max(1, round(fs * rules.outlier_window_sec));
            mask = isoutlier(vals, 'movmedian', w, 'ThresholdFactor', rules.outlier_threshold_factor);
            vals(mask) = NaN;
        end

        function recordOffset(times, vals, rules, opts, offsetValue)
            if nargin < 4 || ~isstruct(opts) || ~isfield(opts, 'record_offset') || ~logical(opts.record_offset)
                return;
            end
            if nargin < 5 || isempty(offsetValue)
                offsetValue = bms.data.CleaningPipeline.resolveOffsetValue(rules.offset_correction, times, vals);
            end
            try
                sensorType = bms.data.CleaningPipeline.optionText(opts, 'sensor_type');
                pointId = bms.data.CleaningPipeline.optionText(opts, 'point_id');
                files = {};
                if isfield(opts, 'files'), files = opts.files; end
                offset_correction_registry('record', struct( ...
                    'sensor_type', sensorType, ...
                    'point_id', pointId, ...
                    'offset_correction', offsetValue, ...
                    'start_time', min(times), ...
                    'end_time', max(times), ...
                    'sample_count', numel(vals), ...
                    'files', {files}));
            catch
            end
        end

        function rules = mergeDefaultRules(rules, cfg, sensorType)
            if ~isstruct(cfg) || ~isfield(cfg, 'defaults') || ~isstruct(cfg.defaults) || ~isfield(cfg.defaults, sensorType)
                return;
            end
            rules = bms.data.CleaningPipeline.applyRuleBlock(rules, cfg.defaults.(sensorType), false);
        end

        function rules = mergePointRules(rules, cfg, sensorType, pointId)
            if ~isstruct(cfg) || ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point) ...
                    || ~isfield(cfg.per_point, sensorType) || ~isstruct(cfg.per_point.(sensorType))
                return;
            end
            [ok, block] = bms.data.PointResolver.getPointConfig(cfg.per_point.(sensorType), pointId, cfg);
            if ~ok
                return;
            end
            rules = bms.data.CleaningPipeline.applyRuleBlock(rules, block, true);
        end

        function rules = applyRuleBlock(rules, block, appendThresholds)
            if ~isstruct(block), return; end
            if isfield(block, 'thresholds') && ~isempty(block.thresholds)
                if appendThresholds && ~isempty(rules.thresholds)
                    rules.thresholds = [rules.thresholds(:); block.thresholds(:)];
                else
                    rules.thresholds = block.thresholds;
                end
            end
            if isfield(block, 'zero_to_nan')
                rules.zero_to_nan = logical(block.zero_to_nan);
            end
            if isfield(block, 'outlier') && isstruct(block.outlier)
                if isfield(block.outlier, 'window_sec'), rules.outlier_window_sec = block.outlier.window_sec; end
                if isfield(block.outlier, 'threshold_factor'), rules.outlier_threshold_factor = block.outlier.threshold_factor; end
            end
            if isfield(block, 'offset_correction')
                offset = bms.data.CleaningPipeline.parseOffsetValue(block.offset_correction);
                if ~isempty(offset), rules.offset_correction = offset; end
            end
            if isfield(block, 'value_scale') && ~isempty(block.value_scale)
                scale = bms.data.CleaningPipeline.parseScaleValue(block.value_scale);
                if ~isempty(scale), rules.value_scale = scale; end
            elseif isfield(block, 'scale_factor') && ~isempty(block.scale_factor)
                scale = bms.data.CleaningPipeline.parseScaleValue(block.scale_factor);
                if ~isempty(scale), rules.value_scale = scale; end
            end
        end

        function offset = parseOffsetValue(raw)
            offset = [];
            if isempty(raw), return; end
            if isstruct(raw)
                mode = bms.data.CleaningPipeline.offsetMode(raw);
                if bms.data.CleaningPipeline.isSupportedOffsetMode(mode)
                    offset = raw;
                    return;
                end
            end
            if ischar(raw) || isstring(raw)
                txt = char(string(raw));
                mode = lower(txt);
                if bms.data.CleaningPipeline.isSupportedOffsetMode(mode)
                    offset = struct('mode', mode);
                    return;
                end
                raw = str2double(txt);
            end
            if isnumeric(raw) && isscalar(raw) && isfinite(raw)
                offset = double(raw);
            end
        end

        function scale = parseScaleValue(raw)
            scale = [];
            if isempty(raw), return; end
            if ischar(raw) || isstring(raw)
                raw = str2double(raw);
            end
            if isnumeric(raw) && isscalar(raw) && isfinite(raw)
                scale = double(raw);
            end
        end

        function offset = resolveOffsetValue(raw, times, vals)
            offset = [];
            if isempty(raw), return; end
            if isnumeric(raw) && isscalar(raw) && isfinite(raw)
                offset = double(raw);
                return;
            end
            if ischar(raw) || isstring(raw)
                parsed = bms.data.CleaningPipeline.parseOffsetValue(raw);
                offset = bms.data.CleaningPipeline.resolveOffsetValue(parsed, times, vals);
                return;
            end
            if ~isstruct(raw)
                return;
            end

            mode = bms.data.CleaningPipeline.offsetMode(raw);
            if ~bms.data.CleaningPipeline.isSupportedOffsetMode(mode)
                return;
            end
            if isempty(times) || isempty(vals) || numel(times) ~= numel(vals)
                return;
            end
            if ~isdatetime(times)
                times = bms.data.TimeSeriesLoader.toDatetime(times);
            end
            vals = vals(:);
            times = times(:);
            valid = isfinite(vals) & ~isnat(times);
            if isfield(raw, 'start_date') && ~isempty(raw.start_date)
                t0 = bms.data.CleaningPipeline.parseOffsetDate(raw.start_date, true);
                valid = valid & times >= t0;
            end
            if isfield(raw, 'end_date') && ~isempty(raw.end_date)
                t1 = bms.data.CleaningPipeline.parseOffsetDate(raw.end_date, false);
                valid = valid & times <= t1;
            end
            if ~any(valid)
                return;
            end
            switch mode
                case {'first_day_mean', 'earliest_day_mean'}
                    firstDay = dateshift(min(times(valid)), 'start', 'day');
                    dayMask = valid & times >= firstDay & times < firstDay + days(1);
                    if ~any(dayMask)
                        return;
                    end
                    baseline = mean(vals(dayMask), 'omitnan');
                    if isfinite(baseline)
                        offset = -baseline;
                    end
                case {'daily_mean', 'day_mean', 'daily_median', 'day_median'}
                    useMedian = contains(mode, 'median');
                    offset = bms.data.CleaningPipeline.groupedBaselineOffset(times, vals, valid, 'day', useMedian);
            end
        end

        function offset = groupedBaselineOffset(times, vals, valid, unit, useMedian)
            offset = [];
            if nargin < 5, useMedian = false; end
            if ~any(valid), return; end
            binTimes = dateshift(times(valid), 'start', unit);
            [g, ~] = findgroups(binTimes);
            if useMedian
                baselines = splitapply(@(x) median(x, 'omitnan'), vals(valid), g);
            else
                baselines = splitapply(@(x) mean(x, 'omitnan'), vals(valid), g);
            end
            offset = zeros(size(vals));
            offset(valid) = -baselines(g);
        end

        function tf = isSupportedOffsetMode(mode)
            tf = any(strcmp(lower(char(string(mode))), { ...
                'first_day_mean', 'earliest_day_mean', ...
                'daily_mean', 'day_mean', 'daily_median', 'day_median'}));
        end

        function tf = isOffsetApplicable(offset, vals)
            tf = false;
            if isempty(offset) || ~isnumeric(offset)
                return;
            end
            if isscalar(offset)
                tf = isfinite(offset) && offset ~= 0;
                return;
            end
            tf = isequal(size(offset), size(vals)) && any(isfinite(offset(:)) & offset(:) ~= 0);
        end

        function out = compactOffsetLogValue(offset, raw)
            if isnumeric(offset) && isscalar(offset)
                out = offset;
                return;
            end
            out = struct();
            if isstruct(raw)
                out.mode = bms.data.CleaningPipeline.offsetMode(raw);
            else
                out.mode = char(string(raw));
            end
            finite = offset(isfinite(offset));
            if ~isempty(finite)
                out.min = min(finite);
                out.max = max(finite);
                out.mean = mean(finite, 'omitnan');
            end
        end

        function mode = offsetMode(raw)
            mode = '';
            if ~isstruct(raw)
                return;
            end
            if isfield(raw, 'mode') && ~isempty(raw.mode)
                mode = lower(char(string(raw.mode)));
            elseif isfield(raw, 'method') && ~isempty(raw.method)
                mode = lower(char(string(raw.method)));
            elseif isfield(raw, 'type') && ~isempty(raw.type)
                mode = lower(char(string(raw.type)));
            end
        end

        function t = parseOffsetDate(value, isStart)
            if nargin < 2
                isStart = true;
            end
            if isdatetime(value)
                t = value;
            else
                txt = char(string(value));
                try
                    t = datetime(txt, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
                catch
                    t = datetime(txt, 'InputFormat', 'yyyy-MM-dd');
                end
            end
            if ~isStart
                if hour(t) == 0 && minute(t) == 0 && second(t) == 0
                    t = dateshift(t, 'start', 'day') + days(1) - seconds(1);
                end
            end
        end

        function sensorType = sharedSensorType(sensorType)
            sensorType = char(string(sensorType));
            if startsWith(sensorType, 'gnss_')
                sensorType = 'gnss';
            else
                sensorType = '';
            end
        end

        function t = parseRuleTime(value)
            if isdatetime(value)
                t = value;
                return;
            end
            txt = char(string(value));
            try
                t = datetime(txt, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
            catch
                t = datetime(txt);
            end
        end

        function text = optionText(opts, field)
            text = '';
            if isstruct(opts) && isfield(opts, field) && ~isempty(opts.(field))
                text = char(string(opts.(field)));
            end
        end

        function n = changedCount(a, b)
            if numel(a) ~= numel(b)
                n = max(numel(a), numel(b));
                return;
            end
            same = (a == b) | (isnan(a) & isnan(b));
            n = sum(~same);
        end
    end
end
