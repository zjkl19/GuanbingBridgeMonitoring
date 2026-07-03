classdef SpectrumPlotService
    %SPECTRUMPLOTSERVICE Plot helpers for spectrum and cable force outputs.

    methods (Static)
        function plotFrequencyTimeseries(datesAll, freqDay, pid, targetFreqs, outDir, style, theorFreqs, theorLabels, cfg, peakLabels)
            if nargin < 10 || isempty(peakLabels)
                peakLabels = bms.analyzer.SpectrumConfigService.defaultPeakLabels(targetFreqs);
            end
            peakLabels = bms.analyzer.SpectrumConfigService.normalizePeakLabels(peakLabels, targetFreqs);
            fig = figure('Visible', 'off', 'Position', [100 100 1000 470]);
            hold on;
            colors = bms.analyzer.SpectrumPlotService.normalizeColors(style.colors);
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
            if ~any(hasLine)
                hold off;
                close(fig);
                warning('SpectrumPlotService:NoFrequencyData', ...
                    'No finite frequency values for point %s; skip frequency timeseries plot.', char(string(pid)));
                return;
            end
            grid on;
            bms.analyzer.SpectrumPlotService.applyDateTickFormat(datesAll);
            xlabel('日期');
            ylabel(style.freq_ylabel);
            labels = arrayfun(@(k, f) sprintf('%s (%.3fHz)', peakLabels{k}, f), (1:numel(targetFreqs)).', targetFreqs(:), 'UniformOutput', false);
            if any(hasLine)
                legend(h(hasLine), labels(hasLine), 'Location', 'eastoutside');
            end
            title(sprintf('%s %s', style.freq_title_prefix, pid));

            bms.analyzer.SpectrumPlotService.applyFrequencyYLim(freqDay, theorFreqs);
            bms.analyzer.SpectrumPlotService.drawTheoreticalLines(datesAll, theorFreqs, theorLabels, h);
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
            colors = bms.analyzer.SpectrumPlotService.normalizeColors(style.colors);
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
            lineMask = isgraphics(h);
            if ~any(lineMask)
                hold off;
                close(fig);
                warning('SpectrumPlotService:NoForceData', ...
                    'No finite force values for group %s; skip force timeseries plot.', char(string(nameTag)));
                return;
            end
            grid on;
            bms.analyzer.SpectrumPlotService.applyDateTickFormat(timesList{find(lineMask, 1, 'first')});
            xlabel('日期');
            ylabel(style.force_ylabel);
            title(sprintf('%s %s', style.force_title_prefix, nameTag));

            goodLines = h(lineMask);
            if numel(goodLines) > 1
                lgd = legend(goodLines, labels(lineMask), 'Location', 'eastoutside');
                lgd.AutoUpdate = 'off';
            end

            allWarnLines = bms.analyzer.SpectrumPlotService.drawWarnLines(warnLineSets);
            bms.analyzer.SpectrumPlotService.applyForceYLim(forceList, valid, forceYLim, allWarnLines);

            firstIdx = find(valid, 1, 'first');
            dt0 = timesList{firstIdx}(1);
            dt1 = timesList{firstIdx}(end);
            safeName = bms.analyzer.StructuralPlotConfigService.sanitizeFilename(strrep(nameTag, ' ', '_'));
            baseName = sprintf('CableForce_%s_%s_%s', safeName, datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd'));
            bms.plot.PlotService.saveModuleBundle(fig, outDir, baseName, cfg);
        end

        function plotFrequencyGroups(cfg, pointIds, datesAll, freqSeriesAll, freqValidAll, outDir, style, groupKey, targetFreqsAll, peakLabelsAll, theorFreqsAll, theorLabelsAll)
            if nargin < 11 || isempty(theorFreqsAll)
                theorFreqsAll = cell(size(freqSeriesAll));
            end
            if nargin < 12 || isempty(theorLabelsAll)
                theorLabelsAll = cell(size(freqSeriesAll));
            end
            groups = bms.analyzer.SpectrumPlotService.resolveFrequencyGroups(cfg, style, groupKey);
            groupNames = fieldnames(groups);
            for gi = 1:numel(groupNames)
                groupName = groupNames{gi};
                pidList = groups.(groupName);
                if isempty(pidList)
                    continue;
                end

                maxPeaks = bms.analyzer.SpectrumPlotService.maxGroupPeakCount(pointIds, pidList, freqSeriesAll, freqValidAll);
                for peakIdx = 1:maxPeaks
                    freqList = {};
                    labels = {};
                    theorFreq = NaN;
                    theorLabel = '';
                    peakLabel = sprintf('峰%d', peakIdx);
                    for pi = 1:numel(pidList)
                        idx = find(strcmp(pointIds, pidList{pi}), 1, 'first');
                        if isempty(idx) || ~freqValidAll(idx) || size(freqSeriesAll{idx}, 2) < peakIdx
                            continue;
                        end
                        values = freqSeriesAll{idx}(:, peakIdx);
                        if ~any(isfinite(values))
                            continue;
                        end
                        freqList{end+1, 1} = values; %#ok<AGROW>
                        labels{end+1, 1} = pidList{pi}; %#ok<AGROW>
                        if numel(peakLabelsAll{idx}) >= peakIdx && ~isempty(peakLabelsAll{idx}{peakIdx})
                            peakLabel = peakLabelsAll{idx}{peakIdx};
                        end
                        if isnan(theorFreq) && numel(theorFreqsAll{idx}) >= peakIdx
                            theorFreq = theorFreqsAll{idx}(peakIdx);
                            if numel(theorLabelsAll{idx}) >= peakIdx && ~isempty(theorLabelsAll{idx}{peakIdx})
                                theorLabel = theorLabelsAll{idx}{peakIdx};
                            end
                        end
                    end
                    if isempty(labels)
                        continue;
                    end

                    groupDisplayName = bms.analyzer.SpectrumPlotService.styledGroupDisplayName(style, groupName, labels);
                    bms.analyzer.SpectrumPlotService.plotFrequencyGroupTimeseries( ...
                        repmat({datesAll}, numel(labels), 1), freqList, labels, groupDisplayName, ...
                        outDir, style, cfg, peakIdx, peakLabel, theorFreq, theorLabel);
                end
            end
        end

        function plotFrequencyGroupTimeseries(timesList, freqList, labels, nameTag, outDir, style, cfg, peakIdx, peakLabel, theorFreq, theorLabel)
            valid = false(numel(freqList), 1);
            for i = 1:numel(freqList)
                valid(i) = ~isempty(freqList{i}) && any(isfinite(freqList{i}));
            end
            if ~any(valid)
                return;
            end

            fig = figure('Visible', 'off', 'Position', [100 100 1000 470]);
            hold on;
            colors = bms.analyzer.StructuralPlotConfigService.distinctColors(max(1, numel(freqList)));
            h = gobjects(numel(freqList), 1);
            for i = 1:numel(freqList)
                if ~valid(i)
                    continue;
                end
                [timesPlot, freqPlot] = prepare_plot_series(timesList{i}, freqList{i});
                if isempty(timesPlot) || isempty(freqPlot) || ~any(isfinite(freqPlot))
                    continue;
                end
                h(i) = plot(timesPlot, freqPlot, 'LineWidth', 1.2, 'Color', colors(i, :));
            end
            validLineMask = isgraphics(h);
            if ~any(validLineMask)
                hold off;
                close(fig);
                warning('SpectrumPlotService:NoGroupFrequencyData', ...
                    'No finite frequency values for group %s; skip frequency group plot.', char(string(nameTag)));
                return;
            end
            grid on;
            bms.analyzer.SpectrumPlotService.applyDateTickFormat(timesList{find(validLineMask, 1, 'first')});
            xlabel('日期');
            ylabel(style.freq_ylabel);

            goodLines = h(validLineMask);
            if ~isempty(goodLines)
                lgd = legend(goodLines, labels(validLineMask), ...
                    'Location', bms.analyzer.SpectrumPlotService.styleField(style, 'group_legend_location', 'northeast'), ...
                    'Box', bms.analyzer.SpectrumPlotService.styleField(style, 'group_legend_box', 'off'), ...
                    'Interpreter', 'none');
                lgd.AutoUpdate = 'off';
            end

            title(sprintf('%s %s %s', style.freq_title_prefix, nameTag, peakLabel), 'Interpreter', 'none');
            freqMat = bms.analyzer.SpectrumPlotService.frequencyMatrix(freqList, valid);
            bms.analyzer.SpectrumPlotService.applyFrequencyYLim(freqMat, theorFreq);
            if isfinite(theorFreq)
                if isempty(theorLabel)
                    theorLabel = sprintf('理论频率 %.3fHz', theorFreq);
                end
                yline(theorFreq, '--', theorLabel, ...
                    'Color', [0.35 0.35 0.35], 'LineWidth', 1, ...
                    'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
            end
            hold off;

            firstIdx = find(valid, 1, 'first');
            dt0 = timesList{firstIdx}(1);
            dt1 = timesList{firstIdx}(end);
            safeName = bms.analyzer.StructuralPlotConfigService.sanitizeFilename(strrep(nameTag, ' ', '_'));
            suffix = '';
            if peakIdx > 1
                suffix = sprintf('_P%d', peakIdx);
            end
            baseName = sprintf('SpecFreq_%s_Group%s_%s_%s', safeName, suffix, datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd'));
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
                    yl = yline(wl.y, '--', bms.analyzer.CableForceService.warnLabel(wl), 'LabelHorizontalAlignment', 'left', ...
                        'HandleVisibility', 'off');
                    if isfield(wl, 'color') && isnumeric(wl.color) && numel(wl.color) == 3
                        yl.Color = bms.analyzer.StructuralPlotConfigService.warnDisplayColor(wl.color);
                    end
                    yl.LineWidth = 1.0;
                    if wl.y >= 0
                        yl.LabelVerticalAlignment = 'bottom';
                    else
                        yl.LabelVerticalAlignment = 'top';
                    end
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
            warnVals = bms.analyzer.SpectrumPlotService.warnValues(warnLines);
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
                groupDisplayName = bms.analyzer.SpectrumPlotService.groupDisplayName(groupName, labels);
                bms.analyzer.SpectrumPlotService.plotForceTimeseries( ...
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

        function name = styledGroupDisplayName(style, groupName, labels)
            name = bms.analyzer.StructuralPlotConfigService.groupLabel(style, groupName, '');
            if ~isempty(name)
                return;
            end
            name = bms.analyzer.SpectrumPlotService.groupDisplayName(groupName, labels);
        end

        function groups = resolveFrequencyGroups(cfg, style, groupKey)
            groupsCfg = [];
            if isstruct(style)
                if isfield(style, 'groups') && ~isempty(style.groups)
                    groupsCfg = style.groups;
                elseif isfield(style, 'group_points') && ~isempty(style.group_points)
                    groupsCfg = style.group_points;
                end
            end
            if isempty(groupsCfg)
                groupsCfg = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, groupKey, struct());
            end
            groups = bms.analyzer.StructuralPlotConfigService.normalizeGroupMap(groupsCfg);
        end

        function n = maxGroupPeakCount(pointIds, pidList, freqSeriesAll, freqValidAll)
            n = 0;
            for pi = 1:numel(pidList)
                idx = find(strcmp(pointIds, pidList{pi}), 1, 'first');
                if isempty(idx) || ~freqValidAll(idx) || isempty(freqSeriesAll{idx})
                    continue;
                end
                n = max(n, size(freqSeriesAll{idx}, 2));
            end
        end

        function mat = frequencyMatrix(freqList, valid)
            mat = [];
            for i = 1:numel(freqList)
                if ~valid(i)
                    continue;
                end
                values = freqList{i}(:);
                if isempty(mat)
                    mat = values;
                else
                    n = max(size(mat, 1), numel(values));
                    if size(mat, 1) < n
                        mat(end+1:n, :) = NaN;
                    end
                    if numel(values) < n
                        values(end+1:n, 1) = NaN;
                    end
                    mat(:, end+1) = values; %#ok<AGROW>
                end
            end
        end

        function value = styleField(style, fieldName, defaultValue)
            value = defaultValue;
            if isstruct(style) && isfield(style, fieldName) && ~isempty(style.(fieldName))
                value = style.(fieldName);
            end
        end

        function applyDateTickFormat(times)
            if nargin < 1 || isempty(times)
                return;
            end
            if iscell(times)
                idx = find(~cellfun(@isempty, times), 1, 'first');
                if isempty(idx)
                    return;
                end
                times = times{idx};
            end
            try
                if isdatetime(times)
                    xtickformat('yyyy-MM-dd');
                elseif isnumeric(times)
                    datetick('x', 'yyyy-mm-dd', 'keeplimits');
                end
            catch ME
                warning('SpectrumPlotService:DateTickFormat', ...
                    'Unable to apply date tick format: %s', ME.message);
            end
        end

        function colors = normalizeColors(raw)
            colors = bms.plot.PlotService.normalizeColors(raw, {});
        end
    end
end
