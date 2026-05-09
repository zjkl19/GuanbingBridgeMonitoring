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

            safeId = strrep(pointId, '-', '_');
            rules = bms.data.CleaningPipeline.mergePointRules(rules, cfg, sensorType, safeId);
            if ~isempty(sharedSensor)
                rules = bms.data.CleaningPipeline.mergePointRules(rules, cfg, sharedSensor, safeId);
            end
            if startsWith(sensorType, 'wind_')
                rules = bms.data.CleaningPipeline.mergePointRules(rules, cfg, 'wind', safeId);
            end
        end

        function rules = emptyRules()
            rules = struct('thresholds', [], 'zero_to_nan', false, ...
                'outlier_window_sec', [], 'outlier_threshold_factor', [], ...
                'offset_correction', []);
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

            [vals, offsetApplied] = bms.data.CleaningPipeline.applyOffset(vals, rules);
            log.offset_applied = offsetApplied;
            if offsetApplied
                log.offset_correction = rules.offset_correction;
                bms.data.CleaningPipeline.recordOffset(times, vals, rules, opts);
            end

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

        function [vals, applied] = applyOffset(vals, rules)
            applied = false;
            if isstruct(rules) && isfield(rules, 'offset_correction') ...
                    && ~isempty(rules.offset_correction) && isnumeric(rules.offset_correction) ...
                    && isscalar(rules.offset_correction) && isfinite(rules.offset_correction) ...
                    && rules.offset_correction ~= 0
                vals = vals + rules.offset_correction;
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
                if isfield(th, 'min') && ~isempty(th.min)
                    vals(tmask & vals < th.min) = NaN;
                end
                if isfield(th, 'max') && ~isempty(th.max)
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

        function recordOffset(times, vals, rules, opts)
            if nargin < 4 || ~isstruct(opts) || ~isfield(opts, 'record_offset') || ~logical(opts.record_offset)
                return;
            end
            try
                sensorType = bms.data.CleaningPipeline.optionText(opts, 'sensor_type');
                pointId = bms.data.CleaningPipeline.optionText(opts, 'point_id');
                files = {};
                if isfield(opts, 'files'), files = opts.files; end
                offset_correction_registry('record', struct( ...
                    'sensor_type', sensorType, ...
                    'point_id', pointId, ...
                    'offset_correction', rules.offset_correction, ...
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

        function rules = mergePointRules(rules, cfg, sensorType, safeId)
            if ~isstruct(cfg) || ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point) ...
                    || ~isfield(cfg.per_point, sensorType) || ~isstruct(cfg.per_point.(sensorType)) ...
                    || ~isfield(cfg.per_point.(sensorType), safeId)
                return;
            end
            rules = bms.data.CleaningPipeline.applyRuleBlock(rules, cfg.per_point.(sensorType).(safeId), true);
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
        end

        function offset = parseOffsetValue(raw)
            offset = [];
            if isempty(raw), return; end
            if ischar(raw) || isstring(raw)
                raw = str2double(raw);
            end
            if isnumeric(raw) && isscalar(raw) && isfinite(raw)
                offset = double(raw);
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
