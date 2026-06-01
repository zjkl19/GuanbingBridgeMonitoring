classdef AutoThresholdProposalService
    %AUTOTHRESHOLDPROPOSALSERVICE Generate draft cleaning-threshold proposals.

    methods (Static)
        function opts = defaultOptions()
            opts = struct();
            opts.module_keys = bms.config.AutoThresholdProposalService.defaultModuleKeys();
            opts.min_valid_count = 30;
            opts.max_points_per_module = Inf;
            opts.max_removed_ratio = 0.20;
            opts.min_removed_count = 1;
            opts.use_auto_cut = true;
            opts.auto_cut_mode = 'standard';
            opts.auto_cut_min_removed_count = 3;
            opts.auto_cut_max_proposals_per_point = 3;
            opts.auto_cut_min_gap_sigma = 8;
            opts.auto_cut_body_gap_fraction = 0.25;
            opts.auto_cut_global_max_span_seconds = 1800;
            opts.auto_cut_window_merge_gap_seconds = 600;
            opts.auto_cut_padding_seconds = 1;
            opts.use_quantile = false;
            opts.quantile_low = 0.5;
            opts.quantile_high = 99.5;
            opts.padding_factor = 0.05;
            opts.use_mad = false;
            opts.mad_factor = 6;
            opts.use_iqr = false;
            opts.iqr_factor = 3;
            opts.use_spike_window = false;
            opts.spike_mad_factor = 8;
            opts.min_window_points = 3;
            opts.max_window_proposals_per_point = 3;
            opts.spike_window_merge_gap_seconds = 600;
            opts.spike_window_padding_seconds = 1;
            opts.use_zero_or_flat = true;
            opts.zero_ratio_threshold = 0.90;
            opts.flat_ratio_threshold = 0.95;
            opts.load_without_existing_cleaning = true;
            opts.capture_preview_series = false;
            opts.preview_sample_count = 20000;
        end

        function keys = defaultModuleKeys()
            keys = {'temperature', 'humidity', 'rainfall', 'wind_speed', ...
                'earthquake', 'deflection', 'bearing_displacement', 'tilt', ...
                'gnss', 'acceleration', 'cable_accel', 'strain', ...
                'dynamic_strain', 'dynamic_strain_lowpass', 'crack'};
        end

        function labels = moduleLabels(keys)
            labels = cell(size(keys));
            for i = 1:numel(keys)
                try
                    spec = bms.config.ModuleConfigRegistry.fromKey(keys{i});
                    if ~isempty(spec.label) && ~strcmp(spec.label, keys{i})
                        labels{i} = sprintf('%s (%s)', keys{i}, spec.label);
                    else
                        labels{i} = keys{i};
                    end
                catch
                    labels{i} = keys{i};
                end
            end
        end

        function result = generate(cfg, rootDir, startDate, endDate, opts)
            if nargin < 5 || isempty(opts)
                opts = struct();
            end
            opts = bms.config.AutoThresholdProposalService.mergeOptions( ...
                bms.config.AutoThresholdProposalService.defaultOptions(), opts);
            modules = bms.config.AutoThresholdProposalService.normalizedModules(opts);

            rootDir = char(string(rootDir));
            startText = bms.config.AutoThresholdProposalService.dateText(startDate, false);
            endText = bms.config.AutoThresholdProposalService.dateText(endDate, false);

            proposals = bms.config.AutoThresholdProposalService.emptyProposal();
            previewSeries = struct('module_key', {}, 'point_id', {}, ...
                'sensor_type', {}, 'times', {}, 'values', {}, 'sample_count', {});
            moduleReports = struct('module_key', {}, 'point_count', {}, ...
                'proposal_count', {}, 'skipped_count', {}, 'message', {});

            cfgForLoad = cfg;
            if bms.config.AutoThresholdProposalService.boolOpt(opts, 'load_without_existing_cleaning', true)
                cfgForLoad = bms.config.AutoThresholdProposalService.disableCleaningRules(cfgForLoad, modules);
            end

            for mi = 1:numel(modules)
                moduleKey = modules{mi};
                [points, subfolder, msg] = bms.config.AutoThresholdProposalService.resolveModuleInputs(cfg, moduleKey);
                if isempty(points)
                    moduleReports(end+1) = struct('module_key', moduleKey, 'point_count', 0, ... %#ok<AGROW>
                        'proposal_count', 0, 'skipped_count', 0, 'message', msg);
                    continue;
                end

                maxPoints = opts.max_points_per_module;
                if isfinite(maxPoints) && numel(points) > maxPoints
                    points = points(1:maxPoints);
                end

                beforeCount = numel(proposals);
                skipped = 0;
                for pi = 1:numel(points)
                    pointId = points{pi};
                    sensorType = bms.config.AutoThresholdProposalService.sensorTypeForPoint(moduleKey, pointId);
                    try
                        [times, values] = load_timeseries_range(rootDir, subfolder, pointId, ...
                            startText, endText, cfgForLoad, sensorType);
                    catch
                        times = [];
                        values = [];
                    end
                    if isempty(values)
                        skipped = skipped + 1;
                        continue;
                    end
                    rows = bms.config.AutoThresholdProposalService.generateForSeries( ...
                        times, values, moduleKey, pointId, sensorType, opts);
                    if ~isempty(rows)
                        if bms.config.AutoThresholdProposalService.boolOpt(opts, 'capture_preview_series', false)
                            previewSeries(end+1) = bms.config.AutoThresholdProposalService.previewSeriesRecord( ... %#ok<AGROW>
                                moduleKey, pointId, sensorType, times, values, opts.preview_sample_count);
                        end
                        proposals = bms.config.AutoThresholdProposalService.appendStruct(proposals, rows);
                    end
                end

                added = numel(proposals) - beforeCount;
                moduleReports(end+1) = struct('module_key', moduleKey, ... %#ok<AGROW>
                    'point_count', numel(points), 'proposal_count', added, ...
                    'skipped_count', skipped, 'message', msg);
            end

            result = struct();
            result.schema_version = 1;
            result.proposal_type = 'auto_threshold_proposals';
            result.created_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
            result.root_dir = rootDir;
            result.start_date = startText;
            result.end_date = endText;
            result.options = opts;
            result.summary = struct('module_count', numel(modules), ...
                'proposal_count', numel(proposals), ...
                'module_reports', moduleReports);
            result.proposals = proposals;
            if bms.config.AutoThresholdProposalService.boolOpt(opts, 'capture_preview_series', false)
                result.preview_series = previewSeries;
            end
        end

        function proposals = generateForSeries(times, values, moduleKey, pointId, sensorType, opts)
            proposals = bms.config.AutoThresholdProposalService.emptyProposal();
            if isempty(values)
                return;
            end
            values = double(values(:));
            finiteMask = isfinite(values);
            finiteValues = values(finiteMask);
            validCount = numel(finiteValues);
            if validCount < opts.min_valid_count
                return;
            end

            if bms.config.AutoThresholdProposalService.boolOpt(opts, 'use_zero_or_flat', true)
                reviewRows = bms.config.AutoThresholdProposalService.zeroFlatReviews( ...
                    finiteValues, moduleKey, pointId, sensorType, validCount, opts);
                proposals = bms.config.AutoThresholdProposalService.appendStruct(proposals, reviewRows);
            end

            if bms.config.AutoThresholdProposalService.boolOpt(opts, 'use_auto_cut', true)
                rows = bms.config.AutoThresholdProposalService.autoCutProposals( ...
                    times, values, moduleKey, pointId, sensorType, validCount, opts);
                proposals = bms.config.AutoThresholdProposalService.appendStruct(proposals, rows);
            end

            if bms.config.AutoThresholdProposalService.boolOpt(opts, 'use_quantile', true)
                low = bms.config.AutoThresholdProposalService.percentile(finiteValues, opts.quantile_low);
                high = bms.config.AutoThresholdProposalService.percentile(finiteValues, opts.quantile_high);
                [low, high] = bms.config.AutoThresholdProposalService.padBounds(low, high, opts.padding_factor);
                row = bms.config.AutoThresholdProposalService.rangeProposal( ...
                    values, moduleKey, pointId, sensorType, 'quantile', low, high, '', '', ...
                    validCount, opts);
                proposals = bms.config.AutoThresholdProposalService.appendStruct(proposals, row);
            end

            if bms.config.AutoThresholdProposalService.boolOpt(opts, 'use_mad', true)
                [low, high] = bms.config.AutoThresholdProposalService.madBounds(finiteValues, opts.mad_factor);
                row = bms.config.AutoThresholdProposalService.rangeProposal( ...
                    values, moduleKey, pointId, sensorType, 'mad', low, high, '', '', ...
                    validCount, opts);
                proposals = bms.config.AutoThresholdProposalService.appendStruct(proposals, row);
            end

            if bms.config.AutoThresholdProposalService.boolOpt(opts, 'use_iqr', false)
                [low, high] = bms.config.AutoThresholdProposalService.iqrBounds(finiteValues, opts.iqr_factor);
                row = bms.config.AutoThresholdProposalService.rangeProposal( ...
                    values, moduleKey, pointId, sensorType, 'iqr', low, high, '', '', ...
                    validCount, opts);
                proposals = bms.config.AutoThresholdProposalService.appendStruct(proposals, row);
            end

            if bms.config.AutoThresholdProposalService.boolOpt(opts, 'use_spike_window', true)
                rows = bms.config.AutoThresholdProposalService.spikeWindowProposals( ...
                    times, values, moduleKey, pointId, sensorType, validCount, opts);
                proposals = bms.config.AutoThresholdProposalService.appendStruct(proposals, rows);
            end
        end

        function cfgNew = applyAccepted(cfg, proposals)
            cfgNew = cfg;
            if isempty(proposals)
                return;
            end
            if ~isstruct(proposals)
                return;
            end
            if ~isfield(cfgNew, 'per_point') || ~isstruct(cfgNew.per_point)
                cfgNew.per_point = struct();
            end
            if ~isfield(cfgNew, 'name_map_global') || ~isstruct(cfgNew.name_map_global)
                cfgNew.name_map_global = struct();
            end

            for i = 1:numel(proposals)
                p = proposals(i);
                if isfield(p, 'selected') && ~logical(p.selected)
                    continue;
                end
                if ~isfield(p, 'kind') || ~any(strcmp(p.kind, {'range', 'window_range'}))
                    continue;
                end
                mn = bms.config.AutoThresholdProposalService.numericField(p, 'min');
                mx = bms.config.AutoThresholdProposalService.numericField(p, 'max');
                hasMin = ~isempty(mn) && isfinite(mn);
                hasMax = ~isempty(mx) && isfinite(mx);
                if ~hasMin && ~hasMax
                    continue;
                end
                if hasMin && hasMax && mn >= mx
                    continue;
                end

                applyKey = bms.config.AutoThresholdProposalService.applyKey(p);
                pointId = char(string(p.point_id));
                safeId = bms.data.PointResolver.configKey(pointId);
                if ~isfield(cfgNew.per_point, applyKey) || ~isstruct(cfgNew.per_point.(applyKey))
                    cfgNew.per_point.(applyKey) = struct();
                end
                if ~isfield(cfgNew.per_point.(applyKey), safeId) || ~isstruct(cfgNew.per_point.(applyKey).(safeId))
                    cfgNew.per_point.(applyKey).(safeId) = struct();
                end
                if ~hasMin
                    mn = NaN;
                end
                if ~hasMax
                    mx = NaN;
                end
                th = struct('min', mn, 'max', mx, ...
                    't_range_start', bms.config.AutoThresholdProposalService.textField(p, 't_range_start'), ...
                    't_range_end', bms.config.AutoThresholdProposalService.textField(p, 't_range_end'));
                existing = [];
                if isfield(cfgNew.per_point.(applyKey).(safeId), 'thresholds')
                    existing = cfgNew.per_point.(applyKey).(safeId).thresholds;
                    existing = bms.config.AutoThresholdProposalService.normalizeThresholdRows(existing);
                end
                if isempty(existing)
                    cfgNew.per_point.(applyKey).(safeId).thresholds = th;
                else
                    cfgNew.per_point.(applyKey).(safeId).thresholds = [existing(:); th];
                end
                cfgNew.name_map_global.(safeId) = pointId;
            end
        end

        function rows = normalizeThresholdRows(rows)
            if isempty(rows) || ~isstruct(rows)
                rows = [];
                return;
            end
            template = struct('min', NaN, 'max', NaN, 't_range_start', '', 't_range_end', '');
            out = repmat(template, numel(rows), 1);
            rows = rows(:);
            for i = 1:numel(rows)
                if isfield(rows(i), 'min') && ~isempty(rows(i).min)
                    out(i).min = rows(i).min;
                end
                if isfield(rows(i), 'max') && ~isempty(rows(i).max)
                    out(i).max = rows(i).max;
                end
                if isfield(rows(i), 't_range_start') && ~isempty(rows(i).t_range_start)
                    out(i).t_range_start = rows(i).t_range_start;
                end
                if isfield(rows(i), 't_range_end') && ~isempty(rows(i).t_range_end)
                    out(i).t_range_end = rows(i).t_range_end;
                end
            end
            rows = out;
        end

        function paths = writeArtifacts(rootDir, result)
            paths = struct('json', '', 'xlsx', '');
            outDir = fullfile(rootDir, 'run_logs');
            if ~exist(outDir, 'dir')
                mkdir(outDir);
            end
            stamp = datestr(now, 'yyyymmdd_HHMMSS');
            paths.json = fullfile(outDir, ['auto_threshold_proposals_' stamp '.json']);
            exportResult = result;
            if isstruct(exportResult) && isfield(exportResult, 'preview_series')
                exportResult = rmfield(exportResult, 'preview_series');
            end
            bms.core.Logger.writeJson(paths.json, exportResult);
            try
                rows = bms.config.AutoThresholdProposalService.proposalsToCell(result.proposals);
                if ~isempty(rows)
                    T = cell2table(rows, 'VariableNames', bms.config.AutoThresholdProposalService.tableColumns());
                    paths.xlsx = fullfile(outDir, ['auto_threshold_proposals_' stamp '.xlsx']);
                    writetable(T, paths.xlsx);
                end
            catch
                paths.xlsx = '';
            end
        end

        function [times, values] = loadSeriesForPreview(cfg, rootDir, startDate, endDate, moduleKey, pointId, ignoreExistingCleaning)
            if nargin < 7
                ignoreExistingCleaning = true;
            end
            if ignoreExistingCleaning
                cfg = bms.config.AutoThresholdProposalService.disableCleaningRules(cfg, {char(string(moduleKey))});
            end
            subfolder = bms.config.ModuleConfigResolver.resolveSubfolder(cfg, moduleKey, '');
            sensorType = bms.config.AutoThresholdProposalService.sensorTypeForPoint(moduleKey, pointId);
            [times, values] = load_timeseries_range(rootDir, subfolder, pointId, ...
                bms.config.AutoThresholdProposalService.dateText(startDate, false), ...
                bms.config.AutoThresholdProposalService.dateText(endDate, false), cfg, sensorType);
        end

        function cols = tableColumns()
            cols = {'selected', 'module_key', 'point_id', 'kind', 'algorithm', ...
                'min', 'max', 't_range_start', 't_range_end', 'valid_count', ...
                'removed_count', 'removed_ratio', 'score', 'reason'};
        end

        function rows = proposalsToCell(proposals)
            rows = cell(0, numel(bms.config.AutoThresholdProposalService.tableColumns()));
            for i = 1:numel(proposals)
                p = proposals(i);
                rows(end+1, :) = {logical(p.selected), p.module_key, p.point_id, p.kind, ... %#ok<AGROW>
                    p.algorithm, p.min, p.max, p.t_range_start, p.t_range_end, ...
                    p.valid_count, p.removed_count, p.removed_ratio, p.score, p.reason};
            end
        end

        function proposals = cellToProposals(data)
            proposals = bms.config.AutoThresholdProposalService.emptyProposal();
            if isempty(data)
                return;
            end
            for i = 1:size(data, 1)
                p = bms.config.AutoThresholdProposalService.emptyProposal();
                p(1).selected = bms.config.AutoThresholdProposalService.cellBool(data{i,1}, true);
                p(1).module_key = char(string(data{i,2}));
                p(1).module_label = p(1).module_key;
                p(1).point_id = char(string(data{i,3}));
                p(1).safe_id = bms.data.PointResolver.configKey(p(1).point_id);
                p(1).sensor_type = bms.config.AutoThresholdProposalService.sensorTypeForPoint(p(1).module_key, p(1).point_id);
                p(1).kind = char(string(data{i,4}));
                p(1).algorithm = char(string(data{i,5}));
                p(1).min = bms.config.AutoThresholdProposalService.cellNumber(data{i,6});
                p(1).max = bms.config.AutoThresholdProposalService.cellNumber(data{i,7});
                p(1).t_range_start = bms.config.AutoThresholdProposalService.cellText(data{i,8});
                p(1).t_range_end = bms.config.AutoThresholdProposalService.cellText(data{i,9});
                p(1).valid_count = bms.config.AutoThresholdProposalService.cellNumber(data{i,10});
                p(1).removed_count = bms.config.AutoThresholdProposalService.cellNumber(data{i,11});
                p(1).removed_ratio = bms.config.AutoThresholdProposalService.cellNumber(data{i,12});
                p(1).score = bms.config.AutoThresholdProposalService.cellNumber(data{i,13});
                p(1).reason = bms.config.AutoThresholdProposalService.cellText(data{i,14});
                p(1).target_field = 'thresholds';
                proposals = bms.config.AutoThresholdProposalService.appendStruct(proposals, p);
            end
        end

        function key = previewCacheKey(moduleKey, pointId)
            key = [char(string(moduleKey)) '|' char(string(pointId))];
        end

        function rec = previewSeriesRecord(moduleKey, pointId, sensorType, times, values, maxCount)
            if nargin < 6 || isempty(maxCount)
                maxCount = 20000;
            end
            [tp, vp] = bms.config.AutoThresholdProposalService.sampleSeries(times, values, maxCount);
            rec = struct();
            rec.module_key = char(string(moduleKey));
            rec.point_id = char(string(pointId));
            rec.sensor_type = char(string(sensorType));
            rec.times = tp;
            rec.values = vp;
            rec.sample_count = numel(vp);
        end

        function [tp, vp] = sampleSeries(times, values, maxCount)
            if nargin < 3 || isempty(maxCount)
                maxCount = 20000;
            end
            values = values(:);
            if isempty(times)
                times = (1:numel(values))';
            else
                times = times(:);
            end
            if numel(times) ~= numel(values)
                n = min(numel(times), numel(values));
                times = times(1:n);
                values = values(1:n);
            end
            if numel(values) > maxCount
                if maxCount < 4
                    idx = unique(round(linspace(1, numel(values), maxCount)), 'stable');
                else
                    idx = bms.config.AutoThresholdProposalService.extremaSampleIndices(values, maxCount);
                end
                values = values(idx);
                times = times(idx);
            end
            tp = times;
            vp = values;
        end

        function txt = algorithmDisplayName(algorithm)
            algorithm = char(string(algorithm));
            switch algorithm
                case 'auto_cut'
                    txt = '智能切线';
                case 'quantile'
                    txt = '分位数范围';
                case 'mad'
                    txt = 'MAD稳健范围';
                case 'iqr'
                    txt = 'IQR四分位范围';
                case 'spike_window'
                    txt = '局部尖峰时间窗';
                case 'zero_ratio'
                    txt = '零值占比提示';
                case 'flat_ratio'
                    txt = '固定值占比提示';
                otherwise
                    txt = algorithm;
            end
        end

        function txt = algorithmDescription(algorithm)
            algorithm = char(string(algorithm));
            switch algorithm
                case 'auto_cut'
                    txt = '自动判断上端或下端异常，先尝试给出一条全时段单边切线；如果这条线会覆盖较长连续时段，则改为输出少量局部时间窗切线。适合一刀切或分几刀切掉明显尖刺。';
                case 'quantile'
                    txt = '按全段数据的低/高分位数给出上下限，适合先快速裁掉极端尾部值。低分位和高分位越靠近 0/100，范围越宽；外扩比例会在分位数范围两侧再放宽一点。';
                case 'mad'
                    txt = '以中位数为中心，用 MAD 估计波动范围，对少量异常值不敏感。系数越大，建议范围越宽，误删风险越低。';
                case 'iqr'
                    txt = '用第 25/75 分位之间的四分位距估计正常范围，适合分布偏斜但主体稳定的数据。系数越大，范围越宽。';
                case 'spike_window'
                    txt = '先用 MAD 找尖峰，再把近邻异常点合并成局部时间窗，按峰值超限强度保留最明显的窗口。系数控制尖峰敏感度，最少点数控制一个窗口至少包含多少异常点，最多窗限制每个测点输出多少个高分窗口。';
                case 'zero_ratio'
                    txt = '当 0 值占比过高时只给人工复核提示，通常用于发现掉线、占位值或传感器异常，不会直接写入上下限。';
                case 'flat_ratio'
                    txt = '当某个固定值占比过高时只给人工复核提示，通常用于发现卡值、数据链路异常或传感器冻结。';
                otherwise
                    txt = '暂无说明。';
            end
        end

        function lines = helpLines()
            lines = { ...
                '自动清洗建议只生成草稿。建议先看右侧预览，再勾选可信条目写入配置。', ...
                '', ...
                '算法说明：', ...
                ['- 智能切线：' bms.config.AutoThresholdProposalService.algorithmDescription('auto_cut')], ...
                ['- 分位数范围：' bms.config.AutoThresholdProposalService.algorithmDescription('quantile')], ...
                ['- MAD稳健范围：' bms.config.AutoThresholdProposalService.algorithmDescription('mad')], ...
                ['- IQR四分位范围：' bms.config.AutoThresholdProposalService.algorithmDescription('iqr')], ...
                ['- 局部尖峰时间窗：' bms.config.AutoThresholdProposalService.algorithmDescription('spike_window')], ...
                ['- 零值占比提示：' bms.config.AutoThresholdProposalService.algorithmDescription('zero_ratio')], ...
                ['- 固定值占比提示：' bms.config.AutoThresholdProposalService.algorithmDescription('flat_ratio')], ...
                '', ...
                '参数含义：', ...
                '- 智能切线模式：保守更少误切，标准用于日常复核，激进会保留更小的正常/异常间隙。', ...
                '- 低/高分位：用于分位数法的上下分位百分比。', ...
                '- 外扩：在分位数范围两侧按范围宽度继续放宽，0.05 表示放宽 5%。', ...
                '- MAD/IQR 系数：系数越大，上下限越宽，越保守。', ...
                '- 局部尖峰 系数/点数/最多窗：分别控制尖峰敏感度、异常最少点数、每个测点按强度最多输出多少个时间窗。', ...
                '- 最少有效点：有效样本不足时跳过，避免小样本误判。', ...
                '- 最大剔除比例：超过该比例的建议会被丢弃，避免把整段正常数据当异常。', ...
                '- 生成时忽略现有清洗阈值：用于直接分析原始曲线，避免旧阈值先把异常点过滤掉。', ...
                '', ...
                '使用建议：先开分位数+MAD+局部尖峰；对长期偏移用全段范围建议，对短时毛刺优先用局部尖峰时间窗。' ...
                };
        end
    end

    methods (Static, Access = private)
        function opts = mergeOptions(defaults, overrides)
            opts = defaults;
            if ~isstruct(overrides)
                return;
            end
            names = fieldnames(overrides);
            for i = 1:numel(names)
                opts.(names{i}) = overrides.(names{i});
            end
        end

        function idx = extremaSampleIndices(values, maxCount)
            n = numel(values);
            bucketCount = max(1, floor((maxCount - 2) / 2));
            edges = unique(round(linspace(1, n + 1, bucketCount + 1)), 'stable');
            idx = [1; n];
            for b = 1:(numel(edges) - 1)
                lo = edges(b);
                hi = min(n, edges(b + 1) - 1);
                if hi < lo
                    continue;
                end
                segment = values(lo:hi);
                finiteIdx = find(isfinite(segment));
                if isempty(finiteIdx)
                    continue;
                end
                [~, minPos] = min(segment(finiteIdx));
                [~, maxPos] = max(segment(finiteIdx));
                idx(end+1, 1) = lo + finiteIdx(minPos) - 1; %#ok<AGROW>
                idx(end+1, 1) = lo + finiteIdx(maxPos) - 1; %#ok<AGROW>
            end
            idx = unique(idx);
            if numel(idx) > maxCount
                keep = unique(round(linspace(1, numel(idx), maxCount)), 'stable');
                idx = idx(keep);
            end
        end

        function modules = normalizedModules(opts)
            modules = {};
            if isfield(opts, 'module_keys') && ~isempty(opts.module_keys)
                modules = bms.data.PointResolver.normalize(opts.module_keys);
            end
            if isempty(modules)
                modules = bms.config.AutoThresholdProposalService.defaultModuleKeys();
            end
            modules = setdiff(modules, {'wim', 'wind_direction', 'wind_rose', ...
                'accel_spectrum', 'cable_accel_spectrum'}, 'stable');
        end

        function [points, subfolder, msg] = resolveModuleInputs(cfg, moduleKey)
            msg = '';
            points = {};
            subfolder = '';
            try
                points = bms.config.ModuleConfigResolver.resolvePoints(cfg, moduleKey, {});
                subfolder = bms.config.ModuleConfigResolver.resolveSubfolder(cfg, moduleKey, '');
            catch ME
                msg = ME.message;
            end
        end

        function sensorType = sensorTypeForPoint(moduleKey, pointId)
            moduleKey = char(string(moduleKey));
            sensorType = moduleKey;
            switch moduleKey
                case 'earthquake'
                    [sensorType, ~] = bms.analyzer.EarthquakeSeriesService.componentFromPoint(pointId);
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

        function key = applyKey(p)
            moduleKey = char(string(p.module_key));
            sensorType = char(string(p.sensor_type));
            if startsWith(sensorType, 'eq_')
                key = sensorType;
                return;
            end
            switch moduleKey
                case 'wind_speed'
                    key = 'wind_speed';
                case {'dynamic_strain', 'dynamic_strain_lowpass'}
                    key = moduleKey;
                otherwise
                    try
                        spec = bms.config.ModuleConfigRegistry.fromKey(moduleKey);
                        key = spec.per_point_key;
                    catch
                        key = moduleKey;
                    end
            end
            if isempty(key)
                key = moduleKey;
            end
        end

        function cfg = disableCleaningRules(cfg, modules)
            keys = modules(:)';
            for i = 1:numel(modules)
                key = modules{i};
                try
                    spec = bms.config.ModuleConfigRegistry.fromKey(key);
                    keys = [keys, {spec.value, spec.per_point_key, spec.point_key, spec.style_key}, spec.aliases(:)']; %#ok<AGROW>
                catch
                end
                if strcmp(key, 'earthquake')
                    keys = [keys, {'eq', 'eq_x', 'eq_y', 'eq_z'}]; %#ok<AGROW>
                elseif strcmp(key, 'wind_speed')
                    keys = [keys, {'wind', 'wind_speed'}]; %#ok<AGROW>
                elseif any(strcmp(key, {'dynamic_strain', 'dynamic_strain_lowpass'}))
                    keys = [keys, {'strain', 'dynamic_strain', 'dynamic_strain_lowpass'}]; %#ok<AGROW>
                end
            end
            keys = unique(keys(~cellfun(@isempty, keys)), 'stable');
            sections = {'defaults', 'per_point'};
            for si = 1:numel(sections)
                section = sections{si};
                if ~isfield(cfg, section) || ~isstruct(cfg.(section))
                    continue;
                end
                for ki = 1:numel(keys)
                    key = keys{ki};
                    if ~isfield(cfg.(section), key) || ~isstruct(cfg.(section).(key))
                        continue;
                    end
                    if strcmp(section, 'defaults')
                        cfg.(section).(key) = bms.config.AutoThresholdProposalService.clearRuleBlock(cfg.(section).(key));
                    else
                        names = fieldnames(cfg.(section).(key));
                        for ni = 1:numel(names)
                            block = cfg.(section).(key).(names{ni});
                            if isstruct(block)
                                cfg.(section).(key).(names{ni}) = bms.config.AutoThresholdProposalService.clearRuleBlock(block);
                            end
                        end
                    end
                end
            end
        end

        function block = clearRuleBlock(block)
            for fn = {'thresholds', 'zero_to_nan', 'outlier'}
                if isfield(block, fn{1})
                    block = rmfield(block, fn{1});
                end
            end
        end

        function p = emptyProposal()
            p = struct('selected', {}, 'module_key', {}, 'module_label', {}, ...
                'point_id', {}, 'safe_id', {}, 'sensor_type', {}, ...
                'kind', {}, 'algorithm', {}, 'min', {}, 'max', {}, ...
                't_range_start', {}, 't_range_end', {}, 'valid_count', {}, ...
                'removed_count', {}, 'removed_ratio', {}, 'score', {}, ...
                'reason', {}, 'target_field', {});
        end

        function out = appendStruct(base, extra)
            if isempty(base)
                out = extra;
            elseif isempty(extra)
                out = base;
            else
                out = [base(:); extra(:)];
            end
        end

        function rows = autoCutProposals(times, values, moduleKey, pointId, sensorType, validCount, opts)
            rows = bms.config.AutoThresholdProposalService.emptyProposal();
            values = values(:);
            if isempty(values)
                return;
            end
            if isempty(times)
                times = (1:numel(values))';
            else
                times = times(:);
            end
            if numel(times) ~= numel(values)
                n = min(numel(times), numel(values));
                times = times(1:n);
                values = values(1:n);
            end

            opts = bms.config.AutoThresholdProposalService.applyAutoCutMode(opts);
            candidates = bms.config.AutoThresholdProposalService.emptyAutoCutCandidate();
            for side = {'low', 'high'}
                cand = bms.config.AutoThresholdProposalService.autoCutCandidate(values, side{1}, validCount, opts);
                if isempty(cand)
                    continue;
                end
                if bms.config.AutoThresholdProposalService.autoCutGlobalSafe(times, values, cand, validCount, opts)
                    cand.kind = 'range';
                    cand.idx0 = 1;
                    cand.idx1 = numel(values);
                    cand.window_count = cand.removed_count;
                    candidates = bms.config.AutoThresholdProposalService.appendStruct(candidates, cand);
                else
                    windowCands = bms.config.AutoThresholdProposalService.autoCutWindowCandidates( ...
                        times, values, cand, validCount, opts);
                    candidates = bms.config.AutoThresholdProposalService.appendStruct(candidates, windowCands);
                end
            end
            if isempty(candidates)
                return;
            end

            maxRows = floor(bms.config.AutoThresholdProposalService.numericOpt( ...
                opts, 'auto_cut_max_proposals_per_point', ...
                bms.config.AutoThresholdProposalService.numericOpt(opts, 'max_window_proposals_per_point', 3)));
            if maxRows < 1
                return;
            end
            rankMatrix = [[candidates.score].', [candidates.window_count].', ...
                [candidates.removed_count].', -[candidates.idx0].'];
            [~, order] = sortrows(rankMatrix, [-1 -2 -3 -4]);
            order = order(1:min(maxRows, numel(order)));
            selected = candidates(order);
            [~, chronological] = sort([selected.idx0]);
            selected = selected(chronological);

            for i = 1:numel(selected)
                cand = selected(i);
                if strcmp(cand.side, 'low')
                    mn = cand.threshold;
                    mx = NaN;
                    direction = 'lower';
                else
                    mn = NaN;
                    mx = cand.threshold;
                    direction = 'upper';
                end
                if strcmp(cand.kind, 'window_range')
                    [t0, t1] = bms.config.AutoThresholdProposalService.windowTimeTexts( ...
                        times, cand.idx0, cand.idx1, opts, 'auto_cut_padding_seconds');
                else
                    t0 = '';
                    t1 = '';
                end
                reason = sprintf('auto cut %s removes %d points; gap %.6g; threshold %.6g', ...
                    direction, cand.window_count, cand.gap, cand.threshold);
                row = bms.config.AutoThresholdProposalService.makeProposal( ...
                    true, moduleKey, pointId, sensorType, cand.kind, 'auto_cut', ...
                    mn, mx, t0, t1, validCount, cand.window_count, ...
                    cand.window_count / max(1, validCount), cand.score, reason);
                rows = bms.config.AutoThresholdProposalService.appendStruct(rows, row);
            end
        end

        function opts = applyAutoCutMode(opts)
            mode = 'standard';
            if isstruct(opts) && isfield(opts, 'auto_cut_mode') && ~isempty(opts.auto_cut_mode)
                mode = lower(strtrim(char(string(opts.auto_cut_mode))));
            end
            switch mode
                case {'conservative', '保守'}
                    opts.auto_cut_min_gap_sigma = 12;
                    opts.auto_cut_body_gap_fraction = 0.20;
                    opts.auto_cut_global_max_span_seconds = 900;
                case {'aggressive', '激进'}
                    opts.auto_cut_min_gap_sigma = 5;
                    opts.auto_cut_body_gap_fraction = 0.35;
                    opts.auto_cut_global_max_span_seconds = 3600;
                otherwise
                    opts.auto_cut_min_gap_sigma = bms.config.AutoThresholdProposalService.numericOpt( ...
                        opts, 'auto_cut_min_gap_sigma', 8);
                    opts.auto_cut_body_gap_fraction = bms.config.AutoThresholdProposalService.numericOpt( ...
                        opts, 'auto_cut_body_gap_fraction', 0.25);
                    opts.auto_cut_global_max_span_seconds = bms.config.AutoThresholdProposalService.numericOpt( ...
                        opts, 'auto_cut_global_max_span_seconds', 1800);
            end
        end

        function cand = emptyAutoCutCandidate()
            cand = struct('side', {}, 'kind', {}, 'threshold', {}, 'gap', {}, ...
                'sigma', {}, 'removed_count', {}, 'window_count', {}, ...
                'removed_ratio', {}, 'score', {}, 'idx0', {}, 'idx1', {});
        end

        function cand = autoCutCandidate(values, side, validCount, opts)
            cand = bms.config.AutoThresholdProposalService.emptyAutoCutCandidate();
            finiteValues = values(isfinite(values));
            n = numel(finiteValues);
            if n < max(10, opts.min_valid_count)
                return;
            end
            sorted = sort(finiteValues);
            minCount = max( ...
                bms.config.AutoThresholdProposalService.numericOpt(opts, 'min_removed_count', 1), ...
                bms.config.AutoThresholdProposalService.numericOpt(opts, 'auto_cut_min_removed_count', 3));
            minCount = max(1, floor(minCount));
            maxCount = floor(n * bms.config.AutoThresholdProposalService.numericOpt(opts, 'max_removed_ratio', 0.20));
            maxCount = min(maxCount, n - 2);
            if maxCount < minCount
                return;
            end
            sigma = bms.config.AutoThresholdProposalService.robustScale(finiteValues);
            minGap = sigma * bms.config.AutoThresholdProposalService.numericOpt(opts, 'auto_cut_min_gap_sigma', 8);
            gapFraction = bms.config.AutoThresholdProposalService.numericOpt(opts, 'auto_cut_body_gap_fraction', 0.25);
            gapFraction = min(0.75, max(0.05, gapFraction));

            best = [];
            if strcmp(side, 'low')
                scan = minCount:maxCount;
                for k = scan
                    gap = sorted(k + 1) - sorted(k);
                    if gap < minGap
                        continue;
                    end
                    threshold = sorted(k + 1) - gapFraction * gap;
                    removed = sum(values < threshold & isfinite(values));
                    if removed < minCount || removed > maxCount
                        continue;
                    end
                    score = bms.config.AutoThresholdProposalService.autoCutScore(gap, sigma, removed, n);
                    best = bms.config.AutoThresholdProposalService.chooseBetterAutoCut(best, ...
                        side, threshold, gap, sigma, removed, validCount, score);
                end
            else
                scan = (n - maxCount):(n - minCount);
                for k = scan
                    if k < 1 || k >= n
                        continue;
                    end
                    gap = sorted(k + 1) - sorted(k);
                    if gap < minGap
                        continue;
                    end
                    threshold = sorted(k) + gapFraction * gap;
                    removed = sum(values > threshold & isfinite(values));
                    if removed < minCount || removed > maxCount
                        continue;
                    end
                    score = bms.config.AutoThresholdProposalService.autoCutScore(gap, sigma, removed, n);
                    best = bms.config.AutoThresholdProposalService.chooseBetterAutoCut(best, ...
                        side, threshold, gap, sigma, removed, validCount, score);
                end
            end
            if ~isempty(best)
                cand = best;
            end
        end

        function score = autoCutScore(gap, sigma, removed, validCount)
            score = (gap / max(sigma, eps)) * sqrt(double(removed)) * ...
                (1 - min(0.95, double(removed) / max(1, double(validCount))));
        end

        function best = chooseBetterAutoCut(best, side, threshold, gap, sigma, removed, validCount, score)
            cand = struct('side', char(string(side)), 'kind', 'range', ...
                'threshold', threshold, 'gap', gap, 'sigma', sigma, ...
                'removed_count', double(removed), 'window_count', double(removed), ...
                'removed_ratio', double(removed) / max(1, validCount), ...
                'score', score, 'idx0', 1, 'idx1', 1);
            if isempty(best) || cand.score > best.score
                best = cand;
            end
        end

        function tf = autoCutGlobalSafe(times, values, cand, validCount, opts)
            mask = bms.config.AutoThresholdProposalService.autoCutMask(values, cand);
            removed = sum(mask);
            if removed < cand.removed_count || removed / max(1, validCount) > opts.max_removed_ratio
                tf = false;
                return;
            end
            spans = bms.config.AutoThresholdProposalService.maskSpans(mask);
            maxSeconds = bms.config.AutoThresholdProposalService.numericOpt( ...
                opts, 'auto_cut_global_max_span_seconds', 1800);
            tf = true;
            for i = 1:size(spans, 1)
                spanSeconds = bms.config.AutoThresholdProposalService.spanDurationSeconds( ...
                    times, spans(i, 1), spans(i, 2));
                if isfinite(spanSeconds) && spanSeconds > maxSeconds
                    tf = false;
                    return;
                end
            end
        end

        function candidates = autoCutWindowCandidates(times, values, cand, validCount, opts)
            candidates = bms.config.AutoThresholdProposalService.emptyAutoCutCandidate();
            mask = bms.config.AutoThresholdProposalService.autoCutMask(values, cand);
            if ~any(mask)
                return;
            end
            spans = bms.config.AutoThresholdProposalService.maskSpans(mask);
            gapSeconds = bms.config.AutoThresholdProposalService.numericOpt( ...
                opts, 'auto_cut_window_merge_gap_seconds', 600);
            spans = bms.config.AutoThresholdProposalService.mergeSpansByGap(spans, times, gapSeconds);
            minCount = max( ...
                bms.config.AutoThresholdProposalService.numericOpt(opts, 'min_removed_count', 1), ...
                bms.config.AutoThresholdProposalService.numericOpt(opts, 'auto_cut_min_removed_count', 3));
            maxSeconds = bms.config.AutoThresholdProposalService.numericOpt( ...
                opts, 'auto_cut_global_max_span_seconds', 1800);
            for i = 1:size(spans, 1)
                idx0 = spans(i, 1);
                idx1 = spans(i, 2);
                count = sum(mask(idx0:idx1));
                if count < minCount
                    continue;
                end
                spanSeconds = bms.config.AutoThresholdProposalService.spanDurationSeconds(times, idx0, idx1);
                if isfinite(spanSeconds) && spanSeconds > maxSeconds
                    continue;
                end
                local = cand;
                local.kind = 'window_range';
                local.idx0 = idx0;
                local.idx1 = idx1;
                local.window_count = double(count);
                local.score = bms.config.AutoThresholdProposalService.autoCutWindowScore( ...
                    values(idx0:idx1), cand, count, validCount);
                candidates = bms.config.AutoThresholdProposalService.appendStruct(candidates, local);
            end
        end

        function score = autoCutWindowScore(values, cand, count, validCount)
            if strcmp(cand.side, 'low')
                excess = max(cand.threshold - values(isfinite(values)), 0);
            else
                excess = max(values(isfinite(values)) - cand.threshold, 0);
            end
            if isempty(excess)
                score = 0;
            else
                score = (max(excess) / max(cand.sigma, eps)) * sqrt(double(count)) * ...
                    (1 - min(0.95, double(count) / max(1, double(validCount))));
            end
        end

        function mask = autoCutMask(values, cand)
            if strcmp(cand.side, 'low')
                mask = isfinite(values) & values < cand.threshold;
            else
                mask = isfinite(values) & values > cand.threshold;
            end
        end

        function sigma = robustScale(values)
            values = values(isfinite(values));
            if isempty(values)
                sigma = 1;
                return;
            end
            med = median(values);
            madSigma = 1.4826 * median(abs(values - med));
            q25 = bms.config.AutoThresholdProposalService.percentile(values, 25);
            q75 = bms.config.AutoThresholdProposalService.percentile(values, 75);
            iqrSigma = (q75 - q25) / 1.349;
            sigma = max([madSigma, iqrSigma, std(values) * 0.05, eps]);
            if ~isfinite(sigma) || sigma <= 0
                sigma = max(std(values), eps);
            end
        end

        function row = rangeProposal(values, moduleKey, pointId, sensorType, algorithm, low, high, t0, t1, validCount, opts)
            row = bms.config.AutoThresholdProposalService.emptyProposal();
            if isempty(low) || isempty(high) || ~isfinite(low) || ~isfinite(high) || low >= high
                return;
            end
            finiteMask = isfinite(values);
            outside = finiteMask & (values < low | values > high);
            removedCount = sum(outside);
            removedRatio = removedCount / max(1, validCount);
            if removedCount < opts.min_removed_count || removedRatio > opts.max_removed_ratio
                return;
            end
            row = bms.config.AutoThresholdProposalService.makeProposal( ...
                true, moduleKey, pointId, sensorType, 'range', algorithm, ...
                low, high, t0, t1, validCount, removedCount, removedRatio, ...
                removedRatio, sprintf('%s bounds remove %d/%d points', algorithm, removedCount, validCount));
        end

        function rows = spikeWindowProposals(times, values, moduleKey, pointId, sensorType, validCount, opts)
            rows = bms.config.AutoThresholdProposalService.emptyProposal();
            [low, high] = bms.config.AutoThresholdProposalService.madBounds( ...
                values(isfinite(values)), opts.spike_mad_factor);
            if isempty(low) || isempty(high) || ~isfinite(low) || ~isfinite(high) || low >= high
                return;
            end
            mask = isfinite(values) & (values < low | values > high);
            if ~any(mask)
                return;
            end
            spans = bms.config.AutoThresholdProposalService.maskSpans(mask);
            spans = bms.config.AutoThresholdProposalService.mergeNearbySpans(spans, times, opts);
            candidates = struct('idx0', {}, 'idx1', {}, 'count', {}, ...
                'ratio', {}, 'score', {}, 'severity', {}, 'excess_area', {});
            for i = 1:size(spans, 1)
                idx0 = spans(i, 1);
                idx1 = spans(i, 2);
                localMask = mask(idx0:idx1);
                count = sum(localMask);
                if count < opts.min_window_points
                    continue;
                end
                [severity, excessArea] = bms.config.AutoThresholdProposalService.spikeWindowScore( ...
                    values(idx0:idx1), low, high);
                if severity <= 0 || ~isfinite(severity)
                    continue;
                end
                ratio = count / max(1, validCount);
                candidates(end+1) = struct( ... %#ok<AGROW>
                    'idx0', idx0, 'idx1', idx1, 'count', count, ...
                    'ratio', ratio, 'score', severity, ...
                    'severity', severity, 'excess_area', excessArea);
            end
            if isempty(candidates)
                return;
            end

            maxRows = floor(bms.config.AutoThresholdProposalService.numericOpt( ...
                opts, 'max_window_proposals_per_point', 3));
            if maxRows < 1
                return;
            end
            rankMatrix = [[candidates.severity].', [candidates.count].', ...
                [candidates.excess_area].', -[candidates.idx0].'];
            [~, order] = sortrows(rankMatrix, [-1 -2 -3 -4]);
            order = order(1:min(maxRows, numel(order)));
            selected = candidates(order);
            [~, chronological] = sort([selected.idx0]);
            selected = selected(chronological);

            for i = 1:numel(selected)
                idx0 = selected(i).idx0;
                idx1 = selected(i).idx1;
                [t0, t1] = bms.config.AutoThresholdProposalService.windowTimeTexts(times, idx0, idx1, opts);
                row = bms.config.AutoThresholdProposalService.makeProposal( ...
                    true, moduleKey, pointId, sensorType, 'window_range', 'spike_window', ...
                    low, high, t0, t1, validCount, selected(i).count, selected(i).ratio, ...
                    selected(i).score, sprintf('local spike window removes %d points; peak excess %.6g', ...
                    selected(i).count, selected(i).severity));
                rows = bms.config.AutoThresholdProposalService.appendStruct(rows, row);
            end
        end

        function spans = mergeNearbySpans(spans, times, opts)
            if size(spans, 1) <= 1
                return;
            end
            gapSeconds = bms.config.AutoThresholdProposalService.numericOpt( ...
                opts, 'spike_window_merge_gap_seconds', 600);
            if gapSeconds < 0 || ~isfinite(gapSeconds)
                gapSeconds = 0;
            end
            spans = bms.config.AutoThresholdProposalService.mergeSpansByGap(spans, times, gapSeconds);
        end

        function merged = mergeSpansByGap(spans, times, gapSeconds)
            if size(spans, 1) <= 1
                merged = spans;
                return;
            end
            if gapSeconds < 0 || ~isfinite(gapSeconds)
                gapSeconds = 0;
            end
            merged = zeros(0, 2);
            current = spans(1, :);
            for i = 2:size(spans, 1)
                gap = bms.config.AutoThresholdProposalService.spanGapSeconds( ...
                    times, current(2), spans(i, 1));
                if isfinite(gap) && gap <= gapSeconds
                    current(2) = spans(i, 2);
                else
                    merged(end+1, :) = current; %#ok<AGROW>
                    current = spans(i, :);
                end
            end
            merged(end+1, :) = current;
        end

        function secondsGap = spanGapSeconds(times, idxEnd, idxNext)
            secondsGap = Inf;
            if isempty(times) || idxEnd < 1 || idxNext < 1 || ...
                    idxEnd > numel(times) || idxNext > numel(times)
                return;
            end
            try
                t0 = times(idxEnd);
                t1 = times(idxNext);
                if isdatetime(t0) || isdatetime(t1)
                    secondsGap = seconds(t1 - t0);
                elseif isnumeric(t0) && isnumeric(t1)
                    delta = double(t1 - t0);
                    if max(abs([double(t0), double(t1)])) > 1000
                        secondsGap = delta * 86400;
                    else
                        secondsGap = delta;
                    end
                end
            catch
                secondsGap = Inf;
            end
        end

        function durationSeconds = spanDurationSeconds(times, idx0, idx1)
            durationSeconds = Inf;
            if isempty(times) || idx0 < 1 || idx1 < 1 || ...
                    idx0 > numel(times) || idx1 > numel(times)
                return;
            end
            try
                t0 = times(idx0);
                t1 = times(idx1);
                if isdatetime(t0) || isdatetime(t1)
                    durationSeconds = seconds(t1 - t0);
                elseif isnumeric(t0) && isnumeric(t1)
                    delta = double(t1 - t0);
                    if max(abs([double(t0), double(t1)])) > 1000
                        durationSeconds = delta * 86400;
                    else
                        durationSeconds = delta;
                    end
                end
                durationSeconds = max(0, durationSeconds);
            catch
                durationSeconds = Inf;
            end
        end

        function [severity, excessArea] = spikeWindowScore(values, low, high)
            values = values(isfinite(values));
            if isempty(values)
                severity = 0;
                excessArea = 0;
                return;
            end
            highExcess = max(values - high, 0);
            lowExcess = max(low - values, 0);
            excess = max(highExcess, lowExcess);
            severity = max(excess);
            excessArea = sum(excess);
        end

        function [t0Text, t1Text] = windowTimeTexts(times, idx0, idx1, opts, paddingField)
            t0Text = '';
            t1Text = '';
            if isempty(times) || idx0 < 1 || idx1 < 1 || idx0 > numel(times) || idx1 > numel(times)
                return;
            end
            if nargin < 5 || isempty(paddingField)
                paddingField = 'spike_window_padding_seconds';
            end
            padSeconds = bms.config.AutoThresholdProposalService.numericOpt( ...
                opts, paddingField, 1);
            if ~isfinite(padSeconds) || padSeconds < 0
                padSeconds = 0;
            end
            t0 = times(idx0);
            t1 = times(idx1);
            try
                if isdatetime(t0) || isdatetime(t1)
                    [t0, t1] = bms.config.AutoThresholdProposalService.expandDatetimeToSecondRange( ...
                        t0, t1, padSeconds);
                elseif isnumeric(t0) && isnumeric(t1) && max(abs([double(t0), double(t1)])) > 1000
                    [dt0, dt1] = bms.config.AutoThresholdProposalService.expandDatetimeToSecondRange( ...
                        datetime(t0, 'ConvertFrom', 'datenum'), ...
                        datetime(t1, 'ConvertFrom', 'datenum'), padSeconds);
                    t0 = datenum(dt0);
                    t1 = datenum(dt1);
                end
            catch
            end
            t0Text = bms.config.AutoThresholdProposalService.timeText(t0, true);
            t1Text = bms.config.AutoThresholdProposalService.timeText(t1, true);
        end

        function [t0, t1] = expandDatetimeToSecondRange(t0, t1, padSeconds)
            sec = 1 / 86400;
            d0 = datenum(t0);
            d1 = datenum(t1);
            startTick = d0 / sec;
            startRound = round(startTick);
            if abs(startTick - startRound) < 1e-4
                startTick = startRound;
            else
                startTick = floor(startTick);
            end
            endTick = d1 / sec;
            endRound = round(endTick);
            if abs(endTick - endRound) < 1e-4
                endTick = endRound;
            else
                endTick = ceil(endTick);
            end
            startDn = startTick * sec - padSeconds * sec;
            endDn = endTick * sec + padSeconds * sec;
            if endDn <= startDn
                endDn = startDn + sec;
            end
            t0 = datetime(startDn, 'ConvertFrom', 'datenum');
            t1 = datetime(endDn, 'ConvertFrom', 'datenum');
        end

        function rows = zeroFlatReviews(values, moduleKey, pointId, sensorType, validCount, opts)
            rows = bms.config.AutoThresholdProposalService.emptyProposal();
            if validCount == 0
                return;
            end
            zeroRatio = sum(values == 0) / validCount;
            if zeroRatio >= opts.zero_ratio_threshold
                rows = bms.config.AutoThresholdProposalService.appendStruct(rows, ...
                    bms.config.AutoThresholdProposalService.makeProposal(false, moduleKey, pointId, ...
                    sensorType, 'review', 'zero_ratio', NaN, NaN, '', '', validCount, ...
                    sum(values == 0), zeroRatio, zeroRatio, 'many zero values; consider zero_to_nan'));
            end
            rounded = round(values, 12);
            [~, ~, ic] = unique(rounded);
            counts = accumarray(ic, 1);
            flatRatio = max(counts) / validCount;
            if flatRatio >= opts.flat_ratio_threshold
                rows = bms.config.AutoThresholdProposalService.appendStruct(rows, ...
                    bms.config.AutoThresholdProposalService.makeProposal(false, moduleKey, pointId, ...
                    sensorType, 'review', 'flat_ratio', NaN, NaN, '', '', validCount, ...
                    max(counts), flatRatio, flatRatio, 'nearly fixed value; review sensor or data link'));
            end
        end

        function p = makeProposal(selected, moduleKey, pointId, sensorType, kind, algorithm, mn, mx, t0, t1, validCount, removedCount, ratio, score, reason)
            labels = bms.config.AutoThresholdProposalService.moduleLabels({moduleKey});
            p = struct();
            p.selected = logical(selected);
            p.module_key = char(string(moduleKey));
            p.module_label = labels{1};
            p.point_id = char(string(pointId));
            p.safe_id = bms.data.PointResolver.configKey(pointId);
            p.sensor_type = char(string(sensorType));
            p.kind = char(string(kind));
            p.algorithm = char(string(algorithm));
            p.min = mn;
            p.max = mx;
            p.t_range_start = char(string(t0));
            p.t_range_end = char(string(t1));
            p.valid_count = double(validCount);
            p.removed_count = double(removedCount);
            p.removed_ratio = double(ratio);
            p.score = double(score);
            p.reason = char(string(reason));
            p.target_field = 'thresholds';
        end

        function spans = maskSpans(mask)
            idx = find(mask(:));
            spans = zeros(0, 2);
            if isempty(idx)
                return;
            end
            startIdx = idx(1);
            prev = idx(1);
            for i = 2:numel(idx)
                if idx(i) == prev + 1
                    prev = idx(i);
                    continue;
                end
                spans(end+1, :) = [startIdx, prev]; %#ok<AGROW>
                startIdx = idx(i);
                prev = idx(i);
            end
            spans(end+1, :) = [startIdx, prev];
        end

        function [low, high] = madBounds(values, factor)
            values = values(isfinite(values));
            if isempty(values)
                low = [];
                high = [];
                return;
            end
            med = median(values);
            sigma = 1.4826 * median(abs(values - med));
            if sigma <= 0 || ~isfinite(sigma)
                sigma = std(values);
            end
            if sigma <= 0 || ~isfinite(sigma)
                low = [];
                high = [];
                return;
            end
            low = med - factor * sigma;
            high = med + factor * sigma;
        end

        function [low, high] = iqrBounds(values, factor)
            q1 = bms.config.AutoThresholdProposalService.percentile(values, 25);
            q3 = bms.config.AutoThresholdProposalService.percentile(values, 75);
            width = q3 - q1;
            if width <= 0 || ~isfinite(width)
                low = [];
                high = [];
                return;
            end
            low = q1 - factor * width;
            high = q3 + factor * width;
        end

        function [low, high] = padBounds(low, high, factor)
            width = high - low;
            if ~isfinite(width) || width <= 0
                return;
            end
            pad = abs(width) * max(0, factor);
            low = low - pad;
            high = high + pad;
        end

        function q = percentile(values, pct)
            values = sort(values(isfinite(values)));
            if isempty(values)
                q = NaN;
                return;
            end
            pct = min(100, max(0, double(pct)));
            pos = 1 + (numel(values) - 1) * pct / 100;
            lo = floor(pos);
            hi = ceil(pos);
            if lo == hi
                q = values(lo);
            else
                q = values(lo) + (values(hi) - values(lo)) * (pos - lo);
            end
        end

        function txt = dateText(value, includeTime)
            if nargin < 2, includeTime = false; end
            txt = bms.config.AutoThresholdProposalService.timeText(value, includeTime);
            if ~includeTime && numel(txt) >= 10
                txt = txt(1:10);
            end
        end

        function txt = timeText(value, includeTime)
            if nargin < 2, includeTime = true; end
            if isempty(value)
                txt = '';
                return;
            end
            try
                if isdatetime(value)
                    dt = value;
                elseif isnumeric(value)
                    dt = datetime(value, 'ConvertFrom', 'datenum');
                else
                    dt = datetime(char(string(value)));
                end
                if includeTime
                    txt = datestr(dt, 'yyyy-mm-dd HH:MM:SS');
                else
                    txt = datestr(dt, 'yyyy-mm-dd');
                end
            catch
                txt = char(string(value));
            end
        end

        function tf = boolOpt(opts, field, defaultValue)
            tf = defaultValue;
            if isstruct(opts) && isfield(opts, field) && ~isempty(opts.(field))
                tf = logical(opts.(field));
            end
        end

        function val = numericField(s, field)
            val = [];
            if isstruct(s) && isfield(s, field)
                val = bms.config.AutoThresholdProposalService.cellNumber(s.(field));
            end
        end

        function val = numericOpt(opts, field, defaultValue)
            val = defaultValue;
            if isstruct(opts) && isfield(opts, field) && ~isempty(opts.(field))
                parsed = bms.config.AutoThresholdProposalService.cellNumber(opts.(field));
                if isfinite(parsed)
                    val = parsed;
                end
            end
        end

        function txt = textField(s, field)
            txt = '';
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                txt = char(string(s.(field)));
            end
        end

        function tf = cellBool(value, defaultValue)
            tf = defaultValue;
            if isempty(value)
                return;
            end
            if islogical(value)
                tf = value;
            elseif isnumeric(value)
                tf = value ~= 0;
            else
                txt = lower(strtrim(char(string(value))));
                tf = any(strcmp(txt, {'true', '1', 'yes', 'y'}));
            end
        end

        function n = cellNumber(value)
            n = NaN;
            if isempty(value)
                return;
            end
            if isnumeric(value)
                n = double(value(1));
            else
                n = str2double(char(string(value)));
            end
        end

        function txt = cellText(value)
            txt = '';
            if ~isempty(value)
                txt = char(string(value));
            end
        end
    end
end
