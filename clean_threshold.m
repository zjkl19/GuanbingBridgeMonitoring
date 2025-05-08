function v = clean_threshold(v, times, params)
% clean_threshold 按阈值过滤数据
%   v: 原始数据向量
%   times: 与 v 对应的时间向量（datetime）
%   params.min, params.max: 有效数据范围
%   params.t_range: [t0, t1] 时间范围（可空），只在此范围内过滤

    if isempty(params.t_range)
        mask = v < params.min | v > params.max;
    else
        t0 = params.t_range(1);
        t1 = params.t_range(2);
        mask = (v < params.min | v > params.max) & (times >= t0 & times <= t1);
    end
    v(mask) = NaN;
end
