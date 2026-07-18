classdef ThresholdCurveRecordService
    %THRESHOLDCURVERECORDSERVICE Load and serialize one manual-cleaning curve.
    %
    % This service deliberately contains no threshold/proposal algorithm.  It
    % is the shared data-loading boundary used by both the lightweight curve
    % request and the independent Beta auto-threshold request.

    methods (Static)
        function opts = defaultOptions()
            opts = struct( ...
                'ignore_existing_cleaning', true, ...
                'prefer_mat_cache', true, ...
                'preview_sample_count', 20000);
        end

        function [curve, times, values, loadMeta] = generate( ...
                cfg, rootDir, startDate, endDate, moduleKey, pointId, opts)
            if nargin < 7 || isempty(opts)
                opts = struct();
            end
            opts = bms.config.ThresholdCurveRecordService.mergeOptions( ...
                bms.config.ThresholdCurveRecordService.defaultOptions(), opts);
            moduleKey = bms.config.ThresholdCurveRecordService.singleText( ...
                moduleKey, 'module_key');
            pointId = bms.config.ThresholdCurveRecordService.singleText( ...
                pointId, 'point_id');
            rootDir = bms.config.ThresholdCurveRecordService.canonicalPath(rootDir);
            if ~isfolder(rootDir)
                error('BMS:ThresholdCurve:DataRootMissing', ...
                    'Curve data root does not exist: %s', rootDir);
            end
            startText = bms.data.TimeRangeResolver.normalizeDateText(startDate);
            endText = bms.data.TimeRangeResolver.normalizeDateText(endDate);
            bms.data.TimeRangeResolver.parseRange(startText, endText);

            [~, subfolder, configuredPointId] = ...
                bms.config.ThresholdCurveRecordService.resolveConfiguredPoint( ...
                    cfg, moduleKey, pointId);
            sensorType = bms.config.ThresholdCurveRecordService.sensorTypeForPoint( ...
                moduleKey, configuredPointId);
            cfgForLoad = cfg;
            if bms.config.ThresholdCurveRecordService.boolOpt( ...
                    opts, 'ignore_existing_cleaning', true)
                cfgForLoad = bms.config.ThresholdCurveRecordService. ...
                    disableCleaningRules(cfgForLoad, {moduleKey});
            end
            if bms.config.ThresholdCurveRecordService.boolOpt( ...
                    opts, 'prefer_mat_cache', true)
                cfgForLoad = bms.config.ThresholdCurveRecordService. ...
                    preferMatCache(cfgForLoad);
            end

            bms.app.StopController.throwIfRequested( ...
                'Curve generation stopped before loading the selected point.');
            bms.app.RunProgressReporter.checkpoint( ...
                'stage', 'load_curve', ...
                'current_point_id', configuredPointId, ...
                'current_date', '', ...
                'processed_dates', 0, ...
                'total_dates', bms.config.ThresholdCurveRecordService. ...
                    dateCount(startText, endText));
            [times, values, loadMeta] = load_timeseries_range( ...
                rootDir, subfolder, configuredPointId, startText, endText, ...
                cfgForLoad, sensorType);
            bms.app.StopController.throwIfRequested( ...
                'Curve generation stopped after loading the selected point.');

            values = values(:);
            if ~isempty(times)
                times = times(:);
            end
            maxCount = bms.config.ThresholdCurveRecordService.numericOpt( ...
                opts, 'preview_sample_count', 20000);
            maxCount = max(1, floor(maxCount));
            [sampleTimes, sampleValues] = ...
                bms.config.AutoThresholdProposalService.sampleSeries( ...
                times, values, maxCount);
            sourceFiles = bms.config.ThresholdCurveRecordService.metaFiles(loadMeta);
            sourceCount = numel(values);
            finiteCount = nnz(isfinite(values));

            curve = struct( ...
                'module_key', moduleKey, ...
                'point_id', configuredPointId, ...
                'sensor_type', sensorType, ...
                'times', sampleTimes, ...
                'values', sampleValues, ...
                'sample_count', numel(sampleValues), ...
                'source_sample_count', sourceCount, ...
                'finite_sample_count', finiteCount, ...
                'source_files', {sourceFiles});
            bms.app.RunProgressReporter.checkpoint( ...
                'stage', 'curve_ready', ...
                'current_point_id', configuredPointId, ...
                'current_date', endText, ...
                'processed_dates', bms.config.ThresholdCurveRecordService. ...
                    dateCount(startText, endText), ...
                'total_dates', bms.config.ThresholdCurveRecordService. ...
                    dateCount(startText, endText));
        end

        function preview = buildPreview(binding, curve)
            preview = bms.config.ThresholdCurveRecordService.bindingFields(binding);
            preview.schema_version = 1;
            preview.artifact_type = 'threshold_curve_preview';
            preview.created_at = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss');
            serialized = bms.config.ThresholdCurveRecordService. ...
                serializableCurves(curve);
            preview.curve_records = serialized;
        end

        function curves = serializableCurves(curves)
            % Force even a one-sample series to JSON arrays.  jsonencode emits
            % numeric/datetime scalars as scalars, while the Python and Qt
            % contract correctly requires parallel time/value arrays.
            for i = 1:numel(curves)
                curves(i).times = cellstr(string(curves(i).times(:)));
                curves(i).values = num2cell(double(curves(i).values(:)));
            end
        end

        function record = buildRecord(binding, curve, previewPath, previewSha256)
            record = bms.config.ThresholdCurveRecordService.bindingFields(binding);
            record.schema_version = 1;
            record.artifact_type = 'threshold_curve_record';
            record.created_at = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:ss');
            record.record_id = bms.config.ThresholdCurveRecordService. ...
                bindingText(binding, 'request_id');
            record.preview_path = char(string(previewPath));
            record.preview_sha256 = lower(char(string(previewSha256)));
            record.curve_record_count = 1;
            record.module_key = curve.module_key;
            record.point_id = curve.point_id;
            record.sensor_type = curve.sensor_type;
            record.source_sample_count = curve.source_sample_count;
            record.finite_sample_count = curve.finite_sample_count;
            record.source_files = curve.source_files;
        end

        function [record, preview] = readRecord(recordPath)
            recordPath = char(string(recordPath));
            record = bms.io.JsonFile.read(recordPath);
            if ~isstruct(record) || ~isfield(record, 'artifact_type') ...
                    || ~strcmp(char(string(record.artifact_type)), ...
                    'threshold_curve_record')
                error('BMS:ThresholdCurve:InvalidRecord', ...
                    'Not a threshold_curve_record artifact: %s', recordPath);
            end
            required = {'preview_path', 'preview_sha256'};
            for i = 1:numel(required)
                if ~isfield(record, required{i}) || isempty(record.(required{i}))
                    error('BMS:ThresholdCurve:InvalidRecord', ...
                        'Curve record is missing %s: %s', required{i}, recordPath);
                end
            end
            previewPath = char(string(record.preview_path));
            if ~isfile(previewPath)
                error('BMS:ThresholdCurve:PreviewMissing', ...
                    'Curve preview referenced by the record is missing: %s', previewPath);
            end
            actualSha = lower(bms.io.JsonFile.sha256(previewPath));
            if ~strcmpi(actualSha, char(string(record.preview_sha256)))
                error('BMS:ThresholdCurve:PreviewHashChanged', ...
                    'Curve preview hash no longer matches its record: %s', previewPath);
            end
            preview = bms.io.JsonFile.read(previewPath);
            if ~isstruct(preview) || ~isfield(preview, 'artifact_type') ...
                    || ~strcmp(char(string(preview.artifact_type)), ...
                    'threshold_curve_preview')
                error('BMS:ThresholdCurve:InvalidPreview', ...
                    'Referenced artifact is not a threshold_curve_preview: %s', previewPath);
            end
            bms.config.ThresholdCurveRecordService.verifyBinding(record, preview);
        end

        function sensorType = sensorTypeForPoint(moduleKey, pointId)
            moduleKey = char(string(moduleKey));
            sensorType = moduleKey;
            switch moduleKey
                case 'earthquake'
                    [sensorType, ~] = ...
                        bms.analyzer.EarthquakeSeriesService.componentFromPoint(pointId);
                case 'wind_speed'
                    sensorType = 'wind_speed';
                case {'dynamic_strain', 'dynamic_strain_lowpass'}
                    sensorType = 'strain';
                otherwise
                    try
                        spec = bms.config.ModuleConfigRegistry.fromKey(moduleKey);
                        if ~isempty(spec.per_point_key)
                            sensorType = spec.per_point_key;
                        end
                    catch
                    end
            end
        end
    end

    methods (Static, Access = private)
        function opts = mergeOptions(defaults, overrides)
            opts = defaults;
            if ~isstruct(overrides), return; end
            names = fieldnames(overrides);
            for i = 1:numel(names)
                opts.(names{i}) = overrides.(names{i});
            end
        end

        function text = singleText(value, fieldName)
            if iscell(value) || (isstring(value) && numel(value) ~= 1) ...
                    || (ischar(value) && size(value, 1) ~= 1)
                error('BMS:ThresholdCurve:SingleSelectionRequired', ...
                    '%s must contain exactly one value.', fieldName);
            end
            text = strtrim(char(string(value)));
            if isempty(text)
                error('BMS:ThresholdCurve:SingleSelectionRequired', ...
                    '%s must contain exactly one non-empty value.', fieldName);
            end
        end

        function [points, subfolder, configuredPointId] = ...
                resolveConfiguredPoint(cfg, moduleKey, pointId)
            try
                bms.config.ModuleConfigRegistry.fromKey(moduleKey);
            catch
                error('BMS:ThresholdCurve:UnsupportedModule', ...
                    'Unsupported curve module: %s', moduleKey);
            end
            points = bms.config.ModuleConfigResolver.resolvePoints(cfg, moduleKey, {});
            points = bms.data.PointResolver.normalize(points);
            matched = {};
            for i = 1:numel(points)
                aliases = bms.data.PointResolver.keyCandidates(points{i}, cfg);
                if any(strcmp(aliases, pointId))
                    matched{end+1} = points{i}; %#ok<AGROW>
                end
            end
            matched = unique(matched, 'stable');
            if isempty(matched)
                error('BMS:ThresholdCurve:PointNotConfigured', ...
                    'Point %s is not configured for module %s.', pointId, moduleKey);
            end
            if numel(matched) ~= 1
                error('BMS:ThresholdCurve:PointAliasAmbiguous', ...
                    'Point alias %s maps to multiple configured points for module %s: %s', ...
                    pointId, moduleKey, strjoin(matched, ', '));
            end
            configuredPointId = matched{1};
            subfolder = bms.config.ModuleConfigResolver.resolveSubfolder(cfg, moduleKey, '');
        end

        function cfg = preferMatCache(cfg)
            if ~isfield(cfg, 'time_series') || ~isstruct(cfg.time_series)
                cfg.time_series = struct();
            end
            cfg.time_series.source_mode = 'prefer_mat';
            if ~isfield(cfg, 'series_source') || ~isstruct(cfg.series_source)
                cfg.series_source = struct();
            end
            cfg.series_source.mode = 'prefer_mat';
            if ~isfield(cfg, 'data_adapter') || ~isstruct(cfg.data_adapter)
                cfg.data_adapter = struct();
            end
            if ~isfield(cfg.data_adapter, 'time_series') ...
                    || ~isstruct(cfg.data_adapter.time_series)
                cfg.data_adapter.time_series = struct();
            end
            cfg.data_adapter.time_series.source_mode = 'prefer_mat';
        end

        function cfg = disableCleaningRules(cfg, modules)
            keys = modules(:)';
            for i = 1:numel(modules)
                key = modules{i};
                try
                    spec = bms.config.ModuleConfigRegistry.fromKey(key);
                    keys = [keys, {spec.value, spec.per_point_key, ...
                        spec.point_key, spec.style_key}, spec.aliases(:)']; %#ok<AGROW>
                catch
                end
                if strcmp(key, 'earthquake')
                    keys = [keys, {'eq', 'eq_x', 'eq_y', 'eq_z'}]; %#ok<AGROW>
                elseif strcmp(key, 'wind_speed')
                    keys = [keys, {'wind', 'wind_speed'}]; %#ok<AGROW>
                elseif any(strcmp(key, {'dynamic_strain', 'dynamic_strain_lowpass'}))
                    keys = [keys, {'strain', 'dynamic_strain', ...
                        'dynamic_strain_lowpass'}]; %#ok<AGROW>
                end
            end
            keys = unique(keys(~cellfun(@isempty, keys)), 'stable');
            sections = {'defaults', 'per_point'};
            for si = 1:numel(sections)
                section = sections{si};
                if ~isfield(cfg, section) || ~isstruct(cfg.(section)), continue; end
                for ki = 1:numel(keys)
                    key = keys{ki};
                    if ~isfield(cfg.(section), key) ...
                            || ~isstruct(cfg.(section).(key)), continue; end
                    if strcmp(section, 'defaults')
                        cfg.(section).(key) = ...
                            bms.config.ThresholdCurveRecordService. ...
                            clearRuleBlock(cfg.(section).(key));
                    else
                        names = fieldnames(cfg.(section).(key));
                        for ni = 1:numel(names)
                            block = cfg.(section).(key).(names{ni});
                            if isstruct(block)
                                cfg.(section).(key).(names{ni}) = ...
                                    bms.config.ThresholdCurveRecordService. ...
                                    clearRuleBlock(block);
                            end
                        end
                    end
                end
            end
        end

        function block = clearRuleBlock(block)
            for name = {'thresholds', 'zero_to_nan', 'outlier'}
                if isfield(block, name{1})
                    block = rmfield(block, name{1});
                end
            end
        end

        function n = dateCount(startText, endText)
            n = numel(bms.data.TimeRangeResolver.daysBetween(startText, endText));
        end

        function files = metaFiles(meta)
            files = {};
            if isstruct(meta) && isfield(meta, 'files') && ~isempty(meta.files)
                files = cellstr(string(meta.files));
            end
        end

        function out = bindingFields(binding)
            names = {'request_type', 'request_id', 'bridge_id', 'config_path', ...
                'config_sha256', 'data_root', 'start_date', 'end_date', ...
                'module_key', 'point_id', 'sensor_type'};
            out = struct();
            for i = 1:numel(names)
                name = names{i};
                out.(name) = ...
                    bms.config.ThresholdCurveRecordService.bindingText(binding, name);
            end
        end

        function value = bindingText(binding, name)
            value = '';
            if isstruct(binding) && isfield(binding, name) ...
                    && ~isempty(binding.(name))
                value = char(string(binding.(name)));
            end
        end

        function verifyBinding(record, preview)
            fields = {'request_type', 'request_id', 'bridge_id', ...
                'config_sha256', 'data_root', 'start_date', 'end_date', ...
                'module_key', 'point_id', 'sensor_type'};
            for i = 1:numel(fields)
                name = fields{i};
                lhs = bms.config.ThresholdCurveRecordService.bindingText(record, name);
                rhs = bms.config.ThresholdCurveRecordService.bindingText(preview, name);
                if ~strcmp(lhs, rhs)
                    error('BMS:ThresholdCurve:BindingMismatch', ...
                        'Curve record/preview binding differs for %s.', name);
                end
            end
        end

        function tf = boolOpt(opts, name, fallback)
            tf = fallback;
            if isstruct(opts) && isfield(opts, name) && ~isempty(opts.(name))
                tf = logical(opts.(name));
            end
        end

        function value = numericOpt(opts, name, fallback)
            value = fallback;
            if isstruct(opts) && isfield(opts, name) && ~isempty(opts.(name))
                value = double(opts.(name));
            end
            if ~isscalar(value) || ~isfinite(value) || value <= 0
                value = fallback;
            end
        end

        function path = canonicalPath(value)
            path = char(string(value));
            try
                path = char(java.io.File(path).getCanonicalPath());
            catch
                path = bms.profile.BridgeProfile.normalizePathText(path);
            end
        end
    end
end
