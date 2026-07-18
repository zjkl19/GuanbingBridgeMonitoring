classdef ManifestWriter
    %MANIFESTWRITER Writes versioned analysis manifest JSON files.

    properties (Constant)
        SchemaVersion = 3
    end

    methods (Static)
        function manifestPath = write(ctx, status, details)
            if nargin < 2 || isempty(status), status = 'unknown'; end
            if nargin < 3 || isempty(details), details = struct(); end
            bms.core.PathResolver.ensureDir(ctx.LogDir);
            manifestPath = fullfile(ctx.LogDir, ['analysis_manifest_' ctx.RunId '.json']);
            try
                manifest = bms.app.ManifestWriter.build(ctx, status, details);
                bms.core.Logger.writeJson(manifestPath, manifest);
            catch ME
                % Never leave a caller pointing at a truncated or absent
                % manifest.  The fallback deliberately omits bulky artifact
                % arrays and marks the run failed, so downstream report gates
                % cannot mistake incomplete evidence for a successful run.
                fallback = bms.app.ManifestWriter.buildWriteFailureFallback( ...
                    ctx, status, details, ME);
                fallbackPath = fullfile(ctx.LogDir, ...
                    ['analysis_manifest_' ctx.RunId '_write_failure.json']);
                bms.core.Logger.writeJson(fallbackPath, fallback);
                warning('BMS:ManifestWriter:FullManifestWriteFailed', ...
                    'Full analysis manifest could not be published; wrote a valid failure manifest instead: %s (%s)', ...
                    fallbackPath, ME.message);
                manifestPath = fallbackPath;
            end
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
            manifest.progress_schema_version = bms.app.RunProgressReporter.SchemaVersion;
            manifest.progress_authority = 'analysis_manifest';
            manifest.module_steps = {};
            manifest.analysis_progress = struct();
            manifest.module_status_counts = struct('ok', 0, 'fail', 0, 'skip', 0, 'missing', 0, 'other', 0);
            manifest.module_artifacts = {};
            manifest.artifact_count = 0;
            manifest.module_catalog = {};
            manifest.enabled_module_specs = {};
            manifest.module_preflight = {};
            manifest.stats_inventory_path = '';
            manifest.stats_inventory_summary_path = '';
            manifest.stats_inventory = struct();
            manifest.data_index_path = '';
            manifest.data_index_summary_path = '';
            manifest.data_index = struct();
            manifest.run_health_report_path = '';
            manifest.run_health_report_summary_path = '';
            manifest.run_health_report = struct();
            manifest.run_preflight = struct();
            manifest.run_request = struct();
            manifest.stats_files = bms.core.Logger.listFiles(ctx.StatsDir, '*.xlsx');
            manifest.stats_schema_registry = bms.io.StatsSchema.registry();
            manifest.expected_stats_files = {};
            manifest.missing_expected_stats = {};
            manifest.missing_stats_files = {};
            manifest.warnings = {};
            manifest.offset_report = struct();
            manifest.details = details;
            if isstruct(details)
                manifest = bms.app.ManifestWriter.applyDetails(manifest, details);
            end
            manifest.written_at = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
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
                records = bms.app.ManifestWriter.normalizeModuleRecords(details.module_logs, manifest.stats_dir);
                manifest.module_logs = records;
                manifest.module_results = records;
                manifest.module_status_counts = bms.app.ManifestWriter.statusCounts(records);
                manifest.module_artifacts = bms.app.ManifestWriter.moduleArtifacts(records);
                manifest.artifact_count = bms.app.ManifestWriter.countArtifacts(manifest.module_artifacts);
            end
            progressFields = {'progress_schema_version','progress_authority', ...
                'module_index','module_total','completed_modules','progress_fraction', ...
                'current_module_key','current_module_label','current_module_status', ...
                'stage','current_point_id','current_date','processed_dates', ...
                'total_dates','message','module_steps','analysis_progress'};
            for i = 1:numel(progressFields)
                name = progressFields{i};
                if isfield(details, name)
                    manifest.(name) = details.(name);
                end
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
                if isstruct(details.run_preflight)
                    if isfield(details.run_preflight, 'data_index_path')
                        manifest.data_index_path = details.run_preflight.data_index_path;
                    end
                    if isfield(details.run_preflight, 'data_index_summary_path')
                        manifest.data_index_summary_path = details.run_preflight.data_index_summary_path;
                    end
                    if isfield(details.run_preflight, 'data_index')
                        manifest.data_index = details.run_preflight.data_index;
                    end
                    if isfield(details.run_preflight, 'stats_inventory_path')
                        manifest.stats_inventory_path = details.run_preflight.stats_inventory_path;
                    end
                    if isfield(details.run_preflight, 'stats_inventory_summary_path')
                        manifest.stats_inventory_summary_path = details.run_preflight.stats_inventory_summary_path;
                    end
                    if isfield(details.run_preflight, 'stats_inventory')
                        manifest.stats_inventory = details.run_preflight.stats_inventory;
                    end
                    if isfield(details.run_preflight, 'run_health_report_path')
                        manifest.run_health_report_path = details.run_preflight.run_health_report_path;
                    end
                    if isfield(details.run_preflight, 'run_health_report_summary_path')
                        manifest.run_health_report_summary_path = details.run_preflight.run_health_report_summary_path;
                    end
                    if isfield(details.run_preflight, 'run_health_report')
                        manifest.run_health_report = details.run_preflight.run_health_report;
                    end
                end
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

        function rows = moduleArtifacts(records)
            rows = {};
            if isempty(records), return; end
            if isstruct(records)
                records = num2cell(records);
            end
            for i = 1:numel(records)
                rec = records{i};
                if ~isstruct(rec) || ~isfield(rec, 'artifacts') || isempty(rec.artifacts)
                    continue;
                end
                key = '';
                label = '';
                if isfield(rec, 'key'), key = char(string(rec.key)); end
                if isfield(rec, 'label'), label = char(string(rec.label)); end
                row = struct();
                row.key = key;
                row.label = label;
                row.artifacts = rec.artifacts;
                rows{end+1} = row; %#ok<AGROW>
            end
        end

        function n = countArtifacts(moduleArtifacts)
            n = 0;
            if isempty(moduleArtifacts), return; end
            if isstruct(moduleArtifacts), moduleArtifacts = num2cell(moduleArtifacts); end
            for i = 1:numel(moduleArtifacts)
                item = moduleArtifacts{i};
                if isstruct(item) && isfield(item, 'artifacts') && ~isempty(item.artifacts)
                    n = n + numel(item.artifacts);
                end
            end
        end

        function out = normalizeModuleRecords(records, statsDir)
            if nargin < 2, statsDir = ''; end
            out = {};
            if isempty(records), return; end
            if isstruct(records)
                records = num2cell(records);
            elseif ~iscell(records)
                records = {records};
            end
            for i = 1:numel(records)
                rec = bms.app.ManifestWriter.normalizeModuleRecord(records{i}, statsDir);
                if ~isempty(rec)
                    out{end+1} = rec; %#ok<AGROW>
                end
            end
        end

        function manifest = buildWriteFailureFallback(ctx, requestedStatus, details, writeError)
            % Keep this path independent of the full manifest builder.  A
            % malformed details field or an allocation failure can occur while
            % build() is still assembling the full document, before JSON
            % encoding starts.  Re-entering build()/toStruct() here would then
            % repeat the same failure and leave no machine-readable result.
            manifest = bms.app.ManifestWriter.minimalContext(ctx);
            manifest.schema_version = bms.app.ManifestWriter.SchemaVersion;
            manifest.manifest_type = 'analysis_run_write_failure';
            manifest.status = 'failed';
            manifest.requested_status = char(string(requestedStatus));
            manifest.message = sprintf('Full analysis manifest write failed: %s', writeError.message);
            manifest.error_type = 'manifest_write_error';
            manifest.write_error_identifier = char(string(writeError.identifier));
            manifest.module_results = {};
            manifest.module_logs = {};
            manifest.progress_schema_version = bms.app.RunProgressReporter.SchemaVersion;
            manifest.progress_authority = 'analysis_manifest';
            manifest.module_steps = {};
            manifest.analysis_progress = struct();
            manifest.module_status_counts = struct('ok', 0, 'fail', 0, 'skip', 0, 'missing', 0, 'other', 0);
            manifest.module_artifacts = {};
            manifest.artifact_count = 0;
            manifest.run_log = '';
            manifest.elapsed_sec = NaN;
            manifest.warnings = {};
            manifest.stats_files = {};
            try
                manifest.stats_files = bms.core.Logger.listFiles(ctx.StatsDir, '*.xlsx');
            catch
                % A failure manifest must remain publishable even when context
                % paths are malformed or unavailable.
            end
            if isstruct(details) && isscalar(details)
                if isfield(details, 'module_logs')
                    records = bms.app.ManifestWriter.safeCompactModuleRecords( ...
                        details.module_logs, manifest.stats_dir);
                    manifest.module_results = records;
                    manifest.module_logs = records;
                    manifest.module_status_counts = bms.app.ManifestWriter.statusCounts(records);
                    progress = bms.app.RunProgressReporter.reconcile(struct(), records, 'analysis_manifest');
                    manifest.module_steps = progress.module_steps;
                    manifest.analysis_progress = progress;
                end
                if isfield(details, 'log_file') && ~isempty(details.log_file)
                    manifest.run_log = bms.app.ManifestWriter.safeStructText(details, 'log_file');
                end
                if isfield(details, 'elapsed_sec') && isnumeric(details.elapsed_sec) ...
                        && isscalar(details.elapsed_sec)
                    manifest.elapsed_sec = details.elapsed_sec;
                end
                if isfield(details, 'warnings')
                    manifest.warnings = bms.app.ManifestWriter.safeWarningTexts(details.warnings);
                elseif isfield(details, 'config_warnings')
                    manifest.warnings = bms.app.ManifestWriter.safeWarningTexts(details.config_warnings);
                end
            end
            manifest.written_at = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
        end

        function manifest = minimalContext(ctx)
            manifest = struct();
            manifest.project_root = bms.app.ManifestWriter.safePropertyText(ctx, 'ProjectRoot');
            manifest.data_root = bms.app.ManifestWriter.safePropertyText(ctx, 'DataRoot');
            manifest.start_date = bms.app.ManifestWriter.safePropertyText(ctx, 'StartDate');
            manifest.end_date = bms.app.ManifestWriter.safePropertyText(ctx, 'EndDate');
            manifest.config_path = bms.app.ManifestWriter.safePropertyText(ctx, 'ConfigPath');
            manifest.stats_dir = bms.app.ManifestWriter.safePropertyText(ctx, 'StatsDir');
            manifest.log_dir = bms.app.ManifestWriter.safePropertyText(ctx, 'LogDir');
            manifest.run_id = bms.app.ManifestWriter.safePropertyText(ctx, 'RunId');
            manifest.created_at = '';
            try
                createdAt = ctx.CreatedAt;
                if isa(createdAt, 'datetime') && ~isempty(createdAt) && ~isnat(createdAt)
                    createdAt.Format = 'yyyy-MM-dd HH:mm:ss';
                    manifest.created_at = char(createdAt);
                end
            catch
            end
            manifest.enabled_modules = {};
            manifest.bridge_profile = struct();
            manifest.date_range = struct( ...
                'start_date', manifest.start_date, 'end_date', manifest.end_date);
        end

        function value = safePropertyText(obj, propertyName)
            value = '';
            try
                raw = obj.(propertyName);
                if ischar(raw) || (isstring(raw) && isscalar(raw))
                    value = char(string(raw));
                end
            catch
            end
        end

        function records = safeCompactModuleRecords(rawRecords, statsDir)
            records = {};
            try
                normalized = bms.app.ManifestWriter.normalizeModuleRecords(rawRecords, statsDir);
            catch
                return;
            end
            if isstruct(normalized)
                normalized = num2cell(normalized);
            end
            for i = 1:numel(normalized)
                rec = normalized{i};
                if ~isstruct(rec)
                    continue;
                end
                compact = struct();
                compact.key = bms.app.ManifestWriter.safeStructText(rec, 'key');
                compact.opt_field = bms.app.ManifestWriter.safeStructText(rec, 'opt_field');
                compact.label = bms.app.ManifestWriter.safeStructText(rec, 'label');
                compact.category = bms.app.ManifestWriter.safeStructText(rec, 'category');
                compact.status = bms.app.ManifestWriter.safeStructText(rec, 'status');
                compact.message = bms.app.ManifestWriter.safeStructText(rec, 'message');
                compact.error_type = bms.app.ManifestWriter.safeStructText(rec, 'error_type');
                compact.started_at = bms.app.ManifestWriter.safeStructText(rec, 'started_at');
                compact.ended_at = bms.app.ManifestWriter.safeStructText(rec, 'ended_at');
                compact.elapsed_sec = bms.app.ManifestWriter.safeFiniteScalar(rec, 'elapsed_sec', NaN);
                compact.stats_file = bms.app.ManifestWriter.safeStructText(rec, 'stats_file');
                compact.stats_path = bms.app.ManifestWriter.safeStructText(rec, 'stats_path');
                compact.stats_exists = bms.app.ManifestWriter.safeLogicalScalar(rec, 'stats_exists', false);
                compact.artifacts = {};
                compact.figure_paths = {};
                compact.artifact_count = 0;
                compact.figure_count = 0;
                records{end+1} = compact; %#ok<AGROW>
            end
        end

        function value = safeStructText(s, fieldName)
            value = '';
            try
                if isstruct(s) && isfield(s, fieldName)
                    raw = s.(fieldName);
                    if ischar(raw) || (isstring(raw) && isscalar(raw))
                        value = char(string(raw));
                    end
                end
            catch
            end
        end

        function value = safeFiniteScalar(s, fieldName, fallback)
            value = fallback;
            try
                raw = s.(fieldName);
                if isnumeric(raw) && isscalar(raw) && (isfinite(raw) || isnan(raw))
                    value = double(raw);
                end
            catch
            end
        end

        function value = safeLogicalScalar(s, fieldName, fallback)
            value = logical(fallback);
            try
                raw = s.(fieldName);
                if (islogical(raw) || isnumeric(raw)) && isscalar(raw)
                    value = logical(raw);
                end
            catch
            end
        end

        function warnings = safeWarningTexts(raw)
            warnings = {};
            if ischar(raw)
                warnings = {raw};
                return;
            end
            if isstring(raw)
                try
                    warnings = cellstr(raw(:));
                catch
                    warnings = {};
                end
                return;
            end
            if ~iscell(raw)
                return;
            end
            for i = 1:numel(raw)
                item = raw{i};
                if ischar(item)
                    warnings{end+1} = item; %#ok<AGROW>
                elseif isstring(item) && isscalar(item)
                    warnings{end+1} = char(item); %#ok<AGROW>
                end
            end
        end

        function rec = normalizeModuleRecord(item, statsDir)
            rec = [];
            if isa(item, 'bms.app.StepResult')
                item = item.toStruct(statsDir);
            elseif isa(item, 'bms.analyzer.AnalyzerResult')
                item = item.toStruct();
            end
            if ~isstruct(item)
                return;
            end

            rec = item;
            key = bms.app.ManifestWriter.fieldText(rec, 'key', '');
            label = bms.app.ManifestWriter.fieldText(rec, 'label', '');
            if isempty(key) && ~isempty(label)
                spec = bms.module.ModuleRegistry.fromLabel(label);
                key = spec.Key;
            elseif ~isempty(key)
                spec = bms.module.ModuleRegistry.fromKey(key);
            else
                spec = bms.module.ModuleSpec('', '', '', '', 'analysis');
            end
            if isempty(key), key = spec.Key; end
            if isempty(label), label = spec.Label; end
            if isempty(label), label = key; end
            rec.key = char(string(key));
            rec.label = char(string(label));

            if ~isfield(rec, 'category') || isempty(rec.category)
                rec.category = spec.Category;
            end
            if ~isfield(rec, 'opt_field') || isempty(rec.opt_field)
                rec.opt_field = spec.OptField;
            end
            if ~isfield(rec, 'status') || isempty(rec.status)
                rec.status = 'unknown';
            end
            if ~isfield(rec, 'message') || isempty(rec.message)
                rec.message = '';
            end
            if ~isfield(rec, 'error_type') || isempty(rec.error_type)
                if strcmpi(char(string(rec.status)), 'fail')
                    rec.error_type = bms.app.ErrorClassifier.classifyText(rec.message);
                else
                    rec.error_type = '';
                end
            end
            if ~isfield(rec, 'started_at'), rec.started_at = ''; end
            if ~isfield(rec, 'ended_at'), rec.ended_at = ''; end
            if ~isfield(rec, 'elapsed_sec') || isempty(rec.elapsed_sec) || ~isnumeric(rec.elapsed_sec)
                rec.elapsed_sec = NaN;
            end
            if ~isfield(rec, 'stats_file') || isempty(rec.stats_file)
                rec.stats_file = spec.StatsFile;
            end
            if ~isfield(rec, 'stats_path') || isempty(rec.stats_path)
                if ~isempty(statsDir) && ~isempty(rec.stats_file)
                    rec.stats_path = fullfile(statsDir, char(string(rec.stats_file)));
                else
                    rec.stats_path = '';
                end
            end
            if ~isfield(rec, 'stats_exists') || isempty(rec.stats_exists)
                rec.stats_exists = ~isempty(rec.stats_path) && isfile(rec.stats_path);
            end
            if ~isfield(rec, 'artifacts') || isempty(rec.artifacts)
                rec.artifacts = {};
            elseif isstruct(rec.artifacts)
                rec.artifacts = num2cell(rec.artifacts);
            end
            rec.figure_paths = bms.analyzer.AnalyzerResult.figurePathsFromArtifacts(rec.artifacts);
            rec.artifact_count = numel(rec.artifacts);
            rec.figure_count = numel(rec.figure_paths);
        end

        function txt = fieldText(s, field, fallback)
            txt = fallback;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                txt = char(string(s.(field)));
            end
        end
    end
end
