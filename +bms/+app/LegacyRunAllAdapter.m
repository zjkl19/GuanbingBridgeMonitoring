classdef LegacyRunAllAdapter
    %LEGACYRUNALLADAPTER Bridges legacy run_all outputs into app-layer schema.

    methods (Static)
        function summary = buildSummary(root, startDate, endDate, opts, cfg, startTs, elapsed, logs, logfile, offsetLog, statsDir, logDir)
            summary = struct();
            summary.data_root = char(root);
            summary.start_date = char(startDate);
            summary.end_date = char(endDate);
            summary.started_at = datestr(startTs, 'yyyy-mm-dd HH:MM:ss');
            summary.ended_at = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss');
            summary.elapsed_sec = elapsed;
            summary.status = 'ok';
            if bms.app.LegacyRunAllAdapter.hasFailures(logs)
                summary.status = 'failed';
            end
            summary.log_dir = char(logDir);
            summary.log_file = char(logfile);
            summary.stats_dir = char(statsDir);
            summary.config_path = '';
            if isstruct(cfg) && isfield(cfg, 'source') && ~isempty(cfg.source)
                summary.config_path = char(cfg.source);
            end
            enabled = bms.app.StepDefinition.enabledFromOptions(opts);
            summary.enabled_modules = cell(1, numel(enabled));
            expected = {};
            for i = 1:numel(enabled)
                summary.enabled_modules{i} = enabled(i).Key;
                if ~isempty(enabled(i).StatsFile)
                    expected{end+1} = fullfile(statsDir, enabled(i).StatsFile); %#ok<AGROW>
                end
            end
            summary.expected_stats_files = expected;
            summary.module_logs = bms.app.LegacyRunAllAdapter.logsToStructs(logs, statsDir);
            summary.stats_files = bms.app.LegacyRunAllAdapter.listStatsFiles(statsDir);
            summary.offset_report = bms.app.LegacyRunAllAdapter.offsetToStruct(offsetLog);
        end

        function out = logsToStructs(logs, statsDir)
            out = {};
            if isempty(logs), return; end
            for i = 1:numel(logs)
                if isempty(logs{i}) || ~isstruct(logs{i}), continue; end
                label = bms.app.LegacyRunAllAdapter.getText(logs{i}, 'label');
                def = bms.app.StepDefinition.fromLabel(label);
                rec = def.toStruct(statsDir);
                rec.status = bms.app.LegacyRunAllAdapter.getText(logs{i}, 'status');
                rec.message = bms.app.LegacyRunAllAdapter.getText(logs{i}, 'message');
                rec.error_type = bms.app.LegacyRunAllAdapter.getText(logs{i}, 'error_type');
                rec.started_at = bms.app.LegacyRunAllAdapter.getText(logs{i}, 'started_at');
                rec.ended_at = bms.app.LegacyRunAllAdapter.getText(logs{i}, 'ended_at');
                rec.elapsed_sec = bms.app.LegacyRunAllAdapter.getNumber(logs{i}, 'elapsed_sec', NaN);
                if isfield(logs{i}, 'key') && ~isempty(logs{i}.key)
                    rec.key = char(string(logs{i}.key));
                end
                if isfield(logs{i}, 'stats_file') && ~isempty(logs{i}.stats_file)
                    rec.stats_file = char(string(logs{i}.stats_file));
                    if ~isempty(statsDir)
                        rec.stats_path = fullfile(statsDir, rec.stats_file);
                    end
                end
                out{end+1} = rec; %#ok<AGROW>
            end
        end

        function files = listStatsFiles(statsDir)
            files = {};
            if ~exist(statsDir, 'dir'), return; end
            d = dir(fullfile(statsDir, '*.xlsx'));
            d = d(~[d.isdir]);
            for i = 1:numel(d)
                files{end+1} = fullfile(d(i).folder, d(i).name); %#ok<AGROW>
            end
        end

        function offset = offsetToStruct(offsetLog)
            offset = struct('status', '', 'message', '', 'error_type', '', 'filepath', '', 'point_count', NaN);
            if isempty(offsetLog) || ~isstruct(offsetLog), return; end
            offset.status = bms.app.LegacyRunAllAdapter.getText(offsetLog, 'status');
            offset.message = bms.app.LegacyRunAllAdapter.getText(offsetLog, 'message');
            offset.error_type = bms.app.LegacyRunAllAdapter.getText(offsetLog, 'error_type');
            offset.filepath = bms.app.LegacyRunAllAdapter.getText(offsetLog, 'filepath');
            offset.point_count = bms.app.LegacyRunAllAdapter.getNumber(offsetLog, 'point_count', NaN);
        end

        function tf = hasFailures(logs)
            tf = false;
            if isempty(logs), return; end
            for i = 1:numel(logs)
                if isempty(logs{i}) || ~isstruct(logs{i}), continue; end
                if isfield(logs{i}, 'status') && strcmpi(logs{i}.status, 'fail')
                    tf = true;
                    return;
                end
            end
        end

        function txt = getText(s, field)
            txt = '';
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                txt = char(string(s.(field)));
            end
        end

        function val = getNumber(s, field, defaultValue)
            val = defaultValue;
            if isstruct(s) && isfield(s, field) && isnumeric(s.(field)) && isscalar(s.(field))
                val = double(s.(field));
            end
        end
    end
end
