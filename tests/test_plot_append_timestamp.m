function test_plot_append_timestamp()
% Verify that plot_common.append_timestamp=false keeps the data period but
% removes the run timestamp from generated image names.

addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'pipeline'));

outDir = fullfile(tempdir, 'gb_append_timestamp_test');
if exist(outDir, 'dir')
    rmdir(outDir, 's');
end
mkdir(outDir);
cleanup = onCleanup(@() cleanup_dir(outDir));

plot_runtime_settings('reset');
fig = figure('Visible', 'off');
plot(1:3);
save_plot_bundle(fig, outDir, 'Demo_20260326_20260426_20260429_153653', ...
    struct('save_emf', false, 'save_fig', false));

assert(isfile(fullfile(outDir, 'Demo_20260326_20260426.jpg')));
assert(~isfile(fullfile(outDir, 'Demo_20260326_20260426_20260429_153653.jpg')));

plot_runtime_settings('set', struct('append_timestamp', true));
fig = figure('Visible', 'off');
plot(1:3);
save_plot_bundle(fig, outDir, 'Demo_20260326_20260426_20260429_153654', ...
    struct('save_emf', false, 'save_fig', false));

assert(isfile(fullfile(outDir, 'Demo_20260326_20260426_20260429_153654.jpg')));
disp('plot append timestamp test ok');
end

function cleanup_dir(outDir)
if exist(outDir, 'dir')
    rmdir(outDir, 's');
end
end
