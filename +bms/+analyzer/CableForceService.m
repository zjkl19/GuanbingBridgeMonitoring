classdef CableForceService
    %CABLEFORCESERVICE Shared helpers for cable-force post-processing.

    methods (Static)
        function [rho, spanLength, decimals, hasParams] = params(cfg, pointId)
            rho = NaN;
            spanLength = NaN;
            decimals = 2;
            hasParams = false;
            if ~isstruct(cfg) || ~isfield(cfg, 'per_point') || ~isfield(cfg.per_point, 'cable_accel')
                return;
            end

            [ok, pointCfg] = bms.data.PointResolver.getPointConfig(cfg.per_point.cable_accel, pointId, cfg);
            if ~ok
                return;
            end

            if isfield(pointCfg, 'rho'), rho = pointCfg.rho; end
            if isfield(pointCfg, 'L'), spanLength = pointCfg.L; end
            if isfield(pointCfg, 'force_decimals') && ~isempty(pointCfg.force_decimals)
                decimals = pointCfg.force_decimals;
            end
            hasParams = isfinite(rho) && isfinite(spanLength);
        end

        function force = compute(freqs, rho, spanLength, decimals)
            force = NaN(size(freqs));
            if isempty(freqs)
                return;
            end
            if isempty(rho) || isempty(spanLength) || ~isfinite(rho) || ~isfinite(spanLength)
                return;
            end

            force = 4 * rho .* (spanLength .^ 2) .* (freqs .^ 2) / 1000;
            if nargin >= 4 && ~isempty(decimals) && isnumeric(decimals)
                force = round(force, decimals);
            end
        end

        function forceYLim = resolveYLim(cfg, pointId, style)
            forceYLim = [];
            if nargin >= 3 && isstruct(style) && isfield(style, 'force_ylim') && ~isempty(style.force_ylim)
                forceYLim = style.force_ylim;
            end
            if isstruct(cfg) && isfield(cfg, 'per_point') && isfield(cfg.per_point, 'cable_accel')
                [ok, pointCfg] = bms.data.PointResolver.getPointConfig(cfg.per_point.cable_accel, pointId, cfg);
                if ok
                    if isfield(pointCfg, 'force_ylim') && ~isempty(pointCfg.force_ylim)
                        forceYLim = pointCfg.force_ylim;
                    end
                end
            end

            if isempty(forceYLim)
                return;
            end
            if ~(isnumeric(forceYLim) && numel(forceYLim) == 2 && all(isfinite(forceYLim(:))))
                warning('测点 %s force_ylim 无效，使用自动范围', char(string(pointId)));
                forceYLim = [];
                return;
            end
            forceYLim = reshape(forceYLim, 1, 2);
            if ~(forceYLim(2) > forceYLim(1))
                warning('测点 %s force_ylim 无效（min>=max），使用自动范围', char(string(pointId)));
                forceYLim = [];
            end
        end

        function warnLines = warnLines(cfg, pointId, style, labelPrefix)
            if nargin < 4
                labelPrefix = '';
            end
            warnLines = {};
            if nargin >= 3 && isstruct(style) && isfield(style, 'force_warn_lines') && ~isempty(style.force_warn_lines)
                warnLines = bms.analyzer.CableForceService.normalizeWarnLines(style.force_warn_lines, style, labelPrefix);
            end
            if ~isstruct(cfg) || ~isfield(cfg, 'per_point') || ~isfield(cfg.per_point, 'cable_accel')
                return;
            end

            [ok, pointCfg] = bms.data.PointResolver.getPointConfig(cfg.per_point.cable_accel, pointId, cfg);
            if ~ok
                return;
            end

            if isfield(pointCfg, 'force_alarm_bounds') && ~isempty(pointCfg.force_alarm_bounds)
                warnLines = bms.analyzer.CableForceService.normalizeAlarmBounds(pointCfg.force_alarm_bounds, style, labelPrefix);
            elseif isfield(pointCfg, 'force_alarm_levels')
                warnLines = bms.analyzer.CableForceService.normalizeWarnLines(pointCfg.force_alarm_levels, style, labelPrefix);
            end
        end

        function warnLines = normalizeAlarmBounds(value, style, labelPrefix)
            warnLines = {};
            if isempty(value) || ~isstruct(value)
                return;
            end
            if nargin < 3
                labelPrefix = '';
            end

            colors = bms.analyzer.CableForceService.alarmColors(style);
            unit = bms.analyzer.StructuralPlotConfigService.warnUnit(style);
            labels = bms.analyzer.CableForceService.boundWarnLabels();
            bounds = {
                'level2', 1, labels{1};
                'level3', 2, labels{2}
            };
            for i = 1:size(bounds, 1)
                field = bounds{i, 1};
                colorIdx = bounds{i, 2};
                levelLabel = bounds{i, 3};
                if ~isfield(value, field) || isempty(value.(field))
                    continue;
                end
                vals = value.(field);
                if ~(isnumeric(vals) && numel(vals) == 2 && all(isfinite(vals(:))))
                    continue;
                end
                vals = sort(reshape(vals, 1, 2));
                warnLines{end+1, 1} = struct( ... %#ok<AGROW>
                    'y', vals(1), ...
                    'color', colors(colorIdx, :), ...
                    'label', bms.analyzer.CableForceService.composeWarnLabel(labelPrefix, ...
                        bms.analyzer.StructuralPlotConfigService.composeWarnValueLabel(levelLabel, vals(1), unit)), ...
                    'level', levelLabel, ...
                    'unit', unit);
                warnLines{end+1, 1} = struct( ... %#ok<AGROW>
                    'y', vals(2), ...
                    'color', colors(colorIdx, :), ...
                    'label', bms.analyzer.CableForceService.composeWarnLabel(labelPrefix, ...
                        bms.analyzer.StructuralPlotConfigService.composeWarnValueLabel(levelLabel, vals(2), unit)), ...
                    'level', levelLabel, ...
                    'unit', unit);
            end
        end

        function warnLines = normalizeWarnLines(value, style, labelPrefix)
            warnLines = {};
            if isempty(value)
                return;
            end
            if nargin < 3
                labelPrefix = '';
            end

            if nargin < 2 || isempty(style)
                colors = [0.72 0.50 0.00; 0.85 0.1 0.1];
            else
                colors = bms.analyzer.CableForceService.alarmColors(style);
            end
            labels = bms.analyzer.CableForceService.defaultWarnLabels();
            unit = bms.analyzer.StructuralPlotConfigService.warnUnit(style);

            if isnumeric(value)
                values = value(:);
                values = values(isfinite(values));
                warnLines = cell(numel(values), 1);
                for i = 1:numel(values)
                    warnLines{i} = struct('y', values(i));
                    if i <= size(colors, 1)
                        warnLines{i}.color = colors(i, :);
                    end
                    if i <= numel(labels)
                        warnLines{i}.label = bms.analyzer.CableForceService.composeWarnLabel(labelPrefix, ...
                            bms.analyzer.StructuralPlotConfigService.composeWarnValueLabel(labels{i}, values(i), unit));
                        warnLines{i}.level = labels{i};
                        warnLines{i}.unit = unit;
                    end
                end
                return;
            end

            if isstruct(value)
                warnLines = num2cell(value);
            elseif iscell(value)
                warnLines = value(:);
            else
                return;
            end

            for i = 1:numel(warnLines)
                warnLine = warnLines{i};
                if ~isstruct(warnLine)
                    continue;
                end
                if (~isfield(warnLine, 'color') || isempty(warnLine.color)) && i <= size(colors, 1)
                    warnLine.color = colors(i, :);
                end
                if (~isfield(warnLine, 'label') || isempty(warnLine.label)) && i <= numel(labels)
                    yValue = NaN;
                    if isfield(warnLine, 'y') && isnumeric(warnLine.y) && isscalar(warnLine.y)
                        yValue = warnLine.y;
                    end
                    if isfinite(yValue)
                        warnLine.label = bms.analyzer.CableForceService.composeWarnLabel(labelPrefix, ...
                            bms.analyzer.StructuralPlotConfigService.composeWarnValueLabel(labels{i}, yValue, unit));
                    else
                        warnLine.label = bms.analyzer.CableForceService.composeWarnLabel(labelPrefix, labels{i});
                    end
                    warnLine.level = labels{i};
                end
                if (~isfield(warnLine, 'unit') || isempty(warnLine.unit)) && ~isempty(unit)
                    warnLine.unit = unit;
                end
                warnLines{i} = warnLine;
            end
        end

        function colors = alarmColors(style)
            colors = [0.72 0.50 0.00; 0.85 0.1 0.1];
            if nargin < 1 || ~isstruct(style) || ~isfield(style, 'force_alarm_colors') || isempty(style.force_alarm_colors)
                return;
            end
            value = style.force_alarm_colors;
            if isnumeric(value) && size(value, 2) == 3
                colors = value;
            elseif isstruct(value) && isfield(value, 'yellow') && isfield(value, 'red')
                colors = [reshape(value.yellow, 1, 3); reshape(value.red, 1, 3)];
            elseif iscell(value) && numel(value) >= 2
                colors = [reshape(value{1}, 1, 3); reshape(value{2}, 1, 3)];
            end
        end

        function label = warnLabel(warnLine)
            label = bms.analyzer.StructuralPlotConfigService.warnLabel(warnLine);
        end

        function labels = defaultWarnLabels()
            labels = {char([19968 32423]), char([20108 32423])};
        end

        function labels = boundWarnLabels()
            labels = {char([20108 32423]), char([19977 32423])};
        end

        function label = composeWarnLabel(prefix, baseLabel)
            if nargin < 1 || isempty(prefix)
                label = baseLabel;
            else
                label = sprintf('%s %s', char(string(prefix)), char(string(baseLabel)));
            end
        end
    end
end
