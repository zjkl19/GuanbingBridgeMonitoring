classdef ManifestReader
    %MANIFESTREADER Reads and summarizes analysis_manifest_*.json files.

    methods (Static)
        function path = latest(resultRoot)
            path = '';
            if nargin < 1 || isempty(resultRoot), return; end
            candidates = {};
            roots = {fullfile(char(resultRoot), 'run_logs'), char(resultRoot)};
            for i = 1:numel(roots)
                files = bms.core.Logger.listFiles(roots{i}, 'analysis_manifest_*.json');
                candidates = [candidates, files]; %#ok<AGROW>
            end
            if isempty(candidates), return; end
            datenums = zeros(1, numel(candidates));
            for i = 1:numel(candidates)
                d = dir(candidates{i});
                if ~isempty(d), datenums(i) = d.datenum; end
            end
            maxTime = max(datenums);
            idxs = find(datenums == maxTime);
            if numel(idxs) > 1
                names = candidates(idxs);
                [~, order] = sort(names);
                idx = idxs(order(end));
            else
                idx = idxs(1);
            end
            path = candidates{idx};
        end

        function manifest = load(path)
            manifest = struct();
            if nargin < 1 || isempty(path) || ~isfile(path)
                return;
            end
            manifest = jsondecode(fileread(path));
        end

        function context = context(resultRoot)
            path = bms.app.ManifestReader.latest(resultRoot);
            manifest = bms.app.ManifestReader.load(path);
            context = struct();
            context.path = path;
            context.available = ~isempty(fieldnames(manifest));
            context.status = bms.app.ManifestReader.fieldText(manifest, 'status');
            context.schema_version = bms.app.ManifestReader.fieldValue(manifest, 'schema_version', []);
            context.bridge_profile = bms.app.ManifestReader.fieldValue(manifest, 'bridge_profile', struct());
            context.data_layout = bms.app.ManifestReader.fieldValue(manifest, 'data_layout', struct());
            context.run_request = bms.app.ManifestReader.fieldValue(manifest, 'run_request', struct());
            context.run_preflight = bms.app.ManifestReader.fieldValue(manifest, 'run_preflight', struct());
            context.missing_modules = bms.app.ManifestReader.missingModules(manifest);
            context.module_artifacts = bms.app.ManifestReader.fieldValue(manifest, 'module_artifacts', {});
            context.artifact_count = bms.app.ManifestReader.fieldValue(manifest, 'artifact_count', 0);
            context.manifest = manifest;
        end

        function missing = missingModules(manifest)
            missing = {};
            if ~isstruct(manifest), return; end
            records = {};
            if isfield(manifest, 'module_preflight')
                records = [records, bms.app.ManifestReader.recordsToCell(manifest.module_preflight)]; %#ok<AGROW>
            end
            if isfield(manifest, 'module_results')
                records = [records, bms.app.ManifestReader.recordsToCell(manifest.module_results)]; %#ok<AGROW>
            elseif isfield(manifest, 'module_logs')
                records = [records, bms.app.ManifestReader.recordsToCell(manifest.module_logs)]; %#ok<AGROW>
            end
            seen = {};
            for i = 1:numel(records)
                rec = records{i};
                if ~isstruct(rec), continue; end
                status = lower(bms.app.ManifestReader.fieldText(rec, 'status'));
                existsValue = bms.app.ManifestReader.fieldValue(rec, 'exists', []);
                isMissing = strcmp(status, 'missing') || strcmp(status, 'fail') || strcmp(status, 'failed') || strcmp(status, 'skip') ...
                    || (islogical(existsValue) && isscalar(existsValue) && ~existsValue);
                if ~isMissing, continue; end
                key = bms.app.ManifestReader.fieldText(rec, 'key');
                if isempty(key), key = bms.app.ManifestReader.fieldText(rec, 'label'); end
                marker = [key ':' status];
                if ismember(marker, seen), continue; end
                seen{end+1} = marker; %#ok<AGROW>
                missing{end+1} = rec; %#ok<AGROW>
            end
        end

        function lines = summaryLines(context)
            lines = {};
            if ~isstruct(context) || ~isfield(context, 'available') || ~context.available
                lines = {'analysis manifest not found'};
                return;
            end
            lines{end+1} = ['manifest=' context.path];
            lines{end+1} = ['status=' char(string(context.status))];
            if isstruct(context.bridge_profile) && isfield(context.bridge_profile, 'bridge_id')
                lines{end+1} = ['profile=' char(string(context.bridge_profile.bridge_id))]; %#ok<AGROW>
            end
            lines{end+1} = sprintf('missing_modules=%d', numel(context.missing_modules));
        end

        function records = recordsToCell(value)
            records = {};
            if isempty(value)
                return;
            elseif iscell(value)
                records = reshape(value, 1, []);
            elseif isstruct(value)
                records = reshape(num2cell(value), 1, []);
            end
        end

        function value = fieldValue(s, name, defaultValue)
            value = defaultValue;
            if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
                value = s.(name);
            end
        end

        function text = fieldText(s, name)
            text = '';
            if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
                text = char(string(s.(name)));
            end
        end
    end
end
