function vals = apply_threshold_rules(vals, times, thresholds)
% apply_threshold_rules  Apply min/max threshold rules to a time series.
%   vals = apply_threshold_rules(vals, times, thresholds)
%
% thresholds follows the same schema as config thresholds:
%   struct('min',...,'max',...,'t_range_start','yyyy-MM-dd HH:mm:ss', ...
%          't_range_end','yyyy-MM-dd HH:mm:ss')

    if isempty(vals) || isempty(thresholds)
        return;
    end
    if ~isstruct(thresholds)
        return;
    end

    thresholds = thresholds(:);
    for k = 1:numel(thresholds)
        th = thresholds(k);
        tmask = true(size(vals));
        if ~isempty(times) && isfield(th, 't_range_start') && isfield(th, 't_range_end') ...
                && ~isempty(th.t_range_start) && ~isempty(th.t_range_end)
            try
                t0 = datetime(th.t_range_start, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
                t1 = datetime(th.t_range_end,   'InputFormat', 'yyyy-MM-dd HH:mm:ss');
                tmask = (times >= t0) & (times <= t1);
                if ~isequal(size(tmask), size(vals)) && numel(tmask) == numel(vals)
                    tmask = reshape(tmask, size(vals));
                end
            catch
                tmask = true(size(vals));
            end
        end

        if isfield(th, 'min') && ~isempty(th.min)
            vals(tmask & vals < th.min) = NaN;
        end
        if isfield(th, 'max') && ~isempty(th.max)
            vals(tmask & vals > th.max) = NaN;
        end
    end
end
