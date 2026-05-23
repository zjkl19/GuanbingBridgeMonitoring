classdef ConfigLinter
    %CONFIGLINTER Higher-level config health checks for project configs.

    methods (Static)
        function result = lint(cfg)
            base = bms.config.SchemaValidator.validateDetailed(cfg);
            result = struct();
            result.errors = base.errors;
            result.infos = {};
            result.checked_at = base.checked_at;
            result.issues = bms.config.ConfigLinter.issueDetails(base.warnings, 'schema');

            extraWarnings = [bms.config.ConfigLinter.checkPerPointReferences(cfg), ...
                bms.config.ConfigLinter.checkPlotWarningPreviews(cfg)];
            result.issues = [result.issues, bms.config.ConfigLinter.issueDetails(extraWarnings, 'config')];

            result.warnings = bms.config.ConfigLinter.messagesBySeverity(result.issues, {'warning', 'error'});
            result.infos = bms.config.ConfigLinter.messagesBySeverity(result.issues, {'info'});
            result.summary = bms.config.ConfigLinter.issueSummary(result.issues, result.errors);
            if ~isempty(result.errors)
                result.status = 'failed';
            elseif ~isempty(result.warnings)
                result.status = 'warning';
            else
                result.status = 'ok';
            end
        end

        function result = lintPath(path)
            cfg = load_config(path);
            result = bms.config.ConfigLinter.lint(cfg);
            result.path = char(string(path));
            if contains(lower(char(string(path))), 'backup') || contains(lower(char(string(path))), 'desktop')
                result.infos{end+1} = 'lint target path looks like a backup or desktop copy';
            end
        end

        function result = scanDirectory(dirPath)
            result = struct('status', 'ok', 'files', {{}}, 'warnings', {{}}, 'errors', {{}});
            if ~isfolder(dirPath)
                result.status = 'failed';
                result.errors{end+1} = ['directory not found: ' char(string(dirPath))];
                return;
            end
            files = dir(fullfile(char(string(dirPath)), '*.json'));
            result.files = arrayfun(@(x) fullfile(x.folder, x.name), files, 'UniformOutput', false);
            for i = 1:numel(files)
                name = lower(files(i).name);
                if contains(name, 'backup') || contains(name, 'desktop')
                    result.warnings{end+1} = ['backup-like config file in active directory: ' files(i).name]; %#ok<AGROW>
                end
            end
            if ~isempty(result.warnings)
                result.status = 'warning';
            end
        end

        function lines = toLogLines(result, maxItems)
            if nargin < 2 || isempty(maxItems)
                maxItems = 8;
            end
            lines = {};
            if ~isstruct(result)
                return;
            end
            warnings = {};
            infos = {};
            errors = {};
            if isfield(result, 'warnings'), warnings = result.warnings; end
            if isfield(result, 'infos'), infos = result.infos; end
            if isfield(result, 'errors'), errors = result.errors; end
            lines{end+1} = sprintf('配置健康检查: status=%s, errors=%d, warnings=%d, infos=%d', ...
                char(string(result.status)), numel(errors), numel(warnings), numel(infos));
            shown = 0;
            for i = 1:numel(errors)
                if shown >= maxItems, break; end
                lines{end+1} = ['  error: ' char(string(errors{i}))]; %#ok<AGROW>
                shown = shown + 1;
            end
            for i = 1:numel(warnings)
                if shown >= maxItems, break; end
                lines{end+1} = ['  warning: ' char(string(warnings{i}))]; %#ok<AGROW>
                shown = shown + 1;
            end
            for i = 1:numel(infos)
                if shown >= maxItems, break; end
                lines{end+1} = ['  info: ' char(string(infos{i}))]; %#ok<AGROW>
                shown = shown + 1;
            end
            total = numel(errors) + numel(warnings) + numel(infos);
            if total > shown
                lines{end+1} = sprintf('  ... 另有 %d 项，详见命令行或导出的检查结果。', total - shown); %#ok<AGROW>
            end
        end
    end

    methods (Static, Access = private)
        function issues = issueDetails(messages, defaultCategory)
            issues = struct('severity', {}, 'category', {}, 'message', {}, 'action', {});
            if isempty(messages)
                return;
            end
            for i = 1:numel(messages)
                msg = char(string(messages{i}));
                if isempty(msg)
                    continue;
                end
                [severity, category, action] = bms.config.ConfigLinter.classifyMessage(msg, defaultCategory);
                issues(end+1) = struct( ... %#ok<AGROW>
                    'severity', severity, ...
                    'category', category, ...
                    'message', msg, ...
                    'action', action);
            end
        end

        function [severity, category, action] = classifyMessage(message, defaultCategory)
            severity = 'warning';
            category = char(string(defaultCategory));
            action = '核查配置项是否符合当前桥梁数据处理链路。';
            msg = char(string(message));

            if contains(msg, 'is configured but empty')
                severity = 'info';
                category = 'optional_empty_points';
                action = '可选测项当前为空；若本桥无需该测项，可保持为空。';
            elseif contains(msg, 'has no file pattern mapping')
                severity = 'info';
                category = 'legacy_file_pattern_fallback';
                action = '当前可能依赖默认文件名匹配或专项读取逻辑；启用该测项前再补充 file_patterns。';
            elseif contains(msg, 'pending_')
                severity = 'info';
                category = 'pending_design_points';
                action = '待接入或待确认测点，运行前不作为阻断项。';
            elseif startsWith(msg, 'reporting.')
                severity = 'info';
                category = 'reporting_specific_config';
                action = '报告专项配置由报告生成器消费，数据处理运行前不作为阻断项。';
            elseif contains(msg, 'threshold min > max') || contains(msg, 'threshold missing min/max')
                severity = 'warning';
                category = 'threshold_schema';
                action = '建议修正阈值上下限或补全 min/max。';
            elseif contains(msg, 'has no matching configured point/group entry')
                severity = 'warning';
                category = 'orphan_per_point_rule';
                action = 'per_point 规则未匹配到 points/groups 中的测点，建议清理或补齐测点映射。';
            elseif contains(msg, 'not registered')
                severity = 'warning';
                category = 'unknown_config_key';
                action = '建议先在 ModuleConfigRegistry 注册该配置 key，再继续使用。';
            elseif contains(msg, 'has no usable subfolder mapping')
                severity = 'warning';
                category = 'missing_subfolder_mapping';
                action = '启用该测项前应补充 subfolders 或确认专项读取逻辑。';
            end
        end

        function messages = messagesBySeverity(issues, severities)
            messages = {};
            if isempty(issues)
                return;
            end
            if ischar(severities) || isstring(severities)
                severities = cellstr(string(severities));
            end
            for i = 1:numel(issues)
                if any(strcmp(issues(i).severity, severities))
                    messages{end+1} = issues(i).message; %#ok<AGROW>
                end
            end
        end

        function summary = issueSummary(issues, errors)
            summary = struct('error', numel(errors), 'warning', 0, 'info', 0, ...
                'categories', struct());
            for i = 1:numel(issues)
                severity = issues(i).severity;
                if isfield(summary, severity)
                    summary.(severity) = summary.(severity) + 1;
                end
                category = matlab.lang.makeValidName(issues(i).category);
                if ~isfield(summary.categories, category)
                    summary.categories.(category) = 0;
                end
                summary.categories.(category) = summary.categories.(category) + 1;
            end
        end

        function warnings = checkPerPointReferences(cfg)
            warnings = {};
            if ~isstruct(cfg) || ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point)
                return;
            end
            known = bms.config.ModuleConfigRegistry.knownConfigKeys();
            modules = fieldnames(cfg.per_point);
            for i = 1:numel(modules)
                moduleKey = modules{i};
                if ~ismember(moduleKey, known)
                    warnings{end+1} = ['per_point.' moduleKey ' is not registered in ModuleConfigRegistry']; %#ok<AGROW>
                    continue;
                end
                configured = bms.config.ModuleConfigResolver.resolvePoints(cfg, moduleKey, {});
                if isempty(configured)
                    continue;
                end
                pointRules = cfg.per_point.(moduleKey);
                if ~isstruct(pointRules)
                    continue;
                end
                pointKeys = fieldnames(pointRules);
                for j = 1:numel(pointKeys)
                    if ~bms.config.ConfigLinter.pointKeyMatches(pointKeys{j}, configured, cfg)
                        warnings{end+1} = sprintf('per_point.%s.%s has no matching configured point/group entry', ...
                            moduleKey, pointKeys{j}); %#ok<AGROW>
                    end
                end
            end
        end

        function warnings = checkPlotWarningPreviews(cfg)
            warnings = {};
            if ~isstruct(cfg)
                return;
            end
            specs = bms.config.ModuleConfigRegistry.plotModuleDefs();
            for i = 1:numel(specs)
                spec = specs(i);
                style = bms.config.ModuleConfigResolver.rawPlotStyle(cfg, spec);
                for j = 1:numel(spec.warn_fields)
                    fieldName = spec.warn_fields{j};
                    try
                        preview = bms.analyzer.PlotWarningLineResolver.tablePreview(cfg, spec, style, fieldName);
                    catch ME
                        warnings{end+1} = sprintf('plot warning preview failed for %s.%s: %s', ...
                            spec.value, fieldName, ME.message); %#ok<AGROW>
                        continue;
                    end
                    if strcmp(preview.source, 'explicit_map') && isempty(preview.rows)
                        warnings{end+1} = sprintf('plot_styles.%s.%s is a group map but resolves to no rows', ...
                            spec.style_key, fieldName); %#ok<AGROW>
                    end
                end
            end
        end

        function tf = pointKeyMatches(pointKey, configured, cfg)
            tf = false;
            pointKey = char(string(pointKey));
            for k = 1:numel(configured)
                candidates = bms.data.PointResolver.keyCandidates(configured{k}, cfg);
                if any(strcmp(candidates, pointKey))
                    tf = true;
                    return;
                end
            end
            original = bms.data.PointResolver.originalId(pointKey, cfg);
            tf = any(strcmp(configured, original));
        end
    end
end
