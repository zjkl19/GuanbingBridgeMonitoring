function context = inspect_analysis_manifest(resultRoot)
%INSPECT_ANALYSIS_MANIFEST Print latest analysis manifest summary.
% Usage:
%   inspect_analysis_manifest('E:\data\2026年3月')

    if nargin < 1 || isempty(resultRoot)
        error('Usage: inspect_analysis_manifest(resultRoot)');
    end
    proj = fileparts(fileparts(mfilename('fullpath')));
    addpath(proj);
    context = bms.app.ManifestReader.context(resultRoot);
    lines = bms.app.ManifestReader.summaryLines(context);
    for i = 1:numel(lines)
        fprintf('%s\n', lines{i});
    end
end
