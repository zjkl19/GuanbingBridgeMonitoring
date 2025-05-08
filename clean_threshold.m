function v = clean_threshold(v, times, params)
% clean_threshold   将超过上下限的值置为 NaN
%   params.min/min, params.max/max, params.t_range 可选
    if isfield(params,'t_range') && ~isempty(params.t_range)
      % 如果指定了时间区间，可先把 times 排除掉不在区间的行
      inwin = times >= params.t_range(1) & times <= params.t_range(2);
    else
      inwin = true(size(v));
    end
    mask = inwin & (v < params.min | v > params.max);
    v(mask) = NaN;
end
