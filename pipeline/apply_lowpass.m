function v_filtered = apply_lowpass(times, vals)
    % APPLY_LOWPASS Apply a zero-phase low-pass filter and preserve NaN gaps.
    %
    % The historical cutoff behavior is kept as a fixed fraction of Nyquist:
    %   Wn = (fs / 50) / (fs / 2) = 0.04
    %
    % Missing segments are linearly interpolated only for filtfilt stability,
    % then restored to NaN so downstream cleaning/statistics keep the original
    % missing-data mask.

    v_filtered = vals;
    if numel(times) < 2 || isempty(vals)
        return;
    end
    if numel(times) ~= numel(vals)
        warning('apply_lowpass:SizeMismatch', ...
            'Low-pass filtering skipped: times and values have different lengths.');
        return;
    end

    dt_all = seconds(diff(times));
    dt_all = dt_all(isfinite(dt_all) & dt_all > 0);
    if isempty(dt_all)
        warning('apply_lowpass:InvalidSamplingInterval', ...
            'Low-pass filtering skipped: no valid sampling interval.');
        return;
    end
    fs = 1 / median(dt_all);

    cutoffRatio = 0.04;
    order = 4;
    Wn = cutoffRatio;
    if Wn <= 0 || Wn >= 1
        warning('apply_lowpass:InvalidCutoff', ...
            'Low-pass filtering skipped: normalized cutoff %.3f is invalid (fs=%.2f Hz).', Wn, fs);
        return;
    end

    [b, a] = butter(order, Wn);

    nan_mask = isnan(vals);
    temp = vals;
    if any(nan_mask(:))
        valid_mask = ~nan_mask;
        if ~any(valid_mask(:))
            return;
        end

        idx = (1:numel(vals))';
        vals_col = vals(:);
        nan_col = nan_mask(:);
        temp_col = vals_col;
        temp_col(nan_col) = interp1(idx(~nan_col), vals_col(~nan_col), ...
            idx(nan_col), 'linear', 'extrap');
        temp = reshape(temp_col, size(vals));
    end

    y = filtfilt(b, a, temp);
    y(nan_mask) = NaN;
    v_filtered = y;
end
