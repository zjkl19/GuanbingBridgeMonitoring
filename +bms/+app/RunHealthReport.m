classdef RunHealthReport
    %RUNHEALTHREPORT Unified run preflight and output health summary.

    methods (Static)
        function report = build(preflight)
            if nargin < 1 || isempty(preflight), preflight = struct(); end

            report = struct();
            report.schema_version = 1;
            report.report_type = 'run_health_report';
            report.generated_at = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss');
            report.root = bms.app.RunHealthReport.textField(preflight, 'root');
            report.start_date = bms.app.RunHealthReport.textField(preflight, 'start_date');
            report.end_date = bms.app.RunHealthReport.textField(preflight, 'end_date');
            report.status = bms.app.RunHealthReport.textField(preflight, 'status');
            report.profile = bms.app.ManifestReader.fieldValue(preflight, 'profile', struct());
            report.data_layout = bms.app.ManifestReader.fieldValue(preflight, 'data_layout', struct());
            report.input_summary = bms.app.RunHealthReport.nestedSummary(preflight, 'data_index');
            report.stats_summary = bms.app.RunHealthReport.nestedSummary(preflight, 'stats_inventory');
            report.point_coverage_summary = bms.app.RunHealthReport.pointCoverageSummary(preflight);
            report.artifact_summary = bms.app.RunHealthReport.artifactSummary(preflight);
            report.wim_summary = bms.app.RunHealthReport.wimSummary(preflight);
            report.issues = bms.app.RunHealthReport.collectIssues(preflight);
            report.issue_counts = bms.app.RunHealthReport.issueCounts(report.issues);
        end

        function summary = nestedSummary(s, field)
            summary = struct();
            value = bms.app.ManifestReader.fieldValue(s, field, struct());
            if isstruct(value) && isfield(value, 'summary')
                summary = value.summary;
            end
        end

        function summary = pointCoverageSummary(preflight)
            rows = bms.app.ManifestReader.recordsToCell(bms.app.ManifestReader.fieldValue(preflight, 'point_coverage', {}));
            summary = struct('module_count', 0, 'designed_count', 0, 'found_count', 0, 'missing_count', 0, 'coverage', 0);
            for i = 1:numel(rows)
                rec = rows{i};
                if ~isstruct(rec), continue; end
                summary.module_count = summary.module_count + 1;
                summary.designed_count = summary.designed_count + bms.app.RunHealthReport.numField(rec, 'designed_count');
                summary.found_count = summary.found_count + bms.app.RunHealthReport.numField(rec, 'found_count');
                summary.missing_count = summary.missing_count + bms.app.RunHealthReport.numField(rec, 'missing_count');
            end
            if summary.designed_count > 0
                summary.coverage = summary.found_count / summary.designed_count;
            end
        end

        function summary = artifactSummary(preflight)
            rows = bms.app.ManifestReader.recordsToCell(bms.app.ManifestReader.fieldValue(preflight, 'result_artifact_preflight', {}));
            summary = struct('record_count', 0, 'possible_stale_count', 0);
            for i = 1:numel(rows)
                rec = rows{i};
                if ~isstruct(rec), continue; end
                summary.record_count = summary.record_count + 1;
                if strcmp(bms.app.RunHealthReport.textField(rec, 'status'), 'possible_stale')
                    summary.possible_stale_count = summary.possible_stale_count + 1;
                end
            end
        end

        function summary = wimSummary(preflight)
            rows = bms.app.ManifestReader.recordsToCell(bms.app.ManifestReader.fieldValue(preflight, 'wim_month_files', {}));
            summary = struct('month_count', 0, 'existing_count', 0, 'missing_count', 0);
            for i = 1:numel(rows)
                rec = rows{i};
                if ~isstruct(rec), continue; end
                summary.month_count = summary.month_count + 1;
                if bms.app.RunHealthReport.logicalField(rec, 'exists')
                    summary.existing_count = summary.existing_count + 1;
                else
                    summary.missing_count = summary.missing_count + 1;
                end
            end
        end

        function issues = collectIssues(preflight)
            issues = {};
            issues = [issues, bms.app.RunHealthReport.messageIssues(preflight, 'errors', 'error', 'preflight_error', 'preflight')]; %#ok<AGROW>
            issues = [issues, bms.app.RunHealthReport.messageIssues(preflight, 'warnings', 'warning', 'preflight_warning', 'preflight')]; %#ok<AGROW>
            issues = [issues, bms.app.RunHealthReport.pointCoverageIssues(preflight)]; %#ok<AGROW>
            issues = [issues, bms.app.RunHealthReport.dataIndexIssues(preflight)]; %#ok<AGROW>
            issues = [issues, bms.app.RunHealthReport.statsInventoryIssues(preflight)]; %#ok<AGROW>
            issues = [issues, bms.app.RunHealthReport.artifactIssues(preflight)]; %#ok<AGROW>
        end

        function issues = messageIssues(s, field, severity, issueType, source)
            issues = {};
            values = bms.app.ManifestReader.fieldValue(s, field, {});
            if ischar(values) || isstring(values), values = cellstr(string(values)); end
            if ~iscell(values), return; end
            for i = 1:numel(values)
                msg = char(string(values{i}));
                if isempty(msg), continue; end
                issues{end+1} = bms.app.RunHealthReport.issue(severity, issueType, source, '', msg); %#ok<AGROW>
            end
        end

        function issues = pointCoverageIssues(preflight)
            issues = {};
            rows = bms.app.ManifestReader.recordsToCell(bms.app.ManifestReader.fieldValue(preflight, 'point_coverage', {}));
            for i = 1:numel(rows)
                rec = rows{i};
                if ~isstruct(rec) || bms.app.RunHealthReport.numField(rec, 'missing_count') <= 0
                    continue;
                end
                key = bms.app.RunHealthReport.textField(rec, 'key');
                msg = sprintf('%s point coverage missing %d/%d configured points', key, ...
                    bms.app.RunHealthReport.numField(rec, 'missing_count'), ...
                    bms.app.RunHealthReport.numField(rec, 'designed_count'));
                issues{end+1} = bms.app.RunHealthReport.issue('warning', 'point_missing', 'point_coverage', key, msg); %#ok<AGROW>
            end
        end

        function issues = dataIndexIssues(preflight)
            issues = {};
            dataIndex = bms.app.ManifestReader.fieldValue(preflight, 'data_index', struct());
            if ~isstruct(dataIndex) || ~isfield(dataIndex, 'modules'), return; end
            modules = bms.app.ManifestReader.recordsToCell(dataIndex.modules);
            for i = 1:numel(modules)
                rec = modules{i};
                if ~isstruct(rec) || bms.app.RunHealthReport.numField(rec, 'missing_point_count') <= 0
                    continue;
                end
                key = bms.app.RunHealthReport.textField(rec, 'key');
                msg = sprintf('%s source files missing for %d/%d indexed points', key, ...
                    bms.app.RunHealthReport.numField(rec, 'missing_point_count'), ...
                    bms.app.RunHealthReport.numField(rec, 'point_count'));
                issues{end+1} = bms.app.RunHealthReport.issue('warning', 'source_missing', 'data_index', key, msg); %#ok<AGROW>
            end
        end

        function issues = statsInventoryIssues(preflight)
            issues = {};
            inventory = bms.app.ManifestReader.fieldValue(preflight, 'stats_inventory', struct());
            if ~isstruct(inventory) || ~isfield(inventory, 'modules'), return; end
            modules = bms.app.ManifestReader.recordsToCell(inventory.modules);
            for i = 1:numel(modules)
                rec = modules{i};
                if ~isstruct(rec), continue; end
                status = bms.app.RunHealthReport.textField(rec, 'status');
                if strcmp(status, 'ok'), continue; end
                key = bms.app.RunHealthReport.textField(rec, 'key');
                severity = 'warning';
                if strcmp(status, 'read_failed')
                    severity = 'error';
                end
                msg = bms.app.RunHealthReport.textField(rec, 'message');
                if isempty(msg)
                    msg = sprintf('%s stats status: %s', key, status);
                end
                issues{end+1} = bms.app.RunHealthReport.issue(severity, ['stats_' status], 'stats_inventory', key, msg); %#ok<AGROW>
            end
        end

        function issues = artifactIssues(preflight)
            issues = {};
            rows = bms.app.ManifestReader.recordsToCell(bms.app.ManifestReader.fieldValue(preflight, 'result_artifact_preflight', {}));
            for i = 1:numel(rows)
                rec = rows{i};
                if ~isstruct(rec) || ~strcmp(bms.app.RunHealthReport.textField(rec, 'status'), 'possible_stale')
                    continue;
                end
                key = bms.app.RunHealthReport.textField(rec, 'key');
                msg = bms.app.RunHealthReport.textField(rec, 'message');
                issues{end+1} = bms.app.RunHealthReport.issue('warning', 'artifact_possible_stale', 'artifact_preflight', key, msg); %#ok<AGROW>
            end
        end

        function counts = issueCounts(issues)
            rows = bms.app.ManifestReader.recordsToCell(issues);
            counts = struct('total', 0, 'error', 0, 'warning', 0, 'info', 0);
            for i = 1:numel(rows)
                rec = rows{i};
                if ~isstruct(rec), continue; end
                counts.total = counts.total + 1;
                severity = bms.app.RunHealthReport.textField(rec, 'severity');
                if isfield(counts, severity)
                    counts.(severity) = counts.(severity) + 1;
                end
            end
        end

        function rec = issue(severity, issueType, source, moduleKey, message)
            rec = struct();
            rec.severity = char(string(severity));
            rec.issue_type = char(string(issueType));
            rec.source = char(string(source));
            rec.module_key = char(string(moduleKey));
            rec.message = char(string(message));
        end

        function T = issueRows(report)
            severity = {};
            issueType = {};
            source = {};
            moduleKey = {};
            message = {};
            issues = bms.app.ManifestReader.recordsToCell(bms.app.ManifestReader.fieldValue(report, 'issues', {}));
            for i = 1:numel(issues)
                rec = issues{i};
                if ~isstruct(rec), continue; end
                severity{end+1, 1} = bms.app.RunHealthReport.textField(rec, 'severity'); %#ok<AGROW>
                issueType{end+1, 1} = bms.app.RunHealthReport.textField(rec, 'issue_type'); %#ok<AGROW>
                source{end+1, 1} = bms.app.RunHealthReport.textField(rec, 'source'); %#ok<AGROW>
                moduleKey{end+1, 1} = bms.app.RunHealthReport.textField(rec, 'module_key'); %#ok<AGROW>
                message{end+1, 1} = bms.app.RunHealthReport.textField(rec, 'message'); %#ok<AGROW>
            end
            T = table(severity, issueType, source, moduleKey, message, ...
                'VariableNames', {'severity','issue_type','source','module_key','message'});
        end

        function T = summaryRows(report)
            metric = {};
            value = {};
            metric = bms.app.RunHealthReport.addSummary(metric, 'status');
            value = bms.app.RunHealthReport.addSummary(value, bms.app.RunHealthReport.textField(report, 'status'));
            counts = bms.app.ManifestReader.fieldValue(report, 'issue_counts', struct());
            names = {'total','error','warning','info'};
            for i = 1:numel(names)
                metric{end+1, 1} = ['issues_' names{i}]; %#ok<AGROW>
                value{end+1, 1} = num2str(bms.app.RunHealthReport.numField(counts, names{i})); %#ok<AGROW>
            end
            T = table(metric, value, 'VariableNames', {'metric','value'});
        end

        function c = addSummary(c, value)
            c{end+1, 1} = char(string(value));
        end

        function path = write(root, report, runId)
            if nargin < 3 || isempty(runId)
                runId = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
            end
            logDir = bms.data.DataLayoutResolver.logDir(root);
            bms.data.DataLayoutResolver.ensureDir(logDir);
            path = fullfile(logDir, ['run_health_' char(string(runId)) '.json']);
            bms.core.Logger.writeJson(path, report);
        end

        function path = writeSummary(root, report, runId)
            if nargin < 3 || isempty(runId)
                runId = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
            end
            logDir = bms.data.DataLayoutResolver.logDir(root);
            bms.data.DataLayoutResolver.ensureDir(logDir);
            path = fullfile(logDir, ['run_health_summary_' char(string(runId)) '.xlsx']);
            if isfile(path)
                delete(path);
            end
            bms.io.StatsWriter.writeSheet(bms.app.RunHealthReport.summaryRows(report), path, 'Summary');
            bms.io.StatsWriter.writeSheet(bms.app.RunHealthReport.issueRows(report), path, 'Issues');
        end

        function tf = enabled(opts, cfg)
            tf = false;
            if isstruct(opts) && isfield(opts, 'buildRunHealthReport') && ~isempty(opts.buildRunHealthReport)
                tf = logical(opts.buildRunHealthReport);
                return;
            end
            if isstruct(cfg) && isfield(cfg, 'run_health') && isstruct(cfg.run_health) ...
                    && isfield(cfg.run_health, 'enabled') && ~isempty(cfg.run_health.enabled)
                tf = logical(cfg.run_health.enabled);
            end
        end

        function value = textField(s, field)
            value = '';
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                value = char(string(s.(field)));
            end
        end

        function value = numField(s, field)
            value = 0;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field)) && isnumeric(s.(field))
                value = double(s.(field));
            end
        end

        function value = logicalField(s, field)
            value = false;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                value = logical(s.(field));
            end
        end
    end
end
