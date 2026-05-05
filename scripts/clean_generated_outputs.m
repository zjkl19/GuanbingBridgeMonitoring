function result = clean_generated_outputs(resultRoot, category, dryRun)
%CLEAN_GENERATED_OUTPUTS Safely list or delete generated output artifacts.
% Usage:
%   clean_generated_outputs('E:\data\2026年3月', 'images', true)  % dry run
%   clean_generated_outputs('E:\data\2026年3月', 'images', false) % delete

    if nargin < 1 || isempty(resultRoot)
        error('Usage: clean_generated_outputs(resultRoot, category, dryRun)');
    end
    if nargin < 2 || isempty(category)
        category = 'all';
    end
    if nargin < 3 || isempty(dryRun)
        dryRun = true;
    end
    proj = fileparts(fileparts(mfilename('fullpath')));
    addpath(proj);
    result = bms.data.ArtifactCleaner.clean(resultRoot, category, logical(dryRun));
    fprintf('dry_run=%d, matched=%d, skipped=%d\n', result.dry_run, numel(result.deleted), numel(result.skipped));
    for i = 1:min(numel(result.deleted), 20)
        fprintf('%s\n', result.deleted{i});
    end
    if numel(result.deleted) > 20
        fprintf('... %d more\n', numel(result.deleted) - 20);
    end
end
