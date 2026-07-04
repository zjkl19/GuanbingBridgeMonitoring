classdef HongtangLowFreqSyncService
    %HONGTANGLOWFREQSYNCSERVICE Builds/extends Hongtang lowfreq/data.xlsx.

    methods (Static)
        function result = run(root, startDate, endDate, cfg)
            if nargin < 4, cfg = struct(); end
            startedAt = datetime('now');
            manifestPath = '';
            try
                options = bms.data.HongtangLowFreqSyncService.optionsFromConfig(root, cfg);
                if ~options.enabled
                    result = bms.analyzer.AnalyzerResult.ok( ...
                        'lowfreq_sync', '', {}, {}, startedAt, datetime('now'), 'lowfreq sync disabled');
                    return;
                end

                bms.core.PathResolver.ensureDir(fileparts(options.output_file));
                copiedTemplate = false;
                if ~isfile(options.output_file)
                    if isempty(options.template_file) || ~isfile(options.template_file)
                        error('BMS:HongtangLowFreqSync:TemplateMissing', ...
                            'lowfreq/data.xlsx is missing and template was not found: %s', options.template_file);
                    end
                    copyfile(options.template_file, options.output_file);
                    copiedTemplate = true;
                end

                [headers, timeCol, existingLastTime, existingRows] = ...
                    bms.data.HongtangLowFreqSyncService.readWorkbookState(options.output_file, options.time_column);
                [rangeStart, rangeEnd] = bms.data.TimeRangeResolver.closedRange(startDate, endDate);
                appendStart = dateshift(rangeStart, 'start', 'hour');
                if ~isnat(existingLastTime)
                    appendStart = max(appendStart, dateshift(existingLastTime, 'start', 'hour') + hours(1));
                end
                appendEnd = dateshift(rangeEnd, 'start', 'hour');

                stats = bms.data.HongtangLowFreqSyncService.emptyStats();
                columnMap = struct([]);
                deviceIds = {};
                if appendStart <= appendEnd
                    credentials = bms.data.HongtangLowFreqSyncService.resolveCredentials(options.credentials_file);
                    client = bms.data.JikangClient(credentials, ...
                        'Timeout', options.request_timeout_sec, 'MaxPages', options.max_pages);
                    deviceIds = bms.data.HongtangLowFreqSyncService.resolveDeviceIds(client, options);
                    sensors = bms.data.HongtangLowFreqSyncService.loadSensorIndex(client, deviceIds);
                    columnMap = bms.data.HongtangLowFreqSyncService.buildColumnMap(headers, sensors, options);
                    times = (appendStart:hours(1):appendEnd)';
                    [rows, stats] = bms.data.HongtangLowFreqSyncService.buildRows(client, times, headers, columnMap, options);
                    if ~isempty(rows)
                        range = sprintf('A%d', existingRows + 1);
                        writecell(rows, options.output_file, 'Sheet', 1, 'Range', range);
                    end
                end

                manifestPath = bms.data.HongtangLowFreqSyncService.writeManifest( ...
                    root, options, copiedTemplate, existingLastTime, appendStart, appendEnd, ...
                    headers, timeCol, columnMap, deviceIds, stats, 'ok', '');
                artifacts = { ...
                    struct('kind', 'data', 'path', options.output_file, 'role', 'lowfreq_workbook'), ...
                    struct('kind', 'manifest', 'path', manifestPath, 'role', 'lowfreq_sync_manifest')};
                message = sprintf('appended_rows=%d; filled_values=%d; missing_values=%d', ...
                    stats.appended_rows, stats.filled_values, stats.missing_values);
                result = bms.analyzer.AnalyzerResult.ok( ...
                    'lowfreq_sync', options.output_file, artifacts, {}, startedAt, datetime('now'), message);
            catch ME
                endedAt = datetime('now');
                if isempty(manifestPath)
                    try
                        options = bms.data.HongtangLowFreqSyncService.optionsFromConfig(root, cfg);
                        manifestPath = bms.data.HongtangLowFreqSyncService.writeFailureManifest(root, options, ME);
                    catch
                    end
                end
                result = bms.analyzer.AnalyzerResult.fail('lowfreq_sync', ME.message, manifestPath, startedAt, endedAt);
            end
        end

        function options = optionsFromConfig(root, cfg)
            section = struct();
            if isstruct(cfg) && isfield(cfg, 'lowfreq_sync') && isstruct(cfg.lowfreq_sync)
                section = cfg.lowfreq_sync;
            end
            projectRoot = bms.core.PathResolver.projectRoot();
            defaultTemplate = fullfile('..', ['2026' char(24180) '1-3' char(26376)], 'lowfreq', 'data.xlsx');

            options = struct();
            options.enabled = bms.data.HongtangLowFreqSyncService.fieldBool(section, 'enabled', true);
            options.output_file = bms.data.HongtangLowFreqSyncService.resolvePath( ...
                root, bms.data.HongtangLowFreqSyncService.fieldText(section, 'output_file', fullfile('lowfreq', 'data.xlsx')));
            options.template_file = bms.data.HongtangLowFreqSyncService.resolvePath( ...
                root, bms.data.HongtangLowFreqSyncService.fieldText(section, 'template_file', defaultTemplate));
            options.credentials_file = bms.data.HongtangLowFreqSyncService.resolvePath( ...
                projectRoot, bms.data.HongtangLowFreqSyncService.fieldText(section, 'credentials_file', ...
                fullfile('config', 'jikang_credentials.local.json')));
            options.project_id = bms.data.HongtangLowFreqSyncService.fieldText(section, 'project_id', '1218');
            options.device_ids = bms.data.HongtangLowFreqSyncService.fieldCellstr(section, 'device_ids', {});
            options.fetch_chunk_days = bms.data.HongtangLowFreqSyncService.fieldDouble(section, 'fetch_chunk_days', 1);
            options.request_timeout_sec = bms.data.HongtangLowFreqSyncService.fieldDouble(section, 'request_timeout_sec', 60);
            options.max_pages = bms.data.HongtangLowFreqSyncService.fieldDouble(section, 'max_pages', 10000);
            options.time_column = bms.data.HongtangLowFreqSyncService.fieldText(section, 'time_column', 'SamplingTime');
            options.missing_token = bms.data.HongtangLowFreqSyncService.fieldText(section, 'missing_token', '--');
            options.manifest_dir = bms.data.HongtangLowFreqSyncService.resolvePath( ...
                root, bms.data.HongtangLowFreqSyncService.fieldText(section, 'manifest_dir', 'run_logs'));
            options.round_digits = bms.data.HongtangLowFreqSyncService.roundDigits(section);
            options.tilt_vertical_param_num = bms.data.HongtangLowFreqSyncService.fieldDouble(section, 'tilt_vertical_param_num', 1);
            options.tilt_horizontal_param_num = bms.data.HongtangLowFreqSyncService.fieldDouble(section, 'tilt_horizontal_param_num', 2);
            options.primary_param_num = bms.data.HongtangLowFreqSyncService.fieldDouble(section, 'primary_param_num', 1);
        end

        function [headers, timeCol, lastTime, rowCount] = readWorkbookState(path, timeColumn)
            C = readcell(path, 'Sheet', 1);
            if isempty(C) || size(C, 1) < 1
                error('BMS:HongtangLowFreqSync:EmptyWorkbook', 'lowfreq workbook is empty: %s', path);
            end
            headers = cellstr(strtrim(string(C(1, :))));
            lastHeader = find(strlength(string(headers)) > 0, 1, 'last');
            if isempty(lastHeader)
                error('BMS:HongtangLowFreqSync:MissingHeader', 'lowfreq workbook has no header row: %s', path);
            end
            headers = headers(1:lastHeader);
            C = C(:, 1:lastHeader);
            idx = find(strcmpi(headers, timeColumn), 1);
            if isempty(idx)
                idx = 1;
            end
            timeCol = idx;
            rowCount = size(C, 1);
            lastTime = NaT;
            if rowCount < 2
                return;
            end
            times = bms.data.HongtangLowFreqSyncService.parseTimeCells(C(2:end, timeCol));
            valid = times(~isnat(times));
            if ~isempty(valid)
                lastTime = max(valid);
            end
        end

        function deviceIds = resolveDeviceIds(client, options)
            deviceIds = options.device_ids;
            if ~isempty(deviceIds)
                return;
            end
            rows = client.listDevices(options.project_id);
            deviceIds = cell(1, numel(rows));
            for i = 1:numel(rows)
                deviceIds{i} = bms.data.HongtangLowFreqSyncService.firstText( ...
                    rows(i), {'mcuCode','idCode','deviceId','rtuId','id'}, '');
            end
            deviceIds = deviceIds(~cellfun(@isempty, deviceIds));
            if isempty(deviceIds)
                error('BMS:HongtangLowFreqSync:NoDevices', ...
                    'No Jikang devices found for project %s.', options.project_id);
            end
        end

        function sensors = loadSensorIndex(client, deviceIds)
            sensors = struct([]);
            for i = 1:numel(deviceIds)
                rows = client.listSensors(deviceIds{i});
                flat = bms.data.HongtangLowFreqSyncService.flattenSensors(deviceIds{i}, rows);
                sensors = bms.data.HongtangLowFreqSyncService.concatStruct(sensors, flat);
            end
            if isempty(sensors)
                error('BMS:HongtangLowFreqSync:NoSensors', 'No Jikang sensors were returned.');
            end
        end

        function sensors = flattenSensors(deviceId, rows)
            sensors = struct([]);
            for i = 1:numel(rows)
                row = rows(i);
                parentName = bms.data.HongtangLowFreqSyncService.firstText( ...
                    row, {'sensorName','name','paraName','parameterName'}, '');
                if isfield(row, 'paraidInfos') && ~isempty(row.paraidInfos)
                    infos = row.paraidInfos;
                    if iscell(infos)
                        infos = [infos{:}];
                    end
                    for k = 1:numel(infos)
                        sensors = bms.data.HongtangLowFreqSyncService.concatStruct( ...
                            sensors, bms.data.HongtangLowFreqSyncService.sensorRecord(deviceId, parentName, infos(k)));
                    end
                else
                    sensors = bms.data.HongtangLowFreqSyncService.concatStruct( ...
                        sensors, bms.data.HongtangLowFreqSyncService.sensorRecord(deviceId, parentName, row));
                end
            end
        end

        function rec = sensorRecord(deviceId, parentName, item)
            if isempty(parentName)
                parentName = bms.data.HongtangLowFreqSyncService.firstText( ...
                    item, {'sensorName','name','paraName','parameterName'}, '');
            end
            rec = struct();
            rec.device_id = char(string(deviceId));
            rec.base_name = char(string(parentName));
            rec.para_id = bms.data.HongtangLowFreqSyncService.firstText( ...
                item, {'paraId','paraid','parameterId','sensorId','id'}, '');
            rec.param_num = bms.data.HongtangLowFreqSyncService.firstNumber(item, {'paramNum','paraNum'}, NaN);
            rec.para_type = bms.data.HongtangLowFreqSyncService.firstNumber(item, {'paraType','parameterType'}, NaN);
            rec.unit = bms.data.HongtangLowFreqSyncService.firstText(item, {'unit','unitName'}, '');
            rec.unit_name = bms.data.HongtangLowFreqSyncService.firstText(item, {'unitName','unit'}, '');
        end

        function columnMap = buildColumnMap(headers, sensors, options)
            columnMap = repmat(bms.data.HongtangLowFreqSyncService.emptyColumnMap(), 1, numel(headers));
            for c = 1:numel(headers)
                rule = bms.data.HongtangLowFreqSyncService.columnRule(headers{c}, options);
                rec = bms.data.HongtangLowFreqSyncService.emptyColumnMap();
                rec.column = c;
                rec.header = headers{c};
                rec.base_name = rule.base_name;
                rec.kind = rule.kind;
                rec.round_digits = rule.round_digits;
                if c == 1 || isempty(rule.base_name)
                    columnMap(c) = rec;
                    continue;
                end
                match = bms.data.HongtangLowFreqSyncService.selectSensor(sensors, rule);
                if ~isempty(match)
                    rec.device_id = match.device_id;
                    rec.para_id = match.para_id;
                    rec.param_num = match.param_num;
                    rec.para_type = match.para_type;
                end
                columnMap(c) = rec;
            end
        end

        function [rows, stats] = buildRows(client, times, headers, columnMap, options)
            stats = bms.data.HongtangLowFreqSyncService.emptyStats();
            stats.appended_rows = numel(times);
            if isempty(times)
                rows = {};
                return;
            end

            sampleMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
            mapped = columnMap(~cellfun(@isempty, {columnMap.para_id}));
            deviceIds = unique({mapped.device_id}, 'stable');
            for i = 1:numel(deviceIds)
                deviceId = deviceIds{i};
                chunks = bms.data.HongtangLowFreqSyncService.dateChunks(min(times), max(times), options.fetch_chunk_days);
                for k = 1:size(chunks, 1)
                    raw = client.fetchSamples(deviceId, chunks(k, 1), chunks(k, 2));
                    [deduped, dropped] = bms.data.HongtangLowFreqSyncService.dedupeSamples(raw);
                    stats.samples_fetched = stats.samples_fetched + numel(raw);
                    stats.duplicate_samples_dropped = stats.duplicate_samples_dropped + dropped;
                    for r = 1:numel(deduped)
                        key = bms.data.HongtangLowFreqSyncService.sampleKey( ...
                            deduped(r).para_id, deduped(r).collect_time);
                        sampleMap(key) = deduped(r);
                    end
                end
            end

            rows = cell(numel(times), numel(headers));
            for r = 1:numel(times)
                rows{r, 1} = datestr(times(r), 'yyyy-mm-dd HH:MM:SS');
                for c = 2:numel(headers)
                    rows{r, c} = options.missing_token;
                    if isempty(columnMap(c).para_id)
                        continue;
                    end
                    key = bms.data.HongtangLowFreqSyncService.sampleKey(columnMap(c).para_id, times(r));
                    if ~isKey(sampleMap, key)
                        continue;
                    end
                    value = sampleMap(key).value;
                    if isempty(value) || (isnumeric(value) && (~isfinite(value) || isnan(value)))
                        continue;
                    end
                    if isnumeric(value)
                        rows{r, c} = round(double(value), columnMap(c).round_digits);
                    else
                        rows{r, c} = value;
                    end
                    stats.filled_values = stats.filled_values + 1;
                end
            end
            stats.expected_values = max(0, numel(times) * (numel(headers) - 1));
            stats.missing_values = stats.expected_values - stats.filled_values;
            stats.mapped_columns = sum(~cellfun(@isempty, {columnMap.para_id}));
            stats.unmapped_columns = max(0, numel(headers) - 1 - stats.mapped_columns);
        end

        function [records, dropped] = dedupeSamples(rows)
            records = struct([]);
            dropped = 0;
            best = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for i = 1:numel(rows)
                rec = bms.data.HongtangLowFreqSyncService.sampleRecord(rows(i));
                if isempty(rec.para_id) || isnat(rec.collect_time)
                    continue;
                end
                key = bms.data.HongtangLowFreqSyncService.sampleKey(rec.para_id, rec.collect_time);
                if ~isKey(best, key)
                    best(key) = rec;
                    continue;
                end
                old = best(key);
                dropped = dropped + 1;
                if bms.data.HongtangLowFreqSyncService.isNewerSample(rec, old)
                    best(key) = rec;
                end
            end
            keys = best.keys;
            for i = 1:numel(keys)
                records = bms.data.HongtangLowFreqSyncService.concatStruct(records, best(keys{i}));
            end
        end

        function rec = sampleRecord(row)
            rec = struct();
            rec.para_id = bms.data.HongtangLowFreqSyncService.firstText( ...
                row, {'paraId','paraid','parameterId','sensorId'}, '');
            collectText = bms.data.HongtangLowFreqSyncService.firstText( ...
                row, {'collectTime','time','timestamp','systemTime'}, '');
            systemText = bms.data.HongtangLowFreqSyncService.firstText(row, {'systemTime'}, collectText);
            rec.collect_time = bms.data.JikangClient.parseDateTime(collectText);
            rec.system_time = bms.data.JikangClient.parseDateTime(systemText);
            rec.value = bms.data.HongtangLowFreqSyncService.parseValue( ...
                bms.data.HongtangLowFreqSyncService.firstAny(row, {'paraValue','value','dataValue'}, []));
        end

        function rule = columnRule(header, options)
            h = char(string(header));
            rule = struct('base_name', h, 'param_num', options.primary_param_num, ...
                'kind', 'strain', 'round_digits', options.round_digits.strain);
            if strcmpi(strtrim(h), options.time_column)
                rule.base_name = '';
                rule.kind = 'time';
                return;
            end
            tok = regexp(h, '^(Q\d+)[-_]([ZH])$', 'tokens', 'once');
            if ~isempty(tok)
                rule.base_name = tok{1};
                rule.kind = 'tilt';
                rule.round_digits = options.round_digits.tilt;
                if strcmpi(tok{2}, 'H')
                    rule.param_num = options.tilt_horizontal_param_num;
                else
                    rule.param_num = options.tilt_vertical_param_num;
                end
                return;
            end
            if ~isempty(regexp(h, '^Z\d+[-_]\d+', 'once'))
                rule.kind = 'displacement';
                rule.round_digits = options.round_digits.displacement;
                rule.param_num = options.primary_param_num;
            end
        end

        function match = selectSensor(sensors, rule)
            match = [];
            if isempty(sensors)
                return;
            end
            target = bms.data.HongtangLowFreqSyncService.normName(rule.base_name);
            keep = false(1, numel(sensors));
            for i = 1:numel(sensors)
                keep(i) = strcmp(bms.data.HongtangLowFreqSyncService.normName(sensors(i).base_name), target);
            end
            candidates = sensors(keep);
            if isempty(candidates)
                return;
            end
            exact = candidates;
            if ~isnan(rule.param_num)
                byParam = candidates([candidates.param_num] == rule.param_num);
                if ~isempty(byParam)
                    exact = byParam;
                end
            end
            match = exact(1);
        end

        function chunks = dateChunks(startTime, endTime, chunkDays)
            chunkDays = max(1, double(chunkDays));
            chunks = NaT(0, 2);
            cursor = startTime;
            while cursor <= endTime
                stopTime = min(endTime, cursor + days(chunkDays) - seconds(1));
                chunks = [chunks; cursor, stopTime]; %#ok<AGROW>
                cursor = stopTime + seconds(1);
            end
        end

        function credentials = resolveCredentials(credentialsFile)
            credentials = struct();
            credentials.base_url = char(string(getenv('JIKANG_BASE_URL')));
            credentials.username = char(string(getenv('JIKANG_USERNAME')));
            credentials.password = char(string(getenv('JIKANG_PASSWORD')));
            credentials.token = char(string(getenv('JIKANG_TOKEN')));

            if (isempty(credentials.base_url) || isempty(credentials.username) || isempty(credentials.password)) && ...
                    ~isempty(credentialsFile) && isfile(credentialsFile)
                fileCreds = jsondecode(fileread(credentialsFile));
                credentials.base_url = bms.data.HongtangLowFreqSyncService.fieldText(fileCreds, 'base_url', credentials.base_url);
                credentials.username = bms.data.HongtangLowFreqSyncService.fieldText(fileCreds, 'username', credentials.username);
                credentials.password = bms.data.HongtangLowFreqSyncService.fieldText(fileCreds, 'password', credentials.password);
                credentials.token = bms.data.HongtangLowFreqSyncService.fieldText(fileCreds, 'token', credentials.token);
            end
        end

        function manifestPath = writeManifest(root, options, copiedTemplate, existingLastTime, appendStart, appendEnd, headers, timeCol, columnMap, deviceIds, stats, status, message)
            manifest = struct();
            manifest.schema_version = 1;
            manifest.manifest_type = 'hongtang_lowfreq_sync';
            manifest.status = status;
            manifest.message = message;
            manifest.created_at = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:SS');
            manifest.data_root = root;
            manifest.output_file = options.output_file;
            manifest.template_file = options.template_file;
            manifest.copied_template = logical(copiedTemplate);
            manifest.existing_last_time = bms.data.HongtangLowFreqSyncService.formatTime(existingLastTime);
            manifest.append_start = bms.data.HongtangLowFreqSyncService.formatTime(appendStart);
            manifest.append_end = bms.data.HongtangLowFreqSyncService.formatTime(appendEnd);
            manifest.time_column_index = timeCol;
            manifest.headers = headers;
            manifest.project_id = options.project_id;
            manifest.device_ids = deviceIds;
            manifest.column_count = numel(headers);
            manifest.mapped_columns = stats.mapped_columns;
            manifest.unmapped_columns = stats.unmapped_columns;
            manifest.unmapped_headers = bms.data.HongtangLowFreqSyncService.unmappedHeaders(columnMap);
            manifest.stats = stats;
            manifestPath = fullfile(options.manifest_dir, ...
                ['hongtang_lowfreq_sync_' datestr(datetime('now'), 'yyyymmdd_HHMMSS') '.json']);
            bms.core.Logger.writeJson(manifestPath, manifest);
        end

        function manifestPath = writeFailureManifest(root, options, ME)
            stats = bms.data.HongtangLowFreqSyncService.emptyStats();
            manifestPath = bms.data.HongtangLowFreqSyncService.writeManifest( ...
                root, options, false, NaT, NaT, NaT, {}, 0, struct([]), {}, stats, 'fail', ME.message);
        end
    end

    methods (Static, Access = private)
        function stats = emptyStats()
            stats = struct();
            stats.appended_rows = 0;
            stats.expected_values = 0;
            stats.filled_values = 0;
            stats.missing_values = 0;
            stats.samples_fetched = 0;
            stats.duplicate_samples_dropped = 0;
            stats.mapped_columns = 0;
            stats.unmapped_columns = 0;
        end

        function rec = emptyColumnMap()
            rec = struct('column', 0, 'header', '', 'base_name', '', 'kind', '', ...
                'device_id', '', 'para_id', '', 'param_num', NaN, 'para_type', NaN, 'round_digits', 3);
        end

        function digits = roundDigits(section)
            digits = struct('tilt', 3, 'strain', 3, 'displacement', 4);
            if isstruct(section) && isfield(section, 'round_digits') && isstruct(section.round_digits)
                digits.tilt = bms.data.HongtangLowFreqSyncService.fieldDouble(section.round_digits, 'tilt', digits.tilt);
                digits.strain = bms.data.HongtangLowFreqSyncService.fieldDouble(section.round_digits, 'strain', digits.strain);
                digits.displacement = bms.data.HongtangLowFreqSyncService.fieldDouble(section.round_digits, 'displacement', digits.displacement);
            end
        end

        function out = parseTimeCells(raw)
            out = NaT(size(raw));
            for i = 1:numel(raw)
                value = raw{i};
                if isempty(value) || (isnumeric(value) && isscalar(value) && isnan(value))
                    continue;
                end
                if isnumeric(value)
                    try
                        out(i) = datetime(value, 'ConvertFrom', 'excel');
                    catch
                    end
                else
                    out(i) = bms.data.JikangClient.parseDateTime(value);
                end
            end
        end

        function value = parseValue(raw)
            value = [];
            if isempty(raw)
                return;
            end
            if isnumeric(raw)
                value = double(raw);
                return;
            end
            text = strtrim(char(string(raw)));
            if isempty(text) || any(strcmpi(text, {'--','null','none','nan'}))
                return;
            end
            num = str2double(text);
            if ~isnan(num)
                value = num;
            else
                value = text;
            end
        end

        function key = sampleKey(paraId, timeValue)
            key = [char(string(paraId)) '|' datestr(timeValue, 'yyyy-mm-dd HH:MM:SS')];
        end

        function tf = isNewerSample(newRec, oldRec)
            tf = false;
            if isnat(oldRec.system_time)
                tf = true;
            elseif ~isnat(newRec.system_time) && newRec.system_time >= oldRec.system_time
                tf = true;
            end
        end

        function out = unmappedHeaders(columnMap)
            out = {};
            for i = 1:numel(columnMap)
                if i == 1
                    continue;
                end
                if isempty(columnMap(i).para_id)
                    out{end+1} = columnMap(i).header; %#ok<AGROW>
                end
            end
        end

        function text = formatTime(value)
            if isempty(value) || (isa(value, 'datetime') && isnat(value))
                text = '';
            else
                text = datestr(value, 'yyyy-mm-dd HH:MM:SS');
            end
        end

        function value = fieldText(s, field, fallback)
            value = fallback;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                value = char(string(s.(field)));
            end
        end

        function value = fieldBool(s, field, fallback)
            value = fallback;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                value = bms.config.ConfigReader.boolValue(s.(field), fallback);
            end
        end

        function value = fieldDouble(s, field, fallback)
            value = fallback;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                value = double(s.(field));
            end
        end

        function value = fieldCellstr(s, field, fallback)
            value = fallback;
            if ~isstruct(s) || ~isfield(s, field) || isempty(s.(field))
                return;
            end
            raw = s.(field);
            if iscell(raw)
                value = cellstr(string(raw));
            elseif ischar(raw) || isstring(raw)
                value = cellstr(string(raw));
            else
                value = cellstr(string(raw(:)));
            end
            value = value(~cellfun(@isempty, value));
        end

        function value = firstAny(s, fields, fallback)
            value = fallback;
            for i = 1:numel(fields)
                f = fields{i};
                if isstruct(s) && isfield(s, f) && ~isempty(s.(f))
                    value = s.(f);
                    return;
                end
            end
        end

        function value = firstText(s, fields, fallback)
            value = fallback;
            raw = bms.data.HongtangLowFreqSyncService.firstAny(s, fields, []);
            if ~isempty(raw)
                value = char(string(raw));
            end
        end

        function value = firstNumber(s, fields, fallback)
            value = fallback;
            raw = bms.data.HongtangLowFreqSyncService.firstAny(s, fields, []);
            if isempty(raw)
                return;
            end
            value = str2double(char(string(raw)));
            if isnan(value) && isnumeric(raw)
                value = double(raw);
            end
        end

        function out = concatStruct(a, b)
            if isempty(a)
                out = b;
            elseif isempty(b)
                out = a;
            else
                out = [a(:); b(:)];
            end
        end

        function n = normName(value)
            n = lower(regexprep(char(string(value)), '[\s_\-]', ''));
        end

        function p = resolvePath(base, p)
            if isempty(p)
                return;
            end
            p = char(string(p));
            if ~bms.data.HongtangLowFreqDataSource.isAbsolutePath(p)
                p = fullfile(base, p);
            end
            try
                p = char(java.io.File(p).getCanonicalPath());
            catch
            end
        end
    end
end
