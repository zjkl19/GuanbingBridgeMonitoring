classdef ManifestWriter
    %MANIFESTWRITER Writes versioned analysis manifest JSON files.

    properties (Constant)
        SchemaVersion = 2
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
            manifest.module_artifacts = {};
            manifest.artifact_count = 0;
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
                records = bms.app.ManifestWriter.normalizeModuleRecords(details.module_logs, manifest.stats_dir);
                manifest.module_logs = records;
                manifest.module_results = records;
                manifest.module_status_counts = bms.app.ManifestWriter.statusCounts(records);
                manifest.module_artifacts = bms.app.ManifestWriter.moduleArtifacts(records);
                manifest.artifact_count = bms.app.ManifestWriter.countArtifacts(manifest.module_artifacts);
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
