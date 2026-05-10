classdef SpectrumAnalysisPipeline
    %SPECTRUMANALYSISPIPELINE Shared acceleration/cable spectrum workflow.

    methods (Static)
        function run(kind, rootDir, startDate, endDate, pointIds, excelFile, subfolder, targetFreqs, tolerance, useParallel, cfg)
            spec = bms.analyzer.SpectrumAnalysisPipeline.spec(kind);

            if nargin < 2 || isempty(rootDir), rootDir = pwd; end
            if nargin < 3 || isempty(startDate), error('必须指定 start_date'); end
            if nargin < 4 || isempty(endDate), error('必须指定 end_date'); end
            if nargin < 11 || isempty(cfg), cfg = load_config(); end
            if nargin < 5 || isempty(pointIds)
                pointIds = bms.analyzer.SpectrumAnalysisPipeline.resolvePoints(cfg, spec);
            else
                pointIds = bms.data.PointResolver.normalize(pointIds);
            end
            if nargin < 6 || isempty(excelFile), excelFile = spec.defaultExcel; end
            if nargin < 7 || isempty(subfolder)
                subfolder = bms.analyzer.SpectrumAnalysisPipeline.resolveSubfolder(cfg, spec);
            end
            if nargin < 8 || isempty(targetFreqs)
                targetFreqs = bms.analyzer.SpectrumAnalysisPipeline.param(cfg, spec, 'target_freqs', spec.defaultTargetFreqs);
            end
            if nargin < 9 || isempty(tolerance)
                tolerance = bms.analyzer.SpectrumAnalysisPipeline.param(cfg, spec, 'tolerance', spec.defaultTolerance);
            end
            if nargin < 10 || isempty(useParallel), useParallel = false; end

            rootDir = char(rootDir);
            excelFile = resolve_data_output_path(rootDir, excelFile, 'stats');
            style = bms.analyzer.SpectrumAnalysisPipeline.plotStyle(cfg, spec);
            dirs = bms.analyzer.SpectrumAnalysisPipeline.ensureOutputDirs(rootDir, spec);
            datesAll = (datetime(startDate):days(1):datetime(endDate)).';
            [theorFreqs, theorLabels] = bms.analyzer.SpectrumAnalysisPipeline.theoreticalFrequencies(cfg, spec);

            if useParallel
                p = gcp('nocreate');
                if isempty(p), parpool('local'); end
            end

            nPts = numel(pointIds);
            forceSeriesAll = cell(nPts, 1);
            forceValidAll = false(nPts, 1);

            for i = 1:nPts
                pid = pointIds{i};
                fprintf('\n---- 测点 %s ----\n', pid);

                [targetFreqsPt, tolerancePt, theorFreqsPt, theorLabelsPt] = ...
                    bms.analyzer.SpectrumAnalysisPipeline.pointParams( ...
                        cfg, pid, spec, targetFreqs, tolerance, theorFreqs, theorLabels);
                [ampDay, freqDay] = bms.analyzer.SpectrumAnalysisPipeline.processPoint( ...
                    datesAll, pid, rootDir, subfolder, targetFreqsPt, tolerancePt, dirs.psdRoot, style, cfg, spec, useParallel);

                forceSeries = [];
                if spec.includeForce
                    [forceSeries, forceWarnLines, forceYLim, hasForceParams] = ...
                        bms.analyzer.SpectrumAnalysisPipeline.cableForceSeries(cfg, pid, freqDay, style);
                    forceSeriesAll{i} = forceSeries;
                    forceValidAll(i) = any(isfinite(forceSeries));
                    if ~hasForceParams
                        warning('测点 %s 未配置 rho/L，索力将为 NaN', pid);
                    end
                end

                bms.analyzer.SpectrumAnalysisPipeline.writePointSheet( ...
                    datesAll, freqDay, ampDay, forceSeries, targetFreqsPt, excelFile, spec.moduleKey, pid);
                bms.analyzer.SpectrumAnalysisPipeline.plotFrequencyTimeseries( ...
                    datesAll, freqDay, pid, targetFreqsPt, dirs.freqRoot, style, theorFreqsPt, theorLabelsPt, cfg);

                if spec.includeForce
                    bms.analyzer.SpectrumAnalysisPipeline.plotForceTimeseries( ...
                        {datesAll}, {forceSeries}, {pid}, pid, dirs.forceRoot, style, forceYLim, {forceWarnLines}, cfg);
                end
            end

            if spec.includeForce
                bms.analyzer.SpectrumAnalysisPipeline.plotCableForceGroups( ...
                    cfg, pointIds, datesAll, forceSeriesAll, forceValidAll, dirs.forceGroupRoot, style);
            end

            fprintf('✓ 已输出 Excel -> %s\n', excelFile);
        end

        function spec = spec(kind)
            defaultPoints = { ...
                'GB-VIB-G04-001-01', 'GB-VIB-G05-001-01', 'GB-VIB-G05-002-01', 'GB-VIB-G05-003-01', ...
                'GB-VIB-G06-001-01', 'GB-VIB-G06-002-01', 'GB-VIB-G06-003-01', 'GB-VIB-G07-001-01'};
            baseStyle = struct( ...
                'psd_ylabel', 'PSD (dB)', ...
                'psd_title_prefix', 'PSD', ...
                'psd_color', [0 0 0], ...
                'freq_ylabel', '峰值频率 (Hz)', ...
                'freq_title_prefix', '峰值频率时程', ...
                'colors', {{[0 0 1], [1 0 0], [0 0.7 0], [0.5 0 0.7]}});

            kind = lower(char(string(kind)));
            switch kind
                case {'accel_spectrum', 'acceleration_spectrum'}
                    spec.moduleKey = 'accel_spectrum';
                    spec.sensorType = 'acceleration';
                    spec.pointKeys = {'accel_spectrum', 'acceleration'};
                    spec.paramsKey = 'accel_spectrum_params';
                    spec.perPointKey = 'accel_spectrum';
                    spec.styleKey = 'accel_spectrum';
                    spec.defaultExcel = 'accel_spec_stats.xlsx';
                    spec.subfolderKeys = {'acceleration_raw'};
                    spec.defaultSubfolder = '波形';
                    spec.freqOutputDir = '频谱峰值曲线_加速度';
                    spec.psdOutputDir = 'PSD_备查';
                    spec.defaultTargetFreqs = [1.150 1.480 2.310];
                    spec.defaultTolerance = 0.15;
                    spec.defaultPoints = defaultPoints;
                    spec.defaultStyle = baseStyle;
                    spec.includeForce = false;
                case {'cable_accel_spectrum', 'cable_acceleration_spectrum'}
                    forceStyle = struct( ...
                        'force_ylabel', '索力 (kN)', ...
                        'force_title_prefix', '索力时程', ...
                        'force_color', [0 0.447 0.741], ...
                        'force_ylim', [], ...
                        'force_alarm_colors', [0.929 0.694 0.125; 0.85 0.1 0.1]);
                    spec.moduleKey = 'cable_accel_spectrum';
                    spec.sensorType = 'cable_accel';
                    spec.pointKeys = {'cable_accel_spectrum', 'cable_accel', 'cable_force'};
                    spec.paramsKey = 'cable_accel_spectrum_params';
                    spec.perPointKey = 'cable_accel';
                    spec.styleKey = 'cable_accel_spectrum';
                    spec.defaultExcel = 'cable_accel_spec_stats.xlsx';
                    spec.subfolderKeys = {'cable_accel_raw', 'cable_accel'};
                    spec.defaultSubfolder = '索力加速度';
                    spec.freqOutputDir = '频谱峰值曲线_索力加速度';
                    spec.psdOutputDir = 'PSD_备查_索力加速度';
                    spec.forceOutputDir = '索力时程图';
                    spec.forceGroupOutputDir = '索力时程图_组图';
                    spec.forceGroupKey = 'cable_force';
                    spec.defaultTargetFreqs = [1.150 1.480 2.310];
                    spec.defaultTolerance = 0.15;
                    spec.defaultPoints = defaultPoints;
                    spec.defaultStyle = bms.config.ConfigReader.mergeStruct(baseStyle, forceStyle);
                    spec.includeForce = true;
                otherwise
                    error('SpectrumAnalysisPipeline:UnsupportedKind', 'Unsupported spectrum pipeline kind: %s', kind);
            end
        end

        function points = resolvePoints(cfg, spec)
            points = {};
            for i = 1:numel(spec.pointKeys)
                points = bms.data.PointResolver.fromConfig(cfg, spec.pointKeys{i}, {});
                if ~isempty(points)
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
            freqs = bms.config.ConfigReader.getField(params, 'theor_freqs', []);
            labels = bms.config.ConfigReader.getField(params, 'theor_labels', {});
            labels = bms.analyzer.SpectrumAnalysisPipeline.normalizeTheorLabels(labels, freqs);
        end

        function [freqs, tol, theorFreqs, theorLabels] = pointParams(cfg, pid, spec, defaultFreqs, defaultTol, defaultTheorFreqs, defaultTheorLabels)
            freqs = defaultFreqs;
            tol = defaultTol;
            theorFreqs = defaultTheorFreqs;
            theorLabels = defaultTheorLabels;

            pt = bms.analyzer.SpectrumAnalysisPipeline.pointConfig(cfg, spec.perPointKey, pid);
            if isstruct(pt)
                freqs = bms.config.ConfigReader.getField(pt, 'target_freqs', freqs);
                tol = bms.config.ConfigReader.getField(pt, 'tolerance', tol);
                theorFreqs = bms.config.ConfigReader.getField(pt, 'theor_freqs', theorFreqs);
                theorLabels = bms.config.ConfigReader.getField(pt, 'theor_labels', theorLabels);
            end
            theorLabels = bms.analyzer.SpectrumAnalysisPipeline.normalizeTheorLabels(theorLabels, theorFreqs);
        end

        function pt = pointConfig(cfg, perPointKey, pid)
            pt = [];
            if ~isstruct(cfg) || ~isfield(cfg, 'per_point') || ~isstruct(cfg.per_point) || ...
                    ~isfield(cfg.per_point, perPointKey) || ~isstruct(cfg.per_point.(perPointKey))
                return;
            end
            perPoint = cfg.per_point.(perPointKey);
            candidates = {char(string(pid)), strrep(char(string(pid)), '-', '_'), bms.data.PointResolver.safeId(pid)};
            candidates = unique(candidates, 'stable');
            for i = 1:numel(candidates)
                if isfield(perPoint, candidates{i})
                    pt = perPoint.(candidates{i});
                    return;
                end
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

        function dirs = ensureOutputDirs(rootDir, spec)
            dirs.freqRoot = fullfile(rootDir, spec.freqOutputDir);
            dirs.psdRoot = fullfile(rootDir, spec.psdOutputDir);
            bms.core.PathResolver.ensureDir(dirs.freqRoot);
            bms.core.PathResolver.ensureDir(dirs.psdRoot);

            if spec.includeForce
                dirs.forceRoot = fullfile(rootDir, spec.forceOutputDir);
                dirs.forceGroupRoot = fullfile(rootDir, spec.forceGroupOutputDir);
                bms.core.PathResolver.ensureDir(dirs.forceRoot);
                bms.core.PathResolver.ensureDir(dirs.forceGroupRoot);
            end
        end

        function [ampDay, freqDay] = processPoint(datesAll, pid, rootDir, subfolder, targetFreqs, tolerance, psdRoot, style, cfg, spec, useParallel)
            nDay = numel(datesAll);
            nFreq = numel(targetFreqs);
            ampDay = NaN(nDay, nFreq);
            freqDay = NaN(nDay, nFreq);

            if useParallel
                parfor di = 1:nDay
                    [ampDay(di, :), freqDay(di, :)] = bms.analyzer.SpectrumPeakService.processOneDay( ...
                        datesAll(di), pid, rootDir, subfolder, spec.sensorType, targetFreqs, tolerance, psdRoot, style, cfg);
                end
            else
                for di = 1:nDay
                    [ampDay(di, :), freqDay(di, :)] = bms.analyzer.SpectrumPeakService.processOneDay( ...
                        datesAll(di), pid, rootDir, subfolder, spec.sensorType, targetFreqs, tolerance, psdRoot, style, cfg);
                end
            end
        end

        function writePointSheet(datesAll, freqDay, ampDay, forceSeries, targetFreqs, excelFile, moduleKey, pid)
            dateCol = datesAll(:);
            freqTbl = array2table(freqDay, 'VariableNames', compose('Freq_%0.3fHz', targetFreqs));
            ampTbl = array2table(ampDay, 'VariableNames', compose('Amp_%0.3fHz', targetFreqs));
            T = [table(dateCol, 'VariableNames', {'Date'}), freqTbl, ampTbl];
            if ~isempty(forceSeries)
                T = [T, table(forceSeries(:), 'VariableNames', {'CableForce_kN'})];
            end
            bms.io.StatsWriter.writeModuleTableChecked(T, excelFile, moduleKey, 'Sheet', pid);
        end

        function [forceSeries, warnLines, forceYLim, hasParams] = cableForceSeries(cfg, pid, freqDay, style)
            [rho, L, forceDecimals, hasParams] = bms.analyzer.CableForceService.params(cfg, pid);
            forceYLim = bms.analyzer.CableForceService.resolveYLim(cfg, pid, style);
            forceSeries = bms.analyzer.CableForceService.compute(freqDay(:, 1), rho, L, forceDecimals);
            warnLines = bms.analyzer.CableForceService.warnLines(cfg, pid, style, '');
        end

        function plotFrequencyTimeseries(datesAll, freqDay, pid, targetFreqs, outDir, style, theorFreqs, theorLabels, cfg)
            fig = figure('Visible', 'off', 'Position', [100 100 1000 470]);
            hold on;
            colors = bms.analyzer.SpectrumAnalysisPipeline.normalizeColors(style.colors);
            h = gobjects(numel(targetFreqs), 1);
            hasLine = false(numel(targetFreqs), 1);
            for k = 1:numel(targetFreqs)
                [datesPlot, freqPlot] = prepare_plot_series(datesAll, freqDay(:, k));
                if isempty(datesPlot) || isempty(freqPlot) || ~any(isfinite(freqPlot))
                    continue;
                end
                if k <= numel(colors)
                    h(k) = plot(datesPlot, freqPlot, 'LineWidth', 1.2, 'Color', colors{k});
                else
                    h(k) = plot(datesPlot, freqPlot, 'LineWidth', 1.2);
                end
                hasLine(k) = isgraphics(h(k));
            end
            grid on;
            xtickformat('yyyy-MM-dd');
            xlabel('日期');
            ylabel(style.freq_ylabel);
            labels = arrayfun(@(k, f) sprintf('峰%d (%.3fHz)', k, f), (1:numel(targetFreqs)).', targetFreqs(:), 'UniformOutput', false);
            if any(hasLine)
                legend(h(hasLine), labels(hasLine), 'Location', 'eastoutside');
            end
            title(sprintf('%s %s', style.freq_title_prefix, pid));

            bms.analyzer.SpectrumAnalysisPipeline.applyFrequencyYLim(freqDay, theorFreqs);
            bms.analyzer.SpectrumAnalysisPipeline.drawTheoreticalLines(datesAll, theorFreqs, theorLabels, h);
            hold off;

            baseName = sprintf('SpecFreq_%s_%s_%s', pid, datestr(datesAll(1), 'yyyymmdd'), datestr(datesAll(end), 'yyyymmdd'));
            bms.plot.PlotService.saveModuleBundle(fig, outDir, baseName, cfg);
        end

        function applyFrequencyYLim(freqDay, theorFreqs)
            if nargin < 2 || isempty(theorFreqs)
                theorFreqs = [];
            end
            dataMin = min(freqDay, [], 'all', 'omitnan');
            dataMax = max(freqDay, [], 'all', 'omitnan');
            if isempty(dataMin) || isempty(dataMax) || ~isfinite(dataMin) || ~isfinite(dataMax)
                return;
            end
            valsMin = dataMin;
            valsMax = dataMax;
            if ~isempty(theorFreqs)
                valsMin = min([valsMin; theorFreqs(:)]);
                valsMax = max([valsMax; theorFreqs(:)]);
            end
            pad = max(0.02, 0.05 * (valsMax - valsMin));
            ylim([valsMin - 0.5 * pad, valsMax + 1.5 * pad]);
        end

        function drawTheoreticalLines(datesAll, theorFreqs, theorLabels, h)
            if isempty(theorFreqs)
                return;
            end
            ax = gca;
            if numel(datesAll) >= 2
                xoff = (datesAll(end) - datesAll(1)) * 0.01;
            else
                xoff = days(1);
            end
            yoff = diff(ylim(ax)) * 0.02;
            xleft = datesAll(1);

            for k = 1:numel(theorFreqs)
                c = [0 0 0];
                if k <= numel(h) && isgraphics(h(k))
                    c = get(h(k), 'Color');
                end
                yline(theorFreqs(k), '--', 'Color', c, 'LineWidth', 1, 'HandleVisibility', 'off');
                text(xleft + xoff, theorFreqs(k) + yoff, theorLabels{k}, ...
                    'Color', c, 'FontSize', 9, 'VerticalAlignment', 'bottom');
            end
        end

        function plotForceTimeseries(timesList, forceList, labels, nameTag, outDir, style, forceYLim, warnLineSets, cfg)
            valid = false(numel(forceList), 1);
            for i = 1:numel(forceList)
                valid(i) = ~isempty(forceList{i}) && any(isfinite(forceList{i}));
            end
            if ~any(valid)
                warning('测点/组 %s 索力全为 NaN，跳过绘图', nameTag);
                return;
            end

            fig = figure('Visible', 'off', 'Position', [100 100 1000 470]);
            hold on;
            colors = bms.analyzer.SpectrumAnalysisPipeline.normalizeColors(style.colors);
            h = gobjects(numel(forceList), 1);
            for i = 1:numel(forceList)
                if ~valid(i)
                    continue;
                end
                if isscalar(forceList)
                    c = style.force_color;
                elseif i <= numel(colors)
                    c = colors{i};
                else
                    cmap = lines(numel(forceList));
                    c = cmap(i, :);
                end
                [timesPlot, forcePlot] = prepare_plot_series(timesList{i}, forceList{i});
                if isempty(timesPlot) || isempty(forcePlot) || ~any(isfinite(forcePlot))
                    continue;
                end
                h(i) = plot(timesPlot, forcePlot, 'LineWidth', 1.2, 'Color', c);
            end
            grid on;
            xtickformat('yyyy-MM-dd');
            xlabel('日期');
            ylabel(style.force_ylabel);
            title(sprintf('%s %s', style.force_title_prefix, nameTag));

            goodLines = h(isgraphics(h));
            if numel(goodLines) > 1
                legend(goodLines, labels(valid), 'Location', 'eastoutside');
            end

            allWarnLines = bms.analyzer.SpectrumAnalysisPipeline.drawWarnLines(warnLineSets);
            bms.analyzer.SpectrumAnalysisPipeline.applyForceYLim(forceList, valid, forceYLim, allWarnLines);

            firstIdx = find(valid, 1, 'first');
            dt0 = timesList{firstIdx}(1);
            dt1 = timesList{firstIdx}(end);
            safeName = bms.analyzer.StructuralPlotConfigService.sanitizeFilename(strrep(nameTag, ' ', '_'));
            baseName = sprintf('CableForce_%s_%s_%s', safeName, datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd'));
            bms.plot.PlotService.saveModuleBundle(fig, outDir, baseName, cfg);
        end

        function allWarnLines = drawWarnLines(warnLineSets)
            allWarnLines = {};
            if nargin < 1 || isempty(warnLineSets)
                return;
            end
            for i = 1:numel(warnLineSets)
                warnLines = warnLineSets{i};
                if isempty(warnLines)
                    continue;
                end
                for k = 1:numel(warnLines)
                    wl = warnLines{k};
                    if ~isstruct(wl) || ~isfield(wl, 'y') || ~isnumeric(wl.y) || ~isfinite(wl.y)
                        continue;
                    end
                    yl = yline(wl.y, '--', bms.analyzer.CableForceService.warnLabel(wl), 'LabelHorizontalAlignment', 'left');
                    if isfield(wl, 'color') && isnumeric(wl.color) && numel(wl.color) == 3
                        yl.Color = reshape(wl.color, 1, 3);
                    end
                    yl.LineWidth = 1.0;
                    allWarnLines{end+1, 1} = wl; %#ok<AGROW>
                end
            end
        end

        function applyForceYLim(forceList, valid, forceYLim, warnLines)
            if nargin >= 3 && ~isempty(forceYLim)
                ylim(forceYLim);
                return;
            end

            dataMin = NaN;
            dataMax = NaN;
            for i = 1:numel(forceList)
                if ~valid(i)
                    continue;
                end
                dataMin = min([dataMin; min(forceList{i}, [], 'all', 'omitnan')], [], 'omitnan');
                dataMax = max([dataMax; max(forceList{i}, [], 'all', 'omitnan')], [], 'omitnan');
            end
            warnVals = bms.analyzer.SpectrumAnalysisPipeline.warnValues(warnLines);
            if ~isempty(warnVals)
                dataMin = min([dataMin; warnVals(:)], [], 'omitnan');
                dataMax = max([dataMax; warnVals(:)], [], 'omitnan');
            end
            if isfinite(dataMin) && isfinite(dataMax)
                pad = max(0.02, 0.05 * (dataMax - dataMin));
                ylim([dataMin - 0.5 * pad, dataMax + 1.5 * pad]);
            end
        end

        function vals = warnValues(warnLines)
            vals = [];
            for i = 1:numel(warnLines)
                wl = warnLines{i};
                if isstruct(wl) && isfield(wl, 'y') && isnumeric(wl.y) && isfinite(wl.y)
                    vals(end+1, 1) = wl.y; %#ok<AGROW>
                end
            end
        end

        function plotCableForceGroups(cfg, pointIds, datesAll, forceSeriesAll, forceValidAll, outDir, style)
            groupsCfg = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, 'cable_force', struct());
            groups = bms.analyzer.StructuralPlotConfigService.normalizeGroupMap(groupsCfg);
            groupNames = fieldnames(groups);
            for gi = 1:numel(groupNames)
                groupName = groupNames{gi};
                pidList = groups.(groupName);
                if isempty(pidList)
                    continue;
                end

                forceList = {};
                labels = {};
                for pi = 1:numel(pidList)
                    idx = find(strcmp(pointIds, pidList{pi}), 1, 'first');
                    if isempty(idx) || ~forceValidAll(idx)
                        continue;
                    end
                    forceList{end+1, 1} = forceSeriesAll{idx}; %#ok<AGROW>
                    labels{end+1, 1} = pidList{pi}; %#ok<AGROW>
                end
                if isempty(labels)
                    continue;
                end

                warnLineSets = cell(numel(labels), 1);
                for pi = 1:numel(labels)
                    warnLineSets{pi} = bms.analyzer.CableForceService.warnLines(cfg, labels{pi}, style, labels{pi});
                end
                groupDisplayName = bms.analyzer.SpectrumAnalysisPipeline.groupDisplayName(groupName, labels);
                bms.analyzer.SpectrumAnalysisPipeline.plotForceTimeseries( ...
                    repmat({datesAll}, numel(labels), 1), forceList, labels, groupDisplayName, outDir, style, [], warnLineSets, cfg);
            end
        end

        function name = groupDisplayName(groupName, labels)
            labels = labels(~cellfun(@isempty, labels));
            if isempty(labels)
                name = groupName;
            elseif numel(labels) <= 4
                name = strjoin(labels(:).', '-');
            else
                name = groupName;
            end
        end

        function colors = normalizeColors(raw)
            colors = bms.plot.PlotService.normalizeColors(raw, {});
        end
    end
end
