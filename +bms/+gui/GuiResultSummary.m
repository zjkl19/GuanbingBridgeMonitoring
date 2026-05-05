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
            summary.module_rows = bms.gui.GuiResultSummary.buildModuleRows(ctx.manifest);
            summary.lines = bms.gui.GuiResultSummary.buildLines(summary);
        end

        function lines = buildLines(summary)
            lines = {};
            lines{end+1} = ['manifest: ' summary.path]; %#ok<AGROW>
            lines{end+1} = ['status: ' summary.status]; %#ok<AGROW>
            c = summary.counts;
            lines{end+1} = sprintf('modules: ok=%d, fail=%d, skip=%d, missing=%d, other=%d', ...
                c.ok, c.fail, c.skip, c.missing, c.other); %#ok<AGROW>
            lines{end+1} = sprintf('artifacts: %d', summary.artifact_count); %#ok<AGROW>
        end

        function rows = buildModuleRows(manifest)
            rows = {};
            records = bms.gui.GuiResultSummary.moduleRecords(manifest);
            if isempty(records), return; end
            if isstruct(records), records = num2cell(records); end
            for i = 1:numel(records)
                rec = records{i};
                if ~isstruct(rec), continue; end
                label = bms.gui.GuiResultSummary.fieldText(rec, 'label', bms.gui.GuiResultSummary.fieldText(rec, 'key', ''));
                status = bms.gui.GuiResultSummary.fieldText(rec, 'status', '');
                elapsed = '';
                if isfield(rec, 'elapsed_sec') && isnumeric(rec.elapsed_sec) && isfinite(rec.elapsed_sec)
                    elapsed = sprintf('%.1f', double(rec.elapsed_sec));
                end
                statsFlag = '';
                statsPath = bms.gui.GuiResultSummary.fieldText(rec, 'stats_path', '');
                if ~isempty(statsPath)
                    if isfile(statsPath), statsFlag = 'OK'; else, statsFlag = 'missing'; end
                end
                figCount = bms.gui.GuiResultSummary.countFigures(rec);
                rows(end+1, :) = {label, status, elapsed, statsFlag, figCount}; %#ok<AGROW>
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

        function records = moduleRecords(manifest)
            records = {};
            if isstruct(manifest) && isfield(manifest, 'module_results')
                records = manifest.module_results;
            elseif isstruct(manifest) && isfield(manifest, 'module_logs')
                records = manifest.module_logs;
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
