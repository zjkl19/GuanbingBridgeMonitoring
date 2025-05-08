function v = clean_zero(v, times, params)
% clean_zero   将值等于 0 的点设为 NaN
    if isfield(params,'t_range') && ~isempty(params.t_range)
      inwin = times >= params.t_range(1) & times <= params.t_range(2);
    else
      inwin = true(size(v));
    end
    mask = inwin & (v == 0);
    v(mask) = NaN;
end
