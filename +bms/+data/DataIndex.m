classdef DataIndex
    %DATAINDEX Builds a lightweight source-file index for one run.

    methods (Static)
        function index = build(root, startDate, endDate, cfg, opts)
            if nargin < 4 || isempty(cfg), cfg = struct(); end
            if nargin < 5 || isempty(opts), opts = struct(); end

            root = char(string(root));
            dataSource = bms.data.DataSourceFactory.create(root, cfg);
            specs = bms.data.DataIndex.specsForIndex(opts);

            index = struct();
            index.schema_version = 1;
            index.index_type = 'analysis_data_index';
            index.root = root;
            index.start_date = char(string(startDate));
            index.end_date = char(string(endDate));
            index.created_at = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss');
            index.data_layout = bms.data.DataLayoutResolver.describe(root, cfg);
            index.modules = {};
            index.summary = struct('module_count', 0, 'point_count', 0, 'found_point_count', 0, ...
                'missing_point_count', 0, 'file_count', 0);

            for i = 1:numel(specs)
                spec = specs(i);
                if strcmp(spec.Category, 'preprocess') || strcmp(spec.Key, 'wim') || isempty(spec.SubfolderKey)
                    continue;
                end
                rec = bms.data.DataIndex.moduleRecord(dataSource, spec, root, startDate, endDate, cfg);
                index.modules{end+1} = rec; %#ok<AGROW>
                index.summary.module_count = index.summary.module_count + 1;
                index.summary.point_count = index.summary.point_count + rec.point_count;
                index.summary.found_point_count = index.summary.found_point_count + rec.found_point_count;
                index.summary.missing_point_count = index.summary.missing_point_count + rec.missing_point_count;
                index.summary.file_count = index.summary.file_count + rec.file_count;
            end
        end

        function specs = specsForIndex(opts)
            specs = bms.module.ModuleRegistry.enabledFromOptions(opts);
            if isempty(specs)
                specs = bms.module.ModuleRegistry.forCategory('analysis');
            end
        end

        function rec = moduleRecord(dataSource, spec, root, startDate, endDate, cfg)
            [hasSubfolder, subfolder] = bms.app.RunPreflight.resolveSubfolder(cfg, spec.SubfolderKey);
            if ~hasSubfolder
                subfolder = '';
            end
            points = bms.app.RunPreflight.configuredPoints(cfg, spec.Key);
            patterns = bms.data.DataIndex.patternsForModule(cfg, spec.Key);

            rec = struct();
            rec.key = spec.Key;
            rec.label = spec.Label;
            rec.subfolder = subfolder;
            rec.stats_file = spec.StatsFile;
            rec.point_count = numel(points);
            rec.found_point_count = 0;
            rec.missing_point_count = 0;
            rec.file_count = 0;
            rec.points = {};

            for i = 1:numel(points)
                pointId = char(string(points{i}));
                pointPatterns = bms.data.DataIndex.expandPatterns(patterns, pointId, cfg, spec.Key);
                files = dataSource.findPointFiles(pointId, subfolder, startDate, endDate, pointPatterns);
                pointRec = struct();
                pointRec.point_id = pointId;
                pointRec.safe_id = bms.data.PointResolver.safeId(pointId);
                pointRec.patterns = pointPatterns;
                pointRec.file_count = numel(files);
                pointRec.status = 'missing';
                if pointRec.file_count > 0
                    pointRec.status = 'found';
                    rec.found_point_count = rec.found_point_count + 1;
                else
                    rec.missing_point_count = rec.missing_point_count + 1;
                end
                pointRec.files = bms.data.CacheManager.buildSourceRecords(files);
                pointRec.days = bms.data.DataIndex.daysFromFiles(files, root);
                rec.file_count = rec.file_count + pointRec.file_count;
                rec.points{end+1} = pointRec; %#ok<AGROW>
            end
        end

        function patterns = patternsForModule(cfg, key)
            patterns = {};
            if isstruct(cfg) && isfield(cfg, 'file_patterns') && isstruct(cfg.file_patterns)
                aliases = bms.config.ModuleConfigRegistry.aliasesForKey(key);
                for i = 1:numel(aliases)
                    alias = aliases{i};
                    if isfield(cfg.file_patterns, alias)
                        raw = cfg.file_patterns.(alias);
                        patterns = bms.data.DataIndex.extractDefaultPatterns(raw);
                        if ~isempty(patterns)
                            return;
                        end
                    end
                end
            end
            patterns = {'{point}.csv', '{point}_*.csv', '*{point}*.csv'};
        end

        function patterns = extractDefaultPatterns(raw)
            patterns = {};
            if isempty(raw)
                return;
            elseif ischar(raw) || isstring(raw)
                patterns = cellstr(string(raw));
            elseif iscell(raw)
                patterns = cellstr(string(raw));
            elseif isstruct(raw)
                if isfield(raw, 'default')
                    patterns = bms.data.DataIndex.extractDefaultPatterns(raw.default);
                end
            end
            patterns = reshape(patterns, 1, []);
            patterns = patterns(~cellfun(@isempty, patterns));
        end

        function patterns = expandPatterns(patterns, pointId, cfg, moduleKey)
            pointId = char(string(pointId));
            fileId = regexprep(pointId, '[-_][XYZ]$', '');
            if nargin >= 4
                sensorType = bms.data.DataIndex.sensorTypeForPoint(moduleKey, pointId);
                fileId = bms.data.TimeSeriesLoader.resolveFileId(cfg, sensorType, pointId);
                fileId = regexprep(fileId, '[-_][XYZ]$', '');
            end
            out = {};
            for i = 1:numel(patterns)
                p = char(string(patterns{i}));
                p = strrep(p, '{point}', pointId);
                p = strrep(p, '{file_id}', fileId);
                out{end+1} = p; %#ok<AGROW>
            end
            out{end+1} = [pointId '.csv']; %#ok<AGROW>
            out = unique(out(~cellfun(@isempty, out)), 'stable');
            patterns = reshape(out, 1, []);
        end

        function sensorType = sensorTypeForPoint(moduleKey, pointId)
            sensorType = char(string(moduleKey));
            switch sensorType
                case 'accel_spectrum'
                    sensorType = 'acceleration';
                case 'cable_accel_spectrum'
                    sensorType = 'cable_accel';
                case {'dynamic_strain', 'dynamic_strain_highpass', 'dynamic_strain_lowpass'}
                    sensorType = 'strain';
                case 'earthquake'
                    [sensorType, ~] = bms.analyzer.EarthquakeSeriesService.componentFromPoint(pointId);
                case 'wind'
                    sensorType = 'wind_speed';
            end
        end

        function days = daysFromFiles(files, root)
            %#ok<INUSD> root is kept for backward-compatible call sites.
            if ischar(files) || isstring(files), files = cellstr(string(files)); end
            days = {};
            for i = 1:numel(files)
                p = char(string(files{i}));
                token = regexp(p, '(\d{4})[-_]?(\d{2})[-_]?(\d{2})', 'tokens', 'once');
                if ~isempty(token)
                    days{end+1} = sprintf('%s-%s-%s', token{1}, token{2}, token{3}); %#ok<AGROW>
                end
            end
            days = unique(days, 'stable');
        end

        function index = load(path)
            path = char(string(path));
            index = jsondecode(fileread(path));
        end

        function T = moduleRows(index)
            moduleKey = {};
            moduleLabel = {};
            pointCount = [];
            foundPointCount = [];
            missingPointCount = [];
            fileCount = [];

            if isstruct(index) && isfield(index, 'modules')
                modules = bms.app.ManifestReader.recordsToCell(index.modules);
                for i = 1:numel(modules)
                    rec = modules{i};
                    if ~isstruct(rec), continue; end
                    moduleKey{end+1, 1} = bms.data.DataIndex.textField(rec, 'key'); %#ok<AGROW>
                    moduleLabel{end+1, 1} = bms.data.DataIndex.textField(rec, 'label'); %#ok<AGROW>
                    pointCount(end+1, 1) = bms.data.DataIndex.numField(rec, 'point_count'); %#ok<AGROW>
                    foundPointCount(end+1, 1) = bms.data.DataIndex.numField(rec, 'found_point_count'); %#ok<AGROW>
                    missingPointCount(end+1, 1) = bms.data.DataIndex.numField(rec, 'missing_point_count'); %#ok<AGROW>
                    fileCount(end+1, 1) = bms.data.DataIndex.numField(rec, 'file_count'); %#ok<AGROW>
                end
            end

            T = table(moduleKey, moduleLabel, pointCount, foundPointCount, missingPointCount, fileCount, ...
                'VariableNames', {'module_key','module_label','point_count','found_point_count','missing_point_count','file_count'});
        end

        function T = pointRows(index)
            moduleKey = {};
            moduleLabel = {};
            pointId = {};
            status = {};
            fileCount = [];
            days = {};
            firstFile = {};

            if isstruct(index) && isfield(index, 'modules')
                modules = bms.app.ManifestReader.recordsToCell(index.modules);
                for i = 1:numel(modules)
                    rec = modules{i};
                    if ~isstruct(rec) || ~isfield(rec, 'points'), continue; end
                    points = bms.app.ManifestReader.recordsToCell(rec.points);
                    for j = 1:numel(points)
                        point = points{j};
                        if ~isstruct(point), continue; end
                        moduleKey{end+1, 1} = bms.data.DataIndex.textField(rec, 'key'); %#ok<AGROW>
                        moduleLabel{end+1, 1} = bms.data.DataIndex.textField(rec, 'label'); %#ok<AGROW>
                        pointId{end+1, 1} = bms.data.DataIndex.textField(point, 'point_id'); %#ok<AGROW>
                        status{end+1, 1} = bms.data.DataIndex.textField(point, 'status'); %#ok<AGROW>
                        fileCount(end+1, 1) = bms.data.DataIndex.numField(point, 'file_count'); %#ok<AGROW>
                        days{end+1, 1} = bms.data.DataIndex.joinTextList(bms.data.DataIndex.fieldValue(point, 'days', {})); %#ok<AGROW>
                        firstFile{end+1, 1} = bms.data.DataIndex.firstSourcePath(point); %#ok<AGROW>
                    end
                end
            end

            T = table(moduleKey, moduleLabel, pointId, status, fileCount, days, firstFile, ...
                'VariableNames', {'module_key','module_label','point_id','status','file_count','days','first_file'});
        end

        function T = missingPointRows(index)
            T = bms.data.DataIndex.pointRows(index);
            if ~isempty(T)
                T = T(strcmp(T.status, 'missing'), :);
            end
        end

        function summary = summarize(index)
            summary = struct();
            if ~isstruct(index)
                return;
            end
            fields = {'schema_version','index_type','root','start_date','end_date','created_at','data_layout','summary'};
            for i = 1:numel(fields)
                if isfield(index, fields{i})
                    summary.(fields{i}) = index.(fields{i});
                end
            end
            summary.modules = {};
            if isfield(index, 'modules')
                modules = bms.app.ManifestReader.recordsToCell(index.modules);
                for i = 1:numel(modules)
                    rec = modules{i};
                    if ~isstruct(rec), continue; end
                    removeFields = intersect(fieldnames(rec), {'points'});
                    out = rec;
                    if ~isempty(removeFields)
                        out = rmfield(out, removeFields);
                    end
                    summary.modules{end+1} = out; %#ok<AGROW>
                end
            end
        end

        function path = write(root, index, runId)
            if nargin < 3 || isempty(runId)
                runId = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
            end
            logDir = bms.data.DataLayoutResolver.logDir(root);
            bms.data.DataLayoutResolver.ensureDir(logDir);
            path = fullfile(logDir, ['data_index_' char(string(runId)) '.json']);
            bms.core.Logger.writeJson(path, index);
        end


        function path = writeSummary(root, index, runId)
            if nargin < 3 || isempty(runId)
                runId = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
            end
            logDir = bms.data.DataLayoutResolver.logDir(root);
            bms.data.DataLayoutResolver.ensureDir(logDir);
            path = fullfile(logDir, ['data_index_summary_' char(string(runId)) '.xlsx']);
            if isfile(path)
                delete(path);
            end
            bms.io.StatsWriter.writeSheet(bms.data.DataIndex.moduleRows(index), path, 'Modules');
            bms.io.StatsWriter.writeSheet(bms.data.DataIndex.pointRows(index), path, 'Points');
            bms.io.StatsWriter.writeSheet(bms.data.DataIndex.missingPointRows(index), path, 'MissingPoints');
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

        function value = fieldValue(s, field, fallback)
            value = fallback;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                value = s.(field);
            end
        end

        function text = joinTextList(value)
            text = '';
            if isempty(value), return; end
            if ischar(value) || isstring(value)
                items = cellstr(string(value));
            elseif iscell(value)
                items = cellstr(string(value));
            else
                try
                    items = cellstr(string(value(:)));
                catch
                    items = {};
                end
            end
            items = items(~cellfun(@isempty, items));
            text = strjoin(items, ', ');
        end

        function path = firstSourcePath(point)
            path = '';
            files = bms.data.DataIndex.fieldValue(point, 'files', {});
            files = bms.app.ManifestReader.recordsToCell(files);
            if isempty(files), return; end
            first = files{1};
            if isstruct(first)
                path = bms.data.DataIndex.textField(first, 'path');
            elseif ischar(first) || isstring(first)
                path = char(string(first));
            end
        end
    end
end
