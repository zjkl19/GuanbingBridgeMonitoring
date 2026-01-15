function v = clean_zero(v, times, params)
% clean_zero 将指定时段内的零值置为 NaN
%   v: 原始数据向量
%   times: 与 v 对应的时间向量（datetime）
%   params.t_range: [t0, t1] 时间范围（可空），只在此范围内处理

    if isempty(params.t_range)
        mask = v == 0;
    else
        t0 = params.t_range(1);
        t1 = params.t_range(2);
        mask = (v == 0) & (times >= t0 & times <= t1);
    end
    v(mask) = NaN;
end