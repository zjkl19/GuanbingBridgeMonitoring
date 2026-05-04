classdef ManifestWriter
    %MANIFESTWRITER Writes versioned analysis manifest JSON files.

    properties (Constant)
        SchemaVersion = 1
    end

    methods (Static)
        function manifestPath = write(ctx, status, details)
            if nargin < 2 || isempty(status), status = 'unknown'; end
            if nargin < 3 || isempty(details), details = struct(); end
            bms.core.PathResolver.ensureDir(ctx.LogDir);
            manifest = bms.app.ManifestWriter.build(ctx, status, details);
            manifestPath = fullfile(ctx.LogDir, ['analysis_manifest_' ctx.RunId '.json']);
            bms.core.Logger.writeJson(manifestPath, manifest);
        end

        function manifest = build(ctx, status, details)
            latestLog = bms.core.PathResolver.latestFile(ctx.LogDir, 'run_log_*.txt');
            manifest = ctx.toStruct();
            manifest.schema_version = bms.app.ManifestWriter.SchemaVersion;
            manifest.manifest_type = 'analysis_run';
            manifest.status = char(status);
            manifest.latest_log = latestLog;
            manifest.run_log = '';
            manifest.elapsed_sec = NaN;
            manifest.module_logs = {};
            manifest.stats_files = bms.core.Logger.listFiles(ctx.StatsDir, '*.xlsx');
            manifest.expected_stats_files = {};
            manifest.missing_expected_stats = {};
            manifest.offset_report = struct();
            manifest.details = details;
            if isstruct(details)
                manifest = bms.app.ManifestWriter.applyDetails(manifest, details);
            end
            manifest.written_at = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss');
        end

        function manifest = applyDetails(manifest, details)
            if isfield(details, 'log_file') && ~isempty(details.log_file)
                manifest.run_log = details.log_file;
                manifest.latest_log = details.log_file;
            end
            if isfield(details, 'elapsed_sec')
                manifest.elapsed_sec = details.elapsed_sec;
            end
            if isfield(details, 'module_logs')
                manifest.module_logs = details.module_logs;
            end
            if isfield(details, 'offset_report')
                manifest.offset_report = details.offset_report;
            end
            if isfield(details, 'stats_files')
                manifest.stats_files = details.stats_files;
            end
            if isfield(details, 'expected_stats_files')
                manifest.expected_stats_files = details.expected_stats_files;
                manifest.missing_expected_stats = bms.app.ManifestWriter.findMissing(details.expected_stats_files);
            end
        end

        function missing = findMissing(paths)
            missing = {};
            if isempty(paths), return; end
            if ischar(paths) || isstring(paths)
                paths = cellstr(string(paths));
            end
            for i = 1:numel(paths)
                p = char(string(paths{i}));
                if ~isempty(p) && ~isfile(p)
                    missing{end+1} = p; %#ok<AGROW>
                end
            end
        end
    end
end
