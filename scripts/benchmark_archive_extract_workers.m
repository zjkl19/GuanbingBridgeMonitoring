function benchmark = benchmark_archive_extract_workers(varargin)
%BENCHMARK_ARCHIVE_EXTRACT_WORKERS Local synthetic ZIP concurrency benchmark.
%   This entry point never accepts a production data root.  It creates small,
%   deterministic daily-export ZIPs below a fresh tempdir folder, runs the
%   requested worker settings, checks serial/parallel output-index equality,
%   and removes all artifacts unless KeepArtifacts=true.
%
% Example:
%   b = benchmark_archive_extract_workers( ...
%       'ArchiveCount', 4, 'FilesPerArchive', 3, ...
%       'PayloadBytes', 65536, 'WorkerSettings', {1,'auto',2,4});

parser = inputParser();
parser.FunctionName = mfilename;
addParameter(parser, 'ArchiveCount', 4, @positiveInteger);
addParameter(parser, 'FilesPerArchive', 3, @positiveInteger);
addParameter(parser, 'PayloadBytes', 65536, @positiveInteger);
addParameter(parser, 'WorkerSettings', {1, 'auto', 2, 4}, ...
    @(value) iscell(value) && ~isempty(value));
addParameter(parser, 'KeepArtifacts', false, ...
    @(value) islogical(value) && isscalar(value));
parse(parser, varargin{:});
options = parser.Results;

if options.ArchiveCount > 31 || options.FilesPerArchive > 50 ...
        || options.PayloadBytes > 1024^2
    error('BMS:ArchiveExtractBenchmark:InputTooLarge', ...
        ['合成基准的安全上限为 31 个 ZIP、每包 50 个文件、每文件 1 MiB；' ...
         '本入口不用于生产数据。']);
end
for i = 1:numel(options.WorkerSettings)
    bms.data.ArchiveExtractService.normalizeWorkerSetting( ...
        options.WorkerSettings{i});
end

benchmarkRoot = tempname(tempdir);
sourceRoot = fullfile(benchmarkRoot, 'synthetic_source');
mkdir(sourceRoot);
if options.KeepArtifacts
    cleanup = []; %#ok<NASGU>
else
    cleanup = onCleanup(@() cleanupBenchmark(benchmarkRoot));
end
poolCleanup = onCleanup(@cleanupPool);

startDay = datetime(2026, 1, 1);
for archiveIndex = 1:options.ArchiveCount
    day = char(startDay + caldays(archiveIndex - 1), 'yyyy-MM-dd');
    stage = fullfile(benchmarkRoot, sprintf('stage_%02d', archiveIndex));
    payloadRoot = fullfile(stage, 'data', 'jlj', 'csv');
    mkdir(payloadRoot);
    for fileIndex = 1:options.FilesPerArchive
        path = fullfile(payloadRoot, sprintf('POINT-%02d.csv', fileIndex));
        payload = deterministicPayload(archiveIndex, fileIndex, options.PayloadBytes);
        writeBytes(path, payload);
    end
    zip(fullfile(sourceRoot, ['data_jlj_' day '.zip']), 'data', stage);
    rmdir(stage, 's');
end

runTemplate = struct( ...
    'requested_workers', [], 'worker_mode', '', 'resolved_workers', 0, ...
    'effective_workers', 0, 'parallel_fallback', false, ...
    'parallel_fallback_reason', '', 'elapsed_seconds', 0, ...
    'archive_count', 0, 'extracted_count', 0, 'failed_count', 0, ...
    'output_consistent', false, 'summary_path', '');
runs = repmat(runTemplate, 1, numel(options.WorkerSettings));
baseline = {};
for runIndex = 1:numel(options.WorkerSettings)
    cleanupPool();
    setting = options.WorkerSettings{runIndex};
    outputRoot = fullfile(benchmarkRoot, sprintf('output_%02d', runIndex));
    summaryPath = fullfile(benchmarkRoot, sprintf('summary_%02d.json', runIndex));
    cfg = struct();
    cfg.vendor = 'jiulongjiang';
    cfg.preprocessing = struct('unzip', struct( ...
        'source_root', sourceRoot, ...
        'output_root', outputRoot, ...
        'max_workers', setting, ...
        'min_free_gib', 0, ...
        'min_free_fraction', 0, ...
        'delete_archives_after_verify', false, ...
        'overwrite_existing', false, ...
        'summary_file', summaryPath));
    started = tic;
    result = bms.data.ArchiveExtractService.run(outputRoot, ...
        char(startDay, 'yyyy-MM-dd'), ...
        char(startDay + caldays(options.ArchiveCount - 1), 'yyyy-MM-dd'), cfg);
    elapsed = toc(started);
    signature = strcat({result.results.archive_index_sha256}, '|', ...
        {result.results.output_index_sha256});
    if isempty(baseline)
        baseline = signature;
    end
    runs(runIndex).requested_workers = result.requested_workers;
    runs(runIndex).worker_mode = result.worker_mode;
    runs(runIndex).resolved_workers = result.resolved_workers;
    runs(runIndex).effective_workers = result.effective_workers;
    runs(runIndex).parallel_fallback = result.parallel_fallback;
    runs(runIndex).parallel_fallback_reason = result.parallel_fallback_reason;
    runs(runIndex).elapsed_seconds = elapsed;
    runs(runIndex).archive_count = result.archive_count;
    runs(runIndex).extracted_count = result.extracted_count;
    runs(runIndex).failed_count = result.failed_count;
    runs(runIndex).output_consistent = isequal(signature, baseline);
    runs(runIndex).summary_path = result.summary_path;
end

benchmark = struct();
benchmark.schema_version = 1;
benchmark.scope = 'local_synthetic_zip_only';
benchmark.benchmark_root = benchmarkRoot;
benchmark.artifacts_preserved = logical(options.KeepArtifacts);
benchmark.archive_count = options.ArchiveCount;
benchmark.files_per_archive = options.FilesPerArchive;
benchmark.payload_bytes = options.PayloadBytes;
benchmark.contract = bms.data.ArchiveExtractService.workerContract();
benchmark.runs = runs;
benchmark.all_outputs_consistent = all([runs.output_consistent]);
benchmark.all_runs_passed = all([runs.failed_count] == 0) ...
    && all([runs.extracted_count] == options.ArchiveCount);

fprintf('[本机合成 ZIP 基准] ZIP=%d，每包文件=%d，每文件=%d bytes\n', ...
    options.ArchiveCount, options.FilesPerArchive, options.PayloadBytes);
for i = 1:numel(runs)
    fprintf(['  requested=%s resolved=%d effective=%d elapsed=%.3fs ' ...
        'fallback=%d consistent=%d\n'], ...
        requestedText(runs(i).requested_workers), runs(i).resolved_workers, ...
        runs(i).effective_workers, runs(i).elapsed_seconds, ...
        runs(i).parallel_fallback, runs(i).output_consistent);
end
assert(benchmark.all_outputs_consistent, '合成 ZIP 串并行输出不一致。');
assert(benchmark.all_runs_passed, '合成 ZIP 基准存在失败运行。');
end

function tf = positiveInteger(value)
tf = isnumeric(value) && isscalar(value) && isfinite(value) ...
    && value >= 1 && value == floor(value);
end

function payload = deterministicPayload(archiveIndex, fileIndex, byteCount)
header = uint8(sprintf('archive=%d,file=%d\n', archiveIndex, fileIndex));
pattern = uint8(mod((0:max(0, byteCount - numel(header) - 1)) ...
    + archiveIndex * 17 + fileIndex * 31, 251));
payload = [header pattern];
payload = payload(1:min(numel(payload), byteCount));
if numel(payload) < byteCount
    payload(end+1:byteCount) = uint8(0);
end
end

function writeBytes(path, bytes)
fid = fopen(path, 'wb');
if fid < 0, error('无法创建合成基准文件：%s', path); end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, bytes, 'uint8');
end

function value = requestedText(requested)
if ischar(requested)
    value = requested;
else
    value = sprintf('%d', requested);
end
end

function cleanupPool()
try
    pool = gcp('nocreate');
    if ~isempty(pool), delete(pool); end
catch
end
end

function cleanupBenchmark(path)
cleanupPool();
if isfolder(path)
    try
        rmdir(path, 's');
    catch
    end
end
end
