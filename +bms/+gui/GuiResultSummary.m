classdef GuiResultSummary
    %GUIRESULTSUMMARY Backend summary model for a future GUI result panel.

    methods (Static)
        function summary = fromResultRoot(resultRoot)
            ctx = bms.app.ManifestReader.context(resultRoot);
            summary = bms.gui.GuiResultSummary.fromManifestContext(ctx);
        end

        function summary = fromManifestContext(ctx)
            summary = struct();
            summary.available = isstruct(ctx) && isfield(ctx, 'available') && ctx.available;
            summary.path = '';
            summary.status = '';
            summary.counts = struct('ok', 0, 'fail', 0, 'skip', 0, 'missing', 0, 'other', 0);
            summary.artifact_count = 0;
            summary.preflight_warning_count = 0;
            summary.missing_stats_count = 0;
            summary.possible_stale_count = 0;
            summary.preflight_error_count = 0;
            summary.lines = {};
            summary.module_rows = {};
            if ~summary.available
                summary.lines = {'analysis manifest not found'};
                return;
            end

            summary.path = ctx.path;
            summary.status = ctx.status;
            if isfield(ctx.manifest, 'module_status_counts') && isstruct(ctx.manifest.module_status_counts)
                summary.counts = bms.gui.GuiResultSummary.mergeCounts(summary.counts, ctx.manifest.module_status_counts);
            else
                summary.counts = bms.app.ManifestWriter.statusCounts(bms.gui.GuiResultSummary.moduleRecords(ctx.manifest));
            end
            if isfield(ctx, 'artifact_count') && isnumeric(ctx.artifact_count)
                summary.artifact_count = double(ctx.artifact_count);
            elseif isfield(ctx.manifest, 'artifact_count') && isnumeric(ctx.manifest.artifact_count)
                summary.artifact_count = double(ctx.manifest.artifact_count);
            end
            detailRows = bms.gui.GuiResultSummary.buildModuleRows(ctx.manifest);
            diagnosticRows = bms.gui.GuiResultSummary.buildDiagnosticRows(ctx.manifest);
            summary.preflight_warning_count = bms.gui.GuiResultSummary.countPreflightWarnings(ctx.manifest);
            summary.preflight_error_count = bms.gui.GuiResultSummary.countPreflightErrors(ctx.manifest);
            summary.missing_stats_count = bms.gui.GuiResultSummary.countMissingStats(ctx.manifest);
            summary.possible_stale_count = bms.gui.GuiResultSummary.countPossibleStale(ctx.manifest);
            summary.lines = bms.gui.GuiResultSummary.buildLines(summary);
            rows = bms.gui.GuiResultSummary.summaryRow(summary);
            if ~isempty(diagnosticRows), rows = [rows; diagnosticRows]; end %#ok<AGROW>
            if ~isempty(detailRows), rows = [rows; detailRows]; end %#ok<AGROW>
            summary.module_rows = rows;
        end

        function lines = buildLines(summary)
            lines = {};
            lines{end+1} = ['manifest: ' summary.path]; %#ok<AGROW>
            lines{end+1} = ['status: ' summary.status]; %#ok<AGROW>
            c = summary.counts;
            lines{end+1} = sprintf('modules: ok=%d, fail=%d, skip=%d, missing=%d, other=%d', ...
                c.ok, c.fail, c.skip, c.missing, c.other); %#ok<AGROW>
            lines{end+1} = sprintf('artifacts: %d', summary.artifact_count); %#ok<AGROW>
            if summary.preflight_error_count > 0
                lines{end+1} = sprintf('preflight errors: %d', summary.preflight_error_count); %#ok<AGROW>
            end
            if summary.preflight_warning_count > 0
                lines{end+1} = sprintf('preflight warnings: %d', summary.preflight_warning_count); %#ok<AGROW>
            end
            if summary.missing_stats_count > 0
                lines{end+1} = sprintf('missing expected stats: %d', summary.missing_stats_count); %#ok<AGROW>
            end
            if summary.possible_stale_count > 0
                lines{end+1} = sprintf('possible stale results: %d', summary.possible_stale_count); %#ok<AGROW>
            end
        end

        function rows = buildModuleRows(manifest)
            rows = {};
            records = bms.gui.GuiResultSummary.moduleRecords(manifest);
            if isempty(records), return; end
            records = bms.app.ManifestReader.recordsToCell(records);
            for i = 1:numel(records)
                rec = records{i};
                if ~isstruct(rec), continue; end
                key = bms.gui.GuiResultSummary.fieldText(rec, 'key', '');
                category = bms.gui.GuiResultSummary.fieldText(rec, 'category', '');
                if strcmp(key, 'offset_correction_report') || strcmp(category, 'postprocess')
                    continue;
                end
                label = bms.gui.GuiResultSummary.fieldText(rec, 'label', bms.gui.GuiResultSummary.fieldText(rec, 'key', ''));
                status = bms.gui.GuiResultSummary.fieldText(rec, 'status', '');
                elapsed = '';
                if isfield(rec, 'elapsed_sec') && isnumeric(rec.elapsed_sec) && isfinite(rec.elapsed_sec)
                    elapsed = sprintf('%.1f', double(rec.elapsed_sec));
                end
                statsFlag = '';
                statsPath = bms.gui.GuiResultSummary.fieldText(rec, 'stats_path', '');
                if ~isempty(statsPath)
                    if isfield(rec, 'stats_exists') && islogical(rec.stats_exists)
                        if rec.stats_exists, statsFlag = 'OK'; else, statsFlag = 'missing'; end
                    elseif isfile(statsPath)
                        statsFlag = 'OK';
                    else
                        statsFlag = 'missing';
                    end
                end
                figCount = bms.gui.GuiResultSummary.countFigures(rec);
                errorType = bms.gui.GuiResultSummary.fieldText(rec, 'error_type', '');
                message = bms.gui.GuiResultSummary.shortText(bms.gui.GuiResultSummary.fieldText(rec, 'message', ''), 120);
                rows(end+1, :) = {label, status, elapsed, statsFlag, figCount, errorType, message}; %#ok<AGROW>
            end
        end

        function row = summaryRow(summary)
            c = summary.counts;
            statsText = sprintf('missing stats=%d', summary.missing_stats_count);
            artifactText = sprintf('artifacts=%d', summary.artifact_count);
            errorText = sprintf('preflight=%d, stale=%d', summary.preflight_warning_count + summary.preflight_error_count, summary.possible_stale_count);
            msg = sprintf('ok=%d, fail=%d, skip=%d, missing=%d, other=%d; %s', ...
                c.ok, c.fail, c.skip, c.missing, c.other, summary.path);
            row = {'Summary', summary.status, '', statsText, artifactText, errorText, msg};
        end

        function rows = buildDiagnosticRows(manifest)
            rows = {};
            if ~isstruct(manifest), return; end
            maxRows = 40;

            if isfield(manifest, 'run_preflight') && isstruct(manifest.run_preflight)
                runPreflight = manifest.run_preflight;
                if isfield(runPreflight, 'errors')
                    rows = bms.gui.GuiResultSummary.appendTextRows(rows, 'Preflight', 'error', 'preflight_error', runPreflight.errors, maxRows);
                end
                if isfield(runPreflight, 'warnings')
                    rows = bms.gui.GuiResultSummary.appendTextRows(rows, 'Preflight', 'warning', 'preflight_warning', runPreflight.warnings, maxRows);
                end
                if isfield(runPreflight, 'result_artifact_preflight')
                    records = bms.app.ManifestReader.recordsToCell(runPreflight.result_artifact_preflight);
                    for i = 1:numel(records)
                        rec = records{i};
                        if ~isstruct(rec), continue; end
                        status = lower(bms.gui.GuiResultSummary.fieldText(rec, 'status', ''));
                        if isempty(status) || strcmp(status, 'ok'), continue; end
                        label = bms.gui.GuiResultSummary.fieldText(rec, 'label', bms.gui.GuiResultSummary.fieldText(rec, 'key', 'Result artifact'));
                        issueType = bms.gui.GuiResultSummary.fieldText(rec, 'issue_type', bms.gui.GuiResultSummary.fieldText(rec, 'stale_type', 'result_artifact'));
                        msg = bms.gui.GuiResultSummary.fieldText(rec, 'message', bms.gui.GuiResultSummary.fieldText(rec, 'stats_path', ''));
                        rows(end+1, :) = {label, status, '', '', '', issueType, bms.gui.GuiResultSummary.shortText(msg, 160)}; %#ok<AGROW>
                        if size(rows, 1) >= maxRows
                            rows(end+1, :) = {'Diagnostics', 'truncated', '', '', '', 'limit', sprintf('Only first %d diagnostic rows are shown.', maxRows)}; %#ok<AGROW>
                            return;
                        end
                    end
                end
            end

            missing = bms.gui.GuiResultSummary.missingStatsList(manifest);
            for i = 1:numel(missing)
                rows(end+1, :) = {'Missing stats', 'missing', '', 'missing', '', 'missing_stats', bms.gui.GuiResultSummary.shortText(missing{i}, 160)}; %#ok<AGROW>
                if size(rows, 1) >= maxRows
                    rows(end+1, :) = {'Diagnostics', 'truncated', '', '', '', 'limit', sprintf('Only first %d diagnostic rows are shown.', maxRows)}; %#ok<AGROW>
                    return;
                end
            end
        end

        function rows = appendTextRows(rows, label, status, issueType, values, maxRows)
            values = bms.gui.GuiResultSummary.toCell(values);
            for i = 1:numel(values)
                msg = char(string(values{i}));
                if isempty(strtrim(msg)), continue; end
                rows(end+1, :) = {label, status, '', '', '', issueType, bms.gui.GuiResultSummary.shortText(msg, 160)}; %#ok<AGROW>
                if size(rows, 1) >= maxRows
                    rows(end+1, :) = {'Diagnostics', 'truncated', '', '', '', 'limit', sprintf('Only first %d diagnostic rows are shown.', maxRows)}; %#ok<AGROW>
                    return;
                end
            end
        end

        function txt = fieldText(s, field, fallback)
            txt = fallback;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                txt = char(string(s.(field)));
            end
        end

        function n = countFigures(rec)
            n = 0;
            if isstruct(rec) && isfield(rec, 'figure_count') && isnumeric(rec.figure_count) && isscalar(rec.figure_count)
                n = double(rec.figure_count);
                return;
            end
            if isstruct(rec) && isfield(rec, 'figure_paths') && ~isempty(rec.figure_paths)
                n = numel(rec.figure_paths);
                return;
            end
            if ~isstruct(rec) || ~isfield(rec, 'artifacts') || isempty(rec.artifacts)
                return;
            end
            artifacts = rec.artifacts;
            if isstruct(artifacts), artifacts = num2cell(artifacts); end
            for i = 1:numel(artifacts)
                a = artifacts{i};
                if isstruct(a) && isfield(a, 'kind') && strcmp(char(string(a.kind)), 'figure')
                    n = n + 1;
                end
            end
        end

        function txt = shortText(txt, maxLen)
            if nargin < 2 || isempty(maxLen), maxLen = 120; end
            txt = char(string(txt));
            txt = regexprep(txt, '\s+', ' ');
            if strlength(string(txt)) > maxLen
                txt = [extractBefore(string(txt), maxLen) '...'];
                txt = char(txt);
            end
        end

        function records = moduleRecords(manifest)
            records = {};
            if isstruct(manifest) && isfield(manifest, 'module_results')
                records = manifest.module_results;
            elseif isstruct(manifest) && isfield(manifest, 'module_logs')
                records = manifest.module_logs;
            end
        end

        function values = missingStatsList(manifest)
            values = {};
            if isstruct(manifest) && isfield(manifest, 'missing_expected_stats') && ~isempty(manifest.missing_expected_stats)
                values = bms.gui.GuiResultSummary.toCell(manifest.missing_expected_stats);
            elseif isstruct(manifest) && isfield(manifest, 'missing_stats_files') && ~isempty(manifest.missing_stats_files)
                values = bms.gui.GuiResultSummary.toCell(manifest.missing_stats_files);
            end
            for i = 1:numel(values)
                values{i} = char(string(values{i}));
            end
        end

        function values = toCell(value)
            values = {};
            if isempty(value)
                return;
            elseif iscell(value)
                values = reshape(value, 1, []);
            elseif isstruct(value)
                values = reshape(num2cell(value), 1, []);
            elseif isstring(value)
                values = cellstr(value);
            else
                values = {value};
            end
        end

        function n = countPreflightWarnings(manifest)
            n = 0;
            if isstruct(manifest) && isfield(manifest, 'run_preflight') && isstruct(manifest.run_preflight) ...
                    && isfield(manifest.run_preflight, 'warnings')
                n = numel(bms.gui.GuiResultSummary.toCell(manifest.run_preflight.warnings));
            end
        end

        function n = countPreflightErrors(manifest)
            n = 0;
            if isstruct(manifest) && isfield(manifest, 'run_preflight') && isstruct(manifest.run_preflight) ...
                    && isfield(manifest.run_preflight, 'errors')
                n = numel(bms.gui.GuiResultSummary.toCell(manifest.run_preflight.errors));
            end
        end

        function n = countMissingStats(manifest)
            n = 0;
            n = numel(bms.gui.GuiResultSummary.missingStatsList(manifest));
        end

        function n = countPossibleStale(manifest)
            n = 0;
            if ~isstruct(manifest) || ~isfield(manifest, 'run_preflight') || ~isstruct(manifest.run_preflight) ...
                    || ~isfield(manifest.run_preflight, 'result_artifact_preflight')
                return;
            end
            records = manifest.run_preflight.result_artifact_preflight;
            records = bms.app.ManifestReader.recordsToCell(records);
            for i = 1:numel(records)
                rec = records{i};
                if isstruct(rec) && isfield(rec, 'status') && strcmp(char(string(rec.status)), 'possible_stale')
                    n = n + 1;
                end
            end
        end

        function base = mergeCounts(base, extra)
            names = fieldnames(base);
            for i = 1:numel(names)
                if isfield(extra, names{i}) && isnumeric(extra.(names{i}))
                    base.(names{i}) = double(extra.(names{i}));
                end
            end
        end
    end
end
