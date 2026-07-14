classdef SpectrumConfigService
    %SPECTRUMCONFIGSERVICE Configuration helpers for spectrum workflows.

    methods (Static)
        function points = resolvePoints(cfg, spec)
            points = {};
            for i = 1:numel(spec.pointKeys)
                points = bms.data.PointResolver.fromConfig(cfg, spec.pointKeys{i}, {});
                if ~isempty(points)
                    return;
                end
            end
            if isfield(spec, 'forceGroupKey') && ~isempty(spec.forceGroupKey)
                groupsCfg = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, spec.forceGroupKey, []);
                points = bms.analyzer.StructuralPlotConfigService.flattenGroups(groupsCfg);
                if ~isempty(points)
                    points = unique(points(:), 'stable');
                    return;
                end
            end
            points = spec.defaultPoints;
        end

        function subfolder = resolveSubfolder(cfg, spec)
            subfolder = '';
            for i = 1:numel(spec.subfolderKeys)
                subfolder = bms.config.ConfigReader.getSubfolder(cfg, spec.subfolderKeys{i}, '');
                if ~isempty(subfolder)
                    return;
                end
            end
            subfolder = spec.defaultSubfolder;
        end

        function style = plotStyle(cfg, spec)
            style = bms.config.ConfigReader.getPlotStyle(cfg, spec.styleKey, spec.defaultStyle);
        end

        function value = param(cfg, spec, field, defaultValue)
            params = bms.config.ConfigReader.getStruct(cfg, spec.paramsKey, struct());
            value = bms.config.ConfigReader.getField(params, field, defaultValue);
        end

        function [freqs, labels] = theoreticalFrequencies(cfg, spec)
            params = bms.config.ConfigReader.getStruct(cfg, spec.paramsKey, struct());
            orders = bms.config.ConfigReader.getField(params, 'peak_orders', []);
            [ok, ~, ~, orderFreqs, orderLabels] = ...
                bms.analyzer.SpectrumConfigService.peakOrdersToParams( ...
                    orders, [], [], [], {}, {});
            if ok && ~isempty(orderFreqs)
                freqs = orderFreqs;
                labels = bms.analyzer.SpectrumConfigService.normalizeTheorLabels( ...
                    orderLabels, freqs);
                return;
            end
            freqs = bms.config.ConfigReader.getField(params, 'theor_freqs', []);
            labels = bms.config.ConfigReader.getField(params, 'theor_labels', {});
            labels = bms.analyzer.SpectrumConfigService.normalizeTheorLabels(labels, freqs);
        end

        function [freqs, tol, theorFreqs, theorLabels, peakLabels] = pointParams(cfg, pid, spec, defaultFreqs, defaultTol, defaultTheorFreqs, defaultTheorLabels, useGlobalPeakOrders)
            if nargin < 8 || isempty(useGlobalPeakOrders)
                useGlobalPeakOrders = true;
            end
            freqs = defaultFreqs;
            tol = defaultTol;
            theorFreqs = defaultTheorFreqs;
            theorLabels = defaultTheorLabels;
            peakLabels = bms.analyzer.SpectrumConfigService.defaultPeakLabels(freqs);

            if useGlobalPeakOrders
                params = bms.config.ConfigReader.getStruct(cfg, spec.paramsKey, struct());
                [ok, freqs2, tol2, theorFreqs2, theorLabels2, peakLabels2] = ...
                    bms.analyzer.SpectrumConfigService.peakOrdersToParams( ...
                        bms.config.ConfigReader.getField(params, 'peak_orders', []), ...
                        freqs, tol, theorFreqs, theorLabels, peakLabels);
                if ok
                    freqs = freqs2;
                    tol = tol2;
                    theorFreqs = theorFreqs2;
                    theorLabels = theorLabels2;
                    peakLabels = peakLabels2;
                end
            end

            pt = bms.analyzer.SpectrumConfigService.pointConfig(cfg, spec.perPointKey, pid);
            if isstruct(pt)
                [ok, freqs2, tol2, theorFreqs2, theorLabels2, peakLabels2] = ...
                    bms.analyzer.SpectrumConfigService.peakOrdersToParams( ...
                        bms.config.ConfigReader.getField(pt, 'peak_orders', []), ...
                        freqs, tol, theorFreqs, theorLabels, peakLabels);
                if ok
                    freqs = freqs2;
                    tol = tol2;
                    theorFreqs = theorFreqs2;
                    theorLabels = theorLabels2;
                    peakLabels = peakLabels2;
                else
                    freqs = bms.config.ConfigReader.getField(pt, 'target_freqs', freqs);
                    tol = bms.config.ConfigReader.getField(pt, 'tolerance', tol);
                    theorFreqs = bms.config.ConfigReader.getField(pt, 'theor_freqs', theorFreqs);
                    theorLabels = bms.config.ConfigReader.getField(pt, 'theor_labels', theorLabels);
                    peakLabels = bms.config.ConfigReader.getField(pt, 'peak_labels', peakLabels);
                end
            end
            tol = bms.analyzer.SpectrumConfigService.normalizeTolerance(tol, freqs);
            theorLabels = bms.analyzer.SpectrumConfigService.normalizeTheorLabels(theorLabels, theorFreqs);
            peakLabels = bms.analyzer.SpectrumConfigService.normalizePeakLabels(peakLabels, freqs);
        end

        function pt = pointConfig(cfg, perPointKey, pid)
            pt = [];
            if ~isstruct(cfg) || ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point) || ...
                    ~isfield(cfg.per_point, perPointKey) || ~isstruct(cfg.per_point.(perPointKey))
                return;
            end
            perPoint = cfg.per_point.(perPointKey);
            [ok, pt] = bms.data.PointResolver.getPointConfig(perPoint, pid, cfg);
            if ~ok
                pt = [];
            end
        end

        function labels = normalizeTheorLabels(labels, freqs)
            if isempty(freqs)
                labels = {};
                return;
            end
            if isstring(labels)
                labels = cellstr(labels(:));
            elseif ischar(labels)
                labels = {labels};
            elseif ~iscell(labels)
                labels = {};
            end
            if numel(labels) ~= numel(freqs)
                labels = arrayfun(@(f) sprintf('理论频率 %.3fHz', f), freqs(:), 'UniformOutput', false);
            end
        end

        function labels = normalizePeakLabels(labels, freqs)
            if isempty(freqs)
                labels = {};
                return;
            end
            if isstring(labels)
                labels = cellstr(labels(:));
            elseif ischar(labels)
                labels = {labels};
            elseif ~iscell(labels)
                labels = {};
            end
            if numel(labels) ~= numel(freqs)
                labels = bms.analyzer.SpectrumConfigService.defaultPeakLabels(freqs);
            end
        end

        function labels = defaultPeakLabels(freqs)
            labels = arrayfun(@(k) sprintf('峰%d', k), (1:numel(freqs)).', 'UniformOutput', false);
        end

        function tol = normalizeTolerance(tol, freqs)
            if isempty(freqs)
                tol = [];
                return;
            end
            if isempty(tol)
                tol = 0.15;
            end
            tol = double(tol(:).');
            if isempty(tol)
                tol = 0.15;
            end
            if isscalar(tol)
                return;
            end
            if numel(tol) < numel(freqs)
                tol(end+1:numel(freqs)) = tol(end);
            elseif numel(tol) > numel(freqs)
                tol = tol(1:numel(freqs));
            end
        end

        function [ok, freqs, tol, theorFreqs, theorLabels, peakLabels] = peakOrdersToParams(orders, fallbackFreqs, fallbackTol, fallbackTheorFreqs, fallbackTheorLabels, fallbackPeakLabels)
            ok = false;
            freqs = fallbackFreqs;
            tol = fallbackTol;
            theorFreqs = fallbackTheorFreqs;
            theorLabels = fallbackTheorLabels;
            if nargin < 6 || isempty(fallbackPeakLabels)
                peakLabels = bms.analyzer.SpectrumConfigService.defaultPeakLabels(fallbackFreqs);
            else
                peakLabels = fallbackPeakLabels;
            end
            if isempty(orders)
                return;
            end
            if iscell(orders)
                try
                    orders = [orders{:}];
                catch
                    return;
                end
            end
            if ~isstruct(orders)
                return;
            end

            outFreqs = [];
            outTol = [];
            outTheor = [];
            outTheorLabels = {};
            outPeakLabels = {};

            for i = 1:numel(orders)
                item = orders(i);
                searchMin = bms.analyzer.SpectrumConfigService.firstNumericField( ...
                    item, {'search_min_hz', 'min_hz', 'lower_hz'});
                searchMax = bms.analyzer.SpectrumConfigService.firstNumericField( ...
                    item, {'search_max_hz', 'max_hz', 'upper_hz'});
                hasRange = isfinite(searchMin) && isfinite(searchMax) && searchMax > searchMin;
                center = bms.analyzer.SpectrumConfigService.firstNumericField( ...
                    item, {'search_center_hz', 'target_hz', 'frequency_hz', 'freq_hz'});
                if ~isfinite(center) && hasRange
                    center = (searchMin + searchMax) / 2;
                end
                if ~isfinite(center)
                    center = bms.analyzer.SpectrumConfigService.firstNumericField( ...
                        item, {'theoretical_hz', 'theor_hz'});
                end
                if ~isfinite(center)
                    continue;
                end
                halfWidth = bms.analyzer.SpectrumConfigService.firstNumericField( ...
                    item, {'search_half_width_hz', 'tolerance_hz', 'half_width_hz'});
                if ~isfinite(halfWidth) && hasRange
                    halfWidth = (searchMax - searchMin) / 2;
                end
                if ~isfinite(halfWidth)
                    if isscalar(fallbackTol) && ~isempty(fallbackTol)
                        halfWidth = fallbackTol;
                    else
                        halfWidth = 0.15;
                    end
                end
                if ~isfinite(halfWidth) || halfWidth <= 0
                    halfWidth = 0.15;
                end
                theor = bms.analyzer.SpectrumConfigService.firstNumericField( ...
                    item, {'theoretical_hz', 'theor_hz'});
                label = bms.analyzer.SpectrumConfigService.orderLabel(item, numel(outFreqs) + 1);
                theorLabel = bms.analyzer.SpectrumConfigService.firstTextField(item, {'theor_label', 'theoretical_label'});
                if isempty(theorLabel) && isfinite(theor)
                    theorLabel = sprintf('理论%s频率 %.3fHz', label, theor);
                end

                outFreqs(end+1) = center; %#ok<AGROW>
                outTol(end+1) = halfWidth; %#ok<AGROW>
                outPeakLabels{end+1} = label; %#ok<AGROW>
                if isfinite(theor)
                    outTheor(end+1) = theor; %#ok<AGROW>
                    outTheorLabels{end+1} = theorLabel; %#ok<AGROW>
                end
            end

            if isempty(outFreqs)
                return;
            end
            freqs = outFreqs;
            tol = outTol;
            theorFreqs = outTheor;
            theorLabels = outTheorLabels;
            peakLabels = outPeakLabels;
            ok = true;
        end

        function value = firstNumericField(s, names)
            value = NaN;
            for i = 1:numel(names)
                name = names{i};
                if isfield(s, name) && ~isempty(s.(name))
                    raw = s.(name);
                    if isnumeric(raw) && isscalar(raw)
                        value = double(raw);
                    elseif isstring(raw) || ischar(raw)
                        value = str2double(char(string(raw)));
                    end
                    if isfinite(value)
                        return;
                    end
                end
            end
        end

        function value = firstTextField(s, names)
            value = '';
            for i = 1:numel(names)
                name = names{i};
                if isfield(s, name) && ~isempty(s.(name))
                    value = char(string(s.(name)));
                    return;
                end
            end
        end

        function label = orderLabel(item, fallbackOrder)
            label = bms.analyzer.SpectrumConfigService.firstTextField(item, {'label', 'name'});
            if ~isempty(label)
                return;
            end
            order = bms.analyzer.SpectrumConfigService.firstNumericField(item, {'order'});
            if ~isfinite(order)
                order = fallbackOrder;
            end
            orderNames = {'一阶', '二阶', '三阶', '四阶', '五阶', '六阶'};
            if order >= 1 && order <= numel(orderNames) && abs(order - round(order)) < eps
                label = orderNames{round(order)};
            else
                label = sprintf('%g阶', order);
            end
        end

        function dirs = ensureOutputDirs(rootDir, spec, style)
            if nargin < 3
                style = struct();
            end
            dirs.freqRoot = fullfile(rootDir, spec.freqOutputDir);
            dirs.psdRoot = fullfile(rootDir, spec.psdOutputDir);
            bms.core.PathResolver.ensureDir(dirs.freqRoot);
            bms.core.PathResolver.ensureDir(dirs.psdRoot);

            if isfield(spec, 'freqGroupOutputDir') && ~isempty(spec.freqGroupOutputDir)
                groupOutputDir = spec.freqGroupOutputDir;
                if isstruct(style) && isfield(style, 'freq_group_output_dir') && ~isempty(style.freq_group_output_dir)
                    groupOutputDir = style.freq_group_output_dir;
                elseif isstruct(style) && isfield(style, 'group_output_dir') && ~isempty(style.group_output_dir)
                    groupOutputDir = style.group_output_dir;
                end
                dirs.freqGroupRoot = fullfile(rootDir, groupOutputDir);
                bms.core.PathResolver.ensureDir(dirs.freqGroupRoot);
            end

            if spec.includeForce
                forceOutputDir = spec.forceOutputDir;
                forceGroupOutputDir = spec.forceGroupOutputDir;
                if isstruct(style) && isfield(style, 'force_output_dir') && ~isempty(style.force_output_dir)
                    forceOutputDir = style.force_output_dir;
                end
                if isstruct(style) && isfield(style, 'force_group_output_dir') && ~isempty(style.force_group_output_dir)
                    forceGroupOutputDir = style.force_group_output_dir;
                end
                dirs.forceRoot = fullfile(rootDir, forceOutputDir);
                dirs.forceGroupRoot = fullfile(rootDir, forceGroupOutputDir);
                bms.core.PathResolver.ensureDir(dirs.forceRoot);
                bms.core.PathResolver.ensureDir(dirs.forceGroupRoot);
            end
        end
    end
end
