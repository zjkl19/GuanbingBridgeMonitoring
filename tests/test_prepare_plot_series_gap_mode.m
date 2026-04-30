function test_prepare_plot_series_gap_mode()
% Verify shared time-series gap rendering honors break/connect modes.

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repoRoot, 'pipeline'));

plot_runtime_settings('reset');

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

plot_runtime_settings('reset');
disp('prepare_plot_series gap mode test ok');
end
