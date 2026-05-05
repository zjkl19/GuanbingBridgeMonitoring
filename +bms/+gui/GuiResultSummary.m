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
            summary.lines = {};
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
            summary.lines = bms.gui.GuiResultSummary.buildLines(summary);
        end

        function lines = buildLines(summary)
            lines = {};
            lines{end+1} = ['manifest: ' summary.path]; %#ok<AGROW>
            lines{end+1} = ['status: ' summary.status]; %#ok<AGROW>
            c = summary.counts;
            lines{end+1} = sprintf('modules: ok=%d, fail=%d, skip=%d, missing=%d, other=%d', ...
                c.ok, c.fail, c.skip, c.missing, c.other); %#ok<AGROW>
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
