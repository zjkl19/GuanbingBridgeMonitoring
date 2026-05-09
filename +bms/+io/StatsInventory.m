classdef StatsInventory
    %STATSINVENTORY Scans expected stats files for a run.

    methods (Static)
        function inventory = build(root, opts, cfg)
            if nargin < 2 || isempty(opts), opts = struct(); end
            if nargin < 3 || isempty(cfg), cfg = struct(); end %#ok<INUSD>

            statsDir = bms.data.DataLayoutResolver.statsDir(root);
            specs = bms.module.ModuleRegistry.enabledFromOptions(opts);
            if isempty(specs)
                specs = bms.module.ModuleRegistry.forCategory('analysis');
            end

            inventory = struct();
            inventory.schema_version = 1;
            inventory.inventory_type = 'stats_inventory';
            inventory.root = char(string(root));
            inventory.stats_dir = statsDir;
            inventory.created_at = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss');
            inventory.modules = {};
            inventory.summary = struct('module_count', 0, 'stats_expected_count', 0, ...
                'stats_existing_count', 0, 'stats_missing_count', 0, ...
                'stats_empty_count', 0, 'stats_read_failed_count', 0);

            for i = 1:numel(specs)
                spec = specs(i);
                if isempty(spec.StatsFile)
                    continue;
                end
                rec = bms.io.StatsInventory.moduleRecord(spec, statsDir);
                inventory.modules{end+1} = rec; %#ok<AGROW>
                inventory.summary.module_count = inventory.summary.module_count + 1;
                inventory.summary.stats_expected_count = inventory.summary.stats_expected_count + 1;
                if strcmp(rec.status, 'missing')
                    inventory.summary.stats_missing_count = inventory.summary.stats_missing_count + 1;
                else
                    inventory.summary.stats_existing_count = inventory.summary.stats_existing_count + 1;
                end
                if strcmp(rec.status, 'empty')
                    inventory.summary.stats_empty_count = inventory.summary.stats_empty_count + 1;
                elseif strcmp(rec.status, 'read_failed')
                    inventory.summary.stats_read_failed_count = inventory.summary.stats_read_failed_count + 1;
                end
            end
        end

        function rec = moduleRecord(spec, statsDir)
            statsPath = spec.statsPath(statsDir);
            rec = struct();
            rec.key = spec.Key;
            rec.label = spec.Label;
            rec.stats_file = spec.StatsFile;
            rec.stats_path = statsPath;
            rec.exists = isfile(statsPath);
            rec.status = 'missing';
            rec.message = ['Expected stats file not found: ' statsPath];
            rec.row_count = 0;
            rec.column_count = 0;
            rec.columns = {};
            rec.modified = '';
            rec.bytes = 0;
            rec.schema = bms.io.StatsSchema.forModule(spec.Key);

            if ~rec.exists
                return;
            end

            info = dir(statsPath);
            if ~isempty(info)
                rec.modified = datestr(info(1).datenum, 'yyyy-mm-dd HH:MM:ss');
                rec.bytes = double(info(1).bytes);
            end

            try
                T = readtable(statsPath, 'VariableNamingRule', 'preserve');
                rec.row_count = height(T);
                rec.column_count = width(T);
                rec.columns = T.Properties.VariableNames;
                if rec.row_count == 0
                    rec.status = 'empty';
                    rec.message = ['Stats file is empty: ' statsPath];
                else
                    rec.status = 'ok';
                    rec.message = '';
                end
            catch ME
                rec.status = 'read_failed';
                rec.message = ME.message;
            end
        end

        function inventory = load(path)
            path = char(string(path));
            inventory = jsondecode(fileread(path));
        end

        function T = rows(inventory)
            moduleKey = {};
            moduleLabel = {};
            statsFile = {};
            status = {};
            rowCount = [];
            columnCount = [];
            existsValue = [];
            modified = {};
            message = {};

            if isstruct(inventory) && isfield(inventory, 'modules')
                modules = bms.app.ManifestReader.recordsToCell(inventory.modules);
                for i = 1:numel(modules)
                    rec = modules{i};
                    if ~isstruct(rec), continue; end
                    moduleKey{end+1, 1} = bms.io.StatsInventory.textField(rec, 'key'); %#ok<AGROW>
                    moduleLabel{end+1, 1} = bms.io.StatsInventory.textField(rec, 'label'); %#ok<AGROW>
                    statsFile{end+1, 1} = bms.io.StatsInventory.textField(rec, 'stats_file'); %#ok<AGROW>
                    status{end+1, 1} = bms.io.StatsInventory.textField(rec, 'status'); %#ok<AGROW>
                    rowCount(end+1, 1) = bms.io.StatsInventory.numField(rec, 'row_count'); %#ok<AGROW>
                    columnCount(end+1, 1) = bms.io.StatsInventory.numField(rec, 'column_count'); %#ok<AGROW>
                    existsValue(end+1, 1) = bms.io.StatsInventory.logicalField(rec, 'exists'); %#ok<AGROW>
                    modified{end+1, 1} = bms.io.StatsInventory.textField(rec, 'modified'); %#ok<AGROW>
                    message{end+1, 1} = bms.io.StatsInventory.textField(rec, 'message'); %#ok<AGROW>
                end
            end

            T = table(moduleKey, moduleLabel, statsFile, status, rowCount, columnCount, existsValue, modified, message, ...
                'VariableNames', {'module_key','module_label','stats_file','status','row_count','column_count','exists','modified','message'});
        end

        function summary = summarize(inventory)
            summary = struct();
            if ~isstruct(inventory), return; end
            fields = {'schema_version','inventory_type','root','stats_dir','created_at','summary'};
            for i = 1:numel(fields)
                if isfield(inventory, fields{i})
                    summary.(fields{i}) = inventory.(fields{i});
                end
            end
            summary.modules = {};
            if isfield(inventory, 'modules')
                modules = bms.app.ManifestReader.recordsToCell(inventory.modules);
                for i = 1:numel(modules)
                    rec = modules{i};
                    if ~isstruct(rec), continue; end
                    out = rec;
                    if isfield(out, 'schema'), out = rmfield(out, 'schema'); end
                    if isfield(out, 'columns'), out = rmfield(out, 'columns'); end
                    summary.modules{end+1} = out; %#ok<AGROW>
                end
            end
        end

        function path = write(root, inventory, runId)
            if nargin < 3 || isempty(runId)
                runId = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
            end
            logDir = bms.data.DataLayoutResolver.logDir(root);
            bms.data.DataLayoutResolver.ensureDir(logDir);
            path = fullfile(logDir, ['stats_inventory_' char(string(runId)) '.json']);
            bms.core.Logger.writeJson(path, inventory);
        end

        function path = writeSummary(root, inventory, runId)
            if nargin < 3 || isempty(runId)
                runId = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
            end
            logDir = bms.data.DataLayoutResolver.logDir(root);
            bms.data.DataLayoutResolver.ensureDir(logDir);
            path = fullfile(logDir, ['stats_inventory_summary_' char(string(runId)) '.xlsx']);
            if isfile(path)
                delete(path);
            end
            bms.io.StatsWriter.writeSheet(bms.io.StatsInventory.rows(inventory), path, 'Stats');
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
