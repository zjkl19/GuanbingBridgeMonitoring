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
            manifest.config_schema_version = bms.app.ManifestWriter.configSchemaVersion(ctx.Config);
            manifest.data_layout = bms.data.DataLayoutResolver.describe(ctx.DataRoot, ctx.Config);
            manifest.latest_log = latestLog;
            manifest.run_log = '';
            manifest.elapsed_sec = NaN;
            manifest.module_logs = {};
            manifest.module_results = {};
            manifest.module_status_counts = struct('ok', 0, 'fail', 0, 'skip', 0, 'missing', 0, 'other', 0);
            manifest.module_catalog = {};
            manifest.enabled_module_specs = {};
            manifest.module_preflight = {};
            manifest.run_preflight = struct();
            manifest.run_request = struct();
            manifest.stats_files = bms.core.Logger.listFiles(ctx.StatsDir, '*.xlsx');
            manifest.expected_stats_files = {};
            manifest.missing_expected_stats = {};
            manifest.missing_stats_files = {};
            manifest.warnings = {};
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
                manifest.module_results = details.module_logs;
                manifest.module_status_counts = bms.app.ManifestWriter.statusCounts(details.module_logs);
            end
            if isfield(details, 'module_catalog')
                manifest.module_catalog = details.module_catalog;
            end
            if isfield(details, 'enabled_module_specs')
                manifest.enabled_module_specs = details.enabled_module_specs;
            end
            if isfield(details, 'module_preflight')
                manifest.module_preflight = details.module_preflight;
            end
            if isfield(details, 'run_preflight')
                manifest.run_preflight = details.run_preflight;
            end
            if isfield(details, 'run_request')
                manifest.run_request = details.run_request;
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
                manifest.missing_stats_files = manifest.missing_expected_stats;
            end
            if isfield(details, 'warnings')
                manifest.warnings = details.warnings;
            elseif isfield(details, 'config_warnings')
                manifest.warnings = details.config_warnings;
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

        function v = configSchemaVersion(cfg)
            v = 1;
            if isstruct(cfg) && isfield(cfg, 'config_schema_version') && ~isempty(cfg.config_schema_version)
                v = cfg.config_schema_version;
            end
        end

        function counts = statusCounts(records)
            counts = struct('ok', 0, 'fail', 0, 'skip', 0, 'missing', 0, 'other', 0);
            if isempty(records), return; end
            if isstruct(records)
                records = num2cell(records);
            end
            for i = 1:numel(records)
                rec = records{i};
                status = 'other';
                if isstruct(rec) && isfield(rec, 'status') && ~isempty(rec.status)
                    status = lower(char(string(rec.status)));
                end
                switch status
                    case {'ok','pass','passed'}
                        counts.ok = counts.ok + 1;
                    case {'fail','failed','error'}
                        counts.fail = counts.fail + 1;
                    case 'skip'
                        counts.skip = counts.skip + 1;
                    case 'missing'
                        counts.missing = counts.missing + 1;
                    otherwise
                        counts.other = counts.other + 1;
                end
            end
        end
    end
end
