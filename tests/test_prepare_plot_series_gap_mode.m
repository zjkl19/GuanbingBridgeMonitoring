function test_prepare_plot_series_gap_mode()
% Verify shared time-series gap rendering honors break/connect modes.

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repoRoot, 'pipeline'));

plot_runtime_settings('reset');
s0 = plot_runtime_settings('get');
assert(strcmp(s0.gap_mode, 'connect'), 'default gap mode should connect points');

x = datetime(2026, 1, 1, 0, [0 1 10 11], 0).';
y = [1; 2; 3; 4];

plot_runtime_settings('set', struct('gap_mode', 'break', 'gap_break_factor', 5));
[xb, yb] = prepare_plot_series(x, y);
assert(numel(xb) > numel(x), 'break mode should insert an internal gap');
assert(any(isnat(xb)) || any(isnan(yb)), 'break mode should include a NaT/NaN gap marker');

plot_runtime_settings('set', struct('gap_mode', 'connect', 'gap_break_factor', 5));
[xc, yc] = prepare_plot_series(x, y);
assert(numel(xc) == numel(x), 'connect mode should not insert gap markers');
assert(~any(isnat(xc)), 'connect mode should not include NaT gap markers');
assert(~any(isnan(yc)), 'connect mode should not include NaN gap markers');

[xs, ys] = prepare_plot_series( ...
    (datetime(2026, 1, 1, 0, 0, 0) + seconds(0:99)).', ...
    [zeros(36, 1); -20; zeros(35, 1); 8; zeros(27, 1)], ...
    struct('gap_mode', 'connect', 'fig_max_points', 10));
assert(any(ys == -20), 'limited plot series should retain the minimum point');
assert(any(ys == 8), 'limited plot series should retain the maximum point');
assert(numel(xs) == numel(ys), 'limited plot series should keep x/y aligned');

spike_idx = (5:10:95).';
dense = zeros(100, 1);
dense(spike_idx) = (1:numel(spike_idx)).';
[xe, ye] = prepare_plot_series( ...
    (datetime(2026, 1, 1, 0, 0, 0) + seconds(0:99)).', ...
    dense, ...
    struct('gap_mode', 'connect', 'fig_max_points', 40));
assert(numel(xe) <= 40, 'bucketed plot series should respect the point budget');
assert(all(ismember((1:numel(spike_idx)).', ye)), ...
    'bucketed plot series should retain local extrema across the dense span');

plot_runtime_settings('reset');
disp('prepare_plot_series gap mode test ok');
end
