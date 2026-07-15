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
                'offset_correction', [], 'value_scale', [], ...
                'exclude_ranges', []);
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
            log.excluded_range_count = 0;
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

            exclusions = [];
            if isstruct(rules) && isfield(rules, 'exclude_ranges')
                exclusions = rules.exclude_ranges;
            end
            before = isnan(vals);
            vals = bms.data.CleaningPipeline.applyExcludeRanges(vals, times, exclusions);
            after = isnan(vals);
            log.excluded_range_count = sum(after & ~before);

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
            log.final_count = numel(vals) - log.final_nan_count;
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

        function vals = applyExcludeRanges(vals, times, ranges)
            %APPLYEXCLUDERANGES Explicitly excludes complete time intervals.
            % This replaces the historical min>max threshold sentinel.  A
            % range is intentionally independent from amplitude thresholds
            % and therefore remains readable in configuration and audits.
            if isempty(vals) || isempty(ranges), return; end
            if iscell(ranges)
                try
                    ranges = [ranges{:}];
                catch
                    return;
                end
            end
            if ~isstruct(ranges), return; end
            ranges = ranges(:);
            for k = 1:numel(ranges)
                item = ranges(k);
                startText = bms.data.CleaningPipeline.firstRangeField( ...
                    item, {'start_time', 'start', 't_range_start'});
                endText = bms.data.CleaningPipeline.firstRangeField( ...
                    item, {'end_time', 'end', 't_range_end'});
                if isempty(startText) || isempty(endText)
                    continue;
                end
                t0 = bms.data.CleaningPipeline.parseRuleTime(startText);
                t1 = bms.data.CleaningPipeline.parseRuleTime(endText);
                if isnat(t0) || isnat(t1) || t1 < t0
                    error('CleaningPipeline:InvalidExcludeRange', ...
                        'exclude_ranges end_time must be greater than or equal to start_time.');
                end
                vals(times >= t0 & times <= t1) = NaN;
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
            catch ME
                warning('CleaningPipeline:recordOffset', ...
                    'Failed to record offset: %s', ME.message);
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
                incomingThresholds = bms.data.CleaningPipeline.normalizeThresholds(block.thresholds);
                if appendThresholds && ~isempty(rules.thresholds)
                    existingThresholds = bms.data.CleaningPipeline.normalizeThresholds(rules.thresholds);
                    rules.thresholds = [existingThresholds(:); incomingThresholds(:)];
                else
                    rules.thresholds = incomingThresholds;
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
            if isfield(block, 'exclude_ranges') && ~isempty(block.exclude_ranges)
                incomingRanges = bms.data.CleaningPipeline.normalizeExcludeRanges(block.exclude_ranges);
                if appendThresholds && ~isempty(rules.exclude_ranges)
                    existingRanges = bms.data.CleaningPipeline.normalizeExcludeRanges(rules.exclude_ranges);
                    rules.exclude_ranges = [existingRanges(:); incomingRanges(:)];
                else
                    rules.exclude_ranges = incomingRanges;
                end
            end
        end

        function ranges = normalizeExcludeRanges(raw)
            ranges = [];
            if isempty(raw), return; end
            if iscell(raw)
                try
                    raw = [raw{:}];
                catch
                    return;
                end
            end
            if isstruct(raw)
                ranges = raw(:);
            end
        end

        function value = firstRangeField(item, names)
            value = '';
            for i = 1:numel(names)
                name = names{i};
                if isfield(item, name) && ~isempty(item.(name))
                    value = item.(name);
                    return;
                end
            end
        end

        function offset = parseOffsetValue(raw)
            offset = [];
            if isempty(raw), return; end
            if isstruct(raw)
                if numel(raw) > 1
                    offset = struct('mode', 'segmented', 'segments', raw(:));
                    return;
                end
                if isfield(raw, 'segments') && isstruct(raw.segments) ...
                        && ~isempty(raw.segments)
                    raw.mode = 'segmented';
                    offset = raw;
                    return;
                end
                mode = bms.data.CleaningPipeline.offsetMode(raw);
                if isempty(mode) && bms.data.CleaningPipeline.hasFixedOffsetValue(raw)
                    raw.mode = 'fixed';
                    offset = raw;
                    return;
                end
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

        function out = normalizeThresholds(raw)
            out = struct('min', {}, 'max', {}, ...
                't_range_start', {}, 't_range_end', {});
            if isempty(raw) || ~isstruct(raw)
                return;
            end
            raw = raw(:);
            out(numel(raw), 1) = struct('min', [], 'max', [], ...
                't_range_start', '', 't_range_end', '');
            for i = 1:numel(raw)
                if isfield(raw(i), 'min'), out(i).min = raw(i).min; end
                if isfield(raw(i), 'max'), out(i).max = raw(i).max; end
                if isfield(raw(i), 't_range_start') && ~isempty(raw(i).t_range_start)
                    out(i).t_range_start = raw(i).t_range_start;
                end
                if isfield(raw(i), 't_range_end') && ~isempty(raw(i).t_range_end)
                    out(i).t_range_end = raw(i).t_range_end;
                end
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

            if numel(raw) > 1
                raw = struct('mode', 'segmented', 'segments', raw(:));
            end

            if isfield(raw, 'segments') && isstruct(raw.segments) ...
                    && ~isempty(raw.segments)
                offset = bms.data.CleaningPipeline.resolveSegmentedOffset( ...
                    raw.segments, times, vals);
                return;
            end

            mode = bms.data.CleaningPipeline.offsetMode(raw);
            if ~bms.data.CleaningPipeline.isSupportedOffsetMode(mode)
                return;
            end
            if any(strcmp(mode, {'fixed', 'constant'})) && ...
                    (isempty(times) || isempty(vals) || numel(times) ~= numel(vals))
                offset = bms.data.CleaningPipeline.fixedOffsetValue(raw);
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
                case {'fixed', 'constant'}
                    value = bms.data.CleaningPipeline.fixedOffsetValue(raw);
                    if isempty(value), return; end
                    offset = zeros(size(vals));
                    offset(valid) = value;
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
                case {'hourly_mean', 'hour_mean', 'hourly_median', 'hour_median'}
                    useMedian = contains(mode, 'median');
                    offset = bms.data.CleaningPipeline.groupedBaselineOffset(times, vals, valid, 'hour', useMedian);
            end
        end

        function offset = resolveSegmentedOffset(segments, times, vals)
            offset = [];
            if isempty(segments) || isempty(times) || isempty(vals) ...
                    || numel(times) ~= numel(vals)
                return;
            end
            if ~isdatetime(times)
                times = bms.data.TimeSeriesLoader.toDatetime(times);
            end
            originalSize = size(vals);
            vals = vals(:);
            times = times(:);
            combined = zeros(size(vals));
            assigned = false(size(vals));
            segments = segments(:);
            for i = 1:numel(segments)
                segment = segments(i);
                mask = bms.data.CleaningPipeline.offsetRuleMask(segment, times, vals);
                if ~any(mask)
                    continue;
                end
                if any(assigned & mask)
                    error('CleaningPipeline:OverlappingOffsetSegments', ...
                        'Offset correction segments overlap at segment %d.', i);
                end
                segmentOffset = bms.data.CleaningPipeline.resolveOffsetValue( ...
                    segment, times, vals);
                if isempty(segmentOffset)
                    continue;
                end
                if isscalar(segmentOffset)
                    combined(mask) = segmentOffset;
                elseif numel(segmentOffset) == numel(vals)
                    segmentOffset = segmentOffset(:);
                    combined(mask) = segmentOffset(mask);
                else
                    error('CleaningPipeline:InvalidSegmentedOffset', ...
                        'Offset segment %d returned an incompatible shape.', i);
                end
                assigned(mask) = true;
            end
            if any(assigned)
                offset = reshape(combined, originalSize);
            end
        end

        function mask = offsetRuleMask(rule, times, vals)
            mask = isfinite(vals) & ~isnat(times);
            if isfield(rule, 'start_date') && ~isempty(rule.start_date)
                t0 = bms.data.CleaningPipeline.parseOffsetDate(rule.start_date, true);
                mask = mask & times >= t0;
            end
            if isfield(rule, 'end_date') && ~isempty(rule.end_date)
                t1 = bms.data.CleaningPipeline.parseOffsetDate(rule.end_date, false);
                mask = mask & times <= t1;
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
                'fixed', 'constant', ...
                'first_day_mean', 'earliest_day_mean', ...
                'daily_mean', 'day_mean', 'daily_median', 'day_median', ...
                'hourly_mean', 'hour_mean', 'hourly_median', 'hour_median', ...
                'segmented'}));
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
            if isstruct(raw) && isscalar(raw) && isfield(raw, 'segments') ...
                    && isstruct(raw.segments)
                out = struct('mode', 'segmented', ...
                    'segment_count', numel(raw.segments));
                finite = offset(isfinite(offset));
                if ~isempty(finite)
                    out.min = min(finite);
                    out.max = max(finite);
                    out.mean = mean(finite, 'omitnan');
                end
                return;
            end
            if isstruct(raw) && bms.data.CleaningPipeline.hasFixedOffsetValue(raw)
                out = bms.data.CleaningPipeline.fixedOffsetValue(raw);
                return;
            end
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

        function tf = hasFixedOffsetValue(raw)
            tf = isstruct(raw) && (isfield(raw, 'value') || isfield(raw, 'offset') || isfield(raw, 'offset_value'));
        end

        function value = fixedOffsetValue(raw)
            value = [];
            if ~isstruct(raw), return; end
            if isfield(raw, 'value')
                value = raw.value;
            elseif isfield(raw, 'offset')
                value = raw.offset;
            elseif isfield(raw, 'offset_value')
                value = raw.offset_value;
            else
                return;
            end
            if ischar(value) || isstring(value)
                value = str2double(char(string(value)));
            end
            if ~(isnumeric(value) && isscalar(value) && isfinite(value))
                value = [];
            else
                value = double(value);
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
            dateOnly = false;
            if isdatetime(value)
                t = value;
            else
                txt = strtrim(char(string(value)));
                dateOnly = ~isempty(regexp(txt, '^\d{4}-\d{2}-\d{2}$', 'once'));
                try
                    t = datetime(txt, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
                catch
                    t = datetime(txt, 'InputFormat', 'yyyy-MM-dd');
                end
            end
            if ~isStart && dateOnly
                t = dateshift(t, 'start', 'day') + days(1) - seconds(1);
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
